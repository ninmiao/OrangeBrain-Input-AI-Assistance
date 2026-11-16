package input.zephyr.windows

import com.osfans.trime.rime.*
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.util.concurrent.TimeUnit
import kotlin.test.*

/** Opt in with ZEPHYR_WANXIANG_FIXTURE: real official downloads + native engine, isolated user directory. */
class WanxiangNativeTest {
    @Test fun officialResourcesDeployWithGrammarAndCanSwitchBack()=runBlocking {
        val path=System.getenv("ZEPHYR_WANXIANG_FIXTURE")
        assumeTrue(!path.isNullOrBlank())
        val root=File(path!!);val user=File(root,"user").apply { mkdirs() }
        val network=WanxiangNetwork()
        val releases=listOf(network.release(false),network.release(true))
        val updater=WanxiangUpdater(user,WindowsWanxiangActivator(root,user),network,{releases[if(it)1 else 0]},
            { println("${it.message}: ${it.done}/${it.total}") })
        updater.update()
        assertTrue(updater.state().grammar)
        assertContains(File(user,"build/zephyr_wanxiang.schema.yaml").readText(),WanxiangUpdater.modelName(releases[1]))
        assertContains(File(user,"default.custom.yaml").readText(),"menu/page_size")
        assertEquals("preserved",File(user,"personal-note.txt").readText())
        val process=ProcessBuilder(File(root,"probe.exe").path,root.path,File(root,"rime.dll").path,"zephyr_wanxiang","run")
            .redirectError(File(root,"probe-errors.log")).redirectOutput(File(root,"probe-output.log")).start()
        assertTrue(process.waitFor(5,TimeUnit.MINUTES));assertEquals(0,process.exitValue())
        val results=File(root,"zephyr_wanxiang-results.tsv").readText()
        assertContains(results,"PARTIAL\t1\t0");assertContains(results,"軟件")
        updater.update(false);assertFalse(updater.state().grammar)
        updater.useFallback();assertFalse(updater.state().enabled)
        updater.update();assertTrue(updater.state().enabled);assertTrue(updater.state().grammar)
    }
}
