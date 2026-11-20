package com.osfans.trime.ai

import kotlin.test.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate

class ApiAdaptersTest {
    private val request=AiRequest(RequestStamp(1,1,1,1,1),AiInput("我 tomorrow 有 meeting 123","前文","后文"),"short correction prompt",false)
    private val values=mapOf("reasoning_effort" to JsonPrimitive("low"),"service_tier" to JsonPrimitive("default"))
    @Test fun openAIRequestsHaveNoHistoryContextOrGeneratedSchema() {
        val p=ChatCompletionsClient().payload("gpt-6.1-terra",request,values,ApiRouting.OPENAI)
        assertEquals(Protocol.encode(request.input),p["input"]!!.jsonPrimitive.content)
        assertTrue(p["instructions"]!!.jsonPrimitive.content.startsWith(request.systemPrompt))
        assertEquals(false,p["store"]!!.jsonPrimitive.boolean)
        assertEquals("low",p["reasoning"]!!.jsonObject["effort"]!!.jsonPrimitive.content)
        assertFalse(p.keys.any { it in setOf("previous_response_id","conversation","response_format","messages","before","after") })
        assertEquals(ApiRouting.OPENAI,ApiRouting.requestUrl("https://api.openai.com/v1/chat/completions"))
    }
    @Test fun routerAlwaysSendsFullPromptWithCompactContextAndNoPreset() {
        val p=ChatCompletionsClient().payload(ApiRouting.DEEPSEEK,request,values,ApiRouting.OPENROUTER,ApiRouting.WAFER)
        val messages=p["messages"]!!.jsonArray
        assertEquals(2,messages.size);assertEquals("system",messages.first().jsonObject["role"]!!.jsonPrimitive.content)
        assertEquals(Protocol.encode(request.input),messages.last().jsonObject["content"]!!.jsonPrimitive.content)
        assertContains(messages.first().jsonObject["content"]!!.jsonPrimitive.content,PromptPackage.OUTPUT_RULE)
        assertFalse(p.containsKey("preset"))
        assertEquals(ApiRouting.WAFER,p["provider"]!!.jsonObject["only"]!!.jsonArray.single().jsonPrimitive.content)
        assertTrue(p["reasoning"]!!.jsonObject["exclude"]!!.jsonPrimitive.boolean)
    }
    @Test fun contextDefaultsTrimUnicodeAndCanBeDisabled() {
        val input=Protocol.context("nihao","😀".repeat(60),"after")
        assertEquals("😀".repeat(50),input.before);assertEquals("",input.after)
        assertEquals(AiInput("nihao"),Protocol.context("nihao","private","secret",false))
        assertEquals("af",Protocol.context("i","b","after",afterLimit=2).after)
    }
    @Test fun geminiThinkingAndModelListAreNative() {
        val p=ChatCompletionsClient().payload(ApiRouting.HYDROGEN,request,values,ApiRouting.GEMINI)
        assertEquals("low",p["generation_config"]!!.jsonObject["thinking_level"]!!.jsonPrimitive.content)
        assertEquals(false,p["store"]!!.jsonPrimitive.boolean)
        assertFalse(p.toString().contains("service_tier"));assertFalse(p.toString().contains("previous_interaction_id"))
        assertEquals(listOf("low","medium","high","xhigh","omit"),ReasoningCapabilities.options(ApiRouting.GEMINI,ApiRouting.HYDROGEN).map { it.value })
        assertFails { ApiRouting.wire(ApiRouting.GEMINI,mapOf("reasoning_effort" to JsonPrimitive("none"))) }
        assertFails { ChatCompletionsClient().payload(ApiRouting.HYDROGEN,request,mapOf("reasoning_effort" to JsonPrimitive("minimal")),ApiRouting.GEMINI) }
        assertEquals("minimal",ChatCompletionsClient().payload("gemini-3.6-flash",request,mapOf("reasoning_effort" to JsonPrimitive("minimal")),ApiRouting.GEMINI)["generation_config"]!!.jsonObject["thinking_level"]!!.jsonPrimitive.content)
        assertFails { ApiRouting.wire(ApiRouting.GEMINI,mapOf("service_tier" to JsonPrimitive("priority"))) }
        assertEquals("https://generativelanguage.googleapis.com/v1beta/models",ModelsClient.listUrl(ApiRouting.GEMINI))
        val ids=ModelsClient.decode("""{"models":[{"name":"models/gemini-4-hydrogen","supportedGenerationMethods":["generateContent"]},{"name":"models/embed","supportedGenerationMethods":["embedContent"]}]}""".toByteArray(),true)
        assertEquals(listOf(ApiRouting.HYDROGEN),ids)
    }
    @Test fun nativeResponsesUseFinalTextAndExcludeThoughtsFromCandidateAndOutputUsage() {
        val client=ChatCompletionsClient()
        val openai="""{"status":"completed","output":[{"type":"reasoning","summary":[{"text":"private thought"}]},{"type":"message","content":[{"type":"output_text","text":"[\"我想喝咖啡\"]"}]}],"usage":{"input_tokens":100,"output_tokens":30,"output_tokens_details":{"reasoning_tokens":23},"input_tokens_details":{"cached_tokens":50}}}"""
        val result=client.decodeEnvelope(openai.toByteArray(),request,ApiRouting.OPENAI)
        assertEquals(listOf("我想喝咖啡"),result.candidates);assertEquals(TokenUsage(100,7,23,50),result.usage)
        val gemini="""{"status":"completed","steps":[{"type":"thought","summary":[{"type":"text","text":"private thought"}]},{"type":"model_output","content":[{"type":"text","text":"[\"我想喝咖啡\"]"}]}],"usage":{"total_input_tokens":103,"total_output_tokens":7,"total_thought_tokens":165,"total_cached_tokens":0}}"""
        assertEquals(TokenUsage(103,7,165,0),client.decodeEnvelope(gemini.toByteArray(),request,ApiRouting.GEMINI).usage)
        assertFailsWith<ApiTruncatedException> { client.decodeEnvelope("""{"status":"incomplete"}""".toByteArray(),request,ApiRouting.GEMINI) }
        assertFailsWith<ApiTruncatedException> { client.decodeEnvelope("""{"status":"incomplete"}""".toByteArray(),request,ApiRouting.OPENAI) }
        assertFailsWith<ApiResponseException> { client.decodeEnvelope("""{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"no"}]}]}""".toByteArray(),request,ApiRouting.OPENAI) }
    }
    @Test fun nativeHttpsRequestsUseCorrectHeadersAndNoHistory()=runBlocking {
        val cert=HeldCertificate.Builder().addSubjectAlternativeName("localhost").addSubjectAlternativeName("127.0.0.1").build()
        val serverTls=HandshakeCertificates.Builder().heldCertificate(cert).build()
        val clientTls=HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        val http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager).build()
        MockWebServer().use { server ->
            server.useHttps(serverTls.sslSocketFactory(),false);server.start()
            try {
                val client=ChatCompletionsClient(http)
                server.enqueue(MockResponse().setBody("""{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"[\"coffee\"]"}]}]}"""))
                assertEquals(listOf("coffee"),client.request(server.url("/v1beta/interactions").toString(),"fixture-secret",ApiRouting.HYDROGEN,request,parameters=values).candidates)
                val google=server.takeRequest();assertEquals("fixture-secret",google.getHeader("x-goog-api-key"));assertNull(google.getHeader("Authorization"));assertEquals("2026-05-20",google.getHeader("Api-Revision"))
                assertEquals(Protocol.encode(request.input),Json.parseToJsonElement(google.body.readUtf8()).jsonObject["input"]!!.jsonPrimitive.content)
                server.enqueue(MockResponse().setBody("""{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"[\"coffee\"]"}]}]}"""))
                assertEquals(listOf("coffee"),client.request(server.url("/v1/responses").toString(),"other-secret","model",request,parameters=values).candidates)
                val openai=server.takeRequest();assertEquals("Bearer other-secret",openai.getHeader("Authorization"));assertNull(openai.getHeader("x-goog-api-key"))
            } finally { http.dispatcher.executorService.shutdownNow();http.connectionPool.evictAll() }
        }
    }
    private fun tlsPair(): Pair<HandshakeCertificates, HandshakeCertificates> {
        val cert=HeldCertificate.Builder().addSubjectAlternativeName("localhost").addSubjectAlternativeName("127.0.0.1").build()
        return HandshakeCertificates.Builder().heldCertificate(cert).build() to HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
    }
    @Test fun unreachableFirstAddressFallsBackWithoutResending()=runBlocking {
        val (serverTls,clientTls)=tlsPair()
        MockWebServer().use { server ->
            server.useHttps(serverTls.sslSocketFactory(),false);server.start(java.net.InetAddress.getByName("127.0.0.1"),0)
            val live=java.net.InetAddress.getByName("127.0.0.1")
            val dead=java.net.InetAddress.getByAddress("localhost",byteArrayOf(127,0,0,2))
            // Production settings: no OkHttp retries, so only the client's own fallback can reach `live`.
            val http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager)
                .retryOnConnectionFailure(false).dns(object:okhttp3.Dns { override fun lookup(hostname:String)=listOf(dead,live) }).build()
            try {
                server.enqueue(MockResponse().setBody("""{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"[\"coffee\"]"}]}]}"""))
                val url="https://localhost:${server.port}/v1/responses"
                assertEquals(listOf("coffee"),ChatCompletionsClient(http).request(url,"secret","model",request,timeoutMs=10000,parameters=values).candidates)
                assertEquals(1,server.requestCount,"The provider receives the request exactly once")
            } finally { http.dispatcher.executorService.shutdownNow();http.connectionPool.evictAll() }
        }
    }
    @Test fun failureAfterRequestIsSentIsNotRetried()=runBlocking {
        val (serverTls,clientTls)=tlsPair()
        MockWebServer().use { server ->
            server.useHttps(serverTls.sslSocketFactory(),false);server.start(java.net.InetAddress.getByName("127.0.0.1"),0)
            val live=java.net.InetAddress.getByName("127.0.0.1")
            val http=OkHttpClient.Builder().sslSocketFactory(clientTls.sslSocketFactory(),clientTls.trustManager)
                .retryOnConnectionFailure(false).dns(object:okhttp3.Dns { override fun lookup(hostname:String)=listOf(live) }).build()
            try {
                server.enqueue(MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AFTER_REQUEST))
                server.enqueue(MockResponse().setBody("""{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"[\"twice\"]"}]}]}"""))
                assertFails { ChatCompletionsClient(http).request("https://localhost:${server.port}/v1/responses","secret","model",request,timeoutMs=10000,parameters=values) }
                assertEquals(1,server.requestCount,"A request the provider already received is never resent")
            } finally { http.dispatcher.executorService.shutdownNow();http.connectionPool.evictAll() }
        }
    }
}
