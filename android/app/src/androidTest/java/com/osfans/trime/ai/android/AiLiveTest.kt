// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.ai.*
import com.osfans.trime.daemon.RimeDaemon
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/** Opt-in, real OpenAI test. A one-shot local TLS bridge supplies a temporary key in memory.
 * Never pass the key through instrumentation arguments, environment, source or test logs.
 */
@org.junit.Ignore("Historical pre-Policy UI flow; use AiLanguageLiveTest for the current Luna language checks")
class AiLiveTest {
    @Test fun realApiModelsParametersAndKeyboard() = runBlocking {
        val token = InstrumentationRegistry.getArguments().getString("live_bridge_token").orEmpty()
        assumeTrue("Live test requires an explicitly started credential bridge", token.isNotBlank())
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val device = UiDevice.getInstance(instrumentation)
        val store = AiStore.get(context)
        val old = store.config
        val endpoint = "https://api.openai.com/v1/chat/completions"
        val sessionName = "ai-live-test"
        val session = RimeDaemon.createSession(sessionName)
        val report = mutableListOf<String>()
        var key = ""
        try {
            key = Json.parseToJsonElement(HttpsDownload.get("${TestNetwork.baseUrl}/credential/$token", 4096).toString(Charsets.UTF_8)).jsonObject.getValue("key").jsonPrimitive.content
            require(key.isNotBlank())
            store.update { it.copy(enabled=false, endpoint=endpoint, model="gpt-4.1-mini", timeoutMs=45000,
                localOverride=null, active=null, completion=false, automatic=false) }
            store.credentials.save(endpoint, key)
            assertTrue("Credential was not encrypted", File(context.noBackupFilesDir, "ai-credential.bin").readBytes().toString(Charsets.UTF_8).let { !it.contains(key) })
            val count = store.refreshModels()
            assertTrue(store.config.discoveredModels.contains("gpt-4.1-mini"))
            report += "Official /models: $count IDs; gpt-4.1-mini found"
            val client = ChatCompletionsClient()
            fun req(input: String, chinese: Boolean) = AiRequest(RequestStamp(1,1,1,1,1), AiInput(input), store.builtin.compose(chinese),false)
            val parameters = mapOf("max_completion_tokens" to JsonPrimitive(512))
            val chinese = client.request(endpoint,key,"gpt-4.1-mini",req("nihao",true),45000,parameters)
            assertTrue(chinese.candidates.first().contains("你好"))
            report += "Direct real Chinese request: passed"
            val english = client.request(endpoint,key,"gpt-4.1-mini",req("这个 model 的 latency 有点高",false),45000, parameters + ("service_tier" to JsonPrimitive("priority")))
            assertFalse(english.candidates.first().any { it in '\u4e00'..'\u9fff' })
            assertTrue(english.candidates.first().contains("model",true))
            report += "Direct real English request with priority: passed (HTTP accepted; returned tier evaluated in host suite)"
            val reasoning = client.request(endpoint,key,"gpt-5-mini",req("I has a meeting tomorow.",false),45000,
                mapOf("reasoning_effort" to JsonPrimitive("low"),"max_completion_tokens" to JsonPrimitive(2048)))
            assertTrue(reasoning.candidates.first().contains("tomorrow",true))
            report += "Direct real low-reasoning request: passed"
            // Select existing deployed schema without destroying the user's demo data.
            val deadline = System.currentTimeMillis()+120000
            var selected = false
            while (!selected && System.currentTimeMillis()<deadline) {
                selected = session.runOnReady { selectSchema("rime_ai_simp") }
                if (!selected) kotlinx.coroutines.delay(500)
            }
            assertTrue("Rime pinyin schema unavailable", selected)
            store.replaceModelCatalog(ModelCatalog(models=listOf(ModelCatalog.template("gpt-4.1-mini"))),endpoint)
            store.saveParameters(endpoint,"gpt-4.1-mini",parameters)
            store.update { it.copy(enabled=true,consent=true,automatic=false) }
            device.executeShellCommand("cmd statusbar collapse")
            device.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
            device.executeShellCommand("ime enable --user 0 ${context.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            device.executeShellCommand("ime set --user 0 ${context.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            instrumentation.context.startActivity(Intent().setClassName(instrumentation.context.packageName,TestEditorActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertTrue(device.wait(Until.hasObject(By.desc("test-editor")),15000))
            device.findObject(By.desc("test-editor")).click()
            device.findObject(By.desc("test-editor")).text = ""
            instrumentation.waitForIdleSync()
            kotlinx.coroutines.delay(500)
            session.runOnReady { clearComposition(); setRuntimeOption("ascii_mode",false) }
            assertTrue(device.wait(Until.hasObject(By.text("重试 / 选区")),15000))
            "nihao".forEach { c -> session.runOnReady { processKey(c.code) }; kotlinx.coroutines.delay(120) }
            device.findObject(By.text("重试 / 选区")).click()
            fun candidate(): UiObject2 {
                assertTrue("Real AI candidate never appeared",device.wait(Until.hasObject(By.descStartsWith("AI 候选：")),50000))
                return device.findObjects(By.descStartsWith("AI 候选：")).first()
            }
            val first = candidate()
            val firstText = first.contentDescription.removePrefix("AI 候选：")
            assertTrue(firstText.contains("你好"))
            assertTrue(session.runOnReady { getCandidates(0,3).isNotEmpty() })
            device.takeScreenshot(File(context.getExternalFilesDir(null),"live-chinese.png"))
            first.click()
            assertTrue(device.wait(Until.hasObject(By.desc("test-editor").text(firstText)),5000))
            kotlinx.coroutines.delay(700)
            assertEquals(firstText,device.findObject(By.desc("test-editor")).text)
            assertFalse(device.hasObject(By.descStartsWith("AI 候选：")))
            report += "Real IME pinyin candidate commits once, local candidates retained: passed; $firstText"
            session.runOnReady { setRuntimeOption("ascii_mode",true) }
            device.findObject(By.desc("test-editor")).text = "这个 model 的 latency 有点高"
            device.findObject(By.text("重试 / 选区")).click()
            val second = candidate()
            val secondText = second.contentDescription.removePrefix("AI 候选：")
            assertFalse(secondText.any { it in '\u4e00'..'\u9fff' })
            device.takeScreenshot(File(context.getExternalFilesDir(null),"live-english.png"))
            second.click()
            if (secondText.length>45) {
                assertTrue(device.wait(Until.hasObject(By.text("采用")),5000))
                device.findObject(By.text("采用")).click()
            }
            assertTrue(device.wait(Until.hasObject(By.desc("test-editor").text(secondText)),5000))
            report += "Real IME mixed-language replacement: passed; $secondText"
            store.update { it.copy(automatic=true) }
            device.findObject(By.desc("test-password")).click()
            device.pressKeyCode(android.view.KeyEvent.KEYCODE_A)
            assertTrue(device.wait(Until.hasObject(By.textContains("隐私字段")),5000))
            assertFalse(device.hasObject(By.descStartsWith("AI 候选：")))
            report += "Password privacy state and absence of candidates: passed; zero-network assertion covered separately by mock test"
        } finally {
            key = ""
            store.credentials.clear()
            store.update { old.copy(enabled=false) }
            RimeDaemon.destroySession(sessionName)
            report += "Credential ciphertext removed: ${!File(context.noBackupFilesDir,"ai-credential.bin").exists()}"
            report += "Credential alias removed: ${!java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.containsAlias("rime-ai-api-v1")}"
            File(context.getExternalFilesDir(null),"live-android-report.txt").writeText(report.joinToString("\n"))
            assertNull("Credential remains after cleanup",store.credentials.read(endpoint))
        }
    }
}
