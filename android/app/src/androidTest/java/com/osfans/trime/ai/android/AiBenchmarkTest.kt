package com.osfans.trime.ai.android

import android.content.ContextWrapper
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.ai.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

class AiBenchmarkTest {
    @Test fun configurationsPersistPerPolicyAndInvalidWritesPreservePreviousData() {
        val original = InstrumentationRegistry.getInstrumentation().targetContext
        val folder = File(original.noBackupFilesDir, "benchmark-test-${UUID.randomUUID()}").apply { mkdirs() }
        val context = object : ContextWrapper(original) { override fun getNoBackupFilesDir() = folder }
        try {
            val first = BenchmarkStore(context, "first")
            assertEquals(5, first.read().entries.size)
            val expected = BenchmarkConfig(entries = listOf(BenchmarkEntry("custom-model", "low", "priority"), BenchmarkEntry(ApiRouting.DEEPSEEK, api="openrouter")), sample = "hello", chinese = false, timeoutMs = 3000)
            first.save(expected)
            assertEquals(expected, BenchmarkStore(context, "first").read())
            assertEquals(BenchmarkConfig(), BenchmarkStore(context, "second").read())
            try { first.save(expected.copy(entries = List(6) { BenchmarkEntry() })); fail("Accepted six rows") } catch (_: IllegalArgumentException) { }
            assertEquals(expected, first.read())
            first.clear(); assertEquals(BenchmarkConfig(), first.read())
        } finally { folder.deleteRecursively() }
    }
    @Test fun mixedPagePersistsBothApisAndRequiresSeparateKeysBeforeSending() {
        val ins=InstrumentationRegistry.getInstrumentation();val context=ins.targetContext
        val device=UiDevice.getInstance(ins);val store=AiStore.get(context);val old=store.config
        val saved=BenchmarkStore(context,"mixed-v2");val previous=saved.read()
        var activity:android.app.Activity?=null
        try {
            saved.save(BenchmarkConfig())
            activity=ins.startActivitySync(Intent(context,BenchmarkActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertTrue(device.wait(Until.hasObject(By.textContains("OpenAI + OpenRouter")),10000))
            device.findObject(By.desc("一键开始测速")).click()
            assertTrue(device.wait(Until.hasObject(By.textContains("尚未配置 Key")),5000))
            assertEquals(setOf("openai","openrouter"),saved.read().entries.map{it.api}.toSet())
            assertEquals(old.selectedPolicyId,store.config.selectedPolicyId)
            assertTrue(device.findObject(By.desc("一键开始测速")).isEnabled)
        } finally { ins.runOnMainSync { activity?.finish() };saved.save(previous) }
    }
}
