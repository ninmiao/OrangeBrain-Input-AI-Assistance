package com.osfans.trime.ai.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.data.prefs.AppPrefs
import com.osfans.trime.daemon.RimeDaemon
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class ClipboardTest {
    @Test fun currentClipboardPastesWithHistoryOffAndRefreshesAfterCopy()=runBlocking {
        val ins=InstrumentationRegistry.getInstrumentation();val device=UiDevice.getInstance(ins)
        val store=AiStore.get(ins.targetContext);val old=store.config
        val pref=AppPrefs.defaultInstance().clipboard.clipboardLimit;val oldLimit=pref.getValue()
        val session=RimeDaemon.createSession("clipboard-test")
        try {
            store.update {it.copy(enabled=false)};pref.setValue(0)
            session.runOnReady {clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
            ins.context.startActivity(Intent().setClassName(ins.context.packageName,TestEditorActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertTrue(device.wait(Until.hasObject(By.desc("剪贴板")),10000))
            fun copy(text:String) {ins.runOnMainSync {(ins.targetContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("fixture",text))}}
            fun paste(text:String) {
                device.findObject(By.desc("剪贴板")).click()
                assertTrue(device.wait(Until.hasObject(By.textStartsWith("当前复制 · ")),5000))
                device.findObject(By.textStartsWith("当前复制 · ")).click()
                if (!device.wait(Until.hasObject(By.desc("test-editor").text(text)),5000)) {
                    assertEquals("Pasting must preserve the current composition",text,device.findObject(By.desc("test-editor"))?.text)
                }
            }
            copy("剪贴板 Paste 123");paste("剪贴板 Paste 123")
            device.findObject(By.desc("test-editor")).text=""
            copy("第二次\n完整内容");paste("第二次\n完整内容")
            device.findObject(By.desc("test-editor")).text=""
            // Exercise actual key events and let editor selection callbacks settle between keys.
            device.findObject(By.desc("test-editor")).click()
            device.waitForIdle()
            session.runOnReady {clearComposition();assertTrue(selectSchema("rime_ai_simp"));setRuntimeOption("ascii_mode",false)}
            for (ch in "NIHAO") {
                device.pressKeyCode(android.view.KeyEvent.keyCodeFromString("KEYCODE_$ch"))
                device.waitForIdle()
            }
            assertEquals("nihao",session.run {rawInputCached})
            copy(" + clipboard");paste("你好 + clipboard")
            assertEquals("",session.runOnReady {rawInputCached})
        } finally {
            device.pressHome()
            session.runOnReady {clearComposition()};RimeDaemon.destroySession("clipboard-test")
            pref.setValue(oldLimit);store.update {old}
        }
    }
}
