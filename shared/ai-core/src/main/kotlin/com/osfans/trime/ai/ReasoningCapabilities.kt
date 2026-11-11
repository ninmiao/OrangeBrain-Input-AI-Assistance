package com.osfans.trime.ai
import java.net.URI
import kotlinx.serialization.json.*

/** Verified 2026-11-09. Unknown models never inherit a universal effort selector. */
object ReasoningCapabilities {
    val all = listOf("none","minimal","low","medium","high","xhigh","max")
    fun choices(levels: List<String>) = levels.map { value -> ParameterChoice(when(value) {
        "none" -> "无思考"; "minimal" -> "极轻"; "low" -> "轻度"; "medium" -> "普通";
        "high" -> "深度"; "xhigh" -> "很高"; "max" -> "最高"; else -> value
    },value) }
    fun known(endpoint:String,model:String):List<String>? {
        val host=runCatching { URI(endpoint).host }.getOrNull()
        val router=host=="openrouter.ai"
        if (!router && host!="api.openai.com") return null
        val id=if(router) model.removePrefix("openai/") else model
        return when {
            router && model in setOf("deepseek/deepseek-v4-flash-0731","deepseek/deepseek-v4-flash-20260731") -> listOf("none","low","high","max")
            id.matches(Regex("gpt-4(?:\\.1|o)(?:-.*)?")) -> emptyList()
            id.matches(Regex("gpt-6(?:\\.1)?-(?:astra|sol)(?:-.*)?")) && !id.startsWith("gpt-6-sol") -> listOf("low","medium","high","xhigh","max")
            id.matches(Regex("gpt-6-(?:luna|sol)(?:-.*)?")) || id.matches(Regex("gpt-6\\.1-terra(?:-.*)?")) || id.matches(Regex("gpt-5\\.6(?:-(?:luna|sol|terra))?(?:-20[0-9-]+)?")) -> listOf("none","low","medium","high","xhigh","max")
            id.matches(Regex("gpt-5\\.4(?:-(?:nano|mini))?(?:-20[0-9-]+)?")) -> listOf("none","low","medium","high","xhigh")
            id.matches(Regex("gpt-5(?:-mini|-nano)?(?:-20[0-9-]+)?")) -> listOf("minimal","low","medium","high")
            id.matches(Regex("(?:o1|o3|o4-mini)(?:-20[0-9-]+)?")) -> listOf("low","medium","high")
            else -> null
        }
    }
    fun definition(endpoint:String,model:String,catalog:ModelCatalog):ModelDefinition? {
        val existing=catalog.models.firstOrNull { it.id==model }
        if (runCatching { URI(endpoint).host }.getOrNull() == "openrouter.ai" && catalog.version.startsWith("models-") && existing!=null) return existing
        val levels=known(endpoint,model) ?: return existing
        val base=existing ?: ModelDefinition(model)
        return base.copy(parameters=base.parameters.filterNot { it.key=="reasoning_effort" } +
            if(levels.isEmpty()) emptyList() else listOf(ModelParameter("reasoning_effort","思考强度",choices=choices(levels))))
    }
    fun options(endpoint:String,model:String,catalog:ModelCatalog=ModelCatalog()):List<ParameterChoice> =
        (definition(endpoint,model,catalog)?.parameters?.firstOrNull { it.key=="reasoning_effort" }?.choices ?: emptyList()) + ParameterChoice("服务端默认（不发送）","omit")
    fun fromModels(bytes:ByteArray):List<ModelDefinition> {
        val data=Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject.getValue("data").jsonArray
        return data.map { item ->
            val obj=item.jsonObject;val id=obj.getValue("id").jsonPrimitive.content
            val reasoning=obj["reasoning"] as? JsonObject
            val levels=when(val efforts=reasoning?.get("supported_efforts")) {
                JsonNull -> all
                is JsonArray -> efforts.map { it.jsonPrimitive.content }.filter { it in all }
                else -> emptyList()
            }.filterNot { it=="none" && reasoning?.get("mandatory")?.jsonPrimitive?.booleanOrNull==true }
            ModelDefinition(id,parameters=if(levels.isEmpty()) emptyList() else listOf(ModelParameter("reasoning_effort","思考强度",choices=choices(levels.distinct()))))
        }
    }
}
