package com.osfans.trime.ai.android

import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.osfans.trime.ai.*
import com.osfans.trime.daemon.RimeDaemon
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class AiFlowTest {
    @Test fun settingsPagePreviewsActualLanguageRule() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        device.executeShellCommand("cmd statusbar collapse")
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, AiSettingsActivity::class.java).putExtra("policy", AiStore.get(instrumentation.targetContext).config.selectedPolicyId).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        try {
            assertTrue(device.wait(Until.hasObject(By.textStartsWith("Policy ·")), 10000))
            fun reveal(selector: androidx.test.uiautomator.BySelector) {
                repeat(20) {
                    if (device.hasObject(selector)) return
                    device.swipe(device.displayWidth / 2, device.displayHeight * 4 / 5,
                        device.displayWidth / 2, device.displayHeight / 4, 30)
                    Thread.sleep(200)
                }
                assertTrue("Settings control not visible", device.hasObject(selector))
            }
            reveal(By.text("预览最终系统提示词"))
            device.findObject(By.text("预览最终系统提示词")).click()
            reveal(By.textContains("当前为中文键盘"))
        } catch (failure: Throwable) {
            device.dumpWindowHierarchy(java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "settings-failure.xml"))
            throw failure
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }

    @Test fun httpsAdapterAndRemoteUpdates() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val store = AiStore.get(instrumentation.targetContext)
        val old = store.config
        try {
            val request = AiRequest(RequestStamp(1,1,1,1,1),AiInput("nihao"),store.builtin.compose("original",true,false),false)
            val result = ChatCompletionsClient().request("${TestNetwork.baseUrl}/v1/chat/completions","emulator-test-key","mock",request)
            assertEquals(listOf("你好，世界"),result.candidates)
            val english = request.copy(systemPrompt = store.builtin.compose("academic",false,false))
            assertEquals("Hello from AI.",ChatCompletionsClient().request("${TestNetwork.baseUrl}/v1/chat/completions","emulator-test-key","mock",english).candidates.single())
            store.update { it.copy(remoteUrl="${TestNetwork.baseUrl}/prompts.json") }
            store.checkRemote(false)
            assertEquals(100L,store.config.active!!.pack.revision)
        } finally { store.update { old } }
    }

    @Test fun keyboardCandidateCommitsOnceAndPasswordBlocksAI() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        device.executeShellCommand("cmd statusbar collapse")
        val context = instrumentation.targetContext
        val store = AiStore.get(context)
        val old = store.config
        val session = RimeDaemon.createSession("ai-flow-test")
        try {
            session.runOnReady { deploy() }
            val deployed = java.io.File(com.osfans.trime.data.base.DataManager.stagingDir, "rime_ai_simp.schema.yaml")
            val table = java.io.File(com.osfans.trime.data.base.DataManager.stagingDir, "rime_ice.table.bin")
            val deadline = System.currentTimeMillis() + 600000
            while ((!deployed.exists() || !table.exists()) && System.currentTimeMillis() < deadline) kotlinx.coroutines.delay(500)
            assertTrue("Rime dictionary deployment did not complete", deployed.exists() && table.exists())
            // File existence is insufficient while Rime maintenance still holds the engine.
            var selected = false
            while (!selected && System.currentTimeMillis() < deadline) {
                selected = session.runOnReady { selectSchema("rime_ai_simp") }
                if (!selected) kotlinx.coroutines.delay(500)
            }
            assertTrue("Cannot select pinyin schema after deployment", selected)
            session.runOnReady { setRuntimeOption("ascii_mode", false) }
            store.credentials.save("${TestNetwork.baseUrl}/v1/chat/completions","emulator-test-key")
            store.update { it.copy(enabled=true,consent=true,automatic=true,traditional=false,endpoint="${TestNetwork.baseUrl}/v1/chat/completions",model="mock",localOverride=null,active=null,style="original") }
            device.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
            device.executeShellCommand("ime enable --user 0 ${context.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            device.executeShellCommand("ime set --user 0 ${context.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            instrumentation.context.startActivity(Intent().setClassName(instrumentation.context.packageName, TestEditorActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertTrue(device.wait(Until.hasObject(By.desc("test-editor")),15000))
            device.findObject(By.desc("test-editor")).click()
            session.runOnReady { setRuntimeOption("ascii_mode",false) }
            assertTrue("AI keyboard panel never appeared", device.wait(Until.hasObject(By.descContains("体输出")), 15000))
            "biru".forEach { key -> session.runOnReady { processKey(key.code) }; kotlinx.coroutines.delay(120) }
            assertTrue("Raw key hint missing", device.wait(Until.hasObject(By.desc("正在输入：biru").text("biru")), 5000))
            device.takeScreenshot(java.io.File(context.getExternalFilesDir(null), "raw-input-biru.png"))
            session.runOnReady { clearComposition() }
            assertTrue(device.wait(Until.gone(By.desc("正在输入：biru")), 5000))
            "nihao".forEach { key ->
                session.runOnReady { processKey(key.code) }
                kotlinx.coroutines.delay(120)
            }
            assertTrue("AI candidate never appeared",device.wait(Until.hasObject(By.text("你好，世界").clazz("android.widget.Button")),20000))
            assertTrue("Local pinyin candidates disappeared", session.runOnReady { getCandidates(0, 3).isNotEmpty() })
            device.takeScreenshot(java.io.File(context.getExternalFilesDir(null), "ai-candidate.png"))
            device.findObject(By.text("你好，世界").clazz("android.widget.Button")).click()
            assertTrue(device.wait(Until.hasObject(By.desc("test-editor").text("你好，世界")),5000))
            Thread.sleep(600)
            assertEquals("你好，世界",device.findObject(By.desc("test-editor")).text)
            assertFalse(device.hasObject(By.descStartsWith("正在输入：")))
            assertFalse(device.hasObject(By.text("你好，世界").clazz("android.widget.Button")))
            session.runOnReady { setRuntimeOption("ascii_mode", true) }
            device.findObject(By.desc("test-editor")).text = "这个 model 的 latency 有点高"
            instrumentation.waitForIdleSync()
            // Exercise the on-screen keyboard after accessibility text replacement has settled.
            val keyboardBounds = device.findObject(By.res(context.packageName, "keyboard_view")).visibleBounds
            device.click(keyboardBounds.centerX(), keyboardBounds.bottom - keyboardBounds.height() / 8)
            assertTrue("English candidate never appeared", device.wait(Until.hasObject(By.text("Hello from AI.").clazz("android.widget.Button")), 15000))
            device.takeScreenshot(java.io.File(context.getExternalFilesDir(null), "ai-english.png"))
            device.findObject(By.text("Hello from AI.").clazz("android.widget.Button")).click()
            assertTrue(device.wait(Until.hasObject(By.desc("test-editor").text("Hello from AI.")), 5000))
            fun count() = Json.parseToJsonElement(HttpsDownload.get("${TestNetwork.baseUrl}/stats", 1024).toString(Charsets.UTF_8)).jsonObject.getValue("requests").jsonPrimitive.int
            val beforePassword = count()
            device.findObject(By.desc("test-password")).click()
            device.pressKeyCode(android.view.KeyEvent.KEYCODE_A)
            assertTrue(device.wait(Until.hasObject(By.textContains("隐私字段")),5000))
            Thread.sleep(500)
            assertEquals("Password field sent a network request", beforePassword, count())
            assertFalse(device.hasObject(By.descStartsWith("正在输入：")))
            assertFalse(device.hasObject(By.text("你好，世界").clazz("android.widget.Button")))
            // Deliberate HTTP 401 must not prevent the local Rime candidate from committing.
            store.credentials.save(store.config.endpoint, "intentionally-invalid-test-key")
            store.update { it }
            device.findObject(By.desc("test-editor")).click()
            device.findObject(By.desc("test-editor")).text = ""
            instrumentation.waitForIdleSync()
            kotlinx.coroutines.delay(500)
            session.runOnReady { clearComposition(); setRuntimeOption("ascii_mode", false) }
            assertTrue(device.wait(Until.hasObject(By.textStartsWith("AI ·")), 5000))
            "biru".forEach { key -> session.runOnReady { processKey(key.code) }; kotlinx.coroutines.delay(120) }
            assertTrue("Raw key hint missing", device.wait(Until.hasObject(By.desc("正在输入：biru").text("biru")), 5000))
            device.takeScreenshot(java.io.File(context.getExternalFilesDir(null), "raw-input-biru.png"))
            session.runOnReady { clearComposition() }
            assertTrue(device.wait(Until.gone(By.desc("正在输入：biru")), 5000))
            "nihao".forEach { key -> session.runOnReady { processKey(key.code) }; kotlinx.coroutines.delay(120) }
            assertTrue("API failure state missing", device.wait(Until.hasObject(By.textContains("暂不可用")), 15000))
            assertTrue("API error blocked local Rime", session.runOnReady { getCandidates(0, 3).isNotEmpty() })
            session.runOnReady { selectCandidate(0) }
            assertTrue("Local candidate failed to commit", device.wait(Until.hasObject(By.desc("test-editor").text("你好")), 5000))
        } catch (failure: Throwable) {
            device.takeScreenshot(java.io.File(context.getExternalFilesDir(null), "ai-failure.png"))
            device.dumpWindowHierarchy(java.io.File(context.getExternalFilesDir(null), "ai-failure.xml"))
            throw failure
        } finally {
            store.credentials.clear(); store.update { old.copy(enabled=false) }; RimeDaemon.destroySession("ai-flow-test")
        }
    }
}
