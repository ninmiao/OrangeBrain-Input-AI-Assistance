package com.osfans.trime.ai.android
import android.content.Intent
import android.os.SystemClock
import android.view.MotionEvent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.daemon.RimeDaemon
import com.osfans.trime.data.prefs.AppPrefs
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
class SpaceCursorTest {
    @Test fun holdSpaceMovesBothDirectionsWithoutTypingAndCancelDoesNotCommit() = runBlocking {
        val ins=InstrumentationRegistry.getInstrumentation(); val d=UiDevice.getInstance(ins)
        val store=AiStore.get(ins.targetContext); val old=store.config
        val session=RimeDaemon.createSession("space-cursor-test")
        try {
            store.update { it.copy(enabled=false) }
            d.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
            d.executeShellCommand("ime enable ${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            d.executeShellCommand("ime set ${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            ins.context.startActivity(Intent().setClassName(ins.context.packageName,TestEditorActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertTrue(d.wait(Until.hasObject(By.desc("test-editor")),10000))
            d.findObject(By.desc("test-editor")).click()
            session.runOnReady { setRuntimeOption("ascii_mode",true) }
            assertTrue(d.wait(Until.hasObject(By.res(ins.targetContext.packageName,"keyboard_view")),10000))
            d.findObject(By.desc("test-editor")).text="abcdefghijkl"
            d.waitForIdle()
            fun position()=d.findObject(By.desc("test-selection")).text.split(":")[1].toInt()
            val bounds=d.findObject(By.res(ins.targetContext.packageName,"keyboard_view")).visibleBounds
            val x=bounds.centerX().toFloat(); val y=(bounds.bottom-bounds.height()/8).toFloat()
            fun drag(delta:Float,cancel:Boolean=false) {
                val start=SystemClock.uptimeMillis()
                fun event(action:Int,px:Float) { val e=MotionEvent.obtain(start,SystemClock.uptimeMillis(),action,px,y,0); ins.uiAutomation.injectInputEvent(e,true);e.recycle() }
                event(MotionEvent.ACTION_DOWN,x)
                Thread.sleep(AppPrefs.defaultInstance().keyboard.longPressTimeout.getValue().toLong()+200)
                for(i in 1..8){event(MotionEvent.ACTION_MOVE,x+delta*i/8);Thread.sleep(35)}
                event(if(cancel) MotionEvent.ACTION_CANCEL else MotionEvent.ACTION_UP,x+delta)
                d.waitForIdle();Thread.sleep(300)
            }
            val before=position(); assertEquals(12,before)
            drag(-100f); val left=position(); assertTrue("Cursor did not move left: $left",left<before)
            assertEquals("abcdefghijkl",d.findObject(By.desc("test-editor")).text)
            drag(60f); assertTrue(position()>left)
            drag(0f,true); assertEquals("abcdefghijkl",d.findObject(By.desc("test-editor")).text)
            d.click(x.toInt(),y.toInt()); d.waitForIdle()
            assertEquals(13,d.findObject(By.desc("test-editor")).text.length)
        } finally { store.update { old }; RimeDaemon.destroySession("space-cursor-test") }
    }
}
