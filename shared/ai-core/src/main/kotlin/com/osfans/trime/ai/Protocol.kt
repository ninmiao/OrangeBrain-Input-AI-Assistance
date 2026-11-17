package com.osfans.trime.ai
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
@Serializable data class AiInput(val input:String,val before:String="",val after:String="")
@Serializable data class TokenUsage(val input:Int?=null,val output:Int?=null,val reasoning:Int?=null,val cached:Int?=null) {
 fun summary()="tokens · in ${input ?: "–"} · out ${output ?: "–"} · think ${reasoning ?: "–"} · cached ${cached ?: "–"}"
}
@Serializable data class AiResult(val candidates:List<String>,val completion:String="",val usage:TokenUsage?=null,val recovered:Boolean=false,val streaming:Boolean=false,val streamError:String="")
object Protocol {
 private val json=Json { ignoreUnknownKeys=true;encodeDefaults=true }
 fun encode(input:AiInput)=NativeCore.invoke("encode",json.encodeToJsonElement(input)).jsonPrimitive.content
 fun decode(text:String,completionEnabled:Boolean=false,candidateCount:Int=1,truncated:Boolean=false):AiResult = json.decodeFromJsonElement(NativeCore.invoke("decode",buildJsonObject{put("text",text);put("truncated",truncated)}))
 fun context(input:String,before:String,after:String,enabled:Boolean=true,beforeLimit:Int=50,afterLimit:Int=0):AiInput {
  val c=NativeCore.invoke("context",buildJsonObject{put("before",before);put("after",after);put("enabled",enabled);put("beforeLimit",beforeLimit);put("afterLimit",afterLimit)}).jsonObject
  return AiInput(input,c.getValue("before").jsonPrimitive.content,c.getValue("after").jsonPrimitive.content)
 }
}
