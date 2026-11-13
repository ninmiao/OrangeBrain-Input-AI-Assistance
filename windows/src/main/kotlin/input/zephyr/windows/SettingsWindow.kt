// SPDX-License-Identifier: GPL-3.0-or-later
package input.zephyr.windows

import com.osfans.trime.ai.*
import java.awt.*
import javax.swing.*
import javax.swing.event.DocumentEvent
import javax.swing.event.DocumentListener
import kotlinx.coroutines.*
import java.util.UUID

class SettingsWindow(private val store:ConfigurationStore,
    private val discoverModels:suspend (String,String)->ModelsClient.Discovery = { endpoint,key -> ModelsClient().discover(endpoint,key) },
    private val confirmDelete:(Component,String)->Boolean = { parent,message ->
        JOptionPane.showConfirmDialog(parent,message,"Delete policy / 删除 Policy",JOptionPane.YES_NO_OPTION,JOptionPane.WARNING_MESSAGE)==JOptionPane.YES_OPTION
    },
    private val measurePolicy:suspend (Configuration,Policy,Wire.Request)->AiResult = { c,p,r -> AiService(store).request(c,p,r) }
):JFrame("Zephyr Input · 微风输入法") {
    private var config=store.load()
    private var policy=config.active()
    private val choices=JList<String>().apply { name="policy-selector"; selectionMode=ListSelectionModel.SINGLE_SELECTION; visibleRowCount=5; font=font.deriveFont(12f) }
    private val deletePolicyButton=JButton("Delete policy / 删除 Policy").apply { name="delete-policy" }
    private val currentPolicy=JLabel().apply { name="current-policy" }
    private var reloadingPolicies=false
    private var reloadingBenchmarks=false
    private val benchmarkSources=mutableListOf<JComboBox<String>>()
    private val name=JTextField();private val endpoint=JTextField().apply { name="api-endpoint" };private val model=EditableModelSelector();private val provider=JComboBox<String>().apply { isEditable=true }
    private var providerOptions=emptyList<ProviderOption>()
    private var providerGeneration=0
    private val providerTimer=Timer(600) { refreshProviders() }.apply { isRepeats=false }
    private var modelGeneration=0
    private val updateModels=JButton("Update models / 更新模型列表").apply { name="refresh-models" }
    private val key=JPasswordField()
    private val reasoning=JComboBox<String>();private val speed=JComboBox(arrayOf("default","priority"))
    private val chinese=JTextArea(7,50);private val english=JTextArea(7,50)
    private val enabled=JCheckBox("Enable cloud AI / 启用云端 AI",config.enabled)
    private val segmentation=JCheckBox("Space marks phrase boundaries / 空格分词",config.wordSegmentation)
    private val enterOriginal=JCheckBox("Enter commits original text / 回车提交原文",config.enterOriginal)
    private val spaceOriginal=JCheckBox("Space commits original + space / 空格提交原文并加空格（优先于分词）",config.spaceOriginal)
    private val languageShortcut=JComboBox(ShortcutOptions.language.values.toTypedArray()).apply { selectedItem=ShortcutOptions.language[config.languageShortcut] }
    private val scriptShortcut=JComboBox(ShortcutOptions.script.values.toTypedArray()).apply { selectedItem=ShortcutOptions.script[config.scriptShortcut] }
    private val debounce=JSpinner(SpinnerNumberModel(config.debounceMs,50,2000,50))
    private val timeout=JSpinner(SpinnerNumberModel(config.timeoutMs,1000,60000,1000))
    private val presetEnabled=JCheckBox("Use OpenRouter Preset / 使用 Preset").apply { name="preset-enabled" }
    private val presetOptions=JPanel().apply { name="preset-options";layout=BoxLayout(this,BoxLayout.Y_AXIS) }
    private val presetChinese=JTextField().apply { name="preset-chinese" }
    private val presetTraditional=JTextField().apply { name="preset-traditional" }
    private val presetEnglish=JTextField().apply { name="preset-english" }
    private val policyLatency=JTextArea(4,50).apply { name="policy-latency-result";isEditable=false;lineWrap=true;wrapStyleWord=true }
    private val testPolicy=JButton("Test latency / 测试当前 Policy").apply { name="test-policy" }
    private val latencyResults=mutableMapOf<String,String>()
    private val testingPolicies=mutableSetOf<String>()
    private val testScope=CoroutineScope(SupervisorJob()+Dispatchers.IO)
    private val status=JLabel("Ready · API keys are encrypted for your Windows account").apply { name="status" }
    init {
        defaultCloseOperation=DISPOSE_ON_CLOSE;minimumSize=Dimension(600,420);size=Dimension(920,800);setLocationRelativeTo(null)
        val tabs=JTabbedPane()
        val settings=column()
        settings.add(JLabel("Zephyr Input",SwingConstants.LEFT).apply { font=font.deriveFont(Font.BOLD,26f) })
        settings.add(JLabel("Both languages: compose → choose → commit / 中英文均先组合，再选词上屏"))
        settings.add(enabled);settings.add(enterOriginal);settings.add(spaceOriginal);settings.add(segmentation)
        settings.add(JLabel("AI returns one candidate, without continuation / AI 固定一个候选，不续写"))
        row(settings,"Debounce (ms) / 等待停顿",debounce)
        row(settings,"Request timeout (ms) / 请求超时",timeout)
        row(settings,"Chinese / English · 中英切换",languageShortcut)
        row(settings,"Simplified / Traditional · 繁简切换",scriptShortcut)
        settings.add(JLabel("Tap Shift alone within 0.5 s / 单独轻按 Shift；组合键与长按不切换。保存后即时生效。"))
        settings.add(JLabel("↑↓: candidates    1…5: choose    Tab: candidate    Enter: original (default)    Ctrl+Enter: original    Esc: cancel"))
        settings.add(JLabel("←→ / Home / End: edit pending input. Space follows the options above."))
        val save=JButton("Save settings / 保存设置");save.addActionListener { attempt { saveGlobal();store.save(config);refreshCurrentPolicy();status.text="Settings saved" } };settings.add(save)
        tabs.addTab("Input / 输入",settingsScroll(settings))
        val p=column()
        row(p,"Name / 名称",name);row(p,"API endpoint / 完整接口地址",endpoint);row(p,"Model / 模型（可选或输入）",model)
        updateModels.addActionListener { refreshModels() };p.add(updateModels)
        p.add(JLabel("Save policy to remember the list / 更新后保存 Policy 可记住模型列表"))
        row(p,"Provider routing / 提供商（可空）",provider)
        row(p,"Reasoning / 思考强度",reasoning);row(p,"Speed / 速度",speed);row(p,"API Key（留空保留已存密钥）",key)
        val refreshProviders=JButton("Refresh providers / 刷新供应商")
        refreshProviders.addActionListener { refreshProviders() };p.add(refreshProviders)
        testPolicy.addActionListener { testSelectedPolicy() };p.add(testPolicy);p.add(JScrollPane(policyLatency))
        presetEnabled.addActionListener { refreshPresetControls() };p.add(presetEnabled)
        row(presetOptions,"简体 / Simplified Preset",presetChinese)
        row(presetOptions,"繁体 / Traditional Preset",presetTraditional)
        row(presetOptions,"英文 / English Preset",presetEnglish)
        presetOptions.add(JLabel("@preset/name · 保存 Policy 后生效；关闭后发送本地完整提示词。"))
        p.add(presetOptions)
        p.add(JLabel("Chinese policy instructions / 中文附加提示词"));p.add(JScrollPane(chinese))
        p.add(JLabel("English policy instructions / 英文附加提示词"));p.add(JScrollPane(english))
        val actions=JPanel(FlowLayout(FlowLayout.LEFT))
        val savePolicy=JButton("Save policy / 保存 Policy").apply { name="save-policy" };savePolicy.addActionListener { attempt { savePolicy();status.text="Policy saved" } }
        val duplicate=JButton("Copy policy + Key / 复制 Policy（含 Key）")
        duplicate.addActionListener { attempt {
            savePolicy()
            val copied=store.duplicatePolicy(policy.id)
            config=store.load();reloadChoices(config.policies.indexOfFirst { it.id==copied.id })
            status.text="Policy copied with independent encrypted Key / 已复制，Key 独立加密保存"
        } };actions.add(duplicate)
        val add=JButton("New policy / 新建");add.addActionListener { config=config.copy(policies=config.policies+Policy(id=UUID.randomUUID().toString(),name="New policy"));reloadChoices(config.policies.lastIndex) };actions.add(add)
        p.add(actions);p.add(JLabel("One plain-text candidate. Presets replace local instructions for their language mode / 只输出一个纯文本候选。"))
        tabs.addTab("Policies / 策略",settingsScroll(p))
        val bench=column();bench.add(JLabel("At most five requests; include every API with a saved Key / 最多五组，每个已配置 Key 的 API 至少一组。"))
        val samples=mutableListOf<Triple<JComboBox<String>,JTextField,Pair<JComboBox<String>,JComboBox<String>>>>()
        val selectedSamples=mutableListOf<JCheckBox>()
        BenchmarkEntry.defaults().forEachIndexed { i,entry ->
            val candidates=config.policies.filter { ApiRouting.api(it.endpoint)==entry.api }
            val initial=candidates.firstOrNull { store.hasKey(it.id) } ?: candidates.firstOrNull() ?: config.active()
            val source=JComboBox(config.policies.map { it.id }.toTypedArray()).apply { name="benchmark-policy-$i" };source.selectedItem=initial.id;benchmarkSources.add(source)
            source.renderer=object:DefaultListCellRenderer() {
                override fun getListCellRendererComponent(list:JList<*>?,value:Any?,index:Int,selected:Boolean,focus:Boolean):Component =
                    super.getListCellRendererComponent(list,config.policies.firstOrNull { it.id==value }?.name ?: value,index,selected,focus)
            }
            val selected=JCheckBox("${i+1}",store.hasKey(initial.id) && ApiRouting.api(initial.endpoint)==entry.api).apply { name="benchmark-enabled-$i" };selectedSamples.add(selected)
            val m=JTextField(entry.model,28).apply { name="benchmark-model-$i" };val r=JComboBox(arrayOf("none","omit","low","medium","high","xhigh","max"));val s=JComboBox(arrayOf("default","priority"))
            r.selectedItem=entry.reasoning;s.selectedItem=entry.speed
            val line=JPanel(FlowLayout(FlowLayout.LEFT));line.add(selected);line.add(source);line.add(m);line.add(r);line.add(s);bench.add(line)
            samples+=Triple(source,m,r to s)
            fun refreshOptions() {
                val previous=r.selectedItem?.toString() ?: "none"
                val url=config.policies.firstOrNull { it.id==source.selectedItem }?.endpoint ?: config.active().endpoint
                val options=ReasoningCapabilities.options(url,m.text).map { it.value }
                r.removeAllItems();options.forEach { r.addItem(it) };r.selectedItem=if(previous in options)previous else "omit"
            }
            source.addActionListener { if(!reloadingBenchmarks) { config.policies.firstOrNull { it.id==source.selectedItem }?.let { m.text=it.model;s.selectedItem=it.speed };refreshOptions() } }
            m.document.addDocumentListener(object:DocumentListener {
                override fun insertUpdate(e:DocumentEvent) { SwingUtilities.invokeLater { refreshOptions() } }
                override fun removeUpdate(e:DocumentEvent) { SwingUtilities.invokeLater { refreshOptions() } }
                override fun changedUpdate(e:DocumentEvent) { SwingUtilities.invokeLater { refreshOptions() } }
            });refreshOptions()
        }
        val output=JTextArea(12,65).apply { isEditable=false;lineWrap=true;wrapStyleWord=true }
        val run=JButton("Run five-model benchmark / 一键测速")
        run.addActionListener { attempt {
            savePolicy();val snapshot=config
            val rows=samples.filterIndexed { i,_ -> selectedSamples[i].isSelected }.map { (source,m,options) -> config.policies.first { it.id==source.selectedItem }.copy(model=m.text.trim(),reasoning=options.first.selectedItem.toString(),speed=options.second.selectedItem.toString()).also { it.validate() } }
            require(rows.size in 1..5) { "Select 1–5 rows / 请选择 1–5 组" }
            require(rows.map { ApiRouting.api(it.endpoint) }.toSet().containsAll(snapshot.policies.filter { store.hasKey(it.id) }.map { ApiRouting.api(it.endpoint) }.toSet())) { "Include each configured API / 请包含每个已配置的 API" }
            background(run) {
                val lines=rows.map { item -> runCatching {
                    val t=System.nanoTime();val result=runBlocking { measurePolicy(snapshot,item,Wire.Request(false,false,"I wnated to recieve teh package")) }
                    "${item.name} · ${item.model} · ${item.reasoning}/${item.speed}: ${(System.nanoTime()-t)/1_000_000} ms\n${result.candidates.joinToString(" / ")}\n${result.usage?.summary().orEmpty()}"
                }.getOrElse { "${item.model}: ${safeError(it)}" } }
                SwingUtilities.invokeLater { output.text=lines.joinToString("\n\n") };"Benchmark finished"
            }
        } }
        bench.add(run);bench.add(JScrollPane(output));tabs.addTab("Benchmark / 测速",settingsScroll(bench))
        listOf(settings,p,bench).forEach { panel -> panel.components.filterIsInstance<JComponent>().forEach { it.alignmentX=Component.LEFT_ALIGNMENT; val preferred=it.preferredSize; it.minimumSize=Dimension(preferred.width,preferred.height); it.maximumSize=Dimension(Int.MAX_VALUE,preferred.height) } }
        val applyPolicy=JButton("Apply policy / 应用此 Policy").apply { name="apply-policy"; font=font.deriveFont(Font.BOLD) }
        applyPolicy.addActionListener { attempt { savePolicy(activate=true);status.text="Policy applied / 已应用 Policy" } }
        choices.cellRenderer=object:DefaultListCellRenderer() {
            override fun getListCellRendererComponent(list:JList<*>?,value:Any?,index:Int,selected:Boolean,focus:Boolean):Component {
                val label=super.getListCellRendererComponent(list,value,index,selected,focus) as JLabel
                val inUse=config.policies.getOrNull(index)?.id==config.selectedPolicy
                label.font=label.font.deriveFont(if(inUse)Font.BOLD else Font.PLAIN)
                if(inUse) { label.background=Color(220,242,228);label.foreground=Color(20,85,46) }
                label.border=BorderFactory.createCompoundBorder(
                    BorderFactory.createLineBorder(if(selected)Color(50,110,200) else label.background,2),
                    BorderFactory.createEmptyBorder(1,6,1,6))
                return label
            }
        }
        deletePolicyButton.addActionListener { attempt { deleteSelectedPolicy() } }
        val policyHeader=JPanel(BorderLayout(8,6)).apply {
            border=BorderFactory.createEmptyBorder(10,14,10,14)
            add(currentPolicy,BorderLayout.NORTH)
            add(JScrollPane(choices).apply { preferredSize=Dimension(400,124) },BorderLayout.CENTER)
            add(JPanel(GridLayout(4,1,0,4)).apply {
                add(applyPolicy);add(savePolicy);add(deletePolicyButton);add(JLabel("选中仅编辑 · 应用后切换"))
            },BorderLayout.EAST)
        }
        add(policyHeader,BorderLayout.NORTH);add(tabs,BorderLayout.CENTER);add(status,BorderLayout.SOUTH)
        choices.addListSelectionListener { event -> val i=choices.selectedIndex;if(!reloadingPolicies && !event.valueIsAdjusting && i in config.policies.indices)loadPolicy(config.policies[i]) }
        reloadChoices(config.policies.indexOfFirst { it.id==config.selectedPolicy })
        val listener=object:DocumentListener {
            override fun insertUpdate(e:DocumentEvent)=refreshReasoningLater()
            override fun removeUpdate(e:DocumentEvent)=refreshReasoningLater()
            override fun changedUpdate(e:DocumentEvent)=refreshReasoningLater()
        };model.document.addDocumentListener(listener)
        endpoint.document.addDocumentListener(object:DocumentListener {
            private fun changed() {
                modelGeneration++;updateModels.isEnabled=true
                SwingUtilities.invokeLater { refreshModelOptions();refreshReasoningLater() }
            }
            override fun insertUpdate(e:DocumentEvent)=changed()
            override fun removeUpdate(e:DocumentEvent)=changed()
            override fun changedUpdate(e:DocumentEvent)=changed()
        })
    }
    private fun settingsScroll(panel:JPanel)=JScrollPane(panel,JScrollPane.VERTICAL_SCROLLBAR_ALWAYS,JScrollPane.HORIZONTAL_SCROLLBAR_AS_NEEDED).apply {
        verticalScrollBar.unitIncrement=24
        horizontalScrollBar.unitIncrement=24
        isWheelScrollingEnabled=true
    }
    private fun column()=object:JPanel(),Scrollable {
        override fun getPreferredScrollableViewportSize()=preferredSize
        override fun getScrollableTracksViewportWidth()=false
        override fun getScrollableTracksViewportHeight()=false
        override fun getScrollableUnitIncrement(rect:Rectangle,orientation:Int,direction:Int)=24
        override fun getScrollableBlockIncrement(rect:Rectangle,orientation:Int,direction:Int)=maxOf(24,(if(orientation==SwingConstants.VERTICAL)rect.height else rect.width)-24)
    }.apply { layout=BoxLayout(this,BoxLayout.Y_AXIS);border=BorderFactory.createEmptyBorder(18,22,18,22) }
    private fun row(panel:JPanel,label:String,field:JComponent) { panel.add(JPanel(BorderLayout(12,6)).apply { border=BorderFactory.createEmptyBorder(4,0,4,0);add(JLabel(label).apply { preferredSize=Dimension(290,28) },BorderLayout.WEST);add(field,BorderLayout.CENTER);maximumSize=Dimension(Int.MAX_VALUE,44) }) }
    private fun refreshCurrentPolicy() {
        val selected=config.active()
        currentPolicy.text="当前 Policy / Active: ${selected.name} · ${selected.model}"+if(config.enabled) "" else " · 云端 AI 已关闭"
        currentPolicy.toolTipText=currentPolicy.text
    }
    private fun reloadChoices(index:Int) {
        reloadingPolicies=true
        try {
            choices.setListData(config.policies.map {
                (if(it.id==config.selectedPolicy) "● 正在使用 / Active · " else "○ ")+"${it.name} · ${it.model} · ${it.reasoning} / ${it.speed}"+
                    if(ApiRouting.isOpenRouter(it.endpoint)) " · ${it.provider.ifBlank { "Auto" }}" else ""
            }.toTypedArray())
            choices.selectedIndex=index.coerceIn(0,config.policies.lastIndex)
        } finally { reloadingPolicies=false }
        loadPolicy(config.policies[choices.selectedIndex]);refreshCurrentPolicy()
        benchmarkSources.forEach { source ->
            val previous=source.selectedItem
            val retained=previous?.takeIf { id -> config.policies.any { it.id==id } }
            reloadingBenchmarks=true
            try {
                source.model=DefaultComboBoxModel(config.policies.map { it.id }.toTypedArray())
                source.selectedItem=retained ?: config.selectedPolicy
            } finally { reloadingBenchmarks=false }
            if(retained==null) { source.selectedIndex=-1;source.selectedItem=config.selectedPolicy }
        }
        deletePolicyButton.isEnabled=config.policies.size>1
        choices.ensureIndexIsVisible(choices.selectedIndex)
    }
    private fun deleteSelectedPolicy() {
        require(config.policies.size>1) { "Keep at least one policy / 至少保留一个 Policy" }
        val selected=policy
        val replacement=config.policies.first { it.id!=selected.id }
        val message="删除 Policy：${selected.name}？\n同时删除该 Policy 单独保存的 Key，无法撤销。"+
            if(config.selectedPolicy==selected.id) "\n正在使用此 Policy；删除后切换为：${replacement.name}" else ""
        if(!confirmDelete(this,message))return
        val index=choices.selectedIndex
        if(store.load().policies.any { it.id==selected.id }) {
            config=store.deletePolicy(selected.id)
        } else {
            config=config.copy(policies=config.policies.filterNot { it.id==selected.id })
        }
        reloadChoices(index.coerceAtMost(config.policies.lastIndex))
        status.text="Policy deleted / 已删除 Policy 及其独立 Key"
    }
    private fun loadPolicy(p:Policy) {
        modelGeneration++;updateModels.isEnabled=true;policy=p
        name.text=p.name;endpoint.text=p.endpoint;model.text=p.model;refreshModelOptions()
        providerOptions=emptyList();provider.removeAllItems();provider.addItem(p.provider);provider.selectedItem=p.provider
        providerTimer.restart();speed.isEnabled=!ApiRouting.isGemini(p.endpoint);speed.selectedItem=p.speed;key.text="";
        presetEnabled.isSelected=p.presets.enabled
        val presets=p.presets.withDefaults()
        presetChinese.text=presets.chinese;presetTraditional.text=presets.traditional;presetEnglish.text=presets.english
        refreshPresetControls()
        policyLatency.text=latencyResults[p.id] ?: "尚未测试此 Policy / Not tested";testPolicy.isEnabled=p.id !in testingPolicies;chinese.text=p.chinesePrompt;english.text=p.englishPrompt
        refreshReasoning(p.reasoning)
    }
    private fun refreshModelOptions() {
        val ep=endpoint.text.trim()
        val cached=policy.modelList?.takeIf { it.endpoint==ep }?.ids.orEmpty()
        model.setOptions(cached+policy.effectiveCatalog(ep).models.map { it.id }+config.policies.filter { it.endpoint==ep }.map { it.model })
    }
    private fun refreshModels() = attempt {
        val ep=endpoint.text.trim();ModelsClient.listUrl(ep)
        val id=policy.id;val generation=++modelGeneration;val previousCatalog=policy.effectiveCatalog(ep)
        val password=key.password
        val entered=try { if(password.isNotEmpty())String(password) else null } finally { password.fill('\u0000') }
        updateModels.isEnabled=false;status.text="Loading models… / 正在更新模型列表…"
        Thread {
            val result=runCatching {
                val secret=entered ?: store.key(id,ep)
                require(secret.isNotBlank()) { "Configure an API Key first / 请先填写或保存当前 Policy 的 Key" }
                ModelListCache.from(ep,runBlocking { discoverModels(ep,secret) },previousCatalog)
            }
            SwingUtilities.invokeLater {
                if(generation!=modelGeneration || id!=policy.id || ep!=endpoint.text.trim() || !isDisplayable)return@invokeLater
                updateModels.isEnabled=true
                result.onSuccess { cache ->
                    policy=policy.copy(modelList=cache)
                    refreshModelOptions();refreshReasoning(reasoning.selectedItem?.toString() ?: "omit")
                    status.text="${cache.ids.size} models loaded / 模型列表已更新，保存 Policy 后保留"
                }.onFailure { status.text="Model update failed / 模型列表更新失败："+(if(it is ApiHttpException) "HTTP ${it.status}" else safeError(it)) }
            }
        }.apply { isDaemon=true;start() }
    }
    override fun dispose() { testScope.cancel();modelGeneration++;providerGeneration++;providerTimer.stop();super.dispose() }
    private fun refreshReasoningLater() { providerTimer.restart(); SwingUtilities.invokeLater { refreshReasoning(reasoning.selectedItem?.toString() ?: "omit") } }
    private fun refreshReasoning(value:String) { reasoning.removeAllItems();ReasoningCapabilities.options(endpoint.text.trim(),model.text.trim(),policy.effectiveCatalog(endpoint.text.trim())).forEach { reasoning.addItem(it.value) };reasoning.selectedItem=if((0 until reasoning.itemCount).any { reasoning.getItemAt(it)==value })value else "omit" }
    private fun providerId():String {
        val value=provider.editor.item?.toString()?.trim().orEmpty()
        return if(value=="Auto / 自动路由") "" else providerOptions.firstOrNull{it.label==value}?.id ?: value
    }
    private fun refreshProviders() {
        val ep=endpoint.text.trim();val m=model.text.trim();val generation=++providerGeneration
        speed.isEnabled=!ApiRouting.isGemini(ep)
        if(!speed.isEnabled) speed.selectedItem="default"
        refreshPresetControls()
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
    private fun saveGlobal() { config=config.copy(languageShortcut=ShortcutOptions.language.entries.first { it.value==languageShortcut.selectedItem }.key,scriptShortcut=ShortcutOptions.script.entries.first { it.value==scriptShortcut.selectedItem }.key,enabled=enabled.isSelected,wordSegmentation=segmentation.isSelected,enterOriginal=enterOriginal.isSelected,spaceOriginal=spaceOriginal.isSelected,completion=false,candidateCount=1,debounceMs=debounce.value as Int,timeoutMs=timeout.value as Int) }
    private fun refreshPresetControls() {
        val router=ApiRouting.isOpenRouter(endpoint.text.trim())
        presetEnabled.isVisible=router
        presetOptions.isVisible=router && presetEnabled.isSelected
        presetOptions.parent?.revalidate();presetOptions.parent?.repaint()
    }
    private fun savePolicy(activate:Boolean=false) {
        saveGlobal();val edited=policy.copy(name=name.text.trim(),endpoint=endpoint.text.trim(),model=model.text.trim(),catalog=if(endpoint.text.trim()==policy.endpoint)policy.catalog else ModelCatalog(),modelList=policy.modelList?.takeIf { it.endpoint==endpoint.text.trim() },provider=if(ApiRouting.isOpenRouter(endpoint.text.trim())) providerId() else "",presets=if(ApiRouting.isOpenRouter(endpoint.text.trim())) PromptPresets(presetChinese.text.trim(),presetTraditional.text.trim(),presetEnglish.text.trim(),enabled=presetEnabled.isSelected).withDefaults() else PromptPresets(),reasoning=reasoning.selectedItem.toString(),speed=speed.selectedItem.toString(),chinesePrompt=chinese.text,englishPrompt=english.text)
        edited.validate();val updated=config.copy(policies=config.policies.map { if(it.id==edited.id)edited else it },selectedPolicy=if(activate)edited.id else config.selectedPolicy)
        val password=key.password
        try { if(password.isNotEmpty())store.saveKey(edited.id,String(password),edited.endpoint) } finally { password.fill('\u0000');key.text="" }
        store.save(updated);config=updated;policy=edited;reloadChoices(config.policies.indexOfFirst { it.id==edited.id })
    }

    private fun testSelectedPolicy() = attempt {
        savePolicy()
        val snapshot=config;val selected=policy
        if(!testingPolicies.add(selected.id)) return@attempt
        val heading="${selected.name} · ${selected.model} · ${selected.reasoning}/${selected.speed}" +
            if(ApiRouting.isOpenRouter(selected.endpoint)) " · ${selected.provider.ifBlank { "Auto" }}" else ""
        latencyResults[selected.id]="$heading\n正在测试… / Running…"
        policyLatency.text=latencyResults[selected.id];testPolicy.isEnabled=false
        testScope.launch {
            val start=System.nanoTime()
            val outcome=try {
                val result=measurePolicy(snapshot,selected,Wire.Request(true,false,"woxianghekafe"))
                require(result.candidates.size==1 && result.candidates.single().isNotBlank()) { "Empty candidate" }
                "$heading\n${(System.nanoTime()-start)/1_000_000} ms · ${result.candidates.single()}\n${result.usage?.summary().orEmpty()}"
            } catch(e:CancellationException) { throw e }
              catch(e:Exception) { "$heading\n${(System.nanoTime()-start)/1_000_000} ms · ${safeError(e)}" }
            SwingUtilities.invokeLater {
                testingPolicies.remove(selected.id)
                if(!isDisplayable)return@invokeLater
                latencyResults[selected.id]=outcome
                if(policy.id==selected.id) { policyLatency.text=outcome;testPolicy.isEnabled=true }
            }
        }
    }

    private fun attempt(block:()->Unit) { try { block() } catch(e:Exception) { status.text=safeError(e) } }
    private fun safeError(e:Throwable)=when(e) {
        is ApiHttpException -> "HTTP ${e.status} · ${AiFailure.from(e).label}"
        is ApiTimeoutException -> "${AiFailure.from(e).label} · ${e.phase.label}"
        is ApiPresetException,is ApiResponseException,is ApiProviderException,is ApiTruncatedException -> AiFailure.from(e).label
        else -> (e.message ?: e.javaClass.simpleName).take(180)
    }
    private fun background(button:JButton,task:()->String) { button.isEnabled=false;status.text="Running…";Thread { val message=runCatching(task).getOrElse(::safeError);SwingUtilities.invokeLater { status.text=message;button.isEnabled=true } }.apply { isDaemon=true;start() } }
}
