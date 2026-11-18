package com.osfans.trime.ai.android

import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.daemon.RimeDaemon
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class CandidateCountTest {
    @Test fun oldCountsMigrateAndPolicyListShowsEffectiveParameters() {
        val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins)
        val store=AiStore.get(ins.targetContext);val old=store.config
        var settings:android.app.Activity?=null
        val ids=mutableListOf<String>()
        try {
            // Exercise loading an actual pre-upgrade saved configuration.
            File(ins.targetContext.noBackupFilesDir,"ai-config.json").writeText(
                Json { encodeDefaults=true }.encodeToString(
                    old.copy(policyVersion=6,candidateCount=5,completion=true,enabled=false,assistantEnabled=true)))
            val migrated=AiStore(ins.targetContext).config
            assertEquals(1,migrated.candidateCount);assertFalse(migrated.completion)
            assertFalse(migrated.assistantEnabled)
            assertEquals(old.policies,migrated.policies);assertEquals(old.selectedPolicyId,migrated.selectedPolicyId)
            store.update { old.copy(candidateCount=5,completion=true,assistantEnabled=false) }
            assertEquals(1,store.config.candidateCount);assertFalse(store.config.completion)
            val first=store.addPolicy("Policy summary fast").also { ids+=it }
            val second=store.addPolicy("Policy summary normal").also { ids+=it }
            store.updatePolicyConfig(first) { it.copy(modelValues=mapOf(it.model to mapOf(
                "reasoning_effort" to JsonPrimitive("low"),"service_tier" to JsonPrimitive("priority")))) }
            assertEquals("思考：轻度 · 速度：Fast / 优先",store.policyParameterSummary(store.config.policies.first { it.id==first }))
            assertEquals("思考：轻度 · 速度：Fast / 优先",store.policyParameterSummary(store.config.policies.first { it.id==second }))
            store.updatePolicyConfig(second) { it.copy(modelValues=emptyMap()) }
            assertEquals("思考：服务端默认 · 速度：服务端默认",store.policyParameterSummary(store.config.policies.first { it.id==second }))
            settings=ins.startActivitySync(Intent(ins.targetContext,AiSettingsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertTrue(d.wait(Until.hasObject(By.text("自动纠错")),5000))
            assertTrue(d.hasObject(By.text("自动助手（含纠错）")))
            assertFalse(d.hasObject(By.textStartsWith("AI 候选数量")))
            assertFalse(d.hasObject(By.text("显示独立补全")))
            val selector=By.desc("选择 Policy Policy summary fast")
            repeat(15) { if(!d.hasObject(selector))d.swipe(d.displayWidth/2,d.displayHeight*4/5,d.displayWidth/2,d.displayHeight/4,20) }
            assertTrue(d.hasObject(selector))
            val row=d.findObject(selector).text
            assertTrue(row.contains(TerraDefaults.MODEL));assertTrue(row.contains("思考：轻度 · 速度：Fast / 优先"))
        } finally {
            ins.runOnMainSync { settings?.finish() }
            ids.forEach { store.deletePolicy(it) };store.update { old }
        }
    }

    @Test fun oneCandidateRequestedAndOnlyBestResponseCanBeAdopted()=runBlocking {
        val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins)
        val store=AiStore.get(ins.targetContext);val old=store.config
        val id=store.addPolicy("Single candidate fixture")
        val s=RimeDaemon.createSession("single-candidate-test")
        try {
            val endpoint="${TestNetwork.baseUrl}/v1/chat/completions"
            store.updatePolicyConfig(id) { it.copy(endpoint=endpoint,model="candidates-test") }
            store.credentialsForPolicy(id).save(endpoint,"emulator-test-key");store.selectPolicy(id)
            store.update { it.copy(enabled=true,assistantEnabled=false,consent=true,automatic=true,wordSegmentation=true,traditional=false) }
            assertTrue(store.prompt(store.config,true).contains("一个完整候选"))
            // Rime deployment and cold IME creation can outlast the old 10-second UI wait.
            s.runOnReady { clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false) }
            d.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
            d.executeShellCommand("ime enable ${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            d.executeShellCommand("ime set ${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            ins.context.startActivity(Intent().setClassName(ins.context.packageName,TestEditorActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertTrue(d.wait(Until.hasObject(By.desc("test-editor")),10000));d.findObject(By.desc("test-editor")).click()
            assertTrue(d.wait(Until.hasObject(By.res(ins.targetContext.packageName,"keyboard_view")),30000))
            s.runOnReady { clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false) }
            d.findObject(By.desc("test-editor")).text="";d.waitForIdle();delay(350)
            "nihao".forEach { c->s.runOnReady { processKey(c.code) };delay(35) }
            val first="你好，这是一段用于验证单个长候选仍然可以横向查看并点击上屏的文字。"
            assertTrue(d.wait(Until.hasObject(By.desc("AI 候选：$first")),5000))
            assertEquals(1,d.findObjects(By.descStartsWith("AI 候选：")).size)
            assertFalse(d.hasObject(By.descStartsWith("AI 补全：")))
            val before=d.findObject(By.desc("test-editor")).text
            val row=d.findObject(By.desc("AI 候选列表，可左右滑动")).visibleBounds
            d.swipe(row.right-12,row.centerY(),row.left+12,row.centerY(),20)
            assertEquals(before,d.findObject(By.desc("test-editor")).text)
            d.swipe(row.left+12,row.centerY(),row.right-12,row.centerY(),20)
            d.findObject(By.desc("AI 候选：$first")).click()
            assertTrue(d.wait(Until.hasObject(By.desc("test-editor").text(first)),5000))
        } finally {
            s.runOnReady { clearComposition() };RimeDaemon.destroySession("single-candidate-test")
            store.selectPolicy(old.selectedPolicyId);store.deletePolicy(id);store.update { old }
        }
    }
}
