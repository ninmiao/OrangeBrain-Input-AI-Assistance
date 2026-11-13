// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive

@Serializable
data class BenchmarkEntry(val model: String = "gpt-6-luna", val reasoning: String = "none", val speed: String = "default", val api: String = "openai", val policyId: String = "", val provider: String = "") {
    fun validate(): BenchmarkEntry {
        require(api in setOf("openai", "openrouter", "gemini"))
        require(policyId.isEmpty() || policyId.matches(Regex("[a-zA-Z0-9-]{1,64}")))
        require(provider.length <= 128 && provider.none { it.isWhitespace() || it.isISOControl() })
        require(api != "openrouter" || speed in setOf("default", "priority", "auto", "omit")) { "OpenRouter 速度请选择普通或优先低延迟" }
        require(model.isNotBlank() && model.length <= 256 && model.none { it.isWhitespace() || it.isISOControl() }) { "请输入有效模型 ID" }
        require(reasoning in reasoningOptions.map { it.value } && speed in speedOptions.map { it.value }) { "请选择有效推理强度和速度" }
        return this
    }
    fun parameters(): Map<String, JsonPrimitive> {
        validate()
        val endpoint=when(api) { "openrouter" -> ApiRouting.OPENROUTER; "gemini" -> ApiRouting.GEMINI; else -> ApiRouting.OPENAI }
        require(api != "gemini" || speed in setOf("default","omit")) { "Gemini 请选择普通速度" }
        val levels=ReasoningCapabilities.known(endpoint,model)
        val nonReasoning = levels?.isEmpty()==true
        require(levels==null || reasoning=="omit" || reasoning in levels || (nonReasoning && reasoning=="none")) { "此模型不支持所选思考强度，请修改此组配置" }
        require(!nonReasoning || reasoning in setOf("none", "omit")) { "此模型没有推理档位，请选择无推理" }
        val originalGpt5 = Regex("gpt-5(?:-mini|-nano)?(?:-\\d{4}-\\d{2}-\\d{2})?").matches(model)
        require(!(originalGpt5 && reasoning == "none")) { "此模型不支持关闭推理；请选择极轻或更换模型" }
        return buildMap {
            if (reasoning != "omit" && !nonReasoning) put("reasoning_effort", JsonPrimitive(reasoning))
            if (speed != "omit") put("service_tier", JsonPrimitive(speed))
        }
    }
    companion object {
        val reasoningOptions = listOf(
            ParameterChoice("无推理", "none"), ParameterChoice("极轻", "minimal"), ParameterChoice("轻度", "low"),
            ParameterChoice("普通", "medium"), ParameterChoice("深度", "high"), ParameterChoice("很高", "xhigh"),
            ParameterChoice("最高", "max"), ParameterChoice("跟随服务端（不发送参数）", "omit"))
        val speedOptions = listOf(ParameterChoice("普通", "default"), ParameterChoice("Fast / 优先（可能额外计费）", "priority"),
            ParameterChoice("自动", "auto"), ParameterChoice("Flex / 弹性", "flex"), ParameterChoice("跟随服务端（不发送参数）", "omit"))
        fun defaults() = listOf("gpt-6-luna", "gpt-5.4-nano", "gpt-4.1-mini").map { BenchmarkEntry(it) } + BenchmarkEntry(ApiRouting.DEEPSEEK, api = "openrouter", provider = ApiRouting.WAFER) + BenchmarkEntry(ApiRouting.HYDROGEN, reasoning="low", api="gemini")
    }
}

@Serializable
data class BenchmarkConfig(val entries: List<BenchmarkEntry> = BenchmarkEntry.defaults(), val sample: String = "wojintianyoumeeting", val chinese: Boolean = true, val timeoutMs: Int = 10000) {
    fun validate(): BenchmarkConfig {
        require(entries.size in 1..5) { "一次请选择 1–5 组配置" }
        entries.forEach { it.validate() }
        require(sample.isNotBlank() && sample.length <= 300) { "样例须为 1–300 个字符" }
        require(timeoutMs in 1000..60000) { "超时须为 1–60 秒" }
        return this
    }
}

data class BenchmarkResult(val entry: BenchmarkEntry, val elapsedMs: Long, val output: String? = null, val error: String? = null, val usage: TokenUsage? = null)

/** One sequential sample per entry. No retry or silent parameter fallback; no credentials retained. */
class BenchmarkRunner(private val nowNanos: () -> Long = System::nanoTime) {
    suspend fun run(config: BenchmarkConfig, send: suspend (BenchmarkEntry, Map<String, JsonPrimitive>) -> AiResult,
        onStart: (Int) -> Unit = {}, onResult: (Int, BenchmarkResult) -> Unit = { _, _ -> }): List<BenchmarkResult> {
        config.validate()
        val results = mutableListOf<BenchmarkResult>()
        config.entries.forEachIndexed { index, entry ->
            currentCoroutineContext().ensureActive()
            onStart(index)
            val start = nowNanos()
            val result = try {
                val response = send(entry, entry.parameters())
                currentCoroutineContext().ensureActive()
                require(response.candidates.isNotEmpty()) { "没有可用候选" }
                BenchmarkResult(entry, (nowNanos() - start) / 1_000_000, output = response.candidates.first(), usage = response.usage)
            } catch (cancelled: CancellationException) { throw cancelled
            } catch (e: Exception) {
                currentCoroutineContext().ensureActive()
                val elapsed = (nowNanos() - start) / 1_000_000
                val error = when {
                    e is ApiHttpException -> "HTTP ${e.status}（请检查模型权限、参数或额度）"
                    e is java.io.InterruptedIOException || elapsed >= config.timeoutMs -> "请求超时"
                    e is ApiPresetException || e is ApiProviderException || e is ApiTruncatedException || e is ApiResponseException -> AiFailure.from(e).label
                    e is java.io.IOException -> "网络连接失败"
                    e is IllegalArgumentException && runCatching { entry.parameters() }.isFailure -> "模型不支持所选推理档位"
                    else -> "响应格式无效或没有可用候选"
                }
                BenchmarkResult(entry, elapsed, error = error)
            }
            results += result
            onResult(index, result)
        }
        return results
    }
}
