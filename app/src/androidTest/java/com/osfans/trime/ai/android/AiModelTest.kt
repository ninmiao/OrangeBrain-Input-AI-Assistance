package com.osfans.trime.ai.android

import android.content.ContextWrapper
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.ai.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

class AiModelTest {
    @Test fun modelValuesPersistPruneAndStayBoundToEndpoint() {
        val original = InstrumentationRegistry.getInstrumentation().targetContext
        val dir = File(original.noBackupFilesDir, "model-test-${UUID.randomUUID()}").apply { mkdirs() }
        val context = object : ContextWrapper(original) { override fun getNoBackupFilesDir() = dir }
        try {
            val store = AiStore(context)
            val endpoint = "https://example.com/v1/chat/completions"
            store.update { it.copy(endpoint = endpoint, model = "a") }
            val pack = ModelCatalog(models = listOf(ModelCatalog.template("a"), ModelCatalog.template("b")))
            store.replaceModelCatalog(pack, endpoint)
            val values = mapOf("reasoning_effort" to JsonPrimitive("low"), "service_tier" to JsonPrimitive("priority"))
            store.saveParameters(endpoint, "a", values)
            assertEquals(values, AiStore(context).parameters())
            store.update { it.copy(model = "b") }; assertTrue(store.parameters().isEmpty())
            store.update { it.copy(model = "a") }; assertEquals(values, store.parameters())
            val generation = store.config.generation
            val modified = pack.copy(models = pack.models.map { it.copy(parameters = it.parameters.filter { p -> p.key != "service_tier" }) })
            store.replaceModelCatalog(modified, endpoint)
            assertTrue(store.config.generation > generation)
            assertEquals(mapOf("reasoning_effort" to JsonPrimitive("low")), store.parameters())
            try { store.saveParameters(endpoint, "a", mapOf("temperature" to JsonPrimitive(10))); fail() } catch (_: IllegalArgumentException) { }
            assertEquals(JsonPrimitive("low"), store.parameters()["reasoning_effort"])
            store.update { it.copy(endpoint = "https://different.example/v1/chat/completions") }
            assertTrue(store.parameters().isEmpty()); assertTrue(store.config.modelCatalog.models.isEmpty())
        } finally { dir.deleteRecursively() }
    }

    @Test fun httpsDiscoveryParameterPayloadAndPublicCatalog() = runBlocking {
        val endpoint = "${TestNetwork.baseUrl}/v1/chat/completions"
        assertTrue(ModelsClient().fetch(endpoint, "emulator-test-key").contains("parameter-test"))
        val pack = ModelCatalog.parse(HttpsDownload.get("${TestNetwork.baseUrl}/model-catalog.json", ModelCatalog.MAX_BYTES))
        assertEquals("parameter-test", pack.models.first().id)
        val store = AiStore.get(InstrumentationRegistry.getInstrumentation().targetContext)
        val request = AiRequest(RequestStamp(1,1,1,1,1), AiInput("nihao"), store.builtin.compose("original", true, false), false)
        val parameters = mapOf("reasoning_effort" to JsonPrimitive("low"), "service_tier" to JsonPrimitive("priority"), "max_completion_tokens" to JsonPrimitive(128))
        val result = ChatCompletionsClient().request(endpoint, "emulator-test-key", "parameter-test", request, parameters = parameters)
        assertEquals("Parameters accepted", result.candidates.single())
    }

    @Test fun modelSettingsSelectsReasoningAndFastWithoutAutomaticDefaults() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        device.executeShellCommand("cmd statusbar collapse")
        val store = AiStore.get(instrumentation.targetContext)
        val old = store.config
        var activity: android.app.Activity? = null
        try {
            store.update { it.copy(endpoint = "${TestNetwork.baseUrl}/v1/chat/completions", model = "parameter-test") }
            store.replaceModelCatalog(ModelCatalog(models = listOf(ModelCatalog.template("parameter-test"))), store.config.endpoint)
            assertTrue(store.parameters().isEmpty())
            activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, ModelSettingsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            fun reveal(selector: BySelector) {
                repeat(15) {
                    if (device.hasObject(selector)) return
                    device.swipe(device.displayWidth / 2, device.displayHeight * 4 / 5, device.displayWidth / 2, device.displayHeight / 4, 30)
                    Thread.sleep(200)
                }
                assertTrue("Model control missing", device.hasObject(selector))
            }
            assertTrue(device.wait(Until.hasObject(By.textStartsWith("当前模型：parameter-test")), 10000))
            reveal(By.textStartsWith("服务档位："))
            device.findObject(By.textStartsWith("服务档位：")).click()
            assertTrue(device.wait(Until.hasObject(By.textStartsWith("Fast /")), 5000))
            device.findObject(By.textStartsWith("Fast /")).click()
            assertTrue(device.wait(Until.hasObject(By.textStartsWith("参数已保存")), 5000))
            reveal(By.textStartsWith("推理强度："))
            device.findObject(By.textStartsWith("推理强度：")).click()
            assertTrue(device.wait(Until.hasObject(By.text("轻度")), 5000))
            device.findObject(By.text("轻度")).click()
            Thread.sleep(500)
            assertEquals(JsonPrimitive("priority"), store.parameters()["service_tier"])
            assertEquals(JsonPrimitive("low"), store.parameters()["reasoning_effort"])
            assertFalse(store.parameters().containsKey("temperature"))
            reveal(By.textStartsWith("输出 Token 上限"))
            device.findObject(By.textStartsWith("输出 Token 上限")).click()
            assertTrue(device.wait(Until.hasObject(By.text("输出 Token 上限（包含推理）")), 5000))
            device.findObject(By.clazz("android.widget.EditText")).text = "128"
            device.findObject(By.text("保存")).click()
            assertTrue(device.wait(Until.hasObject(By.textStartsWith("参数已保存")), 5000))
            Thread.sleep(500)
            assertEquals(JsonPrimitive(128), store.parameters()["max_completion_tokens"])
            val request = AiRequest(RequestStamp(1,1,1,1,1), AiInput("nihao"), store.builtin.compose("original", true, false), false)
            val result = ChatCompletionsClient().request(store.config.endpoint, "emulator-test-key", store.config.model, request, parameters = store.parameters())
            assertEquals("Parameters accepted", result.candidates.single())
        } catch (failure: Throwable) {
            device.dumpWindowHierarchy(File(instrumentation.targetContext.getExternalFilesDir(null), "model-settings-failure.xml"))
            throw failure
        } finally {
            instrumentation.runOnMainSync { activity?.finish() }
            store.update { old }
        }
    }
}
