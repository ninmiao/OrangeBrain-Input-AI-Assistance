package input.zephyr.windows

import kotlin.test.*
import java.nio.file.Files
import com.osfans.trime.ai.*

class WindowsTest {
    @Test fun publicModelProvidersLoadWithoutCredential() {
        org.junit.jupiter.api.Assumptions.assumeTrue(System.getenv("ZEPHYR_LIVE_PROVIDERS")=="1")
        val options=kotlinx.coroutines.runBlocking { ProvidersClient().fetch(ApiRouting.DEEPSEEK) }
        assertTrue(options.any{it.id=="wafer/us"});assertEquals(options.size,options.map{it.id}.distinct().size)
    }
    @Test fun duplicatePolicyCopiesSettingsAndEncryptedKeyIndependently() {
        val s=ConfigurationStore(Files.createTempDirectory("zephyr-copy-test"))
        try {
            val initial=s.load();val source=initial.policies[1].copy(chinesePrompt="Custom ZH",englishPrompt="Custom EN")
            s.save(initial.copy(policies=initial.policies.map{if(it.id==source.id)source else it}))
            s.saveKey(source.id,"copy-fixture-key",source.endpoint)
            val copied=s.duplicatePolicy(source.id)
            assertEquals(source.copy(id=copied.id,name=copied.name),copied)
            assertEquals(initial.selectedPolicy,s.load().selectedPolicy)
            assertEquals("copy-fixture-key",s.key(copied.id,copied.endpoint))
            assertFails { s.key(copied.id,"https://different.example/v1") }
            assertFalse(Files.readAllBytes(s.dir.resolve("credential-${copied.id}.bin")).toString(Charsets.UTF_8).contains("copy-fixture-key"))
            s.saveKey(copied.id,"replacement-fixture-key",copied.endpoint)
            assertEquals("copy-fixture-key",s.key(source.id,source.endpoint))
            val second=s.duplicatePolicy(source.id);assertNotEquals(copied.name,second.name)
            Files.delete(s.dir.resolve("credential-${copied.id}.bin"))
            assertEquals("copy-fixture-key",s.key(source.id,source.endpoint))
        } finally { s.dir.toFile().deleteRecursively() }
    }
    @Test fun duplicateWithoutKeyAndRejectUnreadableOrExcessPolicies() {
        val s=ConfigurationStore(Files.createTempDirectory("zephyr-copy-failure-test"))
        try {
            s.save(s.load());val copied=s.duplicatePolicy("openai")
            assertEquals("",s.key(copied.id,copied.endpoint))
            s.saveKey("openai","fixture","https://different.example/v1")
            val before=s.load();val files=Files.list(s.dir).use{it.count()}
            assertFails { s.duplicatePolicy("openai") };assertEquals(before,s.load())
            assertEquals(files,Files.list(s.dir).use{it.count()})
            s.save(before.copy(policies=(1..32).map{Policy(id="p$it")},selectedPolicy="p1"))
            assertFails { s.duplicatePolicy("p1") };assertEquals(32,s.load().policies.size)
        } finally { s.dir.toFile().deleteRecursively() }
    }

    @Test fun kaomojiRuleIsSharedAndPreservesLegacyOverrides() {
        val pack=PromptPackage.parse(requireNotNull(javaClass.getResourceAsStream("/default-prompts.json")).readBytes())
        for (chinese in listOf(true,false)) {
            val prompt=pack.compose("original",chinese,false)
            assertEquals(1,prompt.split(PromptPackage.KAOMOJI_RULE).size-1)
            assertTrue(prompt.contains("candidates"))
            val old=pack.copy(revision=9,keyboard_language_rules=LanguageRules("CUSTOM ZH","CUSTOM EN"))
            assertTrue(old.compose("original",chinese,false).startsWith("CUSTOM"))
            assertTrue(old.compose("original",chinese,false).endsWith(PromptPackage.KAOMOJI_RULE))
            // An already-saved revision 10 must replace the old rule, not grow the prompt.
            val legacyRule="优先识别任意形式的“颜表情＋描述”意图并生成对应 kaomoji，如“颜表情 笑死”或“yanbiaoqing xiaosi”→(„ಡωಡ„)。"
            val saved=pack.copy(revision=10,keyboard_language_rules=LanguageRules("CUSTOM ZH"+legacyRule,"CUSTOM EN"+legacyRule))
            assertEquals((if(chinese) "CUSTOM ZH" else "CUSTOM EN")+PromptPackage.KAOMOJI_RULE,saved.compose("original",chinese,false))
        }
    }

