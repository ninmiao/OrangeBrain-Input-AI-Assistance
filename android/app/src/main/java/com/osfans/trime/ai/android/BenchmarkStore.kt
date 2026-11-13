// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.content.Context
import android.util.AtomicFile
import com.osfans.trime.ai.BenchmarkConfig
import java.io.File
import java.security.MessageDigest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Per-Policy test configuration only; no keys or response text. */
class BenchmarkStore(context: Context, policyId: String) {
    private val policyHash = MessageDigest.getInstance("SHA-256").digest(policyId.toByteArray()).joinToString("") { "%02x".format(it) }
    private val file = AtomicFile(File(context.noBackupFilesDir, "ai-benchmark-$policyHash.json"))
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }
    @Synchronized fun read(defaults: BenchmarkConfig = BenchmarkConfig()): BenchmarkConfig = runCatching {
        file.openRead().use { stream ->
            require(stream.channel.size() <= 32768)
            json.decodeFromString<BenchmarkConfig>(stream.readBytes().toString(Charsets.UTF_8)).validate()
        }
    }.getOrElse { defaults }
    @Synchronized fun save(config: BenchmarkConfig) {
        val bytes = json.encodeToString(config.validate()).toByteArray(Charsets.UTF_8)
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream) } catch (e: Exception) { file.failWrite(stream); throw e }
    }
    @Synchronized fun clear() = file.delete()
}
