// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.rime

import kotlin.test.*
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.*
import okio.Buffer
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class WanxiangTest {
    @TempDir lateinit var temp:File
    private fun net()=WanxiangNetwork(OkHttpClient.Builder().followRedirects(false).build(),true)
    private fun asset(server:MockWebServer,bytes:ByteArray):WanxiangAsset {
        val file=File(temp,"hash-input");file.writeBytes(bytes)
        return WanxiangAsset("test",server.url("/asset").toString(),bytes.size.toLong(),digest(file))
    }
    private fun zip(extra:String?=null,omit:String?=null):ByteArray {
        val file=File(temp,"fixture.zip")
        ZipOutputStream(file.outputStream()).use { zip ->
            val names=WanxiangUpdater.DICTIONARIES.map { "dicts/$it.dict.yaml" }+listOf("wanxiang_algebra.yaml","lua/do-not-install.lua")+listOfNotNull(extra)
            for(name in names.filter { it!=omit }) { zip.putNextEntry(ZipEntry(name));zip.write("fixture\n".toByteArray());zip.closeEntry() }
        }
        return file.readBytes()
    }
    @Test fun grammarAndWanxiangAreEnabledByDefaultButNoDownloadOnConstruction() {
        val updater=WanxiangUpdater(File(temp,"user"),WanxiangActivator { error("must not activate") })
        assertTrue(updater.state().enabled);assertTrue(updater.state().grammar)
        assertNull(updater.state().dictionary);assertFalse(updater.workspace.exists())
    }
    @Test fun releaseRequiresOfficialAssetAndDigest() {
        val body="""{"tag_name":"v1","assets":[{"name":"rime-wanxiang-base.zip","browser_download_url":"https://github.com/amzxyz/rime-wanxiang/releases/download/v1/rime-wanxiang-base.zip","size":123,"digest":"sha256:${"a".repeat(64)}"}]}"""
        assertEquals("v1",WanxiangCatalog.parse(body,false).version)
        assertFailsWith<IllegalArgumentException> { WanxiangCatalog.parse(body.replace("amzxyz/","attacker/"),false) }
        assertFailsWith<IllegalArgumentException> { WanxiangCatalog.parse(body.replace("sha256:"+"a".repeat(64),""),false) }
        assertFailsWith<IllegalArgumentException> { WanxiangCatalog.parse(body.replace("\"tag_name\"","\"draft\":true,\"tag_name\""),false) }
    }
    @Test fun resumeUsesRangeAndValidatesCompleteDigest()=runBlocking {
        MockWebServer().use { server ->
            val bytes="downloaded-content".toByteArray();val asset=asset(server,bytes);val folder=File(temp,"cache").apply { mkdirs() }
            File(folder,asset.sha256+".part").writeBytes(bytes.copyOfRange(0,5))
            server.enqueue(MockResponse().setResponseCode(206).setHeader("Content-Range","bytes 5-${bytes.lastIndex}/${bytes.size}").setBody(Buffer().write(bytes,5,bytes.size-5)))
            val file=net().download(asset,folder){}
            assertContentEquals(bytes,file.readBytes());assertEquals("bytes=5-",server.takeRequest().getHeader("Range"))
            assertNull(server.takeRequest(20,TimeUnit.MILLISECONDS))
            assertEquals(file,net().download(asset,folder){}) // verified cache, no second request
        }
    }
    @Test fun serverIgnoringRangeRestartsWithoutDuplicatingBytes()=runBlocking {
        MockWebServer().use { server ->
            val bytes="abcdef".toByteArray();val a=asset(server,bytes);val folder=File(temp,"cache").apply { mkdirs() }
            File(folder,a.sha256+".part").writeText("abc")
            server.enqueue(MockResponse().setBody("abcdef"))
            assertContentEquals(bytes,net().download(a,folder){}.readBytes())
        }
    }
    @Test fun mismatchedRangeCannotAppendToPartialFile()=runBlocking {
        MockWebServer().use { server ->
            val a=asset(server,"abcdef".toByteArray());val folder=File(temp,"cache").apply { mkdirs() }
            val partial=File(folder,a.sha256+".part").apply { writeText("abc") }
            server.enqueue(MockResponse().setResponseCode(206).setHeader("Content-Range","bytes 2-5/6").setBody("cdef"))
            assertFailsWith<IllegalArgumentException> { net().download(a,folder){} }
            assertEquals("abc",partial.readText())
        }
    }
    @Test fun corruptDownloadIsDeleted()=runBlocking {
        MockWebServer().use { server ->
            val a=asset(server,"abcdef".toByteArray());val folder=File(temp,"cache")
            server.enqueue(MockResponse().setBody("abcdeg"))
            assertFailsWith<IllegalStateException> { net().download(a,folder){} }
            assertFalse(File(folder,a.sha256+".part").exists());assertFalse(File(folder,a.sha256+".download").exists())
        }
    }
    @Test fun cancellationClosesSocketAndRetainsPartialDownload()=runBlocking {
        MockWebServer().use { server ->
            val a=asset(server,ByteArray(40000){65});val folder=File(temp,"cache")
            server.enqueue(MockResponse().setBody(Buffer().write(ByteArray(40000){65})).throttleBody(1024,100,TimeUnit.MILLISECONDS))
            val started=CompletableDeferred<Unit>()
            val job=launch(Dispatchers.IO) { net().download(a,folder){ if(it.done>0)started.complete(Unit) } }
            withTimeout(5000) { started.await() };job.cancelAndJoin()
            assertTrue(File(folder,a.sha256+".part").length() in 1..39999)
            assertFalse(File(folder,a.sha256+".download").exists())
        }
    }
    @Test fun onlyRequiredDataIsExtractedAndNoUpstreamLuaIsInstalled() {
        val bytes=zip();val input=File(temp,"base.zip").apply { writeBytes(bytes) }
        val release=WanxiangRelease("v1",WanxiangAsset("base","",bytes.size.toLong(),digest(input)))
        val dir=File(temp,"user");val updater=WanxiangUpdater(dir,WanxiangActivator {})
        updater.workspace.mkdirs();updater.extract(input,release)
        assertFalse(dir.walkTopDown().any { it.extension=="lua" })
        assertEquals(8,File(dir,WanxiangUpdater.dictName(release)+"_data").walkTopDown().count { it.isFile })
        assertTrue(File(updater.workspace,"CC-BY-4.0.txt").length()>1000)
        val schema=WanxiangUpdater.schema(release,null)
        assertContains(schema,"user_dict: orangecell_wanxiang");assertContains(schema,"traditionalization");assertContains(schema,"/base/全拼")
        assertFalse(schema.contains("grammar:"));assertFalse(schema.contains("@@"))
    }
    @Test fun zipTraversalIsRejectedEvenForAnIgnoredEntry() {
        val bytes=zip("../outside");val input=File(temp,"bad.zip").apply { writeBytes(bytes) }
        val r=WanxiangRelease("v1",WanxiangAsset("base","",bytes.size.toLong(),digest(input)))
        val updater=WanxiangUpdater(File(temp,"user"),WanxiangActivator {});updater.workspace.mkdirs()
        assertFailsWith<IllegalArgumentException> { updater.extract(input,r) }
        assertFalse(File(temp,"outside").exists())
    }
    @Test fun missingDictionaryIsRejected() {
        val bytes=zip(omit="dicts/zi.dict.yaml");val input=File(temp,"bad.zip").apply { writeBytes(bytes) }
        val r=WanxiangRelease("v1",WanxiangAsset("base","",bytes.size.toLong(),digest(input)))
        val updater=WanxiangUpdater(File(temp,"user"),WanxiangActivator {});updater.workspace.mkdirs()
        assertFailsWith<IllegalArgumentException> { updater.extract(input,r) }
    }
    @Test fun deploymentFailureRestoresSettingsAndLeavesUserDictionaryUntouched()=runBlocking {
        MockWebServer().use { server ->
            val bytes=zip();val release=WanxiangRelease("v1",asset(server,bytes));server.enqueue(MockResponse().setBody(Buffer().write(bytes)))
            val dir=File(temp,"user").apply { mkdirs() }
            val custom=File(dir,"default.custom.yaml").apply { writeText("custom settings") }
            val db=File(dir,"rime_ice.userdb").apply { mkdirs() };File(db,"words").writeText("learned words")
            val activations=mutableListOf<String>()
            val updater=WanxiangUpdater(dir,WanxiangActivator { schema ->
                activations+=schema
                if(schema==WanxiangUpdater.SCHEMA) {custom.writeText("failed change");error("deploy failed")}
            },net(),{release})
            assertFailsWith<IllegalStateException> { updater.update(false) }
            assertEquals(listOf(WanxiangUpdater.SCHEMA,WanxiangUpdater.FALLBACK),activations)
            assertEquals("custom settings",custom.readText());assertEquals("learned words",File(db,"words").readText())
            assertNull(updater.state().dictionary);assertFalse(File(dir,"orangecell_wanxiang.schema.yaml").exists())
        }
    }
    @Test fun defaultUpdateDownloadsModelAndSameLtsTagWithNewDigestUpdates()=runBlocking {
        MockWebServer().use { server ->
            val bytes=zip();val dict=WanxiangRelease("v1",asset(server,bytes));val m1=WanxiangRelease("LTS",asset(server,"model 1".toByteArray()))
            var model=m1
            val dir=File(temp,"user")
            val activated=mutableListOf<String>()
            val updater=WanxiangUpdater(dir,WanxiangActivator { activated+=it },net(),{if(it)model else dict})
            server.enqueue(MockResponse().setBody(Buffer().write(bytes)));server.enqueue(MockResponse().setBody("model 1"))
            updater.update()
            assertTrue(updater.state().grammar);assertTrue(File(dir,"orangecell_wanxiang.schema.yaml").readText().contains(WanxiangUpdater.modelName(model)))
            updater.update();assertEquals(2,activated.size) // reselect even after an external schema change; no download
            model=WanxiangRelease("LTS",asset(server,"model 2".toByteArray()));server.enqueue(MockResponse().setBody("model 2"))
            updater.update();assertEquals(3,activated.size);assertEquals(model,updater.state().model)
            assertTrue(File(dir,WanxiangUpdater.modelName(m1)+".gram").exists()) // one rollback generation kept
            updater.useFallback();assertFalse(updater.state().enabled)
            updater.update(false);assertTrue(updater.state().enabled);assertFalse(updater.state().grammar)
            assertFalse(File(dir,"orangecell_wanxiang.schema.yaml").readText().contains("grammar:"))
        }
    }
    @Test fun journalFromInterruptedDeploymentIsRecoveredBeforeNetworkRequest()=runBlocking {
        val dir=File(temp,"user").apply { mkdirs() }
        val journal=File(dir,".orangecell-wanxiang/transaction").apply { mkdirs() }
        File(dir,"default.custom.yaml").writeText("interrupted change")
        File(journal,"0.backup").writeText("previous settings")
        File(journal,"pending.json").writeText("""{"previousSchema":"rime_ai_simp","existing":["default.custom.yaml"]}""")
        val selected=mutableListOf<String>()
        val updater=WanxiangUpdater(dir,WanxiangActivator {selected+=it},catalog={error("offline")})
        assertFailsWith<IllegalStateException> {updater.update()}
        assertEquals(listOf(WanxiangUpdater.FALLBACK),selected);assertEquals("previous settings",File(dir,"default.custom.yaml").readText())
        assertFalse(File(journal,"pending.json").exists())
    }
}
