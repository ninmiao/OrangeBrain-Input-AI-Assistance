// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.content.Context
import android.util.AtomicFile
import com.osfans.trime.ai.*
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import java.util.UUID

@Serializable
data class PromptVersion(val pack: PromptPackage, val source: String)

@Serializable
data class AiPolicy(
    val id: String,
    val name: String,
    val endpoint: String,
    val model: String,
    val catalog: ModelCatalog = ModelCatalog(),
    val discoveredModels: List<String> = emptyList(),
    val modelValues: Map<String, Map<String, JsonPrimitive>> = emptyMap(),
    val active: PromptVersion? = null,
    val localOverride: PromptPackage? = null,
    val history: List<PromptVersion> = emptyList(),
    val provider: String = "",
) {
    fun applyTo(c: AiConfig) = c.copy(selectedPolicyId = id, endpoint = endpoint, model = model,
        provider = provider, modelCatalog = catalog, discoveredModels = discoveredModels, modelValues = modelValues,
        active = active, localOverride = localOverride, history = history,
        remoteUrl = "", autoUpdate = false, modelCatalogUrl = "")
}

private fun AiConfig.snapshotPolicy(name: String) = AiPolicy(selectedPolicyId, name, endpoint, model,
    modelCatalog, discoveredModels, modelValues, active, localOverride, history, provider)

object TerraDefaults {
    const val MODEL = "gpt-6.1-terra"
    const val ENDPOINT = "https://api.openai.com/v1/chat/completions"
    fun catalog() = ModelCatalog(models = listOf(ModelCatalog.template(MODEL).let { definition ->
        definition.copy(parameters = definition.parameters.filter { it.key in setOf("reasoning_effort", "service_tier", "max_completion_tokens") }
            .map { if (it.key == "reasoning_effort") it.copy(choices = it.choices.filter { choice -> choice.value in setOf("none", "low", "medium", "high", "xhigh", "max") }) else it })
    }))
    fun values() = mapOf(MODEL to mapOf("reasoning_effort" to JsonPrimitive("low"), "service_tier" to JsonPrimitive("priority")))
}

@Serializable
data class AiConfig(
    val generation: Long = 0,
    val enabled: Boolean = false,
    val consent: Boolean = false,
    val automatic: Boolean = true,
    val wordSegmentation: Boolean = true,
    val contextEnabled: Boolean = false,
    val beforeLimit: Int = 200,
    val afterLimit: Int = 50,
    val targetLimit: Int = 300,
    val debounceMs: Long = 200,
    val timeoutMs: Int = 10000,
    val endpoint: String = TerraDefaults.ENDPOINT,
    val model: String = TerraDefaults.MODEL,
    val modelCatalog: ModelCatalog = TerraDefaults.catalog(),
    val discoveredModels: List<String> = emptyList(),
    val modelValues: Map<String, Map<String, JsonPrimitive>> = TerraDefaults.values(),
    val modelCatalogUrl: String = "",
    val style: String = "original",
    val customStyle: String = "风格：忠实保留原意，自然表达。",
    val completion: Boolean = false,
    val candidateCount: Int = 1,
    val remoteUrl: String = "",
    val autoUpdate: Boolean = false,
    val lastCheck: Long = 0,
    val active: PromptVersion? = null,
    val localOverride: PromptPackage? = null,
    val history: List<PromptVersion> = emptyList(),
    val traditional: Boolean = false,
    val selectedPolicyId: String = "default",
    val policies: List<AiPolicy> = emptyList(),
    val policyVersion: Int = 0,
    val provider: String = "",
)

