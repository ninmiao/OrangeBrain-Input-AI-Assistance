package com.osfans.trime.ai.android
import android.content.Intent
import android.view.KeyEvent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.daemon.RimeDaemon
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class PolicyAndSegmentationTest {
    @Test fun singlePolicyLatencyDoesNotSwitchPoliciesOrRequireOtherKeys() {
        val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins)
        val store=AiStore.get(ins.targetContext);val old=store.config
        val id=store.addPolicy("Latency fixture");var activity:android.app.Activity?=null
        try {
            val endpoint="${TestNetwork.baseUrl}/v1/chat/completions"
            store.updatePolicyConfig(id){it.copy(endpoint=endpoint,model="mock")}
            store.credentialsForPolicy(id).save(endpoint,"emulator-test-key")
            fun count()=Json.parseToJsonElement(HttpsDownload.get("${TestNetwork.baseUrl}/stats",1024).toString(Charsets.UTF_8)).jsonObject.getValue("requests").jsonPrimitive.int
            val before=count()
            activity=ins.startActivitySync(Intent(ins.targetContext,AiSettingsActivity::class.java).putExtra("policy",id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            repeat(5) { if(!d.hasObject(By.text("测试当前 Policy 延迟"))) d.swipe(360,1050,360,450,20) }
            assertTrue(d.wait(Until.hasObject(By.text("测试当前 Policy 延迟")),5000))
            d.findObject(By.text("测试当前 Policy 延迟")).click()
            assertTrue(d.wait(Until.hasObject(By.textContains("完整候选返回")),5000))
            assertEquals(before+1,count());assertEquals(old.selectedPolicyId,store.config.selectedPolicyId)
        } finally { ins.runOnMainSync{activity?.finish()};store.deletePolicy(id);store.update{old} }
    }
    @Test fun spacesMarkWordsWithoutWritingRawTextAndToggleRestoresSpaceCommit()=runBlocking {
        val ins=InstrumentationRegistry.getInstrumentation();val d=UiDevice.getInstance(ins)
        val store=AiStore.get(ins.targetContext);val old=store.config;val s=RimeDaemon.createSession("segmentation-test")
        try {
            store.update{it.copy(enabled=true,consent=true,automatic=true,wordSegmentation=true,endpoint="${TestNetwork.baseUrl}/v1/chat/completions",model="segmentation-test",debounceMs=200)}
            store.credentials.save(store.config.endpoint,"emulator-test-key")
            d.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1")
            d.executeShellCommand("ime enable ${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            d.executeShellCommand("ime set ${ins.targetContext.packageName}/com.osfans.trime.ime.core.TrimeInputMethodService")
            ins.context.startActivity(Intent().setClassName(ins.context.packageName,TestEditorActivity::class.java.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertTrue(d.wait(Until.hasObject(By.desc("test-editor")),10000));d.findObject(By.desc("test-editor")).click()
            assertTrue(d.wait(Until.hasObject(By.res(ins.targetContext.packageName,"keyboard_view")),10000))
            s.runOnReady{clearComposition();selectSchema("rime_ai_simp");setRuntimeOption("ascii_mode",false)}
            d.findObject(By.desc("test-editor")).text="";d.waitForIdle();delay(350)
            suspend fun type(text:String){text.forEach{c->s.runOnReady{processKey(c.code)};delay(35)}}
            fun space(){val b=d.findObject(By.res(ins.targetContext.packageName,"keyboard_view")).visibleBounds;d.click(b.centerX(),b.bottom-b.height()/8);d.waitForIdle()}
            type("hanbaowang");space();type("haochi")
            assertTrue("raw="+s.run{rawInputCached}+" editor="+d.findObject(By.desc("test-editor")).text,d.wait(Until.hasObject(By.desc("正在输入：hanbaowang haochi")),5000))
            assertFalse("Raw text leaked into editor",d.findObject(By.desc("test-editor")).text.contains("hanbaowang"))
            assertTrue(d.wait(Until.hasObject(By.text("汉堡王好吃").clazz("android.widget.Button")),5000))
            d.findObject(By.text("汉堡王好吃").clazz("android.widget.Button")).click()
            assertTrue(d.wait(Until.hasObject(By.desc("test-editor").text("汉堡王好吃")),5000))
            d.findObject(By.desc("test-editor")).text="";d.waitForIdle();delay(350);s.runOnReady{clearComposition()}
            type("nihao");space();assertTrue(s.run{rawInputCached}.endsWith("'"))
            d.pressKeyCode(KeyEvent.KEYCODE_DEL);delay(300);assertEquals("nihao",s.run{rawInputCached})
            s.runOnReady{clearComposition()};store.update{it.copy(wordSegmentation=false,enabled=false)}
            type("nihao");space();assertTrue(d.wait(Until.hasObject(By.desc("test-editor").text("你好")),5000))
            d.findObject(By.desc("test-editor")).text="";d.waitForIdle();delay(350);store.update{it.copy(wordSegmentation=true)}
            s.runOnReady{setRuntimeOption("ascii_mode",true)};type("hello");space();type("world")
            assertTrue(d.wait(Until.hasObject(By.desc("test-editor").text("hello world")),5000))
        } finally {s.runOnReady{clearComposition()};store.credentials.clear();store.update{old.copy(enabled=false)};RimeDaemon.destroySession("segmentation-test")}
    }
}
