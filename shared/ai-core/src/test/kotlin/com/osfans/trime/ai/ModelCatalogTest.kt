package com.osfans.trime.ai

import kotlin.test.*
import kotlinx.serialization.json.*

class ModelCatalogTest {
    private val request = AiRequest(RequestStamp(1, 1, 1, 1, 1), AiInput("nihao"), "system", false)
    @Test fun defaultOmitsOptionalParametersAndSelectionUsesTopLevelFields() {
        val client = ChatCompletionsClient()
        assertEquals(setOf("model", "stream", "messages", "max_completion_tokens"), client.payload("test", request).keys)
        val values = mapOf("reasoning_effort" to JsonPrimitive("low"), "service_tier" to JsonPrimitive("priority"), "max_completion_tokens" to JsonPrimitive(128))
        val body = client.payload("test", request, values)
        values.forEach { (key, value) -> assertEquals(value, body[key]) }
        val user = body.getValue("messages").jsonArray[1].jsonObject.getValue("content").jsonPrimitive.content
        assertEquals("""{"i":"nihao"}""",user)
    }
    @Test fun parametersCannotOverrideTransportOrMessages() {
        for (key in listOf("model", "messages", "stream", "api_key", "endpoint", "tools")) {
            assertFails { ChatCompletionsClient().payload("test", request, mapOf(key to JsonPrimitive("bad"))) }
        }
        assertFails { ModelParameters.validateWire(mapOf("max_tokens" to JsonPrimitive(20), "max_completion_tokens" to JsonPrimitive(20))) }
        assertFails { ModelParameters.validateWire(mapOf("temperature" to JsonPrimitive(5))) }
        assertFails { ModelParameters.validateWire(mapOf("top_p" to JsonPrimitive("0.5"))) }
        assertFails { ModelParameters.validateWire(mapOf("max_tokens" to JsonPrimitive(1.5))) }
    }
    @Test fun modelCapabilitiesDoNotAssumeNoneOrShareValues() {
        val p = ModelParameter("reasoning_effort", "推理", choices = listOf(ParameterChoice("轻度", "low")))
        val definition = ModelDefinition("specific", parameters = listOf(p))
        val values = mapOf("reasoning_effort" to JsonPrimitive("none"), "service_tier" to JsonPrimitive("priority"))
        assertTrue(definition.filterValues(values).isEmpty())
        assertTrue(p.accepts(JsonPrimitive("low")))
        val future = p.copy(choices = p.choices + ParameterChoice("未来档位", "future-effort"))
        val pack = ModelCatalog(models = listOf(definition.copy(parameters = listOf(future))))
        assertEquals(pack, ModelCatalog.parse(pack.export().toByteArray()))
        assertTrue(future.accepts(JsonPrimitive("future-effort")))
    }
    @Test fun malformedCatalogDoesNotEnterConfiguration() {
        val model = ModelCatalog.template("test")
        assertFails { ModelCatalog(models = listOf(model, model)).validate() }
        assertFails { ModelCatalog(models = listOf(model.copy(parameters = listOf(ModelParameter("api_key", "secret", choices = listOf(ParameterChoice("a", "a"))))))).validate() }
        assertFails { ModelCatalog(schema_version = 2).validate() }
        assertFails { ModelCatalog(models = (1..2000).map { ModelCatalog.template("model-$it") }).validate() }
        assertFails { ModelCatalog.parse(ByteArray(ModelCatalog.MAX_BYTES + 1)) }
        assertFails { ModelCatalog.parse("{\"models\":[],\"endpoint\":\"https://evil.example\"}".toByteArray()) }
    }
    @Test fun numericAndBooleanParametersKeepTheirWireTypes() {
        val max = ModelParameter("max_tokens", "长度", "integer", min = 1.0, max = 200.0)
        assertTrue(max.accepts(JsonPrimitive(128)))
        assertFalse(max.accepts(JsonPrimitive(128.5)))
        assertFalse(max.accepts(JsonPrimitive("128")))
        assertFalse(max.accepts(JsonPrimitive(201)))
        val thinking = ModelParameter("enable_thinking", "思考", "boolean")
        assertTrue(thinking.accepts(JsonPrimitive(false)))
        assertFalse(thinking.accepts(JsonPrimitive("false")))
    }
    @Test fun modelDiscoveryKeepsOriginAndDoesNotInventCapabilities() {
        assertEquals("https://example.com:9443/api/v1/models", ModelsClient.listUrl("https://example.com:9443/api/v1/chat/completions"))
        listOf("http://example.com/v1/chat/completions", "https://user@example.com/v1/chat/completions", "https://example.com/v1/chat/completions?key=x", "https://example.com/messages").forEach { assertFails { ModelsClient.listUrl(it) } }
        assertEquals(listOf("a", "b"), ModelsClient.decode("{\"data\":[{\"id\":\"b\",\"owned_by\":\"vendor\"},{\"id\":\"a\"},{\"id\":\"a\"}]}".toByteArray()))
        assertFails { ModelsClient.decode("{\"data\":[{\"id\":1}]}".toByteArray()) }
    }
}
