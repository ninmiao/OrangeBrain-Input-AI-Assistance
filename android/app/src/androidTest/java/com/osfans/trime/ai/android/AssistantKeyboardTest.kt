package com.osfans.trime.ai.android

import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.daemon.RimeDaemon
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay
import org.junit.Assert.*
import org.junit.Test

class AssistantKeyboardTest {
 @Test fun assistantHasSeparateRoleAndCommitsOnlyItsText()=exercise(false)
 @Test fun correctionCanCommitWhileAssistantIsStillStreaming()=exercise(true)
 @Test fun manualAssistantRetriesWhenBothAutomaticModesAreOff()=exercise(false, manual=true)
 private fun exercise(correction:Boolean, manual:Boolean=false)=runBlocking {
  val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins)
  val store=AiStore.get(ins.targetContext);val old=store.config
  val idle=Configurator.getInstance().waitForIdleTimeout;Configurator.getInstance().waitForIdleTimeout=0;d.wakeUp()
  val id=store.addPolicy("Assistant keyboard fixture")
  val s=RimeDaemon.createSession("assistant-keyboard-test")
  try {
   val endpoint="${TestNetwork.baseUrl}/v1/chat/completions"
   store.updatePolicyConfig(id){it.copy(endpoint=endpoint,model=if(manual) "assistant-retry-test" else "assistant-stream-test")}
   store.credentialsForPolicy(id).save(endpoint,"emulator-test-key");store.selectPolicy(id)
   store.update{it.copy(enabled=!manual,consent=true,automatic=true,assistantEnabled=!manual,traditional=false)}
   s.runOnReady{clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
   d.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
   val ime="${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService"
   d.executeShellCommand("ime enable $ime");d.executeShellCommand("ime set $ime")
   d.executeShellCommand("am start -W -f 0x10008000 -n ${ins.context.packageName}/${TestEditorActivity::class.java.name}")
   assertTrue(d.wait(Until.hasObject(By.desc("test-editor")),10000));d.findObject(By.desc("test-editor")).click()
   assertTrue(d.wait(Until.hasObject(By.res(ins.targetContext.packageName,"keyboard_view")),30000))
   s.runOnReady{clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
   d.findObject(By.desc("test-editor")).text="";d.waitForIdle();delay(350)
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
