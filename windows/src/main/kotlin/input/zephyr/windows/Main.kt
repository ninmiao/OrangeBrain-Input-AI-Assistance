package input.zephyr.windows

import javax.swing.*
import java.nio.channels.FileChannel
import java.nio.file.StandardOpenOption

fun main(args:Array<String>) {
    val store=ConfigurationStore()
    when(args.firstOrNull()) {
        "--broker" -> FileChannel.open(store.dir.resolve("broker.lock"),StandardOpenOption.CREATE,StandardOpenOption.WRITE).use { channel ->
            val lock=channel.tryLock() ?: return
            lock.use {
                val launcher=System.getProperty("jpackage.app-path")
                if(launcher!=null) {
                    val native=java.nio.file.Paths.get(launcher).parent.resolve("ZephyrServer.exe")
                    val running=ProcessHandle.allProcesses().use { processes -> processes.anyMatch { it.info().command().orElse("").equals(native.toString(),ignoreCase=true) } }
                    if(!running && java.nio.file.Files.exists(native))ProcessBuilder(native.toString()).start()
                }
                PipeBroker(store).run()
            }
        }
        "--evaluate" -> evaluate(args.drop(1),store)
        else -> SwingUtilities.invokeLater {
            UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName())
            val uiFont=javax.swing.plaf.FontUIResource("Microsoft YaHei UI",java.awt.Font.PLAIN,14)
            java.util.Collections.list(UIManager.getDefaults().keys()).filter { UIManager.get(it) is java.awt.Font }.forEach { UIManager.put(it,uiFont) }
            SettingsWindow(store).isVisible=true
        }
    }
}
