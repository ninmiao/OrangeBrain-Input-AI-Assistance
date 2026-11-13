package input.zephyr.windows
import com.osfans.trime.ai.*
import java.awt.Component
import java.awt.Container
import java.awt.GraphicsEnvironment
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.swing.*
import kotlin.test.*

class PolicyLatencyTest {
    private fun <T> edt(block:()->T):T { var r:Result<T>?=null;SwingUtilities.invokeAndWait { r=runCatching(block) };return r!!.getOrThrow() }
    private fun components(c:Container):List<Component> = c.components.flatMap { listOf(it)+if(it is Container)components(it) else emptyList() }
    private inline fun <reified T:Component> find(w:SettingsWindow,name:String)=components(w).first { it.name==name } as T
    private fun waitFor(predicate:()->Boolean) { val deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(8);while(System.nanoTime()<deadline) { if(edt(predicate))return;Thread.sleep(20) };assertTrue(edt(predicate)) }
    @Test fun editedPolicyUsesItsOwnKeyAndLateResultStaysWithOriginalPolicy() {
        org.junit.jupiter.api.Assumptions.assumeFalse(GraphicsEnvironment.isHeadless())
        val store=ConfigurationStore(Files.createTempDirectory("zephyr-latency-"))
        val one=Policy(id="one",model="gpt-6-luna",reasoning="none",speed="default")
        val two=one.copy(id="two",name="Second",model="gpt-6-sol",reasoning="high",speed="priority")
        store.save(Configuration(selectedPolicy="one",policies=listOf(one,two)))
        store.saveKey("one","fixture-one",one.endpoint);store.saveKey("two","fixture-two",two.endpoint)
        val started=CountDownLatch(1);val release=CountDownLatch(1)
        val w=edt { SettingsWindow(store,measurePolicy={ config,p,raw ->
            assertEquals("one",config.selectedPolicy);assertEquals("two",p.id)
            assertEquals("gpt-6.1-terra",p.model);assertEquals("high",p.reasoning);assertEquals("priority",p.speed)
            assertEquals("fixture-two",store.key(p.id,p.endpoint));assertEquals("woxianghekafe",raw.input)
            started.countDown();assertTrue(release.await(5,TimeUnit.SECONDS))
            AiResult(listOf("我想喝咖啡"),usage=TokenUsage(90,7,10,0))
        }).also { it.addNotify() } }
        try {
            edt { find<JList<*>>(w,"policy-selector").selectedIndex=1;find<EditableModelSelector>(w,"model-selector").text="gpt-6.1-terra" }
            edt { find<JButton>(w,"test-policy").doClick() }
            assertTrue(started.await(5,TimeUnit.SECONDS))
            edt { assertFalse(find<JButton>(w,"test-policy").isEnabled);find<JList<*>>(w,"policy-selector").selectedIndex=0 }
            release.countDown()
            Thread.sleep(200)
            edt { assertFalse(find<JTextArea>(w,"policy-latency-result").text.contains("我想喝咖啡"));find<JList<*>>(w,"policy-selector").selectedIndex=1 }
            waitFor { find<JTextArea>(w,"policy-latency-result").text.contains("我想喝咖啡") }
            edt { assertTrue(find<JTextArea>(w,"policy-latency-result").text.contains("think 10")) }
            assertEquals("one",store.load().selectedPolicy)
        } finally { release.countDown();edt { w.dispose() };store.dir.toFile().deleteRecursively() }
    }
    @Test fun httpFailuresRemainVisibleInDedicatedPolicyResult() {
        org.junit.jupiter.api.Assumptions.assumeFalse(GraphicsEnvironment.isHeadless())
        val store=ConfigurationStore(Files.createTempDirectory("zephyr-latency-error-"))
        val w=edt { SettingsWindow(store,measurePolicy={ _,_,_ -> throw ApiHttpException(429) }).also { it.addNotify() } }
        try {
            edt { find<JButton>(w,"test-policy").doClick() }
            waitFor { find<JButton>(w,"test-policy").isEnabled }
            edt { assertTrue(find<JTextArea>(w,"policy-latency-result").text.contains("429"));find<JList<*>>(w,"policy-selector").selectedIndex=1;find<JList<*>>(w,"policy-selector").selectedIndex=0;assertTrue(find<JTextArea>(w,"policy-latency-result").text.contains("429")) }
        } finally { edt { w.dispose() };store.dir.toFile().deleteRecursively() }
    }
}
