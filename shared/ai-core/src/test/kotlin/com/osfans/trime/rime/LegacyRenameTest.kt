// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.rime

import kotlin.test.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

class LegacyRenameTest {
    @Test
    fun replacesOnlyIdentifiers() {
        assertEquals("schema: orangecell_wanxiang", LegacyRename.replaceIdentifiers("schema: zephyr_wanxiang"))
        assertEquals("dir: .orangecell-wanxiang/state.json", LegacyRename.replaceIdentifiers("dir: .zephyr-wanxiang/state.json"))
        assertEquals("  - orangecell_wanxiang_d_2a94c48aa51e_data/dicts/zi", LegacyRename.replaceIdentifiers("  - zephyr_wanxiang_d_2a94c48aa51e_data/dicts/zi"))
        assertEquals("微风 zephyr wind; myzephyr_x", LegacyRename.replaceIdentifiers("微风 zephyr wind; myzephyr_x"))
    }

    @Test
    fun movesUserDictionaryDictionariesAndState(@TempDir dir: File) {
        File(dir, "zephyr_wanxiang.userdb").mkdirs()
        File(dir, "zephyr_wanxiang.userdb/CURRENT").writeText("MANIFEST-000001\n")
        File(dir, "zephyr_wanxiang_d_2a94c48aa51e.dict.yaml").writeText(
            "---\nname: zephyr_wanxiang_d_2a94c48aa51e\nimport_tables:\n  - zephyr_wanxiang_d_2a94c48aa51e_data/dicts/zi\n...\n你\tni\t1\n")
        File(dir, "zephyr_wanxiang_d_2a94c48aa51e_data/dicts").mkdirs()
        File(dir, "user.yaml").writeText("var:\n  previously_selected_schema: zephyr_wanxiang\n")
        File(dir, ".zephyr-wanxiang").mkdirs()
        File(dir, ".zephyr-wanxiang/state.json").writeText("{\"dictionary\":\"zephyr_wanxiang_d_2a94c48aa51e\"}")
        File(dir, "build").mkdirs()
        File(dir, "build/zephyr_wanxiang.schema.yaml").writeText("old")
        File(dir, "build/rime_ice.table.bin").writeText("keep")
        File(dir, "sync/device").mkdirs()
        File(dir, "sync/device/zephyr_wanxiang.userdb.txt").writeText("# snapshot\n")

        assertTrue(LegacyRename.migrate(dir))

        assertEquals("MANIFEST-000001\n", File(dir, "orangecell_wanxiang.userdb/CURRENT").readText())
        assertFalse(File(dir, "zephyr_wanxiang.userdb").exists())
        val dict = File(dir, "orangecell_wanxiang_d_2a94c48aa51e.dict.yaml").readText()
        assertContains(dict, "name: orangecell_wanxiang_d_2a94c48aa51e")
        assertContains(dict, "  - orangecell_wanxiang_d_2a94c48aa51e_data/dicts/zi")
        assertContains(dict, "你\tni\t1")
        assertTrue(File(dir, "orangecell_wanxiang_d_2a94c48aa51e_data/dicts").isDirectory)
        assertContains(File(dir, "user.yaml").readText(), "previously_selected_schema: orangecell_wanxiang")
        assertEquals("{\"dictionary\":\"orangecell_wanxiang_d_2a94c48aa51e\"}\n", File(dir, ".orangecell-wanxiang/state.json").readText())
        assertFalse(File(dir, "build/zephyr_wanxiang.schema.yaml").exists())
        assertTrue(File(dir, "build/rime_ice.table.bin").exists())
        assertTrue(File(dir, "sync/device/orangecell_wanxiang.userdb.txt").exists())

        // The marker stops repeat scans.
        File(dir, "zephyr_ice.custom.yaml").writeText("x")
        assertFalse(LegacyRename.migrate(dir))
        assertTrue(File(dir, "zephyr_ice.custom.yaml").exists())
    }

    @Test
    fun keepsNewDataWhenBothNamesExist(@TempDir dir: File) {
        File(dir, "zephyr_wanxiang.userdb").mkdirs()
        File(dir, "orangecell_wanxiang.userdb").mkdirs()
        File(dir, "orangecell_wanxiang.userdb/CURRENT").writeText("new")
        LegacyRename.migrate(dir)
        assertEquals("new", File(dir, "orangecell_wanxiang.userdb/CURRENT").readText())
        assertTrue(File(dir, "zephyr_wanxiang.userdb").exists())
    }
}
