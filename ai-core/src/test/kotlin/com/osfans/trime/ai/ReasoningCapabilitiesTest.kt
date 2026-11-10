package com.osfans.trime.ai
import kotlin.test.*
class ReasoningCapabilitiesTest {
    private val openai="https://api.openai.com/v1/chat/completions"
    @Test fun modelFamiliesDoNotShareUnsupportedLevels() {
        assertEquals(listOf("none","low","high","max"),ReasoningCapabilities.known(ApiRouting.OPENROUTER,ApiRouting.DEEPSEEK))
        assertFalse(ReasoningCapabilities.known(openai,"gpt-6-astra")!!.contains("none"))
        assertTrue(ReasoningCapabilities.known(openai,"gpt-6-luna")!!.contains("none"))
        assertTrue(ReasoningCapabilities.known(openai,"gpt-6-sol-2026-10-01")!!.contains("none"))
        assertFalse(ReasoningCapabilities.known(openai,"gpt-5.4-nano")!!.contains("max"))
        assertEquals(listOf("omit"),ReasoningCapabilities.options(openai,"gpt-4.1-mini").map{it.value})
        assertEquals(listOf("omit"),ReasoningCapabilities.options(openai,"unknown-future").map{it.value})
        assertFails { BenchmarkEntry(ApiRouting.DEEPSEEK,"medium",api="openrouter").parameters() }
    }
    @Test fun metadataHonorsMandatoryAndMissingEffortAndRefreshOverridesOldChoices() {
        val json="""{"data":[{"id":"a","reasoning":{"mandatory":true,"supported_efforts":["none","low","high"]}},{"id":"b"},{"id":"c","reasoning":{"supported_efforts":null}},{"id":"d","reasoning":{"mandatory":false}}]}"""
        val definitions=ReasoningCapabilities.fromModels(json.toByteArray())
        val catalog=ModelCatalog(version="models-test",models=definitions).validate()
        assertEquals(listOf("low","high","omit"),ReasoningCapabilities.options(ApiRouting.OPENROUTER,"a",catalog).map{it.value})
        assertEquals(listOf("omit"),ReasoningCapabilities.options(ApiRouting.OPENROUTER,"b",catalog).map{it.value})
        assertEquals(8,ReasoningCapabilities.options(ApiRouting.OPENROUTER,"c",catalog).size)
        assertEquals(listOf("omit"),ReasoningCapabilities.options(ApiRouting.OPENROUTER,"d",catalog).map{it.value})
    }
}
