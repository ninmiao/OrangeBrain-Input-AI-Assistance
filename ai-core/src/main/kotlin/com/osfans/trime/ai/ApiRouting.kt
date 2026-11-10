package com.osfans.trime.ai

import java.net.URI
import kotlinx.serialization.json.*

object ApiRouting {
    const val OPENROUTER = "https://openrouter.ai/api/v1/chat/completions"
    const val DEEPSEEK = "deepseek/deepseek-v4-flash-0731"
    const val WAFER = "wafer/us"
    fun isOpenRouter(endpoint: String) = runCatching { URI(endpoint).host.equals("openrouter.ai", true) }.getOrDefault(false)
    fun wire(endpoint: String, values: Map<String, JsonPrimitive>, provider: String = ""): JsonObject {
        ModelParameters.validateWire(values)
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
