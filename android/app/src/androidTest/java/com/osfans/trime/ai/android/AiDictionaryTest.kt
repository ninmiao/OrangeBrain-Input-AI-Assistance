// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.data.base.DefaultSchemaInstaller
import com.osfans.trime.daemon.RimeDaemon
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

class AiDictionaryTest {
    @Test fun migrateOnlyOwnedDefaultsAndPreserveUserFiles() {
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"dictionary-migration-${UUID.randomUUID()}").apply { mkdirs() }
        try {
            assertTrue(DefaultSchemaInstaller.install(dir))
            val config = File(dir,"default.custom.yaml")
            assertTrue(config.readText().contains("rime_ai_simp"))
            assertFalse(DefaultSchemaInstaller.install(dir))
            config.writeText(DefaultSchemaInstaller.LEGACY.trimIndent())
            val userDb = File(dir,"luna_pinyin.userdb.txt").apply { writeText("retained-user-words") }
            assertTrue(DefaultSchemaInstaller.install(dir))
            assertEquals(DefaultSchemaInstaller.LEGACY.trimIndent(),File(dir,"default.custom.before-ice.yaml").readText())
            assertEquals("retained-user-words",userDb.readText())
            val customized = "patch:\n  schema_list:\n    - schema: my_pinyin\n  menu/page_size: 9\n"
            config.writeText(customized)
            assertFalse(DefaultSchemaInstaller.install(dir))
            assertEquals(customized,config.readText())
        } finally { dir.deleteRecursively() }
    }

    @Test fun simplifiedOfflineDictionaryHasCommonWordsAndAbbreviations() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = AiStore.get(context)
        val old = store.config
        val session = RimeDaemon.createSession("ice-dictionary-test")
        val report = mutableListOf<String>()
        try {
            store.update { it.copy(enabled=false,traditional=false) }
            val deadline = System.currentTimeMillis()+600000
            var selected = false
            while (!selected && System.currentTimeMillis()<deadline) {
                selected = session.runOnReady { selectSchema("rime_ai_simp") }
                if (!selected) kotlinx.coroutines.delay(1000)
            }
            assertTrue("New simplified dictionary did not deploy",selected)
            assertEquals("rime_ai_simp",session.runOnReady { selectedSchemaId() })
            assertEquals("rime_ai_simp",session.runOnReady { selectedSchemata().first().id })
            session.runOnReady { setRuntimeOption("ascii_mode",false); setRuntimeOption("traditionalization",false) }
            val cases = linkedMapOf("ruanjian" to "软件","fazhan" to "发展","houmian" to "后面",
                "shujuku" to "数据库","shurufa" to "输入法","rengongzhineng" to "人工智能",
                "zhongguo" to "中国","nihao" to "你好","lvse" to "绿色","rgzn" to "人工智能")
            for ((input,expected) in cases) {
                session.runOnReady { clearComposition() }
                for (c in input) session.runOnReady { processKey(c.code) }
                val candidates = session.runOnReady { getCandidates(0,10).map { it.text } }
                assertTrue("$input: expected $expected; got $candidates",expected in candidates)
                report += "$input -> ${candidates.take(5)}"
            }
            assertFalse(store.config.enabled)
            report += "AI disabled; all candidates came from local Rime tables."
        } finally {
            session.runOnReady { clearComposition() }
            RimeDaemon.destroySession("ice-dictionary-test")
            store.update { old.copy(enabled=false) }
            File(context.getExternalFilesDir(null),"dictionary-test-report.txt").writeText(report.joinToString("\n"))
        }
    }
}
