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
 @Test fun assistantHasSeparateRoleAndCommitsOnlyItsText()=runBlocking {
  val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins)
  val store=AiStore.get(ins.targetContext);val old=store.config
  val id=store.addPolicy("Assistant keyboard fixture")
  val s=RimeDaemon.createSession("assistant-keyboard-test")
  try {
   val endpoint="${TestNetwork.baseUrl}/v1/chat/completions"
   store.updatePolicyConfig(id){it.copy(endpoint=endpoint,model="assistant-test")}
   store.credentialsForPolicy(id).save(endpoint,"emulator-test-key");store.selectPolicy(id)
   store.update{it.copy(enabled=true,consent=true,automatic=true,assistantEnabled=true,traditional=false)}
   s.runOnReady{clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
   d.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
   val ime="${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService"
   d.executeShellCommand("ime enable $ime");d.executeShellCommand("ime set $ime")
   ins.context.startActivity(Intent().setClassName(ins.context.packageName,TestEditorActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
   assertTrue(d.wait(Until.hasObject(By.desc("test-editor")),10000));d.findObject(By.desc("test-editor")).click()
   assertTrue(d.wait(Until.hasObject(By.res(ins.targetContext.packageName,"keyboard_view")),30000))
   s.runOnReady{clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
   d.findObject(By.desc("test-editor")).text="";d.waitForIdle();delay(350)
   "chishenme".forEach {c->s.runOnReady{processKey(c.code)};delay(35)}
   assertTrue(d.wait(Until.hasObject(By.desc("AI 纠错：吃什么？")),10000))
   assertTrue(d.hasObject(By.desc("AI 助手：吃碗面吧。")))
   d.findObject(By.desc("AI 助手：吃碗面吧。")).click()
   assertTrue(d.wait(Until.hasObject(By.desc("test-editor").text("吃碗面吧。")),5000))
  } finally {
   s.runOnReady{clearComposition()};RimeDaemon.destroySession("assistant-keyboard-test")
   store.selectPolicy(old.selectedPolicyId);store.deletePolicy(id);store.update{old}
  }
 }
}
