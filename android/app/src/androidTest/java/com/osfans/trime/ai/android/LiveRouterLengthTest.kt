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
class LiveRouterLengthTest {
    @Test fun explicitNoReasoningLongInput() = runBlocking {
        val url=InstrumentationRegistry.getArguments().getString("live_key_url")
        assumeTrue(url!=null)
        require(url!!.matches(Regex("https://10\\.0\\.2\\.2:8443/live-key/[a-f0-9]{64}")))
        val key=HttpsDownload.get(url,8192).toString(Charsets.UTF_8)
        val store=AiStore.get(InstrumentationRegistry.getInstrumentation().targetContext)
        val seed="jintianwomenyilaitaolunzhongwenheyingwenshurufadecuowenjiuzhenggongnengxiwangkeyigengkuaisu"
        for (length in listOf(100,200)) {
            val request=AiRequest(RequestStamp(0,length.toLong(),0,0,0),AiInput(seed.repeat(4).take(length)),store.builtin.compose("original",true,false),false)
            val start=android.os.SystemClock.elapsedRealtime()
            val result=ChatCompletionsClient().request(ApiRouting.OPENROUTER,key,ApiRouting.DEEPSEEK,request,10000,
                mapOf("reasoning_effort" to JsonPrimitive("none"),"service_tier" to JsonPrimitive("default")),ApiRouting.WAFER)
            assertEquals(1,result.candidates.size);assertTrue(result.candidates.single().isNotBlank())
            InstrumentationRegistry.getInstrumentation().sendStatus(0,Bundle().apply {
                putString("stream","Live OpenRouter emulator: inputLength=$length elapsedMs=${android.os.SystemClock.elapsedRealtime()-start} candidates=1\n")
            })
        }
    }
}
