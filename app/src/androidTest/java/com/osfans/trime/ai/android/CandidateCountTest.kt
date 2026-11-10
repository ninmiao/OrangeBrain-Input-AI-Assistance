package com.osfans.trime.ai.android
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.daemon.RimeDaemon
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class CandidateCountTest {
    @Test fun countSettingsAndHorizontalScrollAdoption()=runBlocking {
        val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins)
        val store=AiStore.get(ins.targetContext);val old=store.config
        val id=store.addPolicy("Candidate fixture")
        val s=RimeDaemon.createSession("candidate-scroll-test")
        var settings:android.app.Activity?=null
        try {
            assertEquals(3,Json.decodeFromString<AiConfig>("{}").candidateCount)
            store.update{it.copy(candidateCount=3)}
            settings=ins.startActivitySync(Intent(ins.targetContext,AiSettingsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            repeat(4){if(!d.hasObject(By.text("AI 候选数量：3 个 · 修改")))d.swipe(600,1050,600,400,20)}
            assertTrue(d.wait(Until.hasObject(By.text("AI 候选数量：3 个 · 修改")),5000))
            d.findObject(By.text("AI 候选数量：3 个 · 修改")).click()
            assertTrue(d.wait(Until.hasObject(By.text("5 个")),3000));d.findObject(By.text("5 个")).click()
            assertTrue(d.wait(Until.hasObject(By.text("AI 候选数量：5 个 · 修改")),5000))
            assertEquals(5,store.config.candidateCount)
            try {store.update{it.copy(candidateCount=6)};fail("Accepted invalid count")}catch(_:IllegalArgumentException){}
            val endpoint="${TestNetwork.baseUrl}/v1/chat/completions"
            store.updatePolicyConfig(id){it.copy(endpoint=endpoint,model="candidates-test")}
            store.credentialsForPolicy(id).save(endpoint,"emulator-test-key");store.selectPolicy(id)
            store.update{it.copy(enabled=true,consent=true,automatic=true,wordSegmentation=true,candidateCount=5)}
            d.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
            d.executeShellCommand("ime enable ${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            d.executeShellCommand("ime set ${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            ins.context.startActivity(Intent().setClassName(ins.context.packageName,TestEditorActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertTrue(d.wait(Until.hasObject(By.desc("test-editor")),10000));d.findObject(By.desc("test-editor")).click()
            assertTrue(d.wait(Until.hasObject(By.res(ins.targetContext.packageName,"keyboard_view")),10000))
            s.runOnReady{clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
            d.findObject(By.desc("test-editor")).text="";d.waitForIdle();delay(350)
            "nihao".forEach{c->s.runOnReady{processKey(c.code)};delay(35)}
            val first="第一候选用于验证横向滑动";val last="第五候选用于验证横向滑动"
            assertTrue(d.wait(Until.hasObject(By.desc("AI 候选：$first")),5000))
            val editorBeforeScroll=d.findObject(By.desc("test-editor")).text
            val row=d.findObject(By.desc("AI 候选列表，可左右滑动")).visibleBounds
            repeat(8){d.swipe(row.right-12,row.centerY(),row.left+12,row.centerY(),20)}
            assertTrue(d.hasObject(By.desc("AI 候选：$last")))
            assertEquals(editorBeforeScroll,d.findObject(By.desc("test-editor")).text)
            repeat(8){d.swipe(row.left+12,row.centerY(),row.right-12,row.centerY(),20)}
            assertTrue(d.hasObject(By.desc("AI 候选：$first")))
            repeat(8){d.swipe(row.right-12,row.centerY(),row.left+12,row.centerY(),20)}
            d.findObject(By.desc("AI 候选：$last")).click()
            assertTrue(d.wait(Until.hasObject(By.desc("test-editor").text(last)),5000))
        } finally {
            s.runOnReady{clearComposition()};RimeDaemon.destroySession("candidate-scroll-test")
            ins.runOnMainSync{settings?.finish()};store.selectPolicy(old.selectedPolicyId);store.deletePolicy(id);store.update{old}
        }
    }
}
