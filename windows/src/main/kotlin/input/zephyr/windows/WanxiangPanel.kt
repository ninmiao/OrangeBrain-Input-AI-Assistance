// SPDX-License-Identifier: GPL-3.0-or-later
package input.zephyr.windows

import com.osfans.trime.rime.*
import com.sun.jna.platform.win32.Advapi32Util
import com.sun.jna.platform.win32.WinReg
import com.sun.jna.platform.win32.Kernel32
import com.sun.jna.platform.win32.WinError
import kotlinx.coroutines.*
import java.awt.*
import java.io.File
import java.util.concurrent.TimeUnit
import javax.swing.*

class WindowsWanxiangActivator(private val image:File,private val data:File):WanxiangActivator {
    override suspend fun activate(schema:String)=withContext(Dispatchers.IO) {
        val helper=File(image,"ZephyrDataDeploy.exe")
        check(helper.isFile) { "请先安装包含词库更新功能的新版 Zephyr Input" }
        val server=File(image,"ZephyrServer.exe")
        fun servers()=ProcessHandle.allProcesses().use { all -> all.filter { it.info().command().orElse("").equals(server.absolutePath,true) }.toList() }
        val wasRunning=servers().isNotEmpty()
        // The TSF component observes this named gate before automatically restarting its server.
        val gate=Kernel32.INSTANCE.CreateMutex(null,false,"ZephyrDeployerExclusiveMutex")
        check(gate!=null) { "无法锁定输入服务" }
        if(Kernel32.INSTANCE.GetLastError()==WinError.ERROR_ALREADY_EXISTS) {
            Kernel32.INSTANCE.CloseHandle(gate);error("另一项输入法安装或部署正在进行，请稍后重试")
        }
        try {
            if(wasRunning) {
                ProcessBuilder(server.path,"/quit").start().waitFor(10,TimeUnit.SECONDS)
                repeat(50) { if(servers().isNotEmpty())Thread.sleep(100) }
                check(servers().isEmpty()) { "输入服务尚未关闭，请完成当前输入后重试" }
            }
            val process=ProcessBuilder(helper.path,File(image,"rime.dll").path,File(image,"data").path,data.path,schema)
                .redirectOutput(ProcessBuilder.Redirect.DISCARD).redirectError(ProcessBuilder.Redirect.DISCARD).start()
            if(!process.waitFor(15,TimeUnit.MINUTES)) { process.destroyForcibly().waitFor();error("词库部署超过 15 分钟，请检查存储空间后重试") }
            check(process.exitValue()==0) { "Rime 部署校验失败（${process.exitValue()}）" }
        } finally {
            Kernel32.INSTANCE.CloseHandle(gate)
            if(wasRunning && servers().isEmpty())ProcessBuilder(server.path).start()
        }
    }
    companion object {
        fun userDirectory():File {
            val configured=runCatching { Advapi32Util.registryGetStringValue(WinReg.HKEY_CURRENT_USER,"Software\\ZephyrInput","RimeUserDir") }.getOrNull()
            return if(!configured.isNullOrBlank())File(configured) else File(System.getenv("APPDATA"),"ZephyrInput/rime")
        }
    }
}

