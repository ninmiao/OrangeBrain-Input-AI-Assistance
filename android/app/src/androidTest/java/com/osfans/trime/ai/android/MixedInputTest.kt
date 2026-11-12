package com.osfans.trime.ai.android
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import android.content.Intent
import android.view.KeyEvent
import com.osfans.trime.daemon.RimeDaemon
import com.osfans.trime.data.prefs.AppPrefs
import com.osfans.trime.data.theme.Theme
import com.osfans.trime.ime.keyboard.Keyboard
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
class MixedInputTest {
 @org.junit.Before fun initializeKeyboardViewport() {
  val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins)
  d.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
  d.executeShellCommand("ime enable ${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
  d.executeShellCommand("ime set ${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
  d.pressHome();d.waitForIdle()
  ins.context.startActivity(Intent().setClassName(ins.context.packageName,TestEditorActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
  d.waitForIdle()
  assertTrue(d.wait(Until.hasObject(By.desc("test-editor")),10000));d.findObject(By.desc("test-editor")).click()
  assertTrue(d.wait(Until.hasObject(By.res(ins.targetContext.packageName,"keyboard_view")),30000));d.waitForIdle()
 }
 @Test fun lettersDigitsAndEditingStayInBothLanguageCompositions()=runBlocking {
  val s=RimeDaemon.createSession("mixed-key-test")
  try {
   s.runOnReady{selectSchema("rime_ai_simp")}
   for(english in listOf(false,true)) for(text in listOf("nihao123test","123abc456","abc2026def",if(english) "hello 123 world" else "nihao123 shijie")) {
    s.runOnReady{clearComposition();setRuntimeOption("ascii_mode",english)}
    for(ch in text) s.runOnReady{if(!processMixedKey(ch.code))processKey(ch.code)}
    assertEquals("english=$english",text,s.run{rawInputCached})
    s.runOnReady{processMixedKey(0xff08)}
    assertEquals(text.dropLast(1),s.run{rawInputCached})
    s.runOnReady{processMixedKey(0xff0d)};assertEquals("",s.run{rawInputCached})
   }
  } finally {s.runOnReady{clearComposition();setRuntimeOption("ascii_mode",false)};RimeDaemon.destroySession("mixed-key-test")}
 }
 @Test fun numberRowCanBeDisabledAndUsesSmallFont()=runBlocking {
  val s=RimeDaemon.createSession("number-row-test");val prefs=AppPrefs.defaultInstance().keyboard;val old=prefs.numberRowEnabled.getValue()
  try {
   s.runOnReady{selectedSchemaId()};val theme=Theme.decodeByConfigId("rime_ai_ios");val cfg=theme.presetKeyboards.getValue("default")
   prefs.numberRowEnabled.setValue(false);val without=Keyboard(theme,cfg);assertEquals(4,without.keys.map{it.row}.distinct().size)
   prefs.numberRowEnabled.setValue(true);val with=Keyboard(theme,cfg);assertEquals(5,with.keys.map{it.row}.distinct().size)
   val row=with.keys.filter{it.row==0};assertEquals(10,row.size)
   row.forEach{assertEquals(16f,it.keyTextSize,0.01f)}
   assertTrue(with.height>without.height)
   row.zipWithNext().forEach{(a,b)->assertTrue(a.x+a.width<=b.x)}
  } finally {prefs.numberRowEnabled.setValue(old);RimeDaemon.destroySession("number-row-test")}
 }
 @Test fun numericPageDoesNotCommitDigitsAheadOfPinyin()=runBlocking {
  val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins);val store=AiStore.get(ins.targetContext);val old=store.config
  val s=RimeDaemon.createSession("mixed-page-test")
  try {
   store.update{it.copy(enabled=false,wordSegmentation=true)}
   d.findObject(By.desc("test-editor")).text="";d.waitForIdle();delay(500)
   s.runOnReady{clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
   for(ch in "nihao") {s.runOnReady{processKey(ch.code)};delay(30)}
   var b=d.findObject(By.res(ins.targetContext.packageName,"keyboard_view")).visibleBounds
   d.click(b.left+b.width()/14,b.bottom-b.height()/10);d.waitForIdle()
   b=d.findObject(By.res(ins.targetContext.packageName,"keyboard_view")).visibleBounds
   d.click(b.left+b.width()/20,b.top+b.height()/8);d.waitForIdle();delay(200)
   assertEquals("nihao1",s.run{rawInputCached});assertFalse(d.findObject(By.desc("test-editor")).text.contains("1"))
   d.pressKeyCode(KeyEvent.KEYCODE_ENTER);delay(250)
   assertEquals("nihao1",d.findObject(By.desc("test-editor")).text)
  } finally {s.runOnReady{clearComposition()};RimeDaemon.destroySession("mixed-page-test");store.update{old}}
 }
}
