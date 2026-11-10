// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.data.base

import android.util.AtomicFile
import java.io.File

/** Migrate only the exact default shipped by this app, preserving custom settings and user DBs. */
internal object DefaultSchemaInstaller {
    const val LEGACY = """
        patch:
          schema_list:
            - schema: luna_pinyin
            - schema: luna_pinyin_simp
    """
    const val CURRENT = """
        patch:
          schema_list:
            - schema: rime_ai_simp
    """
    private fun normalized(text: String) = text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.joinToString("\n")

    fun install(directory: File): Boolean {
        val target = File(directory, "default.custom.yaml")
        val old = if (target.exists()) target.readText() else null
        if (old != null && normalized(old) != normalized(LEGACY)) return false
        if (old != null) {
            val backup = File(directory, "default.custom.before-ice.yaml")
            if (!backup.exists()) target.copyTo(backup)
        }
        val file = AtomicFile(target)
        val stream = file.startWrite()
        try {
            stream.write((CURRENT.trimIndent() + "\n").toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
        return true
    }
}
