package com.osfans.trime.rime

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.test.*

class DualDictionaryTest {
    @TempDir lateinit var root:File
    private fun release(id:Char)=WanxiangRelease("bundled",WanxiangAsset("data","",1,id.toString().repeat(64)))
    private fun bundle():File {
        val dir=File(root,"bundle").apply {mkdirs()};val wx=release('a');val ice=release('b')
        File(dir,"orangecell-dictionaries.json").writeText(wanxiangJson.encodeToString(WanxiangState(dictionary=wx,iceDictionary=ice)))
        File(dir,WanxiangUpdater.dictName(wx)+".dict.yaml").writeText("manifest")
        File(dir,WanxiangUpdater.dictName(wx)+"_algebra.yaml").writeText("algebra")
        File(dir,WanxiangUpdater.iceName(ice)+".dict.yaml").writeText("manifest")
        val names=WanxiangUpdater.DICTIONARIES.map {WanxiangUpdater.dictName(wx)+"_data/dicts/$it.dict.yaml"}+WanxiangUpdater.ICE_DICTIONARIES.map {"cn_dicts/$it.dict.yaml"}
        for(name in names)File(dir,name).apply {parentFile.mkdirs();writeText("词\tci\t1\n")}
        return dir
    }
    private fun updater(dir:File=File(root,"user"),bundle:File=bundle(),activate:WanxiangActivator=WanxiangActivator {})=
        WanxiangUpdater(dir,activate,catalog={error("No network allowed")},bundledDirectory=bundle,iceCatalog={error("No network allowed")})
    @Test fun existingIceSelectionSurvivesUpgradeBeforeFirstUpdaterUse() {
        val u=updater();u.directory.mkdirs()
        File(u.directory,"user.yaml").writeText("var:\n  previously_selected_schema: rime_ai_simp\n")
        assertFalse(u.state().enabled);assertTrue(u.state().grammar)
    }
    @Test fun bundledDictionariesWorkOfflineAndKeepGrammarPreference()=runBlocking {
        val u=updater();assertTrue(u.state().enabled);assertTrue(u.state().grammar)
        assertNotNull(u.state().dictionary);assertNotNull(u.state().iceDictionary)
        u.selectDictionary(true)
        assertFalse(File(u.directory,"orangecell_wanxiang.schema.yaml").readText().contains("grammar:"))
        u.selectDictionary(false);assertFalse(u.state().enabled);assertTrue(u.state().grammar)
        assertContains(File(u.directory,"rime_ai_simp.schema.yaml").readText(),"user_dict: rime_ice")
        u.selectDictionary(true);assertTrue(u.state().enabled);assertTrue(u.state().grammar)
    }
    @Test fun cachedBundleSurvivesAnApplicationUpgradeAndPreservesPersonalTables()=runBlocking {
        val b=bundle();val u=updater(bundle=b)
        File(u.directory,"cn_dicts/base.dict.yaml").apply {parentFile.mkdirs();writeText("personal")}
        u.selectDictionary(true);b.deleteRecursively();u.selectDictionary(false);u.selectDictionary(true)
        for(r in listOf(u.state().dictionary!!,u.state().iceDictionary!!)) {
            val name=if(r==u.state().dictionary)WanxiangUpdater.dictName(r) else WanxiangUpdater.iceName(r)
            val manifest=File(u.directory,"$name.dict.yaml").readText()
            assertContains(manifest,"${name}_data/")
            assertTrue(File(u.directory,"${name}_data").walkTopDown().count {it.isFile}>=5)
        }
        assertEquals("personal",File(u.directory,"cn_dicts/base.dict.yaml").readText())
    }
    @Test fun grammarDownloadDoesNotChangeDictionaryAndSwitchingRestoresIt()=runBlocking {
        MockWebServer().use {server ->
            val bytes="model".toByteArray();val f=File(root,"model").apply {writeBytes(bytes)}
            val model=WanxiangRelease("LTS",WanxiangAsset("model",server.url("/model").toString(),f.length(),digest(f)))
            val calls=mutableListOf<Boolean>()
            val u=WanxiangUpdater(File(root,"user"),WanxiangActivator {},WanxiangNetwork(OkHttpClient(),true),{calls+=it;assertTrue(it);model},bundledDirectory=bundle())
            u.selectDictionary(false);server.enqueue(MockResponse().setBody(Buffer().write(bytes)));u.updateModel()
            assertFalse(u.state().enabled);assertEquals(listOf(true),calls)
            assertFalse(File(u.directory,"orangecell_wanxiang.schema.yaml").readText().contains("grammar:"))
            u.selectDictionary(true);assertContains(File(u.directory,"orangecell_wanxiang.schema.yaml").readText(),WanxiangUpdater.modelName(model))
            u.selectDictionary(false);u.selectDictionary(true,false)
            assertFalse(File(u.directory,"orangecell_wanxiang.schema.yaml").readText().contains("grammar:"))
            assertTrue(File(u.directory,WanxiangUpdater.modelName(model)+".gram").exists())
        }
    }
    @Test fun iceUpdateDoesNotFetchModelOrChangeActiveDictionary()=runBlocking {
        MockWebServer().use {server ->
            val zip=File(root,"ice.zip")
            ZipOutputStream(zip.outputStream()).use {z ->for(name in WanxiangUpdater.ICE_DICTIONARIES) {z.putNextEntry(ZipEntry("cn_dicts/$name.dict.yaml"));z.write("new table".toByteArray());z.closeEntry()}}
            val r=WanxiangRelease("nightly",WanxiangAsset("cn_dicts.zip",server.url("/dict").toString(),zip.length(),digest(zip)))
            val u=WanxiangUpdater(File(root,"user"),WanxiangActivator {},WanxiangNetwork(OkHttpClient(),true),{error("Not a Wanxiang update")},bundledDirectory=bundle(),iceCatalog={r})
            server.enqueue(MockResponse().setBody(Buffer().write(zip.readBytes())));u.updateDictionary(false)
            assertEquals(r,u.state().iceDictionary);assertTrue(u.state().enabled);assertNull(u.state().model)
            assertEquals(1,server.requestCount);u.updateDictionary(false);assertEquals(1,server.requestCount)
            assertContains(File(u.directory,"rime_ai_simp.schema.yaml").readText(),WanxiangUpdater.iceName(r))
        }
    }
    @Test fun failedSwitchRestoresBothSchemasAndSelection()=runBlocking {
        val b=bundle();var fail=false;val u=updater(bundle=b,activate=WanxiangActivator {if(fail && it==WanxiangUpdater.FALLBACK)error("deployment failed")})
        u.selectDictionary(true);val ice=File(u.directory,"rime_ai_simp.schema.yaml");ice.appendText("# custom\n");val previous=ice.readText()
        fail=true;assertFailsWith<IllegalStateException> {u.selectDictionary(false)}
        assertTrue(u.state().enabled);assertEquals(previous,ice.readText())
    }
    @Test fun iceCatalogRejectsWrongRepositoryAndUsesDigestForNightly() {
        val body="""{"tag_name":"nightly","assets":[{"name":"cn_dicts.zip","browser_download_url":"https://github.com/iDvel/rime-ice/releases/download/nightly/cn_dicts.zip","size":123,"digest":"sha256:${"a".repeat(64)}"}]}"""
        val first=WanxiangCatalog.parse(body,false,true)
        assertNotEquals(first,WanxiangCatalog.parse(body.replace("a".repeat(64),"b".repeat(64)),false,true))
        assertFailsWith<IllegalArgumentException> {WanxiangCatalog.parse(body.replace("iDvel/","other/"),false,true)}
    }
}
