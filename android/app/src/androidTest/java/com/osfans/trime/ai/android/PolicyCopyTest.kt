package com.osfans.trime.ai.android
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.File
class PolicyCopyTest {
 @Test fun copiesEncryptedKeyAndSettingsIndependently() {
  val context=InstrumentationRegistry.getInstrumentation().targetContext
  val store=AiStore.get(context);val old=store.config
  val source=store.addPolicy("Copy fixture");val created=mutableListOf(source)
  try {
   store.updatePolicyConfig(source){it.copy(localOverride=store.builtin,provider="test-provider")}
   val endpoint=store.configForPolicy(source).endpoint
   store.credentialsForPolicy(source).save(endpoint,"copy-test-only-key")
   val copy=store.duplicatePolicy(source);created.add(copy)
   val original=store.config.policies.first{it.id==source}
   val duplicate=store.config.policies.first{it.id==copy}
   assertEquals(original.copy(id=copy,name=duplicate.name),duplicate)
   assertEquals(old.selectedPolicyId,store.config.selectedPolicyId)
   assertEquals("copy-test-only-key",store.credentialsForPolicy(copy).read(endpoint))
   assertNull(store.credentialsForPolicy(copy).read("https://different.example/v1"))
   val bytes=File(context.noBackupFilesDir,"ai-credential-$copy.bin").readBytes()
   assertFalse(bytes.toString(Charsets.UTF_8).contains("copy-test-only-key"))
   store.credentialsForPolicy(copy).save(endpoint,"changed-test-key")
   assertEquals("copy-test-only-key",store.credentialsForPolicy(source).read(endpoint))
   val copy2=store.duplicatePolicy(source);created.add(copy2)
   assertNotEquals(duplicate.name,store.config.policies.first{it.id==copy2}.name)
   store.deletePolicy(copy);created.remove(copy)
   assertEquals("copy-test-only-key",store.credentialsForPolicy(source).read(endpoint))
  } finally { created.reversed().forEach{store.deletePolicy(it)};store.update{old} }
 }
 @Test fun missingKeyCopiesButUnreadableKeyDoesNotCreatePartialPolicy() {
  val store=AiStore.get(InstrumentationRegistry.getInstrumentation().targetContext);val old=store.config
  val source=store.addPolicy("No key");val created=mutableListOf(source)
  try {
   val copy=store.duplicatePolicy(source);created.add(copy)
   assertFalse(store.credentialsForPolicy(copy).hasCredential())
   store.credentialsForPolicy(source).save("https://different.example/v1","test-only-key")
   val before=store.config
   try {store.duplicatePolicy(source);fail("Unreadable key must fail")} catch (_: IllegalStateException) {}
   assertEquals(before,store.config)
  } finally {created.reversed().forEach{store.deletePolicy(it)};store.update{old}}
 }
}
