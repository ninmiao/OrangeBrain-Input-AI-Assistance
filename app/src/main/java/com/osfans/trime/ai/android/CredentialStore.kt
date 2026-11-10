// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.net.URI
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class CredentialStore(context: Context, private val alias: String = "rime-ai-api-v1", fileName: String = "ai-credential.bin") {
    private val file = AtomicFile(File(context.noBackupFilesDir, fileName))
    fun hasCredential(): Boolean = file.baseFile.isFile
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    @Synchronized fun save(endpoint: String, secret: String) {
        require(secret.isNotBlank() && !secret.contains('\n') && !secret.contains('\r'))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(origin(endpoint).toByteArray(Charsets.UTF_8))
        val bytes = cipher.doFinal(secret.toByteArray(Charsets.UTF_8))
        val stream = file.startWrite()
        try {
            stream.write(cipher.iv.size)
            stream.write(cipher.iv)
            stream.write(bytes)
            file.finishWrite(stream)
        } catch (e: Exception) { file.failWrite(stream); throw e }
    }

    @Synchronized fun read(endpoint: String): String? = runCatching {
        val bytes = file.openRead().use { it.readBytes() }
        val size = bytes[0].toInt()
        require(size == 12 && bytes.size > size + 16)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(1, 1 + size)))
        cipher.updateAAD(origin(endpoint).toByteArray(Charsets.UTF_8))
        cipher.doFinal(bytes.copyOfRange(1 + size, bytes.size)).toString(Charsets.UTF_8)
    }.getOrNull()

    @Synchronized fun clear() {
        file.delete()
        KeyStore.getInstance("AndroidKeyStore").apply { load(null); deleteEntry(alias) }
    }

    companion object {
        fun origin(endpoint: String): String {
            val uri = URI(endpoint)
            require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null && uri.query == null && uri.fragment == null) { "请输入完整 HTTPS 地址，不能包含查询参数或凭据" }
            return "https://${uri.host.lowercase()}:${if (uri.port == -1) 443 else uri.port}"
        }
    }
}
