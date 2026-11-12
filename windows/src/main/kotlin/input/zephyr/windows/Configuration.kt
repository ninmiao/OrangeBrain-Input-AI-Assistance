// SPDX-License-Identifier: GPL-3.0-or-later
package input.zephyr.windows

import com.osfans.trime.ai.*
import com.sun.jna.platform.win32.Crypt32Util
import kotlinx.serialization.*
import kotlinx.serialization.json.*
import java.nio.file.*
import java.net.URI
import java.util.UUID

@Serializable data class Policy(
    val id: String = UUID.randomUUID().toString(), val name: String = "OpenAI · 6.1 Terra",
    val endpoint: String = "https://api.openai.com/v1/chat/completions", val model: String = "gpt-6.1-terra",
    val provider: String = "", val reasoning: String = "low", val speed: String = "priority",
    val chinesePrompt: String = "", val englishPrompt: String = "",
    val catalog: ModelCatalog = ModelCatalog(),
    val modelList: ModelListCache? = null,
) {
    fun validate() {
        require(id.matches(Regex("[A-Za-z0-9-]{1,64}")))
        require(name.isNotBlank() && model.isNotBlank())
        val url=URI(endpoint)
        require(url.scheme=="https" && !url.host.isNullOrBlank() && url.userInfo==null && url.query==null && url.fragment==null)
        require(speed in listOf("default","priority"))
        require(reasoning in ReasoningCapabilities.options(endpoint,model,effectiveCatalog()).map { it.value }) { "Unsupported reasoning for $model" }
        require(chinesePrompt.length<=8192 && englishPrompt.length<=8192)
        catalog.validate();modelList?.validate()
    }
    fun parameters(): Map<String,JsonPrimitive> = buildMap {
        if(reasoning!="omit") put("reasoning_effort",JsonPrimitive(reasoning))
        put("service_tier",JsonPrimitive(speed))
    }
}
@Serializable data class Configuration(
    val settingsRevision: Int = 0,
    val enabled: Boolean = false, val selectedPolicy: String = "openai", val candidateCount: Int = 1,
    val languageShortcut: String = "shift", val scriptShortcut: String = "ctrl_shift_t",
    val enterOriginal: Boolean = true, val spaceOriginal: Boolean = false,
    val wordSegmentation: Boolean = true, val debounceMs: Int = 200, val timeoutMs: Int = 10000,
    val style: String = "original", val completion: Boolean = false,
    val policies: List<Policy> = listOf(Policy(id="openai"), Policy(id="openrouter",name="OpenRouter · DeepSeek Flash",
        endpoint="https://openrouter.ai/api/v1/chat/completions",model="deepseek/deepseek-v4-flash-0731",provider="wafer/us",reasoning="none",speed="default")),
) {
    fun active() = policies.first { it.id==selectedPolicy }
    fun validate() {
        require(languageShortcut in ShortcutOptions.language.keys && scriptShortcut in ShortcutOptions.script.keys)
        require(candidateCount == 1 && !completion && debounceMs in 50..2000 && timeoutMs in 1000..60000)
        require(policies.size in 1..32 && policies.map { it.id }.distinct().size==policies.size)
        policies.forEach { it.validate() }; active()
        require(style in Prompts.pack.styles.map { it.id })
    }
}
object ShortcutOptions {
    val language=linkedMapOf("shift" to "Shift (tap) / 轻按 Shift", "shift_left" to "Left Shift / 左 Shift", "shift_right" to "Right Shift / 右 Shift", "ctrl_space" to "Ctrl+Space", "ctrl_shift_space" to "Ctrl+Shift+Space", "disabled" to "Disabled / 不使用快捷键")
    val script=linkedMapOf("ctrl_shift_t" to "Ctrl+Shift+T", "ctrl_shift_f" to "Ctrl+Shift+F", "ctrl_shift_c" to "Ctrl+Shift+C", "disabled" to "Disabled / 不使用快捷键")
}
object Prompts {
    val pack = PromptPackage.parse(requireNotNull(javaClass.getResourceAsStream("/default-prompts.json")).use { it.readBytes() })
    fun compose(config: Configuration, policy: Policy, chinese: Boolean, traditional: Boolean): String {
        val custom=if(chinese) policy.chinesePrompt else policy.englishPrompt
        return pack.compose(config.style,chinese,false,traditional=traditional,candidateCount=1) +
            (if(custom.isNotBlank()) "\n附加风格要求（仍仅一个候选，不续写）：$custom" else "")
    }
}
@Serializable private data class Credential(val origin:String,val key:String)
class ConfigurationStore(val dir: Path = Paths.get(System.getenv("APPDATA"),"ZephyrInput")) {
    private val json=Json { prettyPrint=true; encodeDefaults=true; ignoreUnknownKeys=true }
    init { Files.createDirectories(dir) }
    private fun normalize(c:Configuration):Configuration = c.copy(settingsRevision=1,candidateCount=1,completion=false,policies=c.policies.map { p ->
        if(c.settingsRevision<1 && p.endpoint=="https://api.openai.com/v1/chat/completions" && p.model=="gpt-6-luna" && p.reasoning=="none" && p.speed=="default")
            p.copy(model="gpt-6.1-terra",reasoning="low",speed="priority",name=if(p.name=="OpenAI · 6 Luna") "OpenAI · 6.1 Terra" else p.name) else p
    })
    fun load():Configuration = if(Files.exists(dir.resolve("settings.json")))
        normalize(json.decodeFromString<Configuration>(Files.readString(dir.resolve("settings.json")))).also { it.validate() }
        else normalize(Configuration())
    fun save(config:Configuration) { val normalized=normalize(config);normalized.validate();atomic("settings.json",json.encodeToString(normalized).toByteArray()) }
    private fun keyFile(id:String):String { require(id.matches(Regex("[A-Za-z0-9-]{1,64}")));return "credential-$id.bin" }
    private fun defaultEndpoint(id:String)=if(id=="openrouter")"https://openrouter.ai/v1" else "https://api.openai.com/v1"
    private fun origin(endpoint:String):String {
        val uri=URI(endpoint);require(uri.scheme=="https" && !uri.host.isNullOrBlank() && uri.userInfo==null)
        return "https://${uri.host.lowercase()}:${if(uri.port==-1)443 else uri.port}"
    }
    fun saveKey(id:String,key:String,endpoint:String=defaultEndpoint(id)) {
        require(key.isNotBlank() && key.length<8192 && key.none { it=='\r' || it=='\n' })
        val raw=json.encodeToString(Credential(origin(endpoint),key)).toByteArray()
        try { atomic(keyFile(id),Crypt32Util.cryptProtectData(raw)) } finally { raw.fill(0) }
    }
    fun key(id:String,endpoint:String=defaultEndpoint(id)):String {
        val file=dir.resolve(keyFile(id));if(!Files.exists(file)) return ""
        val raw=Crypt32Util.cryptUnprotectData(Files.readAllBytes(file))
        return try {
            val text=raw.toString(Charsets.UTF_8)
            val credential=if(text.startsWith("{"))json.decodeFromString<Credential>(text) else {
                require(id in listOf("openai","openrouter")) { "Save a key for this API origin" }
                Credential(origin(defaultEndpoint(id)),text) // Legacy local provisioning, known origins only.
            }
            require(credential.origin==origin(endpoint)) { "Endpoint origin changed; save a key for this API origin" }
            credential.key
        } finally { raw.fill(0) }
    }
    @Synchronized fun duplicatePolicy(sourceId:String):Policy {
        val config=load()
        require(config.policies.size<32) { "At most 32 policies / 最多 32 个 Policy" }
        val source=config.policies.first { it.id==sourceId }
        val secret=key(sourceId,source.endpoint)
        val id=UUID.randomUUID().toString()
        val base=source.name + " 副本"
        var name=base;var suffix=2
        while(config.policies.any { it.name==name })name="$base ${suffix++}"
        val copy=source.copy(id=id,name=name)
        try {
            if(secret.isNotEmpty())saveKey(id,secret,copy.endpoint)
            save(config.copy(policies=config.policies+copy))
        } catch(e:Exception) {
            runCatching { Files.deleteIfExists(dir.resolve(keyFile(id))) }
            throw e
        }
        return copy
    }
    fun recordRequestStatus(state:String) {
        require(state.matches(Regex("[A-Za-z0-9 ._-]{1,100}")))
        atomic("last-request-status.json", buildJsonObject { put("time",java.time.Instant.now().toString());put("state",state) }.toString().toByteArray())
    }
    private fun atomic(name:String,data:ByteArray) {
        val temp=Files.createTempFile(dir,"write-",".tmp")
        try { Files.write(temp,data);Files.move(temp,dir.resolve(name),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING) }
        finally { Files.deleteIfExists(temp) }
    }
}