class WanxiangPanel(
    private val directory:File=WindowsWanxiangActivator.userDirectory(),
    private val image:File=File(System.getProperty("jpackage.app-path") ?: "ZephyrSettings.exe").absoluteFile.parentFile,
):JPanel() {
    private val scope=CoroutineScope(SupervisorJob()+Dispatchers.IO)
    private var job:Job?=null
    private var cancelable=true
    private val info=JTextArea(6,55).apply { isEditable=false;lineWrap=true;wrapStyleWord=true;isOpaque=false;name="wanxiang-status" }
    private val bar=JProgressBar(0,100).apply { isStringPainted=true }
    private val choice=JComboBox(arrayOf("万象 / Wanxiang","雾凇 / Rime Ice")).apply {name="dictionary-choice"}
    private val grammar=JCheckBox("万象语法模型 · 默认开启，下载后生效 / Grammar",true).apply { name="wanxiang-grammar" }
    private val update=JButton("Update Wanxiang dictionary / 更新万象词表").apply { name="wanxiang-update" }
    private val fallback=JButton("Apply selection offline / 应用选择（离线）").apply { name="wanxiang-fallback" }
    private val ice=JButton("Update Rime Ice dictionary / 更新雾凇词表").apply {name="ice-update"}
    private val model=JButton("Download / update grammar model / 下载或更新万象语法模型").apply {name="grammar-download"}
    private val cancel=JButton("Pause download / 暂停下载").apply { isEnabled=false }
    private val updater=WanxiangUpdater(directory,WindowsWanxiangActivator(image,directory),progress=::showProgress,bundledDirectory=File(image,"data"))
    init {
        layout=BoxLayout(this,BoxLayout.Y_AXIS);border=BorderFactory.createEmptyBorder(18,22,18,22)
        add(JLabel("词库与语法模型 / Dictionaries").apply { font=font.deriveFont(Font.BOLD,24f) })
        add(JLabel("两套词表均已内置，离线可切换；词表和模型可分别从官方 GitHub 更新。"))
        add(JLabel("万象词表 + 万象模型搭配使用；切到雾凇时停用模型，切回后恢复开关。"))
        add(JLabel("模型约 407 MB，单独下载；词表更新不会下载模型。建议预留 1.5 GB 空间。"))
        add(choice);add(grammar);add(fallback);add(update);add(ice);add(model);add(cancel);add(bar);add(info)
        add(JLabel("万象：amzxyz / CC BY 4.0 · 雾凇：iDvel / GPL-3.0-only"))
        val source=JButton("Source & license / 来源与许可")
        source.addActionListener { Desktop.getDesktop().browse(java.net.URI("https://github.com/amzxyz/rime-wanxiang")) };add(source)
        add(JLabel("Data / 数据目录：${directory.absolutePath}"))
        components.filterIsInstance<JComponent>().forEach { it.alignmentX=Component.LEFT_ALIGNMENT }
        runCatching { updater.state() }.onSuccess { grammar.isSelected=it.grammar;choice.selectedIndex=if(it.enabled)0 else 1;info.text=it.summary() }.onFailure { info.text="配置读取失败：${it.message}" }
        fun refreshChoice() {grammar.isEnabled=job==null && choice.selectedIndex==0;model.isEnabled=grammar.isEnabled}
        choice.addActionListener {refreshChoice()};refreshChoice()
        update.addActionListener {start {updater.updateDictionary(true)}}
        ice.addActionListener {start {updater.updateDictionary(false)}}
        model.addActionListener {start {updater.updateModel()}}
        fallback.addActionListener {val selected=choice.selectedIndex==0;val useGrammar=grammar.isSelected;start {updater.selectDictionary(selected,useGrammar)}}
        cancel.addActionListener { if(cancelable)job?.cancel() }
    }
    private fun showProgress(p:WanxiangProgress) { SwingUtilities.invokeLater {
        cancelable=p.canCancel;cancel.isEnabled=p.canCancel && job!=null;info.text=p.message
        bar.isIndeterminate=p.total==0L
        if(p.total>0) { bar.value=(p.done*100/p.total).toInt();bar.string="${p.done/1_000_000} / ${p.total/1_000_000} MB" } else bar.string=p.message.substringBefore('\n')
    } }
    private fun start(block:suspend ()->Unit) {
        if(job!=null)return
        update.isEnabled=false;fallback.isEnabled=false;grammar.isEnabled=false;ice.isEnabled=false;model.isEnabled=false;choice.isEnabled=false;cancel.isEnabled=true;cancelable=true
        job=scope.launch {
            try { block() } catch(_:CancellationException) { showProgress(WanxiangProgress("下载已暂停；再次点击可继续 / Paused; click to resume")) }
            catch(error:Exception) { showProgress(WanxiangProgress("${error.message}\n可重新点击重试 / Click to retry")) }
            finally { SwingUtilities.invokeLater { job=null;runCatching {updater.state()}.onSuccess {choice.selectedIndex=if(it.enabled)0 else 1;grammar.isSelected=it.grammar};update.isEnabled=true;fallback.isEnabled=true;grammar.isEnabled=choice.selectedIndex==0;ice.isEnabled=true;choice.isEnabled=true;model.isEnabled=grammar.isEnabled;cancel.isEnabled=false;bar.isIndeterminate=false } }
        }
    }
    fun close():Boolean {
        if(job!=null && !cancelable) {
            info.text="正在部署，请等待完成后关闭 / Please wait for deployment to finish."
            return false
        }
        scope.cancel();return true
    }
}
