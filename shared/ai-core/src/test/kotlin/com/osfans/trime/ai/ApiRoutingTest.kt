package com.osfans.trime.ai
import kotlin.test.*
import kotlinx.serialization.json.*
class ApiRoutingTest {
    @Test fun routerDisablesThinkingAndPinsExactEndpointWithoutFallback() {
        val input = mapOf("reasoning_effort" to JsonPrimitive("none"), "service_tier" to JsonPrimitive("default"))
        val body = ApiRouting.wire(ApiRouting.OPENROUTER,input,ApiRouting.WAFER)
        assertEquals(JsonPrimitive(false),body.getValue("reasoning").jsonObject["enabled"])
        assertEquals(JsonArray(listOf(JsonPrimitive("wafer/us"))),body.getValue("provider").jsonObject["only"])
        assertEquals(JsonPrimitive(false),body.getValue("provider").jsonObject["allow_fallbacks"])
        assertFalse(body.containsKey("service_tier")); assertFalse(body.containsKey("reasoning_effort"))
        assertEquals(JsonPrimitive("none"),ApiRouting.wire(ApiRouting.OPENAI,input)["reasoning"]!!.jsonObject["effort"])
    }
    @Test fun routerSpeedAndReasoningTranslateWithoutLeakingOpenAIFields() {
        val body=ApiRouting.wire(ApiRouting.OPENROUTER,mapOf("reasoning_effort" to JsonPrimitive("low"),"service_tier" to JsonPrimitive("priority"),"max_completion_tokens" to JsonPrimitive(200)))
        assertEquals(JsonPrimitive("low"),body.getValue("reasoning").jsonObject["effort"])
        assertEquals(JsonPrimitive("latency"),body.getValue("provider").jsonObject["sort"])
        assertEquals(JsonPrimitive(200),body["max_tokens"])
        assertFalse(body.containsKey("max_completion_tokens"))
        assertFails { ApiRouting.wire(ApiRouting.OPENROUTER,mapOf("service_tier" to JsonPrimitive("flex"))) }
        assertFalse(ApiRouting.isOpenRouter("https://openrouter.ai.evil.example/v1/chat/completions"))
    }
}
