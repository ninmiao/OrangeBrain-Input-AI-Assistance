package com.osfans.trime.ai.android

import com.osfans.trime.ai.*
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/** Emulator-only local TLS fixture; never uses a real credential or model. */
class AiTransportRegressionTest {
    private val request=AiRequest(RequestStamp(1,1,1,1,1),AiInput("nihao"),"system",false)
    private suspend fun run(model:String,timeout:Int=10000)=ChatCompletionsClient().request(
        "${TestNetwork.baseUrl}/v1/chat/completions","emulator-test-key",model,request,timeout)
    private suspend fun count():Int=withContext(Dispatchers.IO) {
        val connection=URL("${TestNetwork.baseUrl}/stats").openConnection() as HttpsURLConnection
        connection.connectTimeout=2000;connection.readTimeout=2000
        try { Json.parseToJsonElement(connection.inputStream.bufferedReader().use { it.readText() }).jsonObject.getValue("requests").jsonPrimitive.int }
        finally { connection.disconnect() }
    }
    @Test fun repeatedLongCandidatesRemainUsable()=runBlocking {
        val result=run("transport-duplicates")
        assertEquals(1,result.candidates.size)
        assertTrue(result.candidates.single().contains("会议"))
    }
    @Test fun providerErrorIn200IsCategorized()=runBlocking {
        try { run("transport-provider-error");fail("Expected provider error") }
        catch(error:ApiProviderException) { assertEquals(AiFailure.RATE_LIMIT,AiFailure.from(error));assertFalse(error.toString().contains("private")) }
    }
    @Test fun typingAgainCancelsOldHttpRequestImmediately()=runBlocking {
        val initial=count()
        val old=launch { run("transport-slow-body") }
        withTimeout(4000) { while(count()==initial)delay(20) }
        delay(100)
        val started=System.nanoTime();old.cancelAndJoin()
        val elapsed=(System.nanoTime()-started)/1_000_000
        assertTrue("Cancellation took $elapsed ms",elapsed<1000)
        assertEquals(listOf("你好，世界"),run("mock",3000).candidates)
        println("Android HTTP cancellation completed in $elapsed ms; subsequent request passed")
    }
    @Test fun slowBodyHasARealTotalDeadline()=runBlocking {
        val started=System.nanoTime()
        try { run("transport-slow-body",1000);fail("Expected timeout") }
        catch(error:java.io.InterruptedIOException) { assertEquals(AiFailure.TIMEOUT,AiFailure.from(error)) }
        assertTrue((System.nanoTime()-started)/1_000_000<2500)
    }
}
