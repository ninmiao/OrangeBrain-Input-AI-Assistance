package input.zephyr.windows

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.awt.Component
import java.awt.Container
import java.io.File
import javax.swing.*
import kotlin.test.*

class WanxiangUiTest {
    @TempDir lateinit var directory:File
    private fun all(c:Container):List<Component> = c.components.flatMap {listOf(it)+if(it is Container)all(it) else emptyList()}
    @Test fun defaultModelIsOnAndControlsAreAvailableWithoutCreatingDownloads() {
        SwingUtilities.invokeAndWait {
            val panel=WanxiangPanel(File(directory,"user"),directory)
            try {
                val controls=all(panel)
                assertTrue((controls.single {it.name=="wanxiang-grammar"} as JCheckBox).isSelected)
                assertTrue(controls.single {it.name=="wanxiang-update"}.isEnabled)
                assertTrue(controls.single {it.name=="wanxiang-fallback"}.isEnabled)
                assertFalse(File(directory,"user").exists())
                val choice=controls.single {it.name=="dictionary-choice"} as JComboBox<*>
                assertEquals(2,choice.itemCount)
                assertTrue(controls.single {it.name=="ice-update"}.isEnabled)
                choice.selectedIndex=1
                assertFalse(controls.single {it.name=="wanxiang-grammar"}.isEnabled)
                assertFalse(controls.single {it.name=="grammar-download"}.isEnabled)
                choice.selectedIndex=0
                assertTrue(controls.single {it.name=="grammar-download"}.isEnabled)
                assertTrue((controls.single {it.name=="wanxiang-grammar"} as JCheckBox).isSelected)
            } finally { assertTrue(panel.close()) }
        }
    }
}
