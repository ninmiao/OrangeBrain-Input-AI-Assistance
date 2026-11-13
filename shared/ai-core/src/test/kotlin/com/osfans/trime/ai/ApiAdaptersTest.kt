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
    private val request=AiRequest(RequestStamp(1,1,1,1,1),AiInput("我 tomorrow 有 meeting 123"),"short correction prompt",false)
    private val values=mapOf("reasoning_effort" to JsonPrimitive("low"),"service_tier" to JsonPrimitive("default"))
    @Test fun openAIRequestsHaveNoHistoryContextOrGeneratedSchema() {
        val p=ChatCompletionsClient().payload("gpt-6.1-terra",request,values,ApiRouting.OPENAI)
        assertEquals(request.input.input,p["input"]!!.jsonPrimitive.content)
        assertEquals(request.systemPrompt,p["instructions"]!!.jsonPrimitive.content)
        assertEquals(false,p["store"]!!.jsonPrimitive.boolean)
        assertEquals("low",p["reasoning"]!!.jsonObject["effort"]!!.jsonPrimitive.content)
        assertFalse(p.keys.any { it in setOf("previous_response_id","conversation","response_format","messages","before","after") })
        assertEquals(ApiRouting.OPENAI,ApiRouting.requestUrl("https://api.openai.com/v1/chat/completions"))
    }
    @Test fun presetOnlySendsUserTextAndKeepsModelAndRoutingOverrides() {
        val p=ChatCompletionsClient().payload(ApiRouting.DEEPSEEK,request,values,ApiRouting.OPENROUTER,ApiRouting.WAFER,"@preset/zephyr-zh")
        val messages=p["messages"]!!.jsonArray
        assertEquals(1,messages.size);assertEquals("user",messages.single().jsonObject["role"]!!.jsonPrimitive.content)
        assertEquals(request.input.input,messages.single().jsonObject["content"]!!.jsonPrimitive.content)
        assertFalse(p.toString().contains(request.systemPrompt))
        assertEquals("@preset/zephyr-zh",p["preset"]!!.jsonPrimitive.content)
        assertEquals(ApiRouting.DEEPSEEK,p["model"]!!.jsonPrimitive.content)
        assertEquals(ApiRouting.WAFER,p["provider"]!!.jsonObject["only"]!!.jsonArray.single().jsonPrimitive.content)
        assertFails { ChatCompletionsClient().payload("model",request,endpoint=ApiRouting.OPENROUTER,preset="bare-slug") }
        assertFails { ChatCompletionsClient().payload("model",request,endpoint=ApiRouting.OPENAI,preset="@preset/x") }
    }
    @Test fun presetLanguageSelectionAndValidation() {
        val presets=PromptPresets("@preset/zh","@preset/hant","@preset/en",enabled=true)
        presets.validate();assertEquals("@preset/zh",presets.selected(true,false))
        assertEquals("@preset/hant",presets.selected(true,true));assertEquals("@preset/en",presets.selected(false,true))
        assertFails { PromptPresets(chinese="@preset/a\nsecret",enabled=true).validate() }
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
        val openai="""{"status":"completed","output":[{"type":"reasoning","summary":[{"text":"private thought"}]},{"type":"message","content":[{"type":"output_text","text":"我想喝咖啡"}]}],"usage":{"input_tokens":100,"output_tokens":30,"output_tokens_details":{"reasoning_tokens":23},"input_tokens_details":{"cached_tokens":50}}}"""
        val result=client.decodeEnvelope(openai.toByteArray(),request,ApiRouting.OPENAI)
        assertEquals(listOf("我想喝咖啡"),result.candidates);assertEquals(TokenUsage(100,7,23,50),result.usage)
        val gemini="""{"status":"completed","steps":[{"type":"thought","summary":[{"type":"text","text":"private thought"}]},{"type":"model_output","content":[{"type":"text","text":"我想喝咖啡"}]}],"usage":{"total_input_tokens":103,"total_output_tokens":7,"total_thought_tokens":165,"total_cached_tokens":0}}"""
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
                server.enqueue(MockResponse().setBody("""{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"coffee"}]}]}"""))
                assertEquals(listOf("coffee"),client.request(server.url("/v1beta/interactions").toString(),"fixture-secret",ApiRouting.HYDROGEN,request,parameters=values).candidates)
                val google=server.takeRequest();assertEquals("fixture-secret",google.getHeader("x-goog-api-key"));assertNull(google.getHeader("Authorization"));assertEquals("2026-05-20",google.getHeader("Api-Revision"))
                assertEquals(request.input.input,Json.parseToJsonElement(google.body.readUtf8()).jsonObject["input"]!!.jsonPrimitive.content)
                server.enqueue(MockResponse().setBody("""{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"coffee"}]}]}"""))
                assertEquals(listOf("coffee"),client.request(server.url("/v1/responses").toString(),"other-secret","model",request,parameters=values).candidates)
                val openai=server.takeRequest();assertEquals("Bearer other-secret",openai.getHeader("Authorization"));assertNull(openai.getHeader("x-goog-api-key"))
            } finally { http.dispatcher.executorService.shutdownNow();http.connectionPool.evictAll() }
        }
    }
}
