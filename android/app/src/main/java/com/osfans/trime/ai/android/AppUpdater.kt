// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File
import java.net.URL
import java.security.MessageDigest
import javax.net.ssl.HttpsURLConnection

// App self-update from the repository's dist/ folder. dist/SHA256SUMS lists the current
// installers, so one small file gives the newest version, its file name and its digest.
object AppUpdater {
    const val REPOSITORY = "https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance"
    private const val DIST = "https://raw.githubusercontent.com/ninmiao/OrangeBrain-Input-AI-Assistance/main/dist/"
    private const val MAX_APK = 300L * 1024 * 1024
    private val line = Regex("^([0-9a-f]{64})  (OrangeCell-([0-9]+\\.[0-9]+\\.[0-9]+)-arm64-v8a-demo\\.apk)\\r?$")

    data class Update(val version: String, val file: String, val sha256: String, val url: String, val newer: Boolean)

    fun currentVersion(context: Context): String =
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0.0.0"

    // Only the published demo build (arm64) is in dist/; other builds must not replace themselves with it.
    fun unsupportedReason(context: Context): String? = when {
        !context.packageName.endsWith(".demo") -> "当前不是发布版安装包，不能自动更新"
        "arm64-v8a" !in Build.SUPPORTED_ABIS -> "发布的安装包只支持 ARM64 设备"
        else -> null
    }

    fun compare(a: String, b: String): Int {
        val x = a.split('.').map { it.toInt() }
        val y = b.split('.').map { it.toInt() }
        for (i in 0 until maxOf(x.size, y.size)) {
            val l = x.getOrElse(i) { 0 }
            val r = y.getOrElse(i) { 0 }
            if (l != r) return l.compareTo(r)
        }
        return 0
    }

    fun parse(sums: String, current: String): Update {
        var best: Update? = null
        for (row in sums.lineSequence()) {
            val m = line.matchEntire(row) ?: continue
            val (hash, file, version) = m.destructured
            if (best == null || compare(version, best.version) > 0) best = Update(version, file, hash, DIST + file, false)
        }
        checkNotNull(best) { "dist/SHA256SUMS 里没有 Android 安装包" }
        return best.copy(newer = compare(best.version, current) > 0)
    }

    fun check(current: String): Update = parse(String(HttpsDownload.get(DIST + "SHA256SUMS", 65536)), current)

    // Downloads to cache/updates and verifies SHA-256; reuses an already verified copy.
    fun download(context: Context, update: Update, progress: (Long) -> Unit): File {
        require(update.url.startsWith(DIST) && update.sha256.matches(Regex("[0-9a-f]{64}"))) { "更新地址无效" }
        val folder = File(context.cacheDir, "updates/${update.sha256.take(16)}").apply { mkdirs() }
        val target = File(folder, update.file)
        if (target.isFile && sha256(target) == update.sha256) return target
        val part = File(folder, "download.part")
        val connection = URL(update.url).openConnection() as HttpsURLConnection
        try {
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15000
            connection.readTimeout = 30000
            check(connection.responseCode == 200) { "更新下载 HTTP ${connection.responseCode}" }
            val digest = MessageDigest.getInstance("SHA-256")
            var count = 0L
            var reported = 0L
            connection.inputStream.use { input ->
                part.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        count += n
                        check(count <= MAX_APK) { "更新文件超过上限" }
                        digest.update(buffer, 0, n)
                        output.write(buffer, 0, n)
                        if (count - reported >= 1024 * 1024) { reported = count; progress(count) }
                    }
                }
            }
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            if (actual != update.sha256) { part.delete(); error("SHA-256 校验失败，已丢弃下载") }
            target.delete()
            check(part.renameTo(target)) { "无法保存更新" }
            return target
        } finally { connection.disconnect() }
    }

    fun installIntent(context: Context, file: File): Intent =
        Intent(Intent.ACTION_VIEW)
            .setDataAndType(FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file),
                "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
