// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*

@Serializable
data class ParameterChoice(val label: String, val value: String)

@Serializable
data class ModelParameter(
    val key: String, val label: String, val type: String = "enum",
    val choices: List<ParameterChoice> = emptyList(),
    val min: Double? = null, val max: Double? = null,
) {
    fun accepts(value: JsonPrimitive): Boolean = NativeCore.invoke("accepts",buildJsonObject { put("parameter",Json.encodeToJsonElement(serializer(),this@ModelParameter));put("value",value) }).jsonPrimitive.boolean

}

@Serializable
data class ModelDefinition(val id: String, val name: String = id, val parameters: List<ModelParameter> = emptyList()) {
    fun filterValues(values: Map<String, JsonPrimitive>) = NativeCore.invoke("filterValues",buildJsonObject { put("definition",Json.encodeToJsonElement(serializer(),this@ModelDefinition));put("values",JsonObject(values)) }).jsonObject.mapValues { it.value.jsonPrimitive }

}

/** A manually maintained UI capability catalog, never a claim about account/model availability. */
@Serializable
data class ModelCatalog(val schema_version: Int = 1, val version: String = "local-1", val models: List<ModelDefinition> = emptyList()) {
    fun validate(): ModelCatalog {
        NativeCore.invoke("validateCatalog",json.encodeToJsonElement(serializer(),this))
        return this
    }
    fun export(): String = json.encodeToString(this)
    companion object {
        val allowedKeys = setOf("reasoning_effort", "service_tier", "temperature", "top_p", "max_completion_tokens", "max_tokens", "presence_penalty", "frequency_penalty", "enable_thinking")
        private val json = Json { prettyPrint = true; encodeDefaults = true }
        const val MAX_BYTES = 512 * 1024
        fun parse(bytes: ByteArray): ModelCatalog {
            require(bytes.size <= MAX_BYTES)
            return json.decodeFromString<ModelCatalog>(bytes.toString(Charsets.UTF_8)).validate()
        }
        /** Opt-in template. Users must remove unsupported values for their chosen model/provider. */
        fun template(id: String) = ModelDefinition(id, parameters = listOf(
            ModelParameter("service_tier", "服务档位", choices = listOf(ParameterChoice("普通", "default"), ParameterChoice("Fast / 优先处理（可能额外计费）", "priority"), ParameterChoice("跟随服务端项目设置", "auto"))),
            ModelParameter("reasoning_effort", "推理强度", choices = listOf(
                ParameterChoice("关闭（仅支持 none 的模型）", "none"), ParameterChoice("极轻", "minimal"),
                ParameterChoice("轻度", "low"), ParameterChoice("普通", "medium"), ParameterChoice("深度", "high"),
                ParameterChoice("很高", "xhigh"), ParameterChoice("最高", "max"))),
            ModelParameter("temperature", "Temperature", "number", min = 0.0, max = 2.0),
            ModelParameter("top_p", "Top P", "number", min = 0.0, max = 1.0),
            ModelParameter("max_completion_tokens", "输出 Token 上限（包含推理）", "integer", min = 1.0, max = 131072.0),
        ))
    }
}

object ModelParameters {
 fun validateWire(values:Map<String,JsonPrimitive>) { NativeCore.invoke("validateParameters",JsonObject(values)) }
}
