package com.osfans.trime.ai.android

import android.content.ContextWrapper
import androidx.test.platform.app.InstrumentationRegistry
import com.osfans.trime.ai.*
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AiStorageTest {
    private fun isolatedContext(): ContextWrapper {
        val original = InstrumentationRegistry.getInstrumentation().targetContext
        val folder = File(original.noBackupFilesDir, "tests-${UUID.randomUUID()}").apply { mkdirs() }
        return object : ContextWrapper(original) { override fun getNoBackupFilesDir() = folder }
    }

    @Test fun encryptedCredentialsAreBoundToOriginAndClearable() {
        val context = isolatedContext()
        val credentials = CredentialStore(context, "test-${UUID.randomUUID()}")
        try {
            credentials.save("https://example.com/v1/chat/completions", "test-secret-never-log")
            assertEquals("test-secret-never-log", credentials.read("https://example.com/other"))
            assertNull(credentials.read("https://different.example.com/v1/chat/completions"))
            assertFalse(File(context.noBackupFilesDir, "ai-credential.bin").readBytes().toString(Charsets.ISO_8859_1).contains("test-secret-never-log"))
            credentials.clear()
            assertNull(credentials.read("https://example.com/v1/chat/completions"))
        } finally { credentials.clear(); context.noBackupFilesDir.deleteRecursively() }
    }

    @Test fun promptPersistenceOverrideRollbackAndRevisionRules() {
        val context = isolatedContext()
        try {
            val store = AiStore(context)
            val builtin = store.builtin
            val nextRevision = builtin.revision + 1
            val updated = builtin.copy(revision = nextRevision, version = "test-3", base_prompt = "Remote v3")
            store.activate(updated, "https://example.com/prompt.json", true)
            store.edit(updated.copy(base_prompt = "Local instruction"))
            store.activate(updated.copy(revision = nextRevision + 1, version = "test-4"), "https://example.com/prompt.json", true)
            assertEquals("Local instruction", store.effective().base_prompt)
            assertEquals("Local instruction", AiStore(context).effective().base_prompt)
            try { store.activate(updated, "https://example.com/prompt.json", true); fail("Downgrade accepted") } catch (_: IllegalArgumentException) { }
            assertEquals(nextRevision + 1, store.config.active!!.pack.revision)
            store.clearOverride()
            store.rollback()
            assertEquals(nextRevision, store.config.active!!.pack.revision)
            assertEquals(nextRevision, AiStore(context).config.active!!.pack.revision)
            assertFalse(store.export().contains("endpoint"))
            store.restoreBuiltin()
            assertEquals(builtin, store.effective())
        } finally { context.noBackupFilesDir.deleteRecursively() }
    }
}
