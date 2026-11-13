package com.osfans.trime.ai.android
import android.content.ContextWrapper
import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.ai.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class PlainTextApiTest {
    @Test fun presetFieldsAppearOnlyAfterSwitchingOn() {
        val ins=InstrumentationRegistry.getInstrumentation()
        val store=AiStore.get(ins.targetContext);val old=store.config
        var activity:android.app.Activity?=null
        try {
            store.updatePolicyConfig("openrouter") { it.copy(presets=PromptPresets()) }
            activity=ins.startActivitySync(android.content.Intent(ins.targetContext,AiSettingsActivity::class.java)
                .putExtra("policy","openrouter").addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
            fun descendants(v:android.view.View):List<android.view.View> = listOf(v)+
                if(v is android.view.ViewGroup)(0 until v.childCount).flatMap { descendants(v.getChildAt(it)) } else emptyList()
            fun views()=descendants(activity!!.window.decorView)
            fun toggle()=views().filterIsInstance<android.widget.Switch>().single { it.text.toString()=="使用 OpenRouter Preset" }
            ins.runOnMainSync {
                assertFalse(toggle().isChecked)
                assertFalse(views().filterIsInstance<android.widget.EditText>().any { it.text.toString().startsWith("@preset/") })
                toggle().performClick()
            }
            fun waitFor(enabled:Boolean) {
                val deadline=System.nanoTime()+java.util.concurrent.TimeUnit.SECONDS.toNanos(5)
                var matches=false
                while(!matches && System.nanoTime()<deadline) {
                    ins.waitForIdleSync()
                    ins.runOnMainSync { matches=toggle().isChecked==enabled && views().filterIsInstance<android.widget.EditText>().count { it.text.toString().startsWith("@preset/") }==if(enabled)3 else 0 }
                    if(!matches)Thread.sleep(30)
                }
                assertTrue("Preset fields did not follow switch",matches)
            }
            waitFor(true)
            ins.runOnMainSync {
                assertTrue(views().filterIsInstance<android.widget.EditText>().any { it.text.toString()=="@preset/zephyr-en" })
                toggle().performClick()
            }
            waitFor(false);assertFalse(store.configForPolicy("openrouter").presets.enabled)
        } finally { ins.runOnMainSync { activity?.finish() };store.update { old } }
    }
    @Test fun presetToggleSurvivesReloadWithoutChangingOtherPolicies() {
        val base=InstrumentationRegistry.getInstrumentation().targetContext
        val folder=File(base.noBackupFilesDir,"preset-${UUID.randomUUID()}").apply { mkdirs() }
        val context=object:ContextWrapper(base) { override fun getNoBackupFilesDir()=folder }
        try {
            val store=AiStore(context)
            val c=store.configForPolicy("openrouter")
            assertFalse(c.presets.enabled);assertEquals("",store.preset(c,true))
            assertEquals("@preset/zephyr-en",c.presets.english)
            store.updatePolicyConfig("openrouter") { it.copy(presets=it.presets.copy(enabled=true)) }
            val reloaded=AiStore(context);val on=reloaded.configForPolicy("openrouter")
            assertTrue(on.presets.enabled);assertEquals("@preset/zephyr-zh-hans",reloaded.preset(on,true))
            assertEquals("@preset/zephyr-zh-hant",reloaded.preset(on.copy(traditional=true),true))
            assertEquals("@preset/zephyr-en",reloaded.preset(on,false))
            assertFalse(reloaded.configForPolicy("default").presets.enabled)
            reloaded.updatePolicyConfig("openrouter") { it.copy(presets=it.presets.copy(enabled=false)) }
            val off=reloaded.configForPolicy("openrouter")
            val req=AiRequest(RequestStamp(0,0,0,0,0),AiInput("nihoa"),reloaded.prompt(off,true),false)
            val body=ChatCompletionsClient().payload(off.model,req,endpoint=off.endpoint,preset=reloaded.preset(off,true))
            assertEquals(req.systemPrompt,body["messages"]!!.jsonArray[0].jsonObject["content"]!!.jsonPrimitive.content)
        } finally { folder.deleteRecursively() }
    }
    @Test fun settingsRemoveContextAndStyleAndKeepGeminiDefaults() {
        val base=InstrumentationRegistry.getInstrumentation().targetContext
        val folder=File(base.noBackupFilesDir,"plain-${UUID.randomUUID()}").apply { mkdirs() }
        val context=object:ContextWrapper(base) { override fun getNoBackupFilesDir()=folder }
        try {
            val store=AiStore(context)
            val p=store.config.policies.single { ApiRouting.isGemini(it.endpoint) }
            val c=store.configForPolicy(p.id)
            assertEquals(ApiRouting.HYDROGEN,p.model)
            assertEquals("low",store.parameters(c)["reasoning_effort"]!!.content)
            val serialized=File(folder,"ai-config.json").readText()
            listOf("contextEnabled","beforeLimit","afterLimit","customStyle","\"style\"").forEach { assertFalse(serialized.contains(it)) }
            val prompt=store.prompt(c,true)
            listOf("before","after","上下文","风格","candidates","completion").forEach { assertFalse(prompt.contains(it)) }
            assertEquals("hanbaowang haochi",Protocol.encode(AiInput("hanbaowang haochi")))
        } finally { folder.deleteRecursively() }
    }

    @Test fun switchingSelectedApiClearsOldRouterProviderAndPreset() {
        val base=InstrumentationRegistry.getInstrumentation().targetContext
        val folder=File(base.noBackupFilesDir,"switch-${UUID.randomUUID()}").apply { mkdirs() }
        val context=object:ContextWrapper(base) { override fun getNoBackupFilesDir()=folder }
        try {
            val store=AiStore(context);store.selectPolicy("openrouter")
            store.update { it.copy(presets=PromptPresets(chinese="@preset/zh")) }
            assertEquals(ApiRouting.WAFER,store.config.provider)
            store.updatePolicyConfig("openrouter") { it.copy(endpoint=ApiRouting.GEMINI,model=ApiRouting.HYDROGEN) }
            assertEquals("",store.config.provider);assertEquals(PromptPresets(),store.config.presets)
            store.saveParameters(ApiRouting.GEMINI,ApiRouting.HYDROGEN,mapOf("reasoning_effort" to JsonPrimitive("low")))
            assertEquals("low",store.parameters()["reasoning_effort"]!!.content)
        } finally { folder.deleteRecursively() }
    }
    @Test fun nativeResponsesAndGeminiWorkThroughAndroidTlsTransport()=runBlocking {
        val req=AiRequest(RequestStamp(0,0,0,0,0),AiInput("woxianghekafe"),LanguageRules().chinese,false)
        val client=ChatCompletionsClient()
        val google=client.request("${TestNetwork.baseUrl}/v1beta/interactions","emulator-test-key",ApiRouting.HYDROGEN,req,parameters=mapOf("reasoning_effort" to JsonPrimitive("low")))
        assertEquals("我想喝咖啡",google.candidates.single());assertEquals(7,google.usage?.output)
        val openai=client.request("${TestNetwork.baseUrl}/v1/responses","emulator-test-key","gpt-6.1-terra",req,parameters=mapOf("reasoning_effort" to JsonPrimitive("low")))
        assertEquals("我想喝咖啡",openai.candidates.single())
    }
}
