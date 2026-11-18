package com.osfans.trime.ai.android

import android.accessibilityservice.AccessibilityServiceInfo
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.daemon.RimeDaemon
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.*
import org.junit.Test

class AssistantKeyboardTest {
 @Test fun assistantHasSeparateRoleAndCommitsOnlyItsText()=exercise(false)
 @Test fun correctionCanCommitWhileAssistantIsStillStreaming()=exercise(true)
 @Test fun manualAssistantRetriesWhenBothAutomaticModesAreOff()=exercise(false, manual=true)
 @Test fun directOnlyFollowsAnImeEditAndManualSelectionStillWorks()=exercise(false, direct=true)

 private fun exercise(correction:Boolean, manual:Boolean=false, direct:Boolean=false)=runBlocking {
  val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins)
  val store=AiStore.get(ins.targetContext);val old=store.config
  val idle=Configurator.getInstance().waitForIdleTimeout;Configurator.getInstance().waitForIdleTimeout=0;d.wakeUp()
  val id=store.addPolicy("Assistant keyboard fixture")
  val s=RimeDaemon.createSession("assistant-keyboard-test")
  try {
   val endpoint="${TestNetwork.baseUrl}/v1/chat/completions"
   store.updatePolicyConfig(id){it.copy(endpoint=endpoint,model=if(manual) "assistant-retry-test" else "assistant-stream-test")}
   store.credentialsForPolicy(id).save(endpoint,"emulator-test-key");store.selectPolicy(id)
   store.update{it.copy(enabled=!manual,consent=true,automatic=true,assistantEnabled=!manual,traditional=false,contextEnabled=!direct)}
   s.runOnReady{clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
   d.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
   val ime="${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService"
   d.executeShellCommand("ime enable $ime");d.executeShellCommand("ime set $ime")
   d.executeShellCommand("am start -W -f 0x10008000 -n ${ins.context.packageName}/${TestEditorActivity::class.java.name}")
   assertTrue(d.wait(Until.hasObject(By.desc("test-editor")),10000));d.findObject(By.desc("test-editor")).click()
   assertTrue(d.wait(Until.hasObject(By.res(ins.targetContext.packageName,"keyboard_view")),30000))
   s.runOnReady{clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
   d.findObject(By.desc("test-editor")).text="";d.waitForIdle();delay(350)
   if (direct) {
    fun select(start: Int, end: Int) {
     val selected = By.desc("test-selection").text("selection:$start:$end")
     if (d.hasObject(selected)) return
     val automation = ins.uiAutomation
     automation.serviceInfo = automation.serviceInfo.apply {
      flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
     }
     fun editor(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
      node ?: return null
      if (node.contentDescription?.toString() == "test-editor") return node
      for (i in 0 until node.childCount) editor(node.getChild(i))?.let { return it }
      return null
     }
     val range = Bundle().apply {
      putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, start)
      putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, end)
     }
     val field = automation.windows.asSequence().mapNotNull { editor(it.root) }.firstOrNull()
      ?: editor(automation.rootInActiveWindow)
     assertNotNull("Test editor accessibility node is missing", field)
     field!!.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, range)
     assertTrue("Editor selection did not move to $start..$end", d.wait(Until.hasObject(selected), 5000))
    }
    suspend fun count() = Json.parseToJsonElement(
     HttpsDownload.get(TestNetwork.baseUrl + "/stats", 1024).toString(Charsets.UTF_8)
    ).jsonObject.getValue("requests").jsonPrimitive.int

    val text = "An existing sentence. Fresh input "
    s.runOnReady { setRuntimeOption("ascii_mode", true) }
    d.findObject(By.desc("test-editor")).text = text
    select(text.length, text.length)
    val initial = count()
    s.runOnReady {
     assertTrue(processMixedKey('x'.code))
     assertTrue(processMixedKey(0xff0d))
    }
    assertTrue(d.wait(Until.hasObject(By.desc("test-editor").text(text + "x")), 5000))
    val suggestion = By.desc("AI 纠错：What should I eat?")
    assertTrue("A successful IME text commit should request a candidate", d.wait(Until.hasObject(suggestion), 10000))
    assertTrue(count() > initial)
    assertTrue(d.wait(Until.hasObject(By.desc("AI 状态：已返回")), 5000))
    select(5, 5)
    assertTrue(d.wait(Until.gone(suggestion), 5000))
    val afterEdit = count()
    delay(1000)
    assertEquals("Changing only the caret requested a candidate for old text", afterEdit, count())
    assertEquals(text + "x", d.findObject(By.desc("test-editor")).text)
    select(0, 2)
    d.findObject(By.desc("AI 重试或召唤助手")).click()
    assertTrue("Explicitly selected text should still work", d.wait(Until.hasObject(suggestion), 10000))
    return@runBlocking
   }
   "chishenme".forEach {c->s.runOnReady{processKey(c.code)};delay(35)}
   if(manual) {
    assertTrue(d.wait(Until.hasObject(By.desc("AI 状态：手动触发")),5000))
    delay(500)
    val trigger=By.desc("AI 重试或召唤助手")
    assertTrue(d.wait(Until.hasObject(trigger),5000))
    assertFalse(d.hasObject(By.descStartsWith("AI 纠错：")))
    d.findObject(trigger).click()
    assertTrue(d.wait(Until.hasObject(By.desc("AI 纠错：纠错第1次")),5000))
    d.findObject(trigger).click()
    assertTrue(d.wait(Until.hasObject(By.desc("AI 纠错：纠错第2次")),5000))
    assertFalse(d.hasObject(By.desc("AI 助手：助手第1次")))
    assertTrue(d.wait(Until.hasObject(By.desc("AI 助手：助手第2次")),10000))
    assertFalse(d.hasObject(By.desc("AI 纠错：纠错第1次")))
    d.findObject(By.desc("AI 助手：助手第2次")).click()
    assertTrue(d.wait(Until.hasObject(By.desc("test-editor").text("助手第2次")),5000))
    return@runBlocking
   }
   assertTrue(d.wait(Until.hasObject(By.desc("AI 纠错：吃什么？")),10000))
   assertTrue(d.hasObject(By.text("助手：生成中…")))
   assertTrue(d.hasObject(By.desc("AI 状态：生成中…")))
   assertFalse(d.hasObject(By.desc("AI 助手：吃碗面吧。")))
   if(correction) {
    d.findObject(By.desc("AI 纠错：吃什么？")).click()
    assertTrue(d.wait(Until.hasObject(By.desc("test-editor").text("吃什么？")),5000))
    delay(2500)
    assertEquals("吃什么？",d.findObject(By.desc("test-editor")).text)
    assertFalse(d.hasObject(By.desc("AI 助手：吃碗面吧。")))
    return@runBlocking
   }
   assertTrue(d.wait(Until.hasObject(By.desc("AI 助手：吃碗面吧。")),10000))
   assertTrue(d.wait(Until.hasObject(By.desc("AI 状态：已返回")),5000))
   d.findObject(By.desc("AI 助手：吃碗面吧。")).click()
   assertTrue(d.wait(Until.hasObject(By.desc("test-editor").text("吃碗面吧。")),5000))
  } finally {
   Configurator.getInstance().waitForIdleTimeout=idle
   s.runOnReady{clearComposition()};RimeDaemon.destroySession("assistant-keyboard-test")
   store.selectPolicy(old.selectedPolicyId);store.deletePolicy(id);store.update{old}
  }
 }
}
