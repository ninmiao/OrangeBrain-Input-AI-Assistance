package com.osfans.trime.ai
import kotlin.test.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import java.net.InetAddress

class PresetToggleTest {
    private val request=AiRequest(RequestStamp(0,0,0,0,0),AiInput("nihoa"),"complete local prompt plus custom instructions",false)
    private val missing="""{"error":{"code":404,"message":"private server detail","metadata":{"presetErrorCode":"preset_not_found"}}}"""
    @Test fun defaultsAndToggleRestoreFullPrompt() {
        val defaults=PromptPresets()
        assertFalse(defaults.enabled)
        assertEquals("@preset/zephyr-en",defaults.english)
        val enabled=defaults.copy(enabled=true)
        assertEquals("@preset/zephyr-zh-hans",enabled.selected(true,false))
        assertEquals("@preset/zephyr-zh-hant",enabled.selected(true,true))
        assertEquals("@preset/zephyr-en",enabled.selected(false,true))
        listOf(defaults,enabled,enabled.copy(enabled=false)).forEach { p ->
            val body=ChatCompletionsClient().payload("model",request,endpoint=ApiRouting.OPENROUTER,preset=p.selected(true,false))
            assertEquals(if(p.enabled)1 else 2,body["messages"]!!.jsonArray.size)
            assertEquals(!p.enabled,body.toString().contains(request.systemPrompt))
            assertEquals(p.enabled,"preset" in body)
        }
    }
    @Test fun migrationKeepsCustomReferencesAndDisabledInvalidFieldsDoNotBlockRecovery() {
        val old=Json.decodeFromString<PromptPresets>("""{"chinese":"@preset/custom","traditional":"","english":""}""")
        val p=old.withDefaults();assertFalse(p.enabled)
        assertEquals("@preset/custom",p.chinese);assertEquals(PromptPresets().english,p.english)
        PromptPresets(chinese="bad reference",enabled=false).validate()
        assertFails { PromptPresets(chinese="bad reference",enabled=true).validate() }
        assertFailsWith<ApiPresetException> { PromptPresets(chinese="",enabled=true).selected(true,false) }
    }
    @Test fun successfulHttpErrorEnvelopeStillReportsPresetFailure() {
        val error=assertFailsWith<ApiPresetException> { ChatCompletionsClient().decodeEnvelope(missing.toByteArray(),request,ApiRouting.OPENROUTER,"@preset/missing") }
        assertEquals(AiFailure.PRESET,AiFailure.from(error));assertFalse(error.message!!.contains("private"))
        assertFailsWith<ApiProviderException> { ChatCompletionsClient().decodeEnvelope(missing.toByteArray(),request,ApiRouting.OPENROUTER) }
    }
    @Test fun httpsDistinguishesMissingPresetFromMissingModelAndInvalidKey()=runBlocking {
        val cert=HeldCertificate.Builder().addSubjectAlternativeName("openrouter.ai").build()
        val tls=HandshakeCertificates.Builder().heldCertificate(cert).build()
        val trust=HandshakeCertificates.Builder().addTrustedCertificate(cert.certificate).build()
        val http=OkHttpClient.Builder().sslSocketFactory(trust.sslSocketFactory(),trust.trustManager)
            .dns(object:okhttp3.Dns { override fun lookup(hostname:String)=listOf(InetAddress.getByName("127.0.0.1")) }).build()
        try { MockWebServer().use { server ->
            server.useHttps(tls.sslSocketFactory(),false);server.start()
            val endpoint="https://openrouter.ai:${server.port}/api/v1/chat/completions"
            val client=ChatCompletionsClient(http)
            server.enqueue(MockResponse().setResponseCode(404).setBody(missing))
            assertFailsWith<ApiPresetException> { client.request(endpoint,"fixture","model",request,preset="@preset/missing") }
            server.enqueue(MockResponse().setResponseCode(404).setBody("""{"error":{"message":"Model not found","code":404}}"""))
            assertEquals(404,assertFailsWith<ApiHttpException> { client.request(endpoint,"fixture","model",request,preset="@preset/missing") }.status)
            server.enqueue(MockResponse().setResponseCode(401).setBody("""{"error":{"message":"Invalid key"}}"""))
            assertEquals(AiFailure.AUTHENTICATION,AiFailure.from(assertFailsWith<ApiHttpException> { client.request(endpoint,"fixture","model",request,preset="@preset/missing") }))
        } } finally { http.dispatcher.executorService.shutdownNow();http.connectionPool.evictAll() }
    }
}
