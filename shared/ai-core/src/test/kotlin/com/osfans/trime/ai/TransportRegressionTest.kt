package com.osfans.trime.ai

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import kotlin.test.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate

class TransportRegressionTest {
    private val request = AiRequest(RequestStamp(1,1,1,1,1),AiInput("nihao"),"system",false)
    private fun envelope(content:String="你好") =
        """{"choices":[{"finish_reason":"stop","message":{"content":${kotlinx.serialization.json.JsonPrimitive(content)}}}]}"""

    @Test fun duplicateLongCandidatesKeepFirstAndPreserveOrder() {
        val text="我今天下午有一个重要的会议，需要和 team 一起讨论项目进度以及下周计划，请你明天早上九点之前把整理好的文件发给我。"
        val client=ChatCompletionsClient()
        val result=client.decodeEnvelope(envelope(text).toByteArray(),request)
        assertEquals(listOf(text),result.candidates)
    }
    @Test fun classifiesProviderErrorInsideHttp200WithoutLeakingMessage() {
        val error=assertFailsWith<ApiProviderException> {
            ChatCompletionsClient().decodeEnvelope("""{"error":{"code":429,"message":"private-input-and-key"}}""".toByteArray(),request)
        }
        assertEquals(AiFailure.RATE_LIMIT,AiFailure.from(error));assertFalse(error.toString().contains("private-input"))
    }
    @Test fun truncatedAndMalformedResponsesRemainFailures() {
        assertFailsWith<ApiTruncatedException> { ChatCompletionsClient().decodeEnvelope("""{"choices":[{"finish_reason":"length"}]}""".toByteArray(),request) }
        assertFailsWith<ApiResponseException> { ChatCompletionsClient().decodeEnvelope(envelope(" ").toByteArray(),request) }
    }
    private fun fixture(block: suspend (MockWebServer,ChatCompletionsClient,OkHttpClient)->Unit) = runBlocking {
        val cert=HeldCertificate.Builder().addSubjectAlternativeName("localhost").addSubjectAlternativeName("127.0.0.1").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(cert).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        val http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager)
            .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
        MockWebServer().use { server ->
            server.useHttps(serverTls.sslSocketFactory(),false);server.start()
            try { block(server,ChatCompletionsClient(http),http) }
            finally { http.dispatcher.executorService.shutdownNow();http.connectionPool.evictAll() }
        }
    }
    @Test fun cancellationStopsBlockedBodyAndNextRequestDoesNotQueueBehindIt() = fixture { server,client,http ->
        server.enqueue(MockResponse().setBody(envelope()).setBodyDelay(3,TimeUnit.SECONDS))
        server.enqueue(MockResponse().setBody(envelope()))
        val scope=CoroutineScope(currentCoroutineContext())
        val pending=scope.launch { client.request(server.url("/v1/chat/completions").toString(),"test","model",request,10000) }
        withContext(Dispatchers.IO) { assertNotNull(server.takeRequest(5,TimeUnit.SECONDS)) }
        delay(100)
        val start=System.nanoTime();pending.cancelAndJoin()
        withTimeout(1000) { while(http.dispatcher.runningCallsCount()!=0) delay(10) }
        assertTrue((System.nanoTime()-start)/1_000_000<1000,"Cancelled socket remained active")
        assertEquals(listOf("你好"),client.request(server.url("/v1/chat/completions").toString(),"test","model",request,2000).candidates)
    }
    @Test fun timeoutBeforeHeadersIdentifiesWaitingForProvider() = fixture { server,client,_ ->
        server.enqueue(MockResponse().setBody(envelope()).setHeadersDelay(3,TimeUnit.SECONDS))
        val error=assertFailsWith<ApiTimeoutException> { client.request(server.url("/v1/chat/completions").toString(),"test","model",request,1000) }
        assertEquals(RequestPhase.WAITING,error.phase)
        assertFalse(error.message.orEmpty().contains("test"))
    }
    @Test fun totalDeadlineCoversSlowBody() = fixture { server,client,_ ->
        server.enqueue(MockResponse().setBody(envelope()).setBodyDelay(3,TimeUnit.SECONDS))
        val start=System.nanoTime()
        val error=assertFailsWith<java.io.InterruptedIOException> { client.request(server.url("/v1/chat/completions").toString(),"test","model",request,1000) }
        assertEquals(AiFailure.TIMEOUT,AiFailure.from(error))
        assertEquals(RequestPhase.RECEIVING,(error as ApiTimeoutException).phase)
        assertTrue((System.nanoTime()-start)/1_000_000<2500)
    }
}
