package com.osfans.trime.ai

import kotlin.test.*
import kotlinx.coroutines.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive

class BenchmarkTest {
    @Test fun fiveSmallDefaultsDisableReasoningWithoutUnsupportedLegacyField() {
        val config = BenchmarkConfig().validate()
        assertEquals(5, config.entries.size)
        assertEquals(setOf("openai", "openrouter", "gemini"), config.entries.map { it.api }.toSet())
        config.copy(entries = config.entries.filter { it.api == "openai" }).validate()
        assertEquals(5, config.entries.map { it.model }.distinct().size)
        config.entries.forEach { assertEquals(if(it.api=="gemini")"low" else "none", it.reasoning); assertEquals(JsonPrimitive("default"), it.parameters()["service_tier"]) }
        assertEquals(JsonPrimitive("none"), config.entries.first().parameters()["reasoning_effort"])
        assertFalse(config.entries[2].parameters().containsKey("reasoning_effort"))
        assertFailsWith<IllegalArgumentException> { config.copy(entries = config.entries + BenchmarkEntry()).validate() }
        assertFailsWith<IllegalArgumentException> { config.copy(entries = emptyList()).validate() }
        assertFailsWith<IllegalArgumentException> { config.copy(timeoutMs = 60001).validate() }
    }
    @Test fun wireParametersAreExplicitAndUnsupportedOffIsNeverSilentlyChanged() {
        assertEquals(mapOf("reasoning_effort" to JsonPrimitive("low"), "service_tier" to JsonPrimitive("priority")), BenchmarkEntry(reasoning = "low", speed = "priority").parameters())
        assertTrue(BenchmarkEntry(reasoning = "omit", speed = "omit").parameters().isEmpty())
        assertFailsWith<IllegalArgumentException> { BenchmarkEntry("gpt-5-nano").parameters() }
        assertFailsWith<IllegalArgumentException> { BenchmarkEntry("gpt-4o-mini", "low").parameters() }
        assertFailsWith<IllegalArgumentException> { BenchmarkEntry("a\nb").validate() }
    }
    @Test fun runsSequentiallyAndContinuesAfterFailuresWithAccurateElapsedTime() = runTest {
        var clock = 0L
        val order = mutableListOf<String>()
        val config = BenchmarkConfig(entries = listOf("a", "b", "c").map { BenchmarkEntry(it, api = if (it == "c") "openrouter" else "openai") })
        val results = BenchmarkRunner { clock }.run(config, { entry, _ ->
            order += entry.model; delay(1); clock += 123_000_000
            if (entry.model == "b") throw ApiHttpException(429)
            AiResult(listOf(entry.model), "")
        })
        assertEquals(listOf("a", "b", "c"), order)
        assertTrue(results.all { it.elapsedMs == 123L })
        assertTrue(results[1].error!!.contains("429"))
        assertEquals("c", results.last().output)
    }
    @Test fun cancellationNeverStartsRemainingRequestsOrPublishesCancelledResponse() = runTest {
        val started = mutableListOf<String>(); val finished = mutableListOf<BenchmarkResult>()
        val active = launch {
            BenchmarkRunner().run(BenchmarkConfig(), { entry, _ ->
                started += entry.model; delay(10000); AiResult(listOf("candidate"), "")
            }, onResult = { _, result -> finished += result })
        }
        yield(); active.cancelAndJoin()
        assertEquals(listOf("gpt-6-luna"), started)
        assertTrue(finished.isEmpty())
    }
    @Test fun errorsDoNotExposeProviderBodiesAndInvalidOutputDoesNotWin() = runTest {
        var count = 0
        val result = BenchmarkRunner().run(BenchmarkConfig(entries = listOf(BenchmarkEntry(), BenchmarkEntry(api = "openrouter"))), { _, _ ->
            if (count++ == 0) throw java.io.IOException("secret-provider-body")
            AiResult(emptyList(), "")
        })
        assertTrue(result.all { it.error != null && it.output == null })
        assertFalse(result.toString().contains("secret-provider-body"))
    }
}
