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
    fun known(endpoint:String,model:String):List<String>? = NativeCore.invoke("known",buildJsonObject{put("endpoint",endpoint);put("model",model)}).let { if(it is JsonNull)null else it.jsonArray.map { value -> value.jsonPrimitive.content } }
    fun definition(endpoint:String,model:String,catalog:ModelCatalog):ModelDefinition? {
        val value=NativeCore.invoke("modelDefinition",buildJsonObject { put("endpoint",endpoint);put("model",model);put("catalog",Json.encodeToJsonElement(ModelCatalog.serializer(),catalog)) })
        return if(value is JsonNull)null else Json.decodeFromJsonElement(ModelDefinition.serializer(),value)
    }
    fun options(endpoint:String,model:String,catalog:ModelCatalog=ModelCatalog()):List<ParameterChoice> =
        (definition(endpoint,model,catalog)?.parameters?.firstOrNull { it.key=="reasoning_effort" }?.choices ?: emptyList()) + ParameterChoice("服务端默认（不发送）","omit")
    fun fromModels(bytes:ByteArray):List<ModelDefinition> {
        require(bytes.size<=8*1024*1024)
        return NativeCore.invoke("modelsReasoning",buildJsonObject {put("body",bytes.toString(Charsets.UTF_8))}).jsonArray.map { Json.decodeFromJsonElement(ModelDefinition.serializer(),it) }
    }
}
