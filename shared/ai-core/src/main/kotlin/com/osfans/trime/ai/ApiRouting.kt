package com.osfans.trime.ai
import kotlinx.serialization.json.*
object ApiRouting {
 const val OPENAI="https://api.openai.com/v1/responses"
 const val OPENROUTER="https://openrouter.ai/api/v1/chat/completions"
 const val GEMINI="https://generativelanguage.googleapis.com/v1beta/interactions"
 const val HYDROGEN="gemini-4-hydrogen"
 const val DEEPSEEK="deepseek/deepseek-v4-flash-0731"
 const val WAFER="wafer/us"
 private fun routing(endpoint:String)=NativeCore.invoke("routing",buildJsonObject{put("endpoint",endpoint)}).jsonObject
 fun api(endpoint:String)=routing(endpoint).getValue("api").jsonPrimitive.content
 fun isGemini(endpoint:String)=api(endpoint)=="gemini"
 fun isOpenRouter(endpoint:String)=api(endpoint)=="openrouter"
 fun isResponses(endpoint:String)=routing(endpoint).getValue("responses").jsonPrimitive.boolean
 fun requestUrl(endpoint:String)=routing(endpoint).getValue("url").jsonPrimitive.content
 fun wire(endpoint:String,values:Map<String,JsonPrimitive>,provider:String="")=NativeCore.invoke("wire",buildJsonObject{put("endpoint",endpoint);put("values",JsonObject(values));put("provider",provider)}).jsonObject
}
