package com.osfans.trime.rime

import java.io.File

/**
 * One-time rename of Rime user data written under the product's former name (Zephyr Input).
 *
 * The schema, dictionaries, user dictionary and updater state used `zephyr_` / `.zephyr-` names.
 * They are renamed to `orangecell_` / `.orangecell-` so the learned words and downloaded
 * dictionaries carry over. Compiled output in `build/` is dropped and rebuilt by the next deploy.
 * The Windows broker and server do the same in `OrangeCellMigration.h`.
 */
object LegacyRename {
    const val MARKER = ".orangecell-migrated"
    private const val OLD = "zephyr"
    private const val NEW = "orangecell"
    private val textExtensions = setOf("yaml", "json", "txt")
    private val identifier = Regex("(?<![A-Za-z0-9])$OLD(?=[_-])")

    fun newName(name: String): String? = when {
        name.startsWith(OLD) -> NEW + name.removePrefix(OLD)
        name.startsWith(".$OLD") -> ".$NEW" + name.removePrefix(".$OLD")
        else -> null
    }

    fun replaceIdentifiers(line: String): String = identifier.replace(line, NEW)

    /** Returns true when anything was renamed or rewritten. Safe to call on every start. */
    fun migrate(directory: File): Boolean {
        if (!directory.isDirectory || File(directory, MARKER).exists()) return false
        var changed = false
        fun renameChildren(dir: File) {
            dir.listFiles().orEmpty().forEach { file ->
                val target = newName(file.name)?.let { File(dir, it) } ?: return@forEach
                if (!target.exists() && file.renameTo(target)) changed = true
            }
        }
        renameChildren(directory)
        File(directory, "sync").listFiles().orEmpty().filter { it.isDirectory }.forEach(::renameChildren)
        File(directory, "build").listFiles().orEmpty().filter { it.name.startsWith(OLD) }.forEach {
            if (it.deleteRecursively()) changed = true
        }
        val texts = directory.listFiles().orEmpty().filter { it.isFile && it.extension in textExtensions } +
            File(directory, ".$NEW-wanxiang").walkTopDown().filter { it.isFile }.toList()
        texts.forEach { if (rewrite(it)) changed = true }
        File(directory, MARKER).writeText("Renamed from Zephyr Input data.\n")
        return changed
    }

    /** Streams the file line by line so large dictionaries are never held in memory. */
    private fun rewrite(file: File): Boolean {
        val temp = File(file.path + ".migrating")
        var changed = false
        file.bufferedReader().use { input ->
            temp.bufferedWriter().use { output ->
                input.lineSequence().forEach { line ->
                    val next = replaceIdentifiers(line)
                    if (next != line) changed = true
                    output.write(next)
                    output.write("\n")
                }
            }
        }
        if (!changed) {
            temp.delete()
            return false
        }
        if (!file.delete() || !temp.renameTo(file)) {
            temp.delete()
            return false
        }
        return true
    }
}
