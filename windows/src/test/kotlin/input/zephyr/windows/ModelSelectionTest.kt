package input.zephyr.windows

import com.osfans.trime.ai.*
import java.awt.Component
import java.awt.Container
import java.awt.GraphicsEnvironment
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.swing.*
import kotlin.test.*

class ModelSelectionTest {
    private val endpoint="https://models.example/v1/chat/completions"
    private fun <T> edt(block:()->T):T {
        var result:Result<T>?=null
        SwingUtilities.invokeAndWait { result=runCatching(block) }
        return result!!.getOrThrow()
    }
    private fun components(c:Container):List<Component> = c.components.flatMap { listOf(it)+if(it is Container)components(it) else emptyList() }
    private inline fun <reified T:Component> find(window:SettingsWindow,name:String):T = components(window).first { it.name==name } as T
    private fun waitFor(predicate:()->Boolean) {
        val until=System.nanoTime()+TimeUnit.SECONDS.toNanos(10)
        while(System.nanoTime()<until) { if(edt(predicate))return;Thread.sleep(20) }
        assertTrue(edt(predicate),"UI operation did not finish")
    }
    private fun fixture(fetch:suspend (String,String)->ModelsClient.Discovery,block:(SettingsWindow,ConfigurationStore)->Unit) {
        org.junit.jupiter.api.Assumptions.assumeFalse(GraphicsEnvironment.isHeadless())
        val dir=Files.createTempDirectory("zephyr-model-ui-");val store=ConfigurationStore(dir)
        val first=Policy(id="one",endpoint=endpoint,model="manual-model",reasoning="omit",speed="default")
        store.save(Configuration(selectedPolicy="one",policies=listOf(first,first.copy(id="two",model="second-model"))))
        store.saveKey("one","fixture-one",endpoint);store.saveKey("two","fixture-two",endpoint)
        val window=edt { SettingsWindow(store,fetch).also { it.addNotify() } }
        try { block(window,store) } finally { edt { window.dispose() };dir.toFile().deleteRecursively() }
    }
    @Test fun editableChoicesPreserveTypedModelAndAllowSelection() = edt {
        val picker=EditableModelSelector();picker.text="custom-unlisted"
        picker.setOptions(listOf("server-b","server-a","server-a"))
        assertTrue(picker.isEditable);assertEquals("custom-unlisted",picker.text)
        assertEquals(3,picker.itemCount)
        picker.selectedItem="server-b";assertEquals("server-b",picker.text)
        (picker.editor.editorComponent as JTextField).text="typed-new-model"
        picker.setOptions(listOf("server-c"));assertEquals("typed-new-model",picker.text)
    }
    @Test fun settingsWindowDisplaysUnderWindowsLookAndFeel() {
        org.junit.jupiter.api.Assumptions.assumeFalse(GraphicsEnvironment.isHeadless())
        val previous=edt { UIManager.getLookAndFeel().javaClass.name }
        try {
            edt { UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName()) }
            fixture({ _,_ -> error("No network expected") }) { window,_ ->
                edt {
                    window.isVisible=true
                    assertTrue(window.isShowing)
                    val picker=find<EditableModelSelector>(window,"model-selector")
                    assertTrue(picker.minimumSize.width>0)
                    assertTrue(picker.components.contains(picker.editor.editorComponent))
                    picker.selectedItem="another-model"
                    assertEquals("another-model",picker.text)
                }
            }
        } finally { edt { UIManager.setLookAndFeel(previous) } }
    }
    @Test fun settingsPagesScrollToEveryControlInSmallWindow() {
        fixture({ _,_ -> error("No network expected") }) { window,_ ->
            edt {
                window.size=java.awt.Dimension(640,480)
                window.isVisible=true
                val tabs=components(window).filterIsInstance<JTabbedPane>().single()
                for(i in 0 until tabs.tabCount) {
                    tabs.selectedIndex=i;window.validate()
                    val scroll=tabs.getComponentAt(i) as JScrollPane
                    assertTrue(scroll.verticalScrollBar.isVisible)
                    val panel=scroll.viewport.view as JPanel
                    panel.components.forEach { component ->
                        assertTrue(component.height>=component.preferredSize.height,"Tab $i clipped a control vertically")
                    }
                    val last=panel.components.last()
                    panel.scrollRectToVisible(last.bounds)
                    assertTrue(scroll.viewport.viewRect.intersects(last.bounds),"Tab $i cannot reach final control")
                    if(panel.preferredSize.width>scroll.viewport.extentSize.width)assertTrue(scroll.horizontalScrollBar.isVisible)
                }
                tabs.selectedIndex=1;window.validate()
                val save=find<JButton>(window,"save-policy")
                assertTrue(save.isShowing)
                val buttonBounds=SwingUtilities.convertRectangle(save.parent,save.bounds,window.contentPane)
                assertTrue(window.contentPane.bounds.width>=buttonBounds.x+buttonBounds.width)
                assertTrue(buttonBounds.y<200,"Save policy must stay at the top")
            }
        }
    }
    @Test fun policyListDistinguishesEditingFromAppliedPolicy() {
        fixture({ _,_ -> error("No network expected") }) { window,store ->
            edt {
                window.isVisible=true
                val list=find<JList<String>>(window,"policy-selector")
                val current=find<JLabel>(window,"current-policy")
                assertEquals(2,list.model.size)
                assertTrue(list.model.getElementAt(0).contains("Active"))
                list.selectedIndex=1
                assertEquals("one",store.load().selectedPolicy)
                assertTrue(current.text.contains("manual-model"))
                find<JButton>(window,"save-policy").doClick()
                assertEquals("one",store.load().selectedPolicy)
                find<JButton>(window,"apply-policy").doClick()
                assertEquals("two",store.load().selectedPolicy)
                assertTrue(list.model.getElementAt(1).contains("Active"))
                assertFalse(list.model.getElementAt(0).contains("Active"))
                assertTrue(current.text.contains("second-model"))
                list.selectedIndex=0
                assertEquals("two",store.load().selectedPolicy)
                assertTrue(list.model.getElementAt(1).contains("Active"))
            }
        }
    }
    @Test fun cachedDiscoveryPersistsAndDoesNotCrossEndpoints() {
        val router="https://openrouter.ai/api/v1/chat/completions"
        val definition=ModelDefinition(ApiRouting.DEEPSEEK,parameters=listOf(ModelParameter("reasoning_effort","Effort",choices=ReasoningCapabilities.choices(listOf("low")))))
        val cache=ModelListCache.from(router,ModelsClient.Discovery(listOf(ApiRouting.DEEPSEEK),listOf(definition)))
        val p=Policy(id="openrouter",endpoint=router,model=ApiRouting.DEEPSEEK,reasoning="low",modelList=cache)
        assertEquals(listOf("low","omit"),ReasoningCapabilities.options(router,p.model,p.effectiveCatalog()).map { it.value })
        assertTrue(p.effectiveCatalog(endpoint).models.isEmpty())
        val dir=Files.createTempDirectory("zephyr-model-cache-");val store=ConfigurationStore(dir)
        try { store.save(Configuration(selectedPolicy=p.id,policies=listOf(p)));assertEquals(cache,store.load().active().modelList) }
        finally { dir.toFile().deleteRecursively() }
        assertFails { ModelListCache.from(endpoint,ModelsClient.Discovery(emptyList(),emptyList())) }
        val manual=ModelCatalog(models=listOf(definition))
        assertEquals(manual,ModelListCache.from(endpoint,ModelsClient.Discovery(listOf("custom"),emptyList()),manual).catalog)
    }
    @Test fun refreshUsesPolicyCredentialPreservesInputAndSavesChoices() {
        fixture({ ep,key -> assertEquals(endpoint,ep);assertEquals("fixture-one",key);ModelsClient.Discovery(listOf("server-a","server-b"),emptyList()) }) { w,store ->
            edt { find<JButton>(w,"refresh-models").doClick() }
            waitFor { find<JButton>(w,"refresh-models").isEnabled }
            edt {
                val picker=find<EditableModelSelector>(w,"model-selector")
                assertEquals("manual-model",picker.text)
                assertTrue((0 until picker.itemCount).any { picker.getItemAt(it)=="server-a" })
                picker.selectedItem="server-b"
            }
            edt { find<JButton>(w,"save-policy").doClick() }
            assertEquals("server-b",store.load().active().model)
            assertEquals(listOf("server-a","server-b"),store.load().active().modelList!!.ids)
        }
    }
    @Test fun failureKeepsExistingListAndChangingOriginNeverLeaksStoredKey() {
        val calls=AtomicInteger()
        fixture({ _,_ -> calls.incrementAndGet();throw ApiHttpException(401) }) { w,_ ->
            edt { find<JButton>(w,"refresh-models").doClick() }
            waitFor { find<JButton>(w,"refresh-models").isEnabled }
            edt { assertEquals("manual-model",find<EditableModelSelector>(w,"model-selector").text);assertTrue(find<JLabel>(w,"status").text.contains("401")) }
            edt { find<JTextField>(w,"api-endpoint").text="https://another.example/v1/chat/completions" }
            edt { find<JButton>(w,"refresh-models").doClick() }
            waitFor { find<JButton>(w,"refresh-models").isEnabled }
            assertEquals(1,calls.get())
        }
    }
    @Test fun lateResponseCannotReplaceAnotherPolicyList() {
        val started=CountDownLatch(1);val release=CountDownLatch(1);val finished=CountDownLatch(1)
        fixture({ _,_ -> started.countDown();release.await(10,TimeUnit.SECONDS);finished.countDown();ModelsClient.Discovery(listOf("old-policy-result"),emptyList()) }) { w,store ->
            try {
                edt { find<JButton>(w,"refresh-models").doClick() };assertTrue(started.await(5,TimeUnit.SECONDS))
                edt { find<JList<*>>(w,"policy-selector").selectedIndex=1 }
                release.countDown();assertTrue(finished.await(5,TimeUnit.SECONDS));Thread.sleep(200)
                edt {
                    val picker=find<EditableModelSelector>(w,"model-selector")
                    assertEquals("second-model",picker.text)
                    assertFalse((0 until picker.itemCount).any { picker.getItemAt(it)=="old-policy-result" })
                    find<JButton>(w,"save-policy").doClick()
                }
                assertNull(store.load().policies.first { it.id=="two" }.modelList)
            } finally { release.countDown() }
        }
    }
}
