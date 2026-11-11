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
    fun accepts(value: JsonPrimitive): Boolean = when (type) {
        "enum" -> value.isString && choices.any { it.value == value.content }
        "boolean" -> !value.isString && value.booleanOrNull != null
        "number", "integer" -> !value.isString && value.doubleOrNull?.let {
            it.isFinite() && (min == null || it >= min) && (max == null || it <= max) &&
                (type != "integer" || value.longOrNull != null)
        } == true
        else -> false
    }
}

@Serializable
data class ModelDefinition(val id: String, val name: String = id, val parameters: List<ModelParameter> = emptyList()) {
    fun filterValues(values: Map<String, JsonPrimitive>) = values.filter { (key, value) -> parameters.any { it.key == key && it.accepts(value) } }
}

/** A manually maintained UI capability catalog, never a claim about account/model availability. */
@Serializable
data class ModelCatalog(val schema_version: Int = 1, val version: String = "local-1", val models: List<ModelDefinition> = emptyList()) {
    fun validate(): ModelCatalog {
        require(schema_version == 1 && version.isNotBlank() && version.length <= 100)
        require(models.size <= 2000 && models.map { it.id }.distinct().size == models.size)
        models.forEach { model ->
            require(model.id.isNotBlank() && model.id.length <= 256 && model.id.none { it.isISOControl() })
            require(model.name.isNotBlank() && model.name.length <= 256)
            require(model.parameters.size <= 24 && model.parameters.map { it.key }.distinct().size == model.parameters.size)
            model.parameters.forEach { p ->
                require(p.key in allowedKeys && p.label.isNotBlank() && p.label.length <= 100)
                require(p.type in setOf("enum", "number", "integer", "boolean"))
                require(p.min == null || p.min.isFinite()); require(p.max == null || p.max.isFinite())
                require(p.min == null || p.max == null || p.min <= p.max)
                if (p.type == "enum") {
                    require(p.choices.isNotEmpty() && p.choices.size <= 32 && p.choices.map { it.value }.distinct().size == p.choices.size)
                    require(p.choices.all { it.label.isNotBlank() && it.label.length <= 100 && it.value.isNotBlank() && it.value.length <= 128 })
                } else require(p.choices.isEmpty())
                when (p.key) {
                    "reasoning_effort", "service_tier" -> require(p.type == "enum")
                    "enable_thinking" -> require(p.type == "boolean")
                    "max_tokens", "max_completion_tokens" -> require(p.type == "integer" && p.min != null && p.min >= 1 && p.max != null && p.max <= 1000000)
                    else -> {
                        val range = when (p.key) { "temperature" -> 0.0..2.0; "top_p" -> 0.0..1.0; else -> -2.0..2.0 }
                        require(p.type == "number" && p.min != null && p.max != null && p.min >= range.start && p.max <= range.endInclusive)
                    }
                }
            }
        }
        require(json.encodeToString(this).toByteArray(Charsets.UTF_8).size <= MAX_BYTES)
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
    fun validateWire(values: Map<String, JsonPrimitive>) {
        require(values.keys.all { it in ModelCatalog.allowedKeys })
        require(!(values.containsKey("max_tokens") && values.containsKey("max_completion_tokens")))
        values.forEach { (key, value) ->
            require(value !is JsonNull && value.content.length <= 128)
            when (key) {
                "reasoning_effort", "service_tier" -> require(value.isString && value.content.isNotBlank())
                "enable_thinking" -> require(!value.isString && value.booleanOrNull != null)
                "max_tokens", "max_completion_tokens" -> require(!value.isString && value.longOrNull?.let { it in 1..1000000 } == true)
                else -> {
                    val number = value.doubleOrNull
                    require(!value.isString && number != null && number.isFinite())
                    require(number in when (key) { "temperature" -> 0.0..2.0; "top_p" -> 0.0..1.0; else -> -2.0..2.0 })
                }
            }
        }
    }
}