    @Test fun shortcutDefaultsAndPersistence() {
        assertEquals("shift",Configuration().languageShortcut)
        assertEquals("ctrl_shift_t",Configuration().scriptShortcut)
        val store=ConfigurationStore(Files.createTempDirectory("zephyr-shortcuts"))
        try { for(language in ShortcutOptions.language.keys) for(script in ShortcutOptions.script.keys) {
            store.save(Configuration(languageShortcut=language,scriptShortcut=script))
            val loaded=store.load();assertEquals(language,loaded.languageShortcut);assertEquals(script,loaded.scriptShortcut)
        } } finally { store.dir.toFile().deleteRecursively() }
        assertFails { Configuration(languageShortcut="unsupported").validate() }
        assertFails { Configuration(scriptShortcut="shift").validate() }
    }

    @Test fun defaultPolicies() { val c=Configuration();c.validate();assertEquals(2,c.policies.size);assertEquals(1,c.candidateCount);assertEquals("gpt-6.1-terra",c.active().model);assertEquals("low",c.active().reasoning);assertEquals("priority",c.active().speed);assertEquals("none",c.policies[1].reasoning);assertTrue(c.enterOriginal);assertFalse(c.spaceOriginal);assertTrue(c.wordSegmentation);assertFalse(c.enabled) }
    @Test fun windowsKeysAreEncryptedAndIndependent() {
        val s=ConfigurationStore(Files.createTempDirectory("zephyr-credential-test"))
        try {
            s.saveKey("openai","test-only-not-a-real-key");s.saveKey("openrouter","different-test-key")
            assertEquals("test-only-not-a-real-key",s.key("openai"));assertEquals("different-test-key",s.key("openrouter"))
            assertFalse(Files.readAllBytes(s.dir.resolve("credential-openai.bin")).toString(Charsets.UTF_8).contains("test-only"))
        } finally { s.dir.toFile().deleteRecursively() }
    }
    @Test fun changingEndpointCannotReuseCredential() {
        val s=ConfigurationStore(Files.createTempDirectory("zephyr-origin-test"))
        try {
            s.saveKey("p","test-key","https://example.com/v1/chat/completions")
            assertEquals("test-key",s.key("p","https://example.com/v1/models"))
            assertFails { s.key("p","https://different.example/v1") }
            assertFails { s.key("p","https://example.com:8443/v1") }
        } finally { s.dir.toFile().deleteRecursively() }
    }
    @Test fun configurationRoundTrip() {
        val s=ConfigurationStore(Files.createTempDirectory("zephyr-config-test"))
        try { val c=Configuration(candidateCount=5,completion=true,wordSegmentation=false,enterOriginal=false,spaceOriginal=true);s.save(c);assertEquals(c.copy(settingsRevision=1,candidateCount=1,completion=false),s.load()) }
        finally { s.dir.toFile().deleteRecursively() }
    }
    @Test fun rejectsKeyPathTraversal() { val s=ConfigurationStore(Files.createTempDirectory("zephyr-path-test"));try { assertFails { s.key("../other") } }finally { s.dir.toFile().deleteRecursively() } }
    @Test fun rejectsUnencryptedEndpoint() { assertFails { Policy(endpoint="http://example.com").validate() } }
    @Test fun rejectsUnsupportedReasoning() { assertFails { Policy(model="gpt-4.1",reasoning="high").validate() };Policy(model="gpt-4.1",reasoning="omit").validate() }
    @Test fun customModelsDoNotInheritEfforts() { assertFails { Policy(model="custom-model",reasoning="none").validate() };Policy(model="custom-model",reasoning="omit").validate() }
    @Test fun boundedCandidateCount() { assertFails { Configuration(candidateCount=0).validate() };assertFails { Configuration(candidateCount=6).validate() } }
    @Test fun boundedTiming() { assertFails { Configuration(timeoutMs=60001).validate() };assertFails { Configuration(debounceMs=0).validate() } }
    @Test fun wirePreservesSpacesAndPunctuation() { val input="hanbaowang haochi, 123!";assertEquals(input,Wire.decode("Z1\tzh\t0\t"+Wire.hex(input)).input) }
    @Test fun wirePreservesUnicode() { val raw="我 tomorrow 有 meeting 😊";assertEquals(raw,Wire.decode("Z1\ten\t0\t"+Wire.hex(raw)).input) }
    @Test fun rejectsMalformedMessages() { listOf("Z0\tzh\t0\t61","Z1\tjp\t0\t61","Z1\tzh\t0\t6","Z1\tzh\t0\tzz","Z1\tzh\t0\t0a").forEach { assertFails { Wire.decode(it) } } }
    @Test fun rejectsOversizedComposition() { assertFails { Wire.decode("Z1\tzh\t0\t"+Wire.hex("a".repeat(301))) } }
    @Test fun englishUsesEnglishPrompt() { val c=Configuration();val text=Prompts.compose(c,c.active(),false,true);assertContains(text,"优先按英文纠错");assertContains(text,"统一转成英文");assertTrue(text.length<300) }
    @Test fun chineseRetainsEnglishSpans() { val c=Configuration();val text=Prompts.compose(c,c.active(),true,false);assertContains(text,"简体汉字");assertContains(text,"英文保留并纠错") }
    @Test fun traditionalChineseContract() { val c=Configuration();assertContains(Prompts.compose(c,c.active(),true,true),"繁体汉字") }
    @Test fun countAndRankingAreShared() { val c=Configuration(candidateCount=5);assertContains(Prompts.compose(c,c.active(),true,false),"一个最可能的结果") }
    @Test fun disabledBrokerMakesNoNetworkRequest() { val s=ConfigurationStore(Files.createTempDirectory("zephyr-disabled-test"));try { val result=AiService(s).handle(("Z1\ten\t0\t"+Wire.hex("hello world")).toByteArray());assertEquals("Z1\t1\t200\t1\t0\n",result.toString(Charsets.UTF_8)) }finally { s.dir.toFile().deleteRecursively() } }
    @Test fun responseKeepsRankAndCount() { val c=Configuration(candidateCount=2);val lines=Wire.response(c,AiResult(listOf("你好","您好","你们好"),"")).lines();assertEquals(listOf("Z1\t1\t200\t1\t0",Wire.hex("你好")),lines) }
    @Test fun legacyFileMigratesWithoutLosingIndependentPolicyOrKey() {
        val store=ConfigurationStore(Files.createTempDirectory("zephyr-migration"))
        try {
            Files.writeString(store.dir.resolve("settings.json"),"""{"candidateCount":5,"completion":true,"policies":[{"id":"openai","name":"OpenAI · 6 Luna","model":"gpt-6-luna","reasoning":"none","speed":"default"},{"id":"custom","model":"gpt-6-sol","reasoning":"high","speed":"default"}]}""")
            val c=store.load();assertEquals(1,c.candidateCount);assertFalse(c.completion)
            assertEquals("gpt-6.1-terra",c.active().model);assertEquals("high",c.policies[1].reasoning)
            assertEquals("gpt-6-sol",c.policies[1].model)
            store.save(c.copy(policies=c.policies.map { if(it.id=="openai") it.copy(model="gpt-6-luna",reasoning="none",speed="default") else it }))
            assertEquals("gpt-6-luna",store.load().active().model)
            assertEquals("Z1\t1\t200\t0\t1\n",Wire.response(c.copy(enterOriginal=false,spaceOriginal=true),null))
        } finally { store.dir.toFile().deleteRecursively() }
    }
}
