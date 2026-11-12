// SPDX-License-Identifier: GPL-3.0-or-later
package input.zephyr.windows

import com.osfans.trime.ai.*
import java.awt.*
import javax.swing.*
import javax.swing.event.DocumentEvent
import javax.swing.event.DocumentListener
import kotlinx.coroutines.runBlocking
import java.util.UUID

class SettingsWindow(private val store:ConfigurationStore):JFrame("Zephyr Input · 微风输入法") {
    private var config=store.load()
    private var policy=config.active()
    private val choices=JComboBox<String>()
    private val name=JTextField();private val endpoint=JTextField();private val model=JTextField();private val provider=JComboBox<String>().apply { isEditable=true }
    private var providerOptions=emptyList<ProviderOption>()
    private var providerGeneration=0
    private val providerTimer=Timer(600) { refreshProviders() }.apply { isRepeats=false }
    private val key=JPasswordField()
    private val reasoning=JComboBox<String>();private val speed=JComboBox(arrayOf("default","priority"))
    private val chinese=JTextArea(7,50);private val english=JTextArea(7,50)
    private val active=JCheckBox("Use this policy / 使用此 Policy")
    private val enabled=JCheckBox("Enable cloud AI / 启用云端 AI",config.enabled)
    private val segmentation=JCheckBox("Space marks phrase boundaries / 空格分词",config.wordSegmentation)
    private val enterOriginal=JCheckBox("Enter commits original text / 回车提交原文",config.enterOriginal)
    private val spaceOriginal=JCheckBox("Space commits original + space / 空格提交原文并加空格（优先于分词）",config.spaceOriginal)
    private val languageShortcut=JComboBox(ShortcutOptions.language.values.toTypedArray()).apply { selectedItem=ShortcutOptions.language[config.languageShortcut] }
    private val scriptShortcut=JComboBox(ShortcutOptions.script.values.toTypedArray()).apply { selectedItem=ShortcutOptions.script[config.scriptShortcut] }
    private val debounce=JSpinner(SpinnerNumberModel(config.debounceMs,50,2000,50))
    private val timeout=JSpinner(SpinnerNumberModel(config.timeoutMs,1000,60000,1000))
    private val style=JComboBox(Prompts.pack.styles.map { it.id }.toTypedArray())
    private val status=JLabel("Ready · API keys are encrypted for your Windows account")
    init {
        defaultCloseOperation=DISPOSE_ON_CLOSE;minimumSize=Dimension(780,660);size=Dimension(920,800);setLocationRelativeTo(null)
        val tabs=JTabbedPane()
        val settings=column()
        settings.add(JLabel("Zephyr Input",SwingConstants.LEFT).apply { font=font.deriveFont(Font.BOLD,26f) })
        settings.add(JLabel("Both languages: compose → choose → commit / 中英文均先组合，再选词上屏"))
        settings.add(enabled);settings.add(enterOriginal);settings.add(spaceOriginal);settings.add(segmentation)
        settings.add(JLabel("AI returns one candidate, without continuation / AI 固定一个候选，不续写"))
        row(settings,"Debounce (ms) / 等待停顿",debounce)
        row(settings,"Request timeout (ms) / 请求超时",timeout);row(settings,"Expression style / 表达风格",style)
        style.selectedItem=config.style
        row(settings,"Chinese / English · 中英切换",languageShortcut)
        row(settings,"Simplified / Traditional · 繁简切换",scriptShortcut)
        settings.add(JLabel("Tap Shift alone within 0.5 s / 单独轻按 Shift；组合键与长按不切换。保存后即时生效。"))
        settings.add(JLabel("↑↓: candidates    1…5: choose    Tab: candidate    Enter: original (default)    Ctrl+Enter: original    Esc: cancel"))
        settings.add(JLabel("←→ / Home / End: edit pending input. Space follows the options above."))
        val save=JButton("Save settings / 保存设置");save.addActionListener { attempt { saveGlobal();store.save(config);status.text="Settings saved" } };settings.add(save)
        tabs.addTab("Input / 输入",JScrollPane(settings))
        val p=column();row(p,"Policy",choices);p.add(active)
        row(p,"Name / 名称",name);row(p,"API endpoint / 完整接口地址",endpoint);row(p,"Model ID / 模型",model);row(p,"Provider routing / 提供商（可空）",provider)
        row(p,"Reasoning / 思考强度",reasoning);row(p,"Speed / 速度",speed);row(p,"API Key（留空保留已存密钥）",key)
        val refreshProviders=JButton("Refresh providers / 刷新供应商")
        refreshProviders.addActionListener { refreshProviders() };p.add(refreshProviders)
        p.add(JLabel("Chinese policy instructions / 中文附加提示词"));p.add(JScrollPane(chinese))
        p.add(JLabel("English policy instructions / 英文附加提示词"));p.add(JScrollPane(english))
        val actions=JPanel(FlowLayout(FlowLayout.LEFT))
        val savePolicy=JButton("Save policy / 保存 Policy");savePolicy.addActionListener { attempt { savePolicy();status.text="Policy saved" } };actions.add(savePolicy)
        val test=JButton("Test latency / 测试当前 Policy");test.addActionListener {
            attempt { savePolicy();val snapshot=config;val selected=policy
                background(test) { val started=System.nanoTime();val result=runBlocking { AiService(store).request(snapshot,selected,Wire.Request(true,false,"fanfaxisizhazheng")) }
                    "${(System.nanoTime()-started)/1_000_000} ms · ${result.candidates.joinToString(" / ")}" }
            }
        };actions.add(test)
        val duplicate=JButton("Copy policy + Key / 复制 Policy（含 Key）")
        duplicate.addActionListener { attempt {
            savePolicy()
            val copied=store.duplicatePolicy(policy.id)
            config=store.load();reloadChoices(config.policies.indexOfFirst { it.id==copied.id })
            status.text="Policy copied with independent encrypted Key / 已复制，Key 独立加密保存"
        } };actions.add(duplicate)
        val add=JButton("New policy / 新建");add.addActionListener { config=config.copy(policies=config.policies+Policy(id=UUID.randomUUID().toString(),name="New policy"));reloadChoices(config.policies.lastIndex) };actions.add(add)
        p.add(actions);p.add(JLabel("Additional prompts cannot change the JSON schema. Core language rules remain shared with Android."))
        tabs.addTab("Policies / 策略",JScrollPane(p))
        val bench=column();bench.add(JLabel("At most five sequential requests. Each row can select either saved API policy."))
        val samples=mutableListOf<Triple<JComboBox<String>,JTextField,Pair<JComboBox<String>,JComboBox<String>>>>()
        val defaultModels=listOf("gpt-6-luna","deepseek/deepseek-v4-flash-0731","gpt-5.4-nano","gpt-5.4-mini","gpt-6-sol")
        defaultModels.forEachIndexed { i,id ->
            val source=JComboBox(arrayOf("openai","openrouter"));source.selectedItem=if(i==1)"openrouter" else "openai"
            val m=JTextField(id,28);val r=JComboBox(arrayOf("none","omit","low","medium","high","xhigh","max"));val s=JComboBox(arrayOf("default","priority"))
            val line=JPanel(FlowLayout(FlowLayout.LEFT));line.add(source);line.add(m);line.add(r);line.add(s);bench.add(line)
            samples+=Triple(source,m,r to s)
            fun refreshOptions() {
                val previous=r.selectedItem?.toString() ?: "none"
                val url=if(source.selectedItem=="openrouter")"https://openrouter.ai/api/v1/chat/completions" else "https://api.openai.com/v1/chat/completions"
                val options=ReasoningCapabilities.options(url,m.text).map { it.value }
                r.removeAllItems();options.forEach { r.addItem(it) };r.selectedItem=if(previous in options)previous else "omit"
            }
            source.addActionListener { refreshOptions() }
            m.document.addDocumentListener(object:DocumentListener {
                override fun insertUpdate(e:DocumentEvent) { SwingUtilities.invokeLater { refreshOptions() } }
                override fun removeUpdate(e:DocumentEvent) { SwingUtilities.invokeLater { refreshOptions() } }
                override fun changedUpdate(e:DocumentEvent) { SwingUtilities.invokeLater { refreshOptions() } }
            });refreshOptions()
        }
        val output=JTextArea(12,65).apply { isEditable=false;lineWrap=true;wrapStyleWord=true }
        val run=JButton("Run five-model benchmark / 一键测速")
        run.addActionListener { attempt {
            saveGlobal();store.save(config)
            val rows=samples.map { (source,m,options) -> config.policies.first { it.id==source.selectedItem }.copy(model=m.text.trim(),reasoning=options.first.selectedItem.toString(),speed=options.second.selectedItem.toString()).also { it.validate() } }
            require(rows.map { it.endpoint }.distinct().size>=2) { "Keep at least one OpenAI and one OpenRouter row" }
            background(run) {
                val lines=rows.map { item -> runCatching {
                    val t=System.nanoTime();val result=runBlocking { AiService(store).request(config,item,Wire.Request(false,false,"I wnated to recieve teh package")) }
                    "${item.model}: ${(System.nanoTime()-t)/1_000_000} ms · ${result.candidates.joinToString(" / ")}"
                }.getOrElse { "${item.model}: ${safeError(it)}" } }
                SwingUtilities.invokeLater { output.text=lines.joinToString("\n\n") };"Benchmark finished"
            }
        } }
        bench.add(run);bench.add(JScrollPane(output));tabs.addTab("Benchmark / 测速",JScrollPane(bench))
        listOf(settings,p,bench).forEach { panel -> panel.components.filterIsInstance<JComponent>().forEach { it.alignmentX=Component.LEFT_ALIGNMENT } }
        add(tabs,BorderLayout.CENTER);add(status,BorderLayout.SOUTH)
        choices.addActionListener { val i=choices.selectedIndex;if(i in config.policies.indices)loadPolicy(config.policies[i]) }
        reloadChoices(config.policies.indexOfFirst { it.id==config.selectedPolicy })
        val listener=object:DocumentListener {
            override fun insertUpdate(e:DocumentEvent)=refreshReasoningLater()
            override fun removeUpdate(e:DocumentEvent)=refreshReasoningLater()
            override fun changedUpdate(e:DocumentEvent)=refreshReasoningLater()
        };model.document.addDocumentListener(listener);endpoint.document.addDocumentListener(listener)
    }
    private fun column()=JPanel().apply { layout=BoxLayout(this,BoxLayout.Y_AXIS);border=BorderFactory.createEmptyBorder(18,22,18,22) }
    private fun row(panel:JPanel,label:String,field:JComponent) { panel.add(JPanel(BorderLayout(12,6)).apply { border=BorderFactory.createEmptyBorder(4,0,4,0);add(JLabel(label).apply { preferredSize=Dimension(290,28) },BorderLayout.WEST);add(field,BorderLayout.CENTER);maximumSize=Dimension(Int.MAX_VALUE,44) }) }
    private fun reloadChoices(index:Int) { choices.removeAllItems();config.policies.forEach { choices.addItem("${it.name} · ${it.model} · ${it.reasoning} / ${it.speed}" + if(ApiRouting.isOpenRouter(it.endpoint)) " · ${it.provider.ifBlank { "Auto" }}" else "") };choices.selectedIndex=index.coerceAtLeast(0) }
    private fun loadPolicy(p:Policy) { policy=p;name.text=p.name;endpoint.text=p.endpoint;model.text=p.model;providerOptions=emptyList();provider.removeAllItems();provider.addItem(p.provider);provider.selectedItem=p.provider;providerTimer.restart();speed.selectedItem=p.speed;key.text="";chinese.text=p.chinesePrompt;english.text=p.englishPrompt;active.isSelected=config.selectedPolicy==p.id;refreshReasoning(p.reasoning) }
    private fun refreshReasoningLater() { providerTimer.restart(); SwingUtilities.invokeLater { refreshReasoning(reasoning.selectedItem?.toString() ?: "omit") } }
    private fun refreshReasoning(value:String) { reasoning.removeAllItems();ReasoningCapabilities.options(endpoint.text,model.text,policy.catalog).forEach { reasoning.addItem(it.value) };reasoning.selectedItem=if((0 until reasoning.itemCount).any { reasoning.getItemAt(it)==value })value else "omit" }
    private fun providerId():String {
        val value=provider.editor.item?.toString()?.trim().orEmpty()
        return if(value=="Auto / 自动路由") "" else providerOptions.firstOrNull{it.label==value}?.id ?: value
    }
    private fun refreshProviders() {
        val ep=endpoint.text.trim();val m=model.text.trim();val generation=++providerGeneration
        provider.isEnabled=ApiRouting.isOpenRouter(ep)
        if(!provider.isEnabled || !m.contains('/'))return
        Thread {
            val result=runCatching { runBlocking { ProvidersClient().fetch(m) } }
            SwingUtilities.invokeLater {
                if(generation!=providerGeneration || ep!=endpoint.text.trim() || m!=model.text.trim() || !isDisplayable)return@invokeLater
                result.onSuccess { options ->
                    val selected=providerId();providerOptions=options;provider.removeAllItems();provider.addItem("Auto / 自动路由")
                    options.forEach{provider.addItem(it.label)}
                    provider.selectedItem=if(selected.isBlank())"Auto / 自动路由" else options.firstOrNull{it.id==selected}?.label ?: selected
                    status.text="Providers loaded: ${options.size} / 已获取供应商，原选择保留"
                }.onFailure { status.text="Provider lookup failed; retry or type an ID / 获取失败，可重试或手动填写" }
            }
        }.apply{isDaemon=true;start()}
    }
    private fun saveGlobal() { config=config.copy(languageShortcut=ShortcutOptions.language.entries.first { it.value==languageShortcut.selectedItem }.key,scriptShortcut=ShortcutOptions.script.entries.first { it.value==scriptShortcut.selectedItem }.key,enabled=enabled.isSelected,wordSegmentation=segmentation.isSelected,enterOriginal=enterOriginal.isSelected,spaceOriginal=spaceOriginal.isSelected,completion=false,candidateCount=1,debounceMs=debounce.value as Int,timeoutMs=timeout.value as Int,style=style.selectedItem.toString()) }
    private fun savePolicy() {
        saveGlobal();val edited=policy.copy(name=name.text.trim(),endpoint=endpoint.text.trim(),model=model.text.trim(),provider=providerId(),reasoning=reasoning.selectedItem.toString(),speed=speed.selectedItem.toString(),chinesePrompt=chinese.text,englishPrompt=english.text)
        edited.validate();config=config.copy(policies=config.policies.map { if(it.id==edited.id)edited else it },selectedPolicy=if(active.isSelected)edited.id else config.selectedPolicy)
        val password=key.password
        try { if(password.isNotEmpty())store.saveKey(edited.id,String(password),edited.endpoint) } finally { password.fill('\u0000');key.text="" }
        store.save(config);policy=edited
    }
    private fun attempt(block:()->Unit) { try { block() } catch(e:Exception) { status.text=safeError(e) } }
    private fun safeError(e:Throwable)=if(e is ApiHttpException) "API HTTP error" else (e.message ?: e.javaClass.simpleName).take(180)
    private fun background(button:JButton,task:()->String) { button.isEnabled=false;status.text="Running…";Thread { val message=runCatching(task).getOrElse(::safeError);SwingUtilities.invokeLater { status.text=message;button.isEnabled=true } }.apply { isDaemon=true;start() } }
}
