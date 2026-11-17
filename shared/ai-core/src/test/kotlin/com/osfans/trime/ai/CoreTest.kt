package com.osfans.trime.ai

import kotlin.test.*
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.test.*
import kotlinx.serialization.json.*

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class CoreTest {
    private fun request(revision: Long = 1) = AiRequest(
        RequestStamp(1, revision, 1, 1, 1), AiInput("nihao"), "system", false)

    @Test fun wireContainsOnlyCurrentText() {
        assertEquals("""{"i":"你好"}""",Protocol.encode(AiInput("你好")))
        assertFails { Protocol.encode(AiInput("a".repeat(301))) }
    }
    @Test fun emptyAndOversizedResultsAreRejectedWithoutAlteringUserPunctuation() {
        listOf("", " ","a".repeat(2001),"a\u0000b").forEach { assertFails { Protocol.decode(it) } }
        val content="\"咖啡\"，谢谢！\n{hello: world}"
        assertEquals(listOf(content),Protocol.decode(JsonArray(listOf(JsonPrimitive(content))).toString()).candidates)
    }

    @Test fun waits200msAndDebounces() = runTest {
        var calls = 0
        val states = mutableListOf<AiState>()
        val coordinator = AiRequestCoordinator(this, { calls++; AiResult(listOf("你好"), "") }, states::add)
        coordinator.submit(request(), true, false)
        advanceTimeBy(199); runCurrent(); assertEquals(0, calls)
        coordinator.submit(request(2), true, false)
        advanceTimeBy(199); runCurrent(); assertEquals(0, calls)
        advanceTimeBy(1); runCurrent(); assertEquals(1, calls)
        assertEquals(2, (states.last() as AiState.Ready).request.stamp.inputRevision)
    }

    @Test fun lateResponseCannotOverwriteNewConfiguration() = runTest {
        val states = mutableListOf<AiState>()
        val coordinator = AiRequestCoordinator(this, { req ->
            withContext(NonCancellable) { delay(if (req.stamp.promptGeneration == 1L) 1000 else 1) }
            AiResult(listOf(req.stamp.promptGeneration.toString()), "")
        }, states::add)
        coordinator.submit(request(), true, false)
        advanceTimeBy(200); runCurrent()
        val changed = request().copy(stamp = request().stamp.copy(promptGeneration = 2))
        coordinator.submit(changed, true, false)
        advanceUntilIdle()
        assertEquals(listOf("2"), states.filterIsInstance<AiState.Ready>().map { it.result.candidates.single() })
    }

    @Test fun privacyAndSessionEndPreventRequests() = runTest {
        var calls = 0
        val coordinator = AiRequestCoordinator(this, { calls++; AiResult(emptyList(), "") }, {})
        coordinator.submit(request(), true, true)
        advanceUntilIdle()
        coordinator.submit(request(), false, false)
        advanceUntilIdle()
        coordinator.submit(request(), true, false)
        coordinator.invalidate()
        advanceUntilIdle()
        assertEquals(0, calls)
    }

    @Test fun eachSnapshotDimensionInvalidatesInFlightResult() = runTest {
        val base = request()
        val stamps = listOf(
            base.stamp.copy(editorSession = 2), base.stamp.copy(inputRevision = 2),
            base.stamp.copy(promptGeneration = 2), base.stamp.copy(keyboardGeneration = 2),
            base.stamp.copy(apiGeneration = 2),
        )
        for (stamp in stamps) {
            val ready = mutableListOf<AiState.Ready>()
            val coordinator = AiRequestCoordinator(this, {
                withContext(NonCancellable) { delay(500) }
                AiResult(listOf("ok"), "")
            }, { if (it is AiState.Ready) ready.add(it) })
            coordinator.submit(base, true, false)
            advanceTimeBy(200); runCurrent()
            coordinator.submit(base.copy(stamp = stamp), true, false)
            advanceUntilIdle()
            assertEquals(listOf(stamp), ready.map { it.request.stamp })
        }
    }

    @Test fun promptPackageCompatibilityAndLanguagePriority() {
        val text = requireNotNull(javaClass.getResource("/default-prompts.json")).readText()
        val pack = PromptPackage.parse(text.toByteArray())
        assertContains(pack.compose(false),"转英文")
        assertContains(pack.compose(true,true),"繁体")
        assertContains(pack.compose(true),"简体")
        assertContains(pack.compose(true),"前文")
        assertFalse(pack.compose(true).contains("风格"))
        assertFalse(pack.compose(true).contains("candidates"))
        val obj = Json.parseToJsonElement(text).jsonObject
        val old = JsonObject(obj - "keyboard_language_rules")
        assertEquals(LanguageRules(), PromptPackage.parse(old.toString().toByteArray()).keyboard_language_rules)
        val partial = JsonObject(obj + ("keyboard_language_rules" to buildJsonObject { put("chinese", "中文") }))
        assertContains(PromptPackage.parse(partial.toString().toByteArray()).compose(true),"中文")
        assertFails { PromptPackage.parse(ByteArray(128 * 1024 + 1)) }
        assertFails { PromptPackage.parse(text.replace("\"schema_version\": 3", "\"schema_version\": 99").toByteArray()) }
    }
}
