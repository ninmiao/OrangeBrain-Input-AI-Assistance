// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.content.ContextWrapper
import android.content.Intent
import android.view.KeyEvent
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.osfans.trime.data.prefs.AppPrefs
import com.osfans.trime.data.theme.Theme
import com.osfans.trime.daemon.RimeDaemon
import com.osfans.trime.ime.keyboard.Keyboard
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

class AiRedesignTest {
    @Test fun legacyCredentialMigrationAndIndependentPolicies() {
        val original = InstrumentationRegistry.getInstrumentation().targetContext
        val folder = File(original.noBackupFilesDir, "policy-test-${UUID.randomUUID()}").apply { mkdirs() }
        val context = object : ContextWrapper(original) { override fun getNoBackupFilesDir() = folder }
        var second = ""
        try {
            val legacy = AiConfig(modelCatalog = com.osfans.trime.ai.ModelCatalog(), modelValues = emptyMap())
            val obj = Json { encodeDefaults = true }.encodeToJsonElement(legacy).jsonObject
            File(folder, "ai-config.json").writeText(JsonObject(obj - setOf("policies", "selectedPolicyId", "policyVersion", "traditional")).toString())
            CredentialStore(context).save(legacy.endpoint, "legacy-test-key")
            val store = AiStore(context)
            assertEquals("legacy-test-key", store.credentials.read(legacy.endpoint))
            assertEquals("none", store.parameters()["reasoning_effort"]!!.content)
            assertEquals("default", store.parameters()["service_tier"]!!.content)
            assertEquals(2, store.config.policies.size)
            assertEquals("wafer/us", store.configForPolicy("openrouter").provider)
            assertFalse(store.credentialsForPolicy("openrouter").hasCredential())
            second = store.addPolicy("Independent")
            assertFalse(store.credentialsForPolicy(second).hasCredential())
            store.credentialsForPolicy(second).save(legacy.endpoint, "other-test-key")
            store.updatePolicyConfig(second) { it.copy(localOverride = store.builtin.copy(base_prompt = "Independent prompt")) }
            assertEquals("default", store.config.selectedPolicyId)
            assertNotEquals("Independent prompt", store.effective().base_prompt)
            val generation = store.config.generation
            store.selectPolicy(second)
            assertTrue(store.config.generation > generation)
            assertEquals("other-test-key", store.credentials.read(legacy.endpoint))
            assertEquals("Independent prompt", store.effective().base_prompt)
            val reload = AiStore(context)
            assertEquals(second, reload.config.selectedPolicyId)
            reload.selectPolicy("default")
            assertEquals("legacy-test-key", reload.credentials.read(legacy.endpoint))
            assertNotEquals("Independent prompt", reload.effective().base_prompt)
            reload.deletePolicy(second)
            assertEquals(2, reload.config.policies.size)
            assertEquals("legacy-test-key", reload.credentials.read(legacy.endpoint))
            assertFalse(File(folder, "ai-config.json").readText().contains("test-key"))
        } finally {
            CredentialStore(context).clear()
            if (second.isNotEmpty()) CredentialStore(context, "rime-ai-policy-$second", "ai-credential-$second.bin").clear()
            folder.deleteRecursively()
        }
    }
    @Test fun qwertyRowsBoundsAndAdjustableHeight() = runBlocking {
        val session = RimeDaemon.createSession("layout-test")
        val prefs = AppPrefs.defaultInstance().keyboard
        val originalHeight = prefs.keyboardHeightDp.getValue()
        try {
            session.runOnReady { selectedSchemaId() }
            val theme = Theme.decodeByConfigId("rime_ai_ios")
            val colors = theme.colorSchemes.first { it.id == "default" }.colors
            for (name in listOf("hilited_candidate_text_color", "candidate_text_color", "off_key_text_color"))
                assertEquals("Invisible text: $name", 255, android.graphics.Color.alpha(com.osfans.trime.util.ColorUtils.parseColor(colors.getValue(name))))
            prefs.keyboardHeightDp.setValue(250)
            val keyboard = Keyboard(theme, theme.presetKeyboards.getValue("default"))
            val rows = keyboard.keys.groupBy { it.row }
            assertEquals(listOf(10, 9, 9, 4), rows.toSortedMap().values.map { it.size })
            assertEquals("qwertyuiop", rows[0]!!.map { ('a'.code + it.code - KeyEvent.KEYCODE_A).toChar() }.joinToString(""))
            assertEquals("asdfghjkl", rows[1]!!.map { ('a'.code + it.code - KeyEvent.KEYCODE_A).toChar() }.joinToString(""))
            assertEquals(KeyEvent.KEYCODE_SHIFT_LEFT, rows[2]!!.first().code)
            assertEquals(KeyEvent.KEYCODE_DEL, rows[2]!!.last().code)
            assertEquals(KeyEvent.KEYCODE_SWITCH_CHARSET, rows[3]!![1].code)
            assertEquals(KeyEvent.KEYCODE_SPACE, rows[3]!![2].code)
            assertEquals(KeyEvent.KEYCODE_ENTER, rows[3]!!.last().code)
            rows.values.forEach { row ->
                row.zipWithNext().forEach { (left, right) -> assertTrue(left.x + left.width <= right.x) }
                row.forEach { assertTrue(it.x >= 0 && it.width > 0 && it.height > 0 && it.y + it.height <= keyboard.height) }
            }
            assertTrue(rows[1]!!.first().x > rows[0]!!.first().x)
            prefs.keyboardHeightDp.setValue(310)
            assertTrue(Keyboard(theme, theme.presetKeyboards.getValue("default")).height > keyboard.height)
            listOf("ios_numbers", "ios_symbols").forEach { name ->
                assertEquals(4, Keyboard(theme, theme.presetKeyboards.getValue(name)).keys.map { it.row }.distinct().size)
            }
        } finally { prefs.keyboardHeightDp.setValue(originalHeight); RimeDaemon.destroySession("layout-test") }
    }
    @Test fun nativeScriptToggleAndPromptFollowSameState() = runBlocking {
        val session = RimeDaemon.createSession("script-test")
        val store = AiStore.get(InstrumentationRegistry.getInstrumentation().targetContext)
        val old = store.config
        try {
            store.update { it.copy(enabled = false) }
            assertTrue(session.runOnReady { selectSchema("rime_ai_simp") })
            session.runOnReady { setRuntimeOption("ascii_mode", false) }
            suspend fun candidates(traditional: Boolean): List<String> {
                store.update { it.copy(traditional = traditional) }
                session.runOnReady { clearComposition(); setRuntimeOption("traditionalization", traditional) }
                for (c in "shurufa") session.runOnReady { processKey(c.code) }
                return session.runOnReady { getCandidates(0, 5).map { it.text } }
            }
            assertTrue("输入法" in candidates(false))
            assertTrue(store.prompt(store.config, true).contains("CHINESE SCRIPT: Simplified"))
            assertTrue("輸入法" in candidates(true))
            assertTrue(store.prompt(store.config, true).contains("CHINESE SCRIPT: Traditional"))
            assertTrue(store.prompt(store.config, false).contains("KEYBOARD OUTPUT CONTRACT: English keyboard"))
            assertTrue("输入法" in candidates(false))
        } finally {
            session.runOnReady { clearComposition(); setRuntimeOption("traditionalization", false) }
            store.update { old }; RimeDaemon.destroySession("script-test")
        }
    }
    @Test fun settingsLabelsFeedbackAndPolicyList() {
        val ins = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(ins)
        val activity = ins.startActivitySync(Intent(ins.targetContext, AiSettingsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        try {
            assertTrue(device.wait(Until.hasObject(By.text("AI 云端候选")), 10000))
            assertTrue(device.hasObject(By.text("停手等待（毫秒，50–2000）").clazz("android.widget.TextView")))
            fun reveal(selector: BySelector) {
                repeat(20) { if (device.hasObject(selector)) return; device.swipe(device.displayWidth-30, device.displayHeight*4/5, device.displayWidth-30, device.displayHeight/4, 20); Thread.sleep(120) }
                assertTrue("Missing settings: $selector", device.hasObject(selector))
            }
            reveal(By.text("按键震动"))
            reveal(By.text("按键音"))
            reveal(By.text("按键放大弹出动画"))
            reveal(By.desc("键盘高度"))
            reveal(By.text("新增 Policy"))
            assertTrue(device.hasObject(By.descStartsWith("选择 Policy ")))
        } finally { ins.runOnMainSync { activity.finish() } }
    }
}
