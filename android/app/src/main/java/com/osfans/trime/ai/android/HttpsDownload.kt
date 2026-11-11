// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import java.io.ByteArrayOutputStream
import java.net.URL
import javax.net.ssl.HttpsURLConnection

object HttpsDownload {
    // Separate public-document connection: never attaches the model key or input.
    fun get(address: String, limit: Int): ByteArray {
        CredentialStore.origin(address)
        val connection = URL(address).openConnection() as HttpsURLConnection
        try {
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 10000
            connection.readTimeout = 10000
            check(connection.responseCode == 200) { "更新 HTTP ${connection.responseCode}" }
            return connection.inputStream.use { input ->
                val result = ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    require(result.size() + n <= limit) { "下载内容超过上限" }
                    result.write(buffer, 0, n)
                }
                result.toByteArray()
            }
        } finally { connection.disconnect() }
    }
}
