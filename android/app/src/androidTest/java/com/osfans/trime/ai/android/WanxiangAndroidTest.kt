package com.osfans.trime.ai.android

import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.osfans.trime.data.base.DataManager
import com.osfans.trime.daemon.RimeDaemon
import com.osfans.trime.rime.*
import com.osfans.trime.rime.android.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

class WanxiangAndroidTest {
    @Test fun dictionaryScreenShowsDownloadAndEnabledGrammar() {
        val ins=InstrumentationRegistry.getInstrumentation();val device=UiDevice.getInstance(ins)
        val activity=ins.startActivitySync(Intent(ins.targetContext,WanxiangActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        try {
            assertTrue(device.wait(Until.hasObject(By.text("更新万象词表")),10000))
            assertTrue(device.findObject(By.desc("万象语法模型开关")).isChecked)
            assertTrue(device.hasObject(By.text("更新雾凇词表")))
        } finally { ins.runOnMainSync { activity.finish() } }
    }
    @Test fun bundledTablesSwitchOfflineWithAndWithoutCachedGrammar()=runBlocking {
        val updater=WanxiangUpdater(DataManager.userDataDir,AndroidWanxiangActivator,catalog={error("No network expected")},bundledDirectory=DataManager.sharedDataDir,iceCatalog={error("No network expected")})
        val old=updater.state()
        val session=RimeDaemon.createSession("dual-bundled-test")
        try {
            assertNotNull(old.dictionary);assertNotNull(old.iceDictionary)
            for(wanxiang in listOf(true,false,true)) {
                updater.selectDictionary(wanxiang,false)
                assertEquals(if(wanxiang)WanxiangUpdater.SCHEMA else WanxiangUpdater.FALLBACK,session.runOnReady {selectedSchemaId()})
                session.runOnReady {
                    clearComposition();setRuntimeOption("ascii_mode",false);setRuntimeOption("traditionalization",false)
                    for(c in "ruanjian")processKey(c.code)
                    assertTrue("软件" in getCandidates(0,10).map {it.text})
                    clearComposition();for(c in "rgzn")processKey(c.code)
                    assertTrue("人工智能" in getCandidates(0,10).map {it.text});clearComposition()
                }
                assertFalse(File(DataManager.userDataDir,"zephyr_wanxiang.schema.yaml").readText().contains("grammar:"))
            }
            updater.selectDictionary(true,true)
            updater.selectDictionary(false);assertTrue(updater.state().grammar)
            updater.selectDictionary(true);assertTrue(updater.state().grammar)
            if(old.model!=null) assertTrue(File(DataManager.userDataDir,"zephyr_wanxiang.schema.yaml").readText().contains("grammar:"))
        } finally {session.runOnReady {clearComposition()};RimeDaemon.destroySession("dual-bundled-test");updater.selectDictionary(old.enabled,old.grammar)}
    }
    @Test fun realWanxiangDeploymentGrammarAndSegmentedSelection()=runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("wanxiang")=="1")
        val user=DataManager.userDataDir
        val report=File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null),"wanxiang-test-report.txt")
        val network=WanxiangNetwork()
        val dict=network.release(false);val model=network.release(true)
        val updater=WanxiangUpdater(user,AndroidWanxiangActivator,network,{ if(it)model else dict },{report.appendText("${it.message}: ${it.done}/${it.total}\n")})
        val store=AiStore.get(InstrumentationRegistry.getInstrumentation().targetContext);val old=store.config
        val session=RimeDaemon.createSession("wanxiang-regression")
        try {
            store.update {it.copy(enabled=false)}
            updater.update()
            assertTrue(updater.state().grammar)
            assertTrue(File(user,"build/zephyr_wanxiang.schema.yaml").readText().contains(WanxiangUpdater.modelName(model)))
            assertTrue("Grammar model must be mapped by Rime",File("/proc/self/maps").readText().contains(WanxiangUpdater.modelName(model)))
            session.runOnReady {assertEquals(WanxiangUpdater.SCHEMA,selectedSchemaId());setRuntimeOption("ascii_mode",false)}
            for((input,expected) in listOf("nihao" to "你好","ruanjian" to "软件","nihoa" to "你好","shurufa" to "输入法","zhongguo" to "中国")) {
                session.runOnReady {
                    clearComposition();setRuntimeOption("traditionalization",false)
                    for(c in input)processKey(c.code)
                    val words=getCandidates(0,10).map {it.text};assertTrue("$input: $words",expected in words)
                    report.appendText("$input -> $words\n")
                }
            }
            session.runOnReady {
                clearComposition();for(c in "xianzaishurufahouxuanyouwenti")processKey(c.code)
                val index=getCandidates(0,10).indexOfFirst {it.text=="现在"};assertTrue(index>=0);assertTrue(selectCandidate(index))
                assertTrue(rawInputCached.contains("shurufa"));assertTrue(compositionCached.preedit.orEmpty().startsWith("现在"))
                clearComposition();setRuntimeOption("traditionalization",true);for(c in "ruanjian")processKey(c.code)
                assertTrue("軟件" in getCandidates(0,10).map {it.text});clearComposition();setRuntimeOption("traditionalization",false)
            }
            updater.useFallback();assertTrue(updater.state().grammar);assertEquals(WanxiangUpdater.FALLBACK,session.runOnReady {selectedSchemaId()})
            updater.update(false);assertFalse(updater.state().grammar)
            updater.update();assertTrue(updater.state().grammar)
            report.appendText("PASS: grammar, full pinyin, typo, traditionalization, segmented selection, fallback, model toggle\n")
        } finally { session.runOnReady {clearComposition()};RimeDaemon.destroySession("wanxiang-regression");store.update {old} }
    }
    @Test fun updateButtonRunsForegroundService() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("wanxiang")=="1")
        val ins=InstrumentationRegistry.getInstrumentation();val device=UiDevice.getInstance(ins)
        val session=RimeDaemon.createSession("wanxiang-button-test")
        runBlocking {session.runOnReady {clearComposition();selectSchema(WanxiangUpdater.FALLBACK)}}
        val activity=ins.startActivitySync(Intent(ins.targetContext,WanxiangActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        try {
            assertTrue(device.wait(Until.hasObject(By.text("更新万象词表")),10000))
            device.findObject(By.text("应用选择（离线）")).click()
            val deadline=System.currentTimeMillis()+600000
            while(System.currentTimeMillis()<deadline && !WanxiangDownloadService.state.value.progress.message.contains("Ready"))Thread.sleep(100)
            assertTrue(WanxiangDownloadService.state.value.progress.message,WanxiangDownloadService.state.value.progress.message.contains("Ready"))
            assertEquals(WanxiangUpdater.SCHEMA,runBlocking {session.runOnReady {selectedSchemaId()}})
        } finally { ins.runOnMainSync {activity.finish()};RimeDaemon.destroySession("wanxiang-button-test") }
    }
}
