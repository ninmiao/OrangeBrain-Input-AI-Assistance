package input.zephyr.windows
import com.osfans.trime.ai.*
import java.awt.Component
import java.awt.Container
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import javax.swing.*
import kotlin.test.*

/** Explicit opt-in; the key is supplied through the test process environment only. */
class GeminiPolicyLiveTest {
    private fun <T> edt(block:()->T):T { var r:Result<T>?=null;SwingUtilities.invokeAndWait { r=runCatching(block) };return r!!.getOrThrow() }
    private fun components(c:Container):List<Component> = c.components.flatMap { listOf(it)+if(it is Container)components(it) else emptyList() }
    @Test fun policyLatencyButtonCallsGeminiWithEncryptedPolicyCredential() {
        val key=System.getenv("ZEPHYR_GEMINI_TEST_KEY")
        org.junit.jupiter.api.Assumptions.assumeTrue(!key.isNullOrBlank())
        val store=ConfigurationStore(Files.createTempDirectory("zephyr-live-gemini-"))
        store.save(Configuration(selectedPolicy="gemini",timeoutMs=30000,policies=listOf(geminiPolicy())))
        store.saveKey("gemini",key!!,ApiRouting.GEMINI)
        val w=edt { SettingsWindow(store).also { it.addNotify() } }
        try {
            val button=edt { components(w).filterIsInstance<JButton>().first { it.name=="test-policy" }.also { it.doClick() } }
            val deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(40)
            while(System.nanoTime()<deadline && !edt { button.isEnabled })Thread.sleep(50)
            val text=edt { components(w).filterIsInstance<JTextArea>().first { it.name=="policy-latency-result" }.text }
            assertTrue(text.contains("ms · "),text)
            assertTrue(text.contains("low/default"));assertTrue(text.contains("tokens"));assertEquals("gemini",store.load().selectedPolicy)
            println("Gemini policy latency button: "+text.replace('\n',' '))
        } finally { edt { w.dispose() };store.dir.toFile().deleteRecursively() }
    }
}
