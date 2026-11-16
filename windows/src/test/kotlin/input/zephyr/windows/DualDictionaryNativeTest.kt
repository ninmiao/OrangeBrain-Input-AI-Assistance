package input.zephyr.windows

import com.osfans.trime.rime.*
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.util.concurrent.TimeUnit
import kotlin.test.*

class DualDictionaryNativeTest {
    @Test fun bundledSelectionAndOfficialIceUpdateUseTheRealRimeEngine()=runBlocking {
        val path=System.getenv("ZEPHYR_WANXIANG_FIXTURE");assumeTrue(!path.isNullOrBlank())
        val root=File(path!!);val user=File(root,"user");val network=WanxiangNetwork()
        val u=WanxiangUpdater(user,WindowsWanxiangActivator(root,user),catalog={error("No model download expected")},bundledDirectory=File(root,"data"))
        fun probe(schema:String) {
            val p=ProcessBuilder(File(root,"probe.exe").path,root.path,File(root,"rime.dll").path,schema,"run").redirectError(File(root,"dual-probe-errors.log")).redirectOutput(File(root,"dual-probe-output.log")).start()
            assertTrue(p.waitFor(5,TimeUnit.MINUTES));assertEquals(0,p.exitValue())
            assertContains(File(root,"$schema-results.tsv").readText(),"軟件")
        }
        u.selectDictionary(true,false);probe(WanxiangUpdater.SCHEMA)
        u.selectDictionary(false);probe(WanxiangUpdater.FALLBACK)
        // Force a real transfer rather than accepting the identical bundled snapshot.
        val downloadUser=File(root,"ice-download-user")
        File(downloadUser,".zephyr-wanxiang").mkdirs()
        File(downloadUser,".zephyr-wanxiang/state.json").writeText("""{"enabled":false,"grammar":true}""")
        val download=WanxiangUpdater(downloadUser,WindowsWanxiangActivator(root,downloadUser),network,catalog={error("No Wanxiang resource requested")})
        download.updateDictionary(false)
        assertNotNull(download.state().iceDictionary);assertNull(download.state().model)
        assertTrue(File(downloadUser,"build/rime_ai_simp.schema.yaml").isFile)
        assertTrue(download.state().grammar);assertFalse(download.state().enabled)
        u.selectDictionary(true,true);assertTrue(u.state().grammar)
        assertContains(File(user,"build/zephyr_wanxiang.schema.yaml").readText(),"grammar:")
    }
}