class AiStore internal constructor(private val context: Context) {
    private val file = AtomicFile(File(context.noBackupFilesDir, "ai-config.json"))
    val builtin = PromptPackage.parse(context.assets.open("ai/default-prompts.json").use { it.readBytes() })
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }
    private val state = MutableStateFlow(runCatching {
        json.decodeFromString<AiConfig>(file.openRead().use { it.readBytes().toString(Charsets.UTF_8) })
    }.getOrDefault(AiConfig()))
    val changes = state.asStateFlow()
    val config: AiConfig get() = state.value
    val credentials get() = credentialsFor(config)
    fun credentialsFor(c: AiConfig) = credentialsForPolicy(c.selectedPolicyId)
    fun credentialsForPolicy(id: String): CredentialStore {
        require(id.matches(Regex("[a-zA-Z0-9-]{1,64}")))
        return if (id == "default") CredentialStore(context) else
            CredentialStore(context, "rime-ai-policy-$id", "ai-credential-$id.bin")
    }
    init {
        // Migrate old multi-candidate/completion preferences without touching policies or keys.
        if (config.candidateCount != 1 || config.completion) update { it }
        if (config.policyVersion == 0 || config.policies.isEmpty()) update { original ->
            var c = original.copy(remoteUrl = "", autoUpdate = false, modelCatalogUrl = "", policyVersion = 1)
            if (c.model.isBlank()) c = c.copy(endpoint = TerraDefaults.ENDPOINT, model = TerraDefaults.MODEL)
            if (c.model == TerraDefaults.MODEL && c.endpoint == TerraDefaults.ENDPOINT && c.modelValues[c.model].isNullOrEmpty())
                c = c.copy(modelCatalog = TerraDefaults.catalog(), modelValues = TerraDefaults.values())
            c.copy(policies = listOf(c.snapshotPolicy("默认 Policy")))
        }
        if (config.policyVersion < 2) update { c ->
            val router = AiConfig(selectedPolicyId = "openrouter", endpoint = ApiRouting.OPENROUTER,
                model = ApiRouting.DEEPSEEK, provider = ApiRouting.WAFER,
                modelCatalog = ModelCatalog(models = listOf(ModelDefinition(ApiRouting.DEEPSEEK, parameters = listOf(
                    ModelParameter("reasoning_effort", "思考强度", choices = listOf(ParameterChoice("无思考", "none"), ParameterChoice("轻度", "low"), ParameterChoice("普通", "medium"), ParameterChoice("深度", "high"))),
                    ModelParameter("service_tier", "路由速度", choices = listOf(ParameterChoice("普通", "default"), ParameterChoice("优先低延迟", "priority"))),
                    ModelParameter("max_tokens", "输出 Token 上限", "integer", min = 1.0, max = 32768.0)
                )))), modelValues = mapOf(ApiRouting.DEEPSEEK to mapOf("reasoning_effort" to JsonPrimitive("none"), "service_tier" to JsonPrimitive("default"))))
                .snapshotPolicy("OpenRouter · DeepSeek Flash")
            c.copy(policyVersion = 2, policies = c.policies.map { if (it.id == "default" && it.name == "默认 Policy") it.copy(name = "OpenAI · 6 Luna") else it } +
                if (c.policies.any { ApiRouting.isOpenRouter(it.endpoint) }) emptyList() else listOf(router))
        }
        if (config.policyVersion < 3) update { c ->
            val policies = c.policies.map { p ->
                val values = p.modelValues[p.model]
                if (p.endpoint == TerraDefaults.ENDPOINT && p.model == "gpt-6-luna" &&
                    values?.get("reasoning_effort")?.content in listOf(null, "none") &&
                    values?.get("service_tier")?.content in listOf(null, "default"))
                    p.copy(name = if (p.name in listOf("默认 Policy", "OpenAI · 6 Luna")) "OpenAI · 6.1 Terra" else p.name,
                        model = TerraDefaults.MODEL, catalog = TerraDefaults.catalog(),
                        modelValues = p.modelValues + TerraDefaults.values()) else
                    if (p.model == TerraDefaults.MODEL && p.name == "OpenAI · 6 Luna") p.copy(name = "OpenAI · 6.1 Terra") else p
            }
            policies.first { it.id == c.selectedPolicyId }.applyTo(c).copy(policies = policies, policyVersion = 3)
        }
    }
    fun effective(c: AiConfig = config) = c.localOverride ?: c.active?.pack ?: builtin
    fun prompt(c: AiConfig, chinese: Boolean): String {
        val pack = effective(c)
        val style = c.style.takeIf { it == "custom" || pack.styles.any { s -> s.id == it } } ?: "original"
        return pack.compose(style, chinese, false, c.customStyle, c.traditional, 1)
    }

    fun policyParameterSummary(policy: AiPolicy): String {
        val c = policy.applyTo(config)
        val values = parameters(c)
        val definition = definition(c)
        fun display(key: String, fallback: String = "服务端默认"): String {
            val value = values[key]?.content ?: return fallback
            return when (key) {
                "reasoning_effort" -> ReasoningCapabilities.choices(listOf(value)).single().label
                "service_tier" -> when (value) {
                    "default" -> "普通"; "priority" -> "Fast / 优先"; "auto" -> "自动"; "flex" -> "Flex / 弹性"
                    else -> definition?.parameters?.firstOrNull { it.key == key }?.choices?.firstOrNull { it.value == value }?.label ?: value
                }
                else -> value
            }
        }
        val thinking = values["enable_thinking"]?.content?.let { if (it == "false") "无思考" else "已开启" }
        return "思考：${display("reasoning_effort", thinking ?: "服务端默认")} · 速度：${display("service_tier")}"
    }

    fun configForPolicy(id: String): AiConfig { val c = config; return c.policies.first { it.id == id }.applyTo(c) }
    @Synchronized fun updatePolicyConfig(id: String, transform: (AiConfig) -> AiConfig) {
        if (config.selectedPolicyId == id) { update(transform); return }
        update { c ->
            val policy = c.policies.first { it.id == id }
            var edited = transform(policy.applyTo(c))
            if (edited.endpoint != policy.endpoint) edited = edited.copy(modelCatalog = ModelCatalog(), modelValues = emptyMap(), discoveredModels = emptyList())
            edited.modelCatalog.validate()
            edited = edited.copy(modelValues = edited.modelValues.mapNotNull { (model, values) ->
                ReasoningCapabilities.definition(edited.endpoint,model,edited.modelCatalog)?.let { model to it.filterValues(values) }
            }.toMap())
            edited.modelValues.values.forEach { ModelParameters.validateWire(it) }
            val replacement = edited.snapshotPolicy(policy.name)
            c.copy(policies = c.policies.map { if (it.id == id) replacement else it })
        }
    }
    fun refreshKnownCapabilities(id: String) = updatePolicyConfig(id) { c ->
        require(c.model.isNotBlank())
        val definition = definition(c) ?: ModelDefinition(c.model)
        c.copy(modelCatalog = c.modelCatalog.copy(models = c.modelCatalog.models.filterNot { it.id == c.model } + definition))
    }
    fun selectPolicy(id: String) = update { c -> c.policies.first { it.id == id }.applyTo(c) }
    fun renamePolicy(id: String, name: String) = update { c ->
        require(name.isNotBlank() && name.length <= 80)
        c.copy(policies = c.policies.map { if (it.id == id) it.copy(name = name.trim()) else it })
    }
    fun addPolicy(name: String): String {
        val id = UUID.randomUUID().toString()
        update { c ->
            require(c.policies.size < 20)
            c.copy(policies = c.policies + AiConfig(selectedPolicyId = id).snapshotPolicy(name))
        }
        return id
    }
    @Synchronized fun duplicatePolicy(sourceId: String): String {
        val source = config.policies.first { it.id == sourceId }
        require(config.policies.size < 20) { "最多保存 20 个 Policy" }
        val sourceCredentials = credentialsForPolicy(sourceId)
        val secret = if (sourceCredentials.hasCredential())
            sourceCredentials.read(source.endpoint) ?: error("原 Policy 密钥无法读取，请重新配置后再复制") else null
        val id = UUID.randomUUID().toString()
        val base = source.name.take(65) + " 副本"
        var name = base
        var suffix = 2
        while (config.policies.any { it.name == name }) name = "$base ${suffix++}"
        val destination = credentialsForPolicy(id)
        try {
            if (secret != null) destination.save(source.endpoint, secret)
            update { it.copy(policies = it.policies + source.copy(id = id, name = name)) }
        } catch (e: Exception) {
            runCatching { destination.clear() }
            throw e
        }
        return id
    }

    fun deletePolicy(id: String) {
        update { c ->
            require(c.policies.size > 1)
            val remaining = c.policies.filterNot { it.id == id }
            if (c.selectedPolicyId == id) remaining.first().applyTo(c).copy(policies = remaining) else c.copy(policies = remaining)
        }
        credentialsForPolicy(id).clear()
        BenchmarkStore(context, id).clear()
    }

    // Only publish after atomic disk commit. No observer can see half-applied configuration.
    @Synchronized
    fun update(transform: (AiConfig) -> AiConfig) {
        val old = config
        var next = transform(old).copy(generation = old.generation + 1, candidateCount = 1, completion = false)
        // Capabilities and values belong to this exact endpoint, not just a model name.
        if (next.endpoint != old.endpoint && next.selectedPolicyId == old.selectedPolicyId && !(old.policyVersion == 0 && next.policyVersion == 1)) next = next.copy(modelCatalog = ModelCatalog(), discoveredModels = emptyList(), modelValues = emptyMap(), modelCatalogUrl = "")
        next.modelCatalog.validate()
        next = next.copy(modelValues = next.modelValues.mapNotNull { (id, values) ->
            ReasoningCapabilities.definition(next.endpoint,id,next.modelCatalog)?.let { id to it.filterValues(values) }
        }.toMap())
        next.modelValues.values.forEach { ModelParameters.validateWire(it) }
        require(next.debounceMs in 50..2000 && next.timeoutMs in 1000..60000)
        require(next.beforeLimit in 0..200 && next.afterLimit in 0..50 && next.targetLimit in 1..300)
        if (next.style != "custom" && effective(next).styles.none { it.id == next.style }) next = next.copy(style = "original")
        require(next.policies.map { it.id }.distinct().size == next.policies.size)
        if (next.policies.isNotEmpty()) {
            val name = next.policies.first { it.id == next.selectedPolicyId }.name
            val snapshot = next.snapshotPolicy(name)
            next = next.copy(policies = next.policies.map { if (it.id == snapshot.id) snapshot else it })
        }
        val stream = file.startWrite()
        try {
            stream.write(json.encodeToString(next).toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
        } catch (e: Exception) {
            file.failWrite(stream)
            throw e
        }
        state.value = next
    }

    fun edit(pack: PromptPackage) = update { it.copy(localOverride = pack) }
    fun clearOverride() = update { it.copy(localOverride = null) }
    fun restoreBuiltin() = update { it.copy(active = null, localOverride = null) }
    fun rollback() = update {
        require(it.history.isNotEmpty()) { "没有可回滚版本" }
        it.copy(active = it.history.first(), history = it.history.drop(1))
    }
    fun activate(pack: PromptPackage, source: String, automatic: Boolean) = update {
        val old = it.active
        if (automatic) {
            require(old == null || (old.source == source && old.pack.package_id == pack.package_id)) { "来源或包 ID 变化，请手动导入" }
            require(pack.revision > (old?.pack?.revision ?: if (pack.package_id == builtin.package_id) builtin.revision else -1)) { "没有更新版本" }
        }
        it.copy(active = PromptVersion(pack, source), history = (listOfNotNull(old) + it.history).take(5))
    }

    suspend fun checkRemote(automatic: Boolean) = withContext(Dispatchers.IO) {
        val url = config.remoteUrl
        update { it.copy(lastCheck = System.currentTimeMillis()) }
        val pack = PromptPackage.parse(HttpsDownload.get(url, 128 * 1024))
        // Do not activate a result fetched from a URL which changed during the download.
        synchronized(this@AiStore) {
            require(url == config.remoteUrl) { "更新来源已改变" }
            activate(pack, url, automatic)
        }
    }

    fun definition(c:AiConfig) = ReasoningCapabilities.definition(c.endpoint,c.model,c.modelCatalog)
    fun parameters(c: AiConfig = config): Map<String, JsonPrimitive> = definition(c)?.filterValues(c.modelValues[c.model] ?: emptyMap()) ?: emptyMap()
    fun replaceModelCatalog(catalog: ModelCatalog, endpoint: String, policyId: String = config.selectedPolicyId) = updatePolicyConfig(policyId) {
        require(it.endpoint == endpoint && endpoint.isNotBlank()) { "连接已变化，请重新打开" }
        it.copy(modelCatalog = catalog.validate())
    }
    fun saveParameters(endpoint: String, model: String, values: Map<String, JsonPrimitive>, policyId: String = config.selectedPolicyId) = updatePolicyConfig(policyId) {
        require(it.endpoint == endpoint && it.model == model) { "模型或连接已变化" }
        val definition = definition(it) ?: error("请先维护模型参数列表")
        require(definition.filterValues(values) == values) { "参数不在已维护的可用列表内" }
        ModelParameters.validateWire(values)
        it.copy(modelCatalog=it.modelCatalog.copy(models=it.modelCatalog.models.filterNot { m -> m.id==model }+definition), modelValues = it.modelValues + (model to values.toMap()))
    }
    suspend fun refreshModels(policyId: String = config.selectedPolicyId): Int {
        val captured = configForPolicy(policyId)
        val key = withContext(Dispatchers.IO) { credentialsFor(captured).read(captured.endpoint) } ?: error("请先配置密钥")
        val discovered = ModelsClient().discover(captured.endpoint, key)
        val ids=discovered.ids
        withContext(Dispatchers.IO) { updatePolicyConfig(policyId) {
            require(it.generation == captured.generation) { "配置已变化，请重新刷新" }
            it.copy(discoveredModels = ids, modelCatalog = if(discovered.definitions.isEmpty()) it.modelCatalog else ModelCatalog(version="models-2026-11-09",models=discovered.definitions.map { fresh ->
                val previous=it.modelCatalog.models.firstOrNull { old -> old.id==fresh.id }
                fresh.copy(parameters=(previous?.parameters?.filterNot { p -> p.key=="reasoning_effort" } ?: emptyList())+fresh.parameters)
            }))
        } }
        return ids.size
    }

    fun export(): String = Json { prettyPrint = true; encodeDefaults = true }.encodeToString(effective())

    companion object {
        @Volatile private var instance: AiStore? = null
        fun get(context: Context): AiStore = instance ?: synchronized(this) {
            instance ?: AiStore(context.applicationContext).also { instance = it }
        }
    }
}
