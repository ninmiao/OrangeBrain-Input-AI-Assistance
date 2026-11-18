package com.osfans.trime.ai.android

import androidx.test.platform.app.InstrumentationRegistry
import android.os.Bundle
import com.osfans.trime.ai.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in emulator-only test. A one-use local TLS fixture supplies a key in memory;
 * no key is stored in app preferences, test sources, arguments or reports. */
class LiveKaomojiTest {
    @Test fun kaomojiChineseAndPinyin() = runBlocking {
        val url=InstrumentationRegistry.getArguments().getString("live_key_url")
        assumeTrue(url!=null)
        require(url!!.matches(Regex("https://10\\.0\\.2\\.2:8443/live-key/[a-f0-9]{64}")))
        val key=HttpsDownload.get(url,8192).toString(Charsets.UTF_8)
        val store=AiStore.get(InstrumentationRegistry.getInstrumentation().targetContext)
        val cases=listOf(true to "颜表情 笑死",true to "yanbiaoqing xiaosi",false to "kaomoji laughing",true to "颜表情 伤心")
        for ((index,pair) in cases.withIndex()) {
            val (chinese,raw)=pair
            val request=AiRequest(RequestStamp(0,index.toLong(),0,0,0),AiInput(raw),store.builtin.compose(chinese, assistantEnabled=true),false,assistantEnabled=true)
            val start=android.os.SystemClock.elapsedRealtime()
            val result=ChatCompletionsClient().request(ApiRouting.OPENROUTER,key,ApiRouting.DEEPSEEK,request,10000,
                mapOf("reasoning_effort" to JsonPrimitive("none"),"service_tier" to JsonPrimitive("default")),ApiRouting.WAFER)
            assertEquals(2,result.candidates.size)
            val candidate=result.candidates[1]
            assertTrue("Expected symbols, got: $candidate",candidate.any { !it.isLetterOrDigit() && !it.isWhitespace() })
            assertFalse("Must not echo trigger: $candidate",candidate.contains("颜表情") || candidate.contains("yanbiaoqing"))
            assertTrue("Expected a compact expression: $candidate",candidate.length in 2..60)
            InstrumentationRegistry.getInstrumentation().sendStatus(0,Bundle().apply {
                putString("stream","Live OpenRouter emulator: case=$index result=$candidate elapsedMs=${android.os.SystemClock.elapsedRealtime()-start} candidates=2\n")
            })
        }
    }
}
