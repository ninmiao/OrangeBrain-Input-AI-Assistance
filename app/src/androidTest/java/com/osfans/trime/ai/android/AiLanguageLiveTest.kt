// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.ai.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/** Opt-in: seven fixed language cases, one request each; temporary credential stays in memory. */
class AiLanguageLiveTest {
    @Test fun lunaNoReasoningLanguageAndScriptCases() = runBlocking {
        val token = InstrumentationRegistry.getArguments().getString("live_bridge_token").orEmpty()
        assumeTrue("Explicit live credential bridge required", token.isNotBlank())
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val pack = AiStore.get(context).builtin
        data class Case(val name: String, val input: String, val chinese: Boolean, val traditional: Boolean = false, val expected: List<String>)
        val cases = listOf(
            Case("Chinese pinyin", "wojintianxiangquchaoshi", true, expected = listOf("我今天想去超市")),
            Case("English in Chinese keyboard", "I has a meeting tomorow.", true, expected = listOf("I have a meeting tomorrow")),
            Case("Mixed pinyin and English", "wojintianyoumeeting", true, expected = listOf("我今天有", "meeting")),
            Case("Traditional pinyin", "shurufazhichijianfanqiehuan", true, true, listOf("輸入法", "簡繁", "切換")),
            Case("English correction first", "I has a meeting tomorow.", false, expected = listOf("I have a meeting tomorrow")),
            Case("Mixed input translated to English", "我 tomorrow 有 meeting", false, expected = listOf("meeting", "tomorrow")),
            Case("Chinese translated to English", "我今天想去超市", false, expected = listOf("want", "supermarket", "today"))
        )
        val report = mutableListOf("Model: gpt-6-luna; reasoning_effort=none; service_tier=default; built-in prompt ${pack.version}")
        var key = ""
        var passed = 0
        try {
            key = Json.parseToJsonElement(HttpsDownload.get("${TestNetwork.baseUrl}/credential/$token", 4096).toString(Charsets.UTF_8)).jsonObject.getValue("key").jsonPrimitive.content
            for (case in cases) {
                val start = android.os.SystemClock.elapsedRealtime()
                val request = AiRequest(RequestStamp(1, 1, 1, 1, 1), AiInput(case.input), pack.compose("original", case.chinese, false, traditional = case.traditional), false)
                try {
                    val result = ChatCompletionsClient().request(LunaDefaults.ENDPOINT, key, LunaDefaults.MODEL, request, 10000, LunaDefaults.values().getValue(LunaDefaults.MODEL))
                    val first = result.candidates.first()
                    val ok = case.expected.all { first.contains(it, true) } && (case.chinese || first.none { it in '\u4e00'..'\u9fff' })
                    if (ok) passed++
                    report += "${case.name}: ${if (ok) "PASS" else "FAIL"} (${android.os.SystemClock.elapsedRealtime()-start} ms) | ${case.input} -> $first"
                } catch (e: Exception) { report += "${case.name}: FAIL (${e.javaClass.simpleName})" }
            }
            report += "Passed: $passed / ${cases.size}"
            assertTrue("Language quality mismatch; inspect language-live-report.txt", passed == cases.size)
        } finally {
            key = ""
            File(context.getExternalFilesDir(null), "language-live-report.txt").writeText(report.joinToString("\n"))
        }
    }
}
