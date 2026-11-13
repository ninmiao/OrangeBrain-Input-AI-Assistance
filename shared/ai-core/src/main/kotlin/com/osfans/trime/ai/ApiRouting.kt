package com.osfans.trime.ai

import java.net.URI
import kotlinx.serialization.json.*

object ApiRouting {
    const val OPENAI = "https://api.openai.com/v1/responses"
    const val GEMINI = "https://generativelanguage.googleapis.com/v1beta/interactions"
    const val HYDROGEN = "gemini-4-hydrogen"
    fun isGemini(endpoint: String) = runCatching { val u = URI(endpoint); u.host.equals("generativelanguage.googleapis.com", true) || u.path.endsWith("/interactions") }.getOrDefault(false)
    fun api(endpoint: String) = if (isGemini(endpoint)) "gemini" else if (isOpenRouter(endpoint)) "openrouter" else "openai"
    fun isResponses(endpoint: String) = runCatching { val u = URI(endpoint); u.path.endsWith("/responses") || (u.host == "api.openai.com" && u.path.endsWith("/chat/completions")) }.getOrDefault(false)
    fun requestUrl(endpoint: String) = if (isResponses(endpoint) && endpoint.endsWith("/chat/completions")) endpoint.removeSuffix("chat/completions") + "responses" else endpoint
    fun validatePreset(preset: String) {
        require(preset.isEmpty() || preset.matches(Regex("@preset/[A-Za-z0-9][A-Za-z0-9_-]{0,127}"))) { "Preset must be @preset/name / Preset 请填写 @preset/名称" }
    }
    const val OPENROUTER = "https://openrouter.ai/api/v1/chat/completions"
    const val DEEPSEEK = "deepseek/deepseek-v4-flash-0731"
    const val WAFER = "wafer/us"
    fun isOpenRouter(endpoint: String) = runCatching { URI(endpoint).host.equals("openrouter.ai", true) }.getOrDefault(false)
    fun wire(endpoint: String, values: Map<String, JsonPrimitive>, provider: String = ""): JsonObject {
        ModelParameters.validateWire(values)
        if (isGemini(endpoint)) {
            require(provider.isEmpty()) { "Gemini does not support OpenRouter provider routing" }
            require(values.keys.all { it in setOf("reasoning_effort", "service_tier", "max_tokens", "max_completion_tokens") }) { "Unsupported Gemini parameter" }
            require(values["service_tier"]?.content in setOf(null, "default", "auto")) { "Gemini speed: default" }
            return buildJsonObject {
                values["reasoning_effort"]?.let { effort ->
                    require(effort.content in listOf("minimal", "low", "medium", "high", "xhigh")) { "Unsupported Gemini thinking level" }
                    put("thinking_level", effort)
                }
                (values["max_completion_tokens"] ?: values["max_tokens"])?.let { put("max_output_tokens", it) }
            }
        }
        if (isResponses(endpoint) && !isOpenRouter(endpoint)) return buildJsonObject {
            values.filterKeys { it !in setOf("reasoning_effort", "max_tokens", "max_completion_tokens", "enable_thinking") }.forEach { (k,v) -> put(k,v) }
            values["reasoning_effort"]?.let { effort -> putJsonObject("reasoning") { put("effort", effort) } }
            (values["max_completion_tokens"] ?: values["max_tokens"])?.let { put("max_output_tokens", it) }
            require("enable_thinking" !in values) { "Use reasoning_effort for OpenAI" }
        }
        if (!isOpenRouter(endpoint)) return JsonObject(values)
        require(provider.length <= 128 && provider.none { it.isWhitespace() || it.isISOControl() })
        return buildJsonObject {
            values.filterKeys { it !in setOf("reasoning_effort", "service_tier", "enable_thinking", "max_completion_tokens") }.forEach { (k,v) -> put(k,v) }
            values["max_completion_tokens"]?.let { put("max_tokens",it) }
            val effort = values["reasoning_effort"]?.content
            if (effort != null) putJsonObject("reasoning") {
                if (effort == "none") put("enabled",false) else { put("enabled",true); put("effort",effort) }
            } else values["enable_thinking"]?.let { enabled -> putJsonObject("reasoning") { put("enabled",enabled) } }
            val speed = values["service_tier"]?.content
            require(speed in setOf(null,"default","auto","priority")) { "OpenRouter 不支持此速度模式" }
            if (provider.isNotBlank() || speed == "priority") putJsonObject("provider") {
                if (provider.isNotBlank()) {
                    putJsonArray("only") { add(provider) }
                    put("allow_fallbacks",false)
                }
                if (speed == "priority") put("sort","latency")
            }
        }
    }
}
