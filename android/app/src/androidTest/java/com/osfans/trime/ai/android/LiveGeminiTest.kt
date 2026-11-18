package com.osfans.trime.ai.android
import android.os.Bundle
import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.ai.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Explicit opt-in: a one-use local TLS URL supplies the test key in memory. */
class LiveGeminiTest {
    @Test fun shortLongMixedAndKaomojiCandidates()=runBlocking {
        val ins=InstrumentationRegistry.getInstrumentation()
        val url=InstrumentationRegistry.getArguments().getString("live_key_url")
        assumeTrue(url!=null)
        require(url!!.matches(Regex("https://10\\.0\\.2\\.2:8443/live-key/[a-f0-9]{64}")))
        val key=HttpsDownload.get(url,8192).toString(Charsets.UTF_8)
        assertTrue(ModelsClient().fetch(ApiRouting.GEMINI,key).contains(ApiRouting.HYDROGEN))
        val pack=AiStore.get(ins.targetContext).builtin
        val cases=Json.parseToJsonElement(ins.context.assets.open("ai/gemini-smoke.json").bufferedReader().use { it.readText() }).jsonArray
        val results=mutableListOf<JsonObject>()
        for(item in cases) {
            val row=item.jsonObject;val raw=row.getValue("input").jsonPrimitive.content
            val chinese=row.getValue("chinese").jsonPrimitive.boolean;val traditional=row.getValue("traditional").jsonPrimitive.boolean
            val kaomoji = row["kaomoji"]?.jsonPrimitive?.booleanOrNull == true
            val start=android.os.SystemClock.elapsedRealtime()
            val result=runCatching {
                val request=AiRequest(RequestStamp(0,0,0,0,0),AiInput(raw),pack.compose(chinese,traditional,kaomoji),false,assistantEnabled=kaomoji)
                ChatCompletionsClient().request(ApiRouting.GEMINI,key,ApiRouting.HYDROGEN,request,30000,mapOf("reasoning_effort" to JsonPrimitive("low"),"service_tier" to JsonPrimitive("default")))
            }
            val record=buildJsonObject {
                put("id",row.getValue("id"));put("length",raw.length);put("language",if(chinese)"zh" else "en")
                put("elapsed_ms",android.os.SystemClock.elapsedRealtime()-start)
                put("success",result.isSuccess)
                result.onSuccess {
                    val candidate=if (kaomoji) it.candidates[1] else it.candidates.single()
                    require(candidate.isNotBlank() && !candidate.startsWith("{\"candidates\""))
                    if(!chinese)require(candidate.none { c -> c in '\u3400'..'\u9fff' })
                    if(kaomoji)require(candidate.length in 2..60 && candidate.none { c -> c in '\u3400'..'\u9fff' })
                    put("output",candidate)
                    fun normalized(s:String)=s.lowercase().filter { c -> c.isLetterOrDigit() }
                    put("normalized_match",row.getValue("expected").jsonArray.any { e -> normalized(e.jsonPrimitive.content)==normalized(candidate) })
                    it.usage?.let { usage -> put("input_tokens",usage.input?.let(::JsonPrimitive) ?: JsonNull);put("output_tokens",usage.output?.let(::JsonPrimitive) ?: JsonNull);put("thinking_tokens",usage.reasoning?.let(::JsonPrimitive) ?: JsonNull) }
                }.onFailure { put("error",it.javaClass.simpleName);if(it is ApiHttpException)put("http",it.status) }
            }
            results.add(record)
            ins.sendStatus(0,Bundle().apply { putString("stream","Gemini smoke: $record\n") })
        }
        val report=JsonArray(results).toString()
        java.io.File(ins.targetContext.cacheDir,"gemini-smoke.json").writeText(report)
        assertEquals("Some Gemini requests failed; see synthetic case report",cases.size,results.count { it.getValue("success").jsonPrimitive.boolean })
    }
}
