package com.osfans.trime.ai
import kotlinx.serialization.json.*
object PolicyBenchmarks {
 fun validate(selected:List<String>,available:List<String>):List<String> = NativeCore.invoke("benchmarkPolicies",buildJsonObject {put("selected",JsonArray(selected.map(::JsonPrimitive)));put("available",JsonArray(available.map(::JsonPrimitive)))}).jsonArray.map {it.jsonPrimitive.content}
}
