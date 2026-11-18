package com.osfans.trime.ai.android

import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.osfans.trime.daemon.RimeDaemon
import com.osfans.trime.data.prefs.AppPrefs
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EnglishTypingPreviewTest {
    @Test
    fun previewTracksEnglishEditsAndHidesInPasswordFields() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        val store = AiStore.get(instrumentation.targetContext)
        val old = store.config
        val session = RimeDaemon.createSession("english-typing-preview")
        val editor = By.desc("test-editor")
        val keyboard = By.res(instrumentation.targetContext.packageName, "keyboard_view")
        val anyPreview = By.descStartsWith("正在输入：")
        val numberRow = AppPrefs.defaultInstance().keyboard.numberRowEnabled
        val oldNumberRow = numberRow.getValue()
        fun tapKey(column: Double, row: Int) {
            val bounds = device.findObject(keyboard).visibleBounds
            device.click(bounds.left + (bounds.width() * column).toInt(),
                bounds.top + bounds.height() * (2 * row + 1) / 8)
            device.waitForIdle()
        }
        fun expect(text: String) {
            val matches = device.wait(Until.hasObject(By.desc("正在输入：$text").text(text)), 5000)
            assertTrue("Preview expected '$text', Rime had '${session.run { rawInputCached }}'", matches)
        }
        try {
            device.wakeUp()
            numberRow.setValue(false)
            store.update { it.copy(enabled = false, assistantEnabled = false) }
            device.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
            val ime = "${instrumentation.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService"
            device.executeShellCommand("ime enable $ime")
            device.executeShellCommand("ime set $ime")
            val testEditor = "${instrumentation.context.packageName}/${TestEditorActivity::class.java.name}"
            device.executeShellCommand("am start -W -f 0x10008000 -n $testEditor")
            assertTrue(device.wait(Until.hasObject(editor), 10000))
            device.findObject(editor).click()
            assertTrue(device.wait(Until.hasObject(keyboard), 30000))
            session.runOnReady {
                clearComposition()
                selectSchema("rime_ai_simp")
                setRuntimeOption("ascii_mode", true)
            }
            device.waitForIdle()
            assertFalse(device.hasObject(anyPreview))

            tapKey(.15, 0) // w
            tapKey(.25, 0) // e
            tapKey(.51, 3) // Space
            tapKey(.85, 0) // o
            tapKey(.80, 1) // k
            expect("we ok")
            tapKey(.92, 2) // Delete
            expect("we o")
            tapKey(.88, 3) // Enter
            assertTrue(device.wait(Until.gone(anyPreview), 5000))
            assertTrue(device.wait(Until.hasObject(By.desc("test-editor").text("we o")), 5000))
            tapKey(.10, 1) // a
            assertTrue(device.wait(Until.hasObject(By.desc("正在输入：a")), 5000))

            session.runOnReady { setRuntimeOption("ascii_mode", false) }
            assertTrue(device.wait(Until.gone(anyPreview), 5000))
            session.runOnReady { clearComposition() }
            "biru".forEach { c -> session.runOnReady { processKey(c.code) } }
            assertTrue(device.wait(Until.hasObject(By.desc("正在输入：biru")), 5000))

            device.findObject(By.desc("test-password")).click()
            session.runOnReady { setRuntimeOption("ascii_mode", true) }
            tapKey(.10, 1)
            assertTrue(device.wait(Until.gone(anyPreview), 5000))
        } finally {
            session.runOnReady { clearComposition() }
            RimeDaemon.destroySession("english-typing-preview")
            numberRow.setValue(oldNumberRow)
            store.update { old }
        }
    }
}
