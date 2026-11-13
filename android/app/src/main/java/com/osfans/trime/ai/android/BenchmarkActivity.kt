// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.os.Bundle
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.*
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import com.osfans.trime.ai.*
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class BenchmarkActivity : AppCompatActivity() {
    private lateinit var store: AiStore
    private lateinit var saved: BenchmarkStore
    private lateinit var policyId: String
    private var config = BenchmarkConfig()
    private var job: Job? = null
    private lateinit var page: LinearLayout
    private lateinit var cards: LinearLayout
    private lateinit var status: TextView
    private lateinit var sample: EditText
    private lateinit var timeout: EditText
    private lateinit var chinese: Switch
    private lateinit var start: Button
    private lateinit var stop: Button
    private val controls = mutableListOf<View>()
    private val results = linkedMapOf<Int, BenchmarkResult>()
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN or WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        title = "一键测速"
        setContentView(TextView(this).apply { text = "加载测速配置…" })
        lifecycleScope.launch {
            store = withContext(Dispatchers.IO) { AiStore.get(this@BenchmarkActivity) }
            policyId = intent.getStringExtra("policy") ?: store.config.selectedPolicyId
            if (store.config.policies.none { it.id == policyId }) { finish(); return@launch }
            saved = BenchmarkStore(this@BenchmarkActivity, "mixed-v3")
            config = withContext(Dispatchers.IO) {
                val available=store.config.policies.filter { store.credentialsForPolicy(it.id).hasCredential() }.map { ApiRouting.api(it.endpoint) }.toSet()
                val defaults=BenchmarkEntry.defaults().filter { it.api in available }.ifEmpty { BenchmarkEntry.defaults() }
                saved.read(BenchmarkConfig(entries=defaults))
            }
            state?.getString("draft")?.let { raw -> runCatching { Json.decodeFromString<BenchmarkConfig>(raw).validate() }.getOrNull()?.let { config = it } }
            render()
        }
    }
    private fun text(parent: LinearLayout, value: String, size: Float = 15f) = TextView(this).apply {
        text = value; textSize = size; setPadding(0, dp(5), 0, dp(5)); parent.addView(this)
    }
    private fun button(parent: LinearLayout, value: String, action: () -> Unit) = Button(this).apply {
        text = value; isAllCaps = false; contentDescription = value; parent.addView(this); setOnClickListener { action() }
    }
    private fun input(parent: LinearLayout, caption: String, value: String, numeric: Boolean = false) = EditText(this).apply {
        id = View.generateViewId(); text(parent, caption).labelFor = id
        setText(value); contentDescription = caption; isSaveEnabled = false
        inputType = if (numeric) InputType.TYPE_CLASS_NUMBER else InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        maxLines = 3; parent.addView(this)
    }
    private fun render() {
        controls.clear()
        val outer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), 0, dp(16), 0) }
        ViewCompat.setOnApplyWindowInsetsListener(outer) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(dp(16) + bars.left, bars.top, dp(16) + bars.right, bars.bottom); insets
        }
        text(outer, "一键测速 · 最多 5 组", 24f)
        text(outer, "OpenAI / OpenRouter / Gemini · 已配置 Key 的每种 API 至少 1 组 · 最多 5 组")
        val actions = LinearLayout(this); outer.addView(actions)
        start = button(actions, "一键开始测速") { begin() }.apply { layoutParams = LinearLayout.LayoutParams(0, dp(52), 1f) }
        stop = button(actions, "停止后续测试") {
            job?.cancel(); stop.isEnabled = false
            status.text = "正在停止…当前连接会在超时前结束，之后不再发送请求。"
        }.apply { isEnabled = false; layoutParams = LinearLayout.LayoutParams(0, dp(52), 1f) }
        val scroll = ScrollView(this); outer.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        page = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(0, 0, 0, dp(24)); isFocusableInTouchMode = true }; scroll.addView(page)
        status = text(page, "尚未测速。点一次会发送 ${config.entries.size} 次请求，可能产生 API 费用。")
        status.contentDescription = "测速结果"
        text(page, "同一样例逐组测试，显示从发出请求到完整候选返回的耗时（含网络）。单次结果供参考，受网络、缓存与输出长度影响。")
        sample = input(page, "共同输入样例（1–300 字符）", config.sample); controls += sample
        timeout = input(page, "每组超时（秒，1–60）", (config.timeoutMs / 1000).toString(), true); controls += timeout
        chinese = Switch(this).apply { text = "中文键盘（关闭为英文）"; isChecked = config.chinese; page.addView(this) }; controls += chinese
        controls += button(page, "保存测速配置") { change { it } }
        cards = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }; page.addView(cards)
        config.entries.forEachIndexed { index, entry ->
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL; setPadding(dp(12), dp(8), dp(12), dp(8))
                background = android.graphics.drawable.GradientDrawable().apply { cornerRadius = dp(10).toFloat(); setStroke(dp(1), 0xffb4b8bf.toInt()) }
            }
            cards.addView(card, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(10) })
            text(card, "${index + 1}. ${entry.api} · ${entry.model}", 18f)
            text(card, "推理：${BenchmarkEntry.reasoningOptions.first { it.value == entry.reasoning }.label}    速度：${BenchmarkEntry.speedOptions.first { it.value == entry.speed }.label}" + if (entry.api == "openrouter") "\n提供商：${entry.provider.ifBlank { "自动" }}" else "")
            val row = LinearLayout(this); card.addView(row)
            button(row, "修改第 ${index + 1} 组") { edit(index) }.apply { layoutParams = LinearLayout.LayoutParams(0, -2, 1f) }
            button(row, "删除第 ${index + 1} 组") { change { it.copy(entries = it.entries.filterIndexed { i, _ -> i != index }) } }
                .apply { isEnabled = config.entries.size > 1; layoutParams = LinearLayout.LayoutParams(0, -2, 1f) }
        }
        controls += button(page, "添加一组（${config.entries.size}/5）") { change { it.copy(entries = it.entries + BenchmarkEntry()) } }
            .apply { isEnabled = config.entries.size < 5 }
        controls += button(page, "恢复三种 API 的 5 组预设") { change { it.copy(entries = BenchmarkEntry.defaults()) } }
        text(page, "预设按小型、低成本系列选择，并非官方参数量排名。部分旧型号已进入弃用期，是否可用以当前接口为准。模型 ID 可手动填写或从 Policy 的模型列表选择。")
        text(page, "每组选择自己的 Policy，使用对应接口和 Key；不改变键盘当前 Policy。OpenRouter 无思考发送 reasoning.enabled=false；普通速度不附加排序，Fast 优先低延迟，固定提供商时仍限制在该端点。开始前会检查所选 Policy 的凭据，不会串用 Key。")
        setContentView(outer)
        // The loading view may already have consumed the initial inset dispatch.
        ViewCompat.requestApplyInsets(outer)
    }
    private fun draft() = config.copy(sample = sample.text.toString(), chinese = chinese.isChecked,
        timeoutMs = (timeout.text.toString().toIntOrNull()?.takeIf { it in 1..60 } ?: error("超时须为 1–60 秒")) * 1000).validate()
    private fun change(transform: (BenchmarkConfig) -> BenchmarkConfig) {
        try { config = transform(draft()).validate(); saved.save(config); results.clear(); render(); status.text = "测速配置已保存" }
        catch (e: IllegalArgumentException) { status.text = e.message }
        catch (e: IllegalStateException) { status.text = e.message }
        catch (_: Exception) { status.text = "保存失败，请重试" }
    }
    private fun edit(index: Int) {
        val entry = config.entries[index]
        val panel = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(8), dp(20), dp(8)) }
        val model = input(panel, "模型 ID", entry.model).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            imeOptions = EditorInfo.IME_FLAG_FORCE_ASCII; setSingleLine()
        }
        val policies = store.config.policies
        val policyPicker = Spinner(this).apply {
            contentDescription = "API / Policy"
            adapter = ArrayAdapter(this@BenchmarkActivity, android.R.layout.simple_spinner_dropdown_item, policies.map { it.name })
            setSelection(policies.indexOfFirst { it.id == entry.policyId }.takeIf { it >= 0 }
                ?: policies.indexOfFirst { ApiRouting.api(it.endpoint) == entry.api }.coerceAtLeast(0))
            text(panel, "API / Policy"); panel.addView(this)
        }
        val provider = input(panel, "OpenRouter 提供商（留空自动）", entry.provider).apply { setSingleLine() }
        var initialPolicy = policyPicker.selectedItemPosition
        policyPicker.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) = Unit
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (position != initialPolicy) {
                    model.setText(policies[position].model); provider.setText(policies[position].provider)
                    initialPolicy = position
                }
            }
        }
        val policy = store.configForPolicy(policies[policyPicker.selectedItemPosition].id)
        val models = (BenchmarkEntry.defaults().map { it.model } + policy.model + policy.discoveredModels + policy.modelCatalog.models.map { it.id }).distinct()
        button(panel, "从模型列表选择") { AlertDialog.Builder(this).setTitle("模型").setItems(models.toTypedArray()) { _, i -> model.setText(models[i]) }.show() }
        fun picker(caption: String, choices: List<ParameterChoice>, value: String): Spinner {
            val label = text(panel, caption)
            return Spinner(this).apply { id = View.generateViewId(); label.labelFor = id; contentDescription = caption
                adapter = ArrayAdapter(this@BenchmarkActivity, android.R.layout.simple_spinner_dropdown_item, choices.map { it.label })
                setSelection(choices.indexOfFirst { it.value == value }); panel.addView(this)
            }
        }
        var reasoningChoices=ReasoningCapabilities.options(policy.endpoint,model.text.toString().trim(),policy.modelCatalog)
        val reasoning = picker("推理强度", reasoningChoices, entry.reasoning).apply {
            setSelection(reasoningChoices.indexOfFirst { it.value==entry.reasoning }.takeIf { it>=0 } ?: reasoningChoices.lastIndex)
        }
        fun refreshReasoning() {
            val previous=reasoningChoices.getOrNull(reasoning.selectedItemPosition)?.value ?: "omit"
            val currentPolicy=store.configForPolicy(policies[policyPicker.selectedItemPosition].id)
            reasoningChoices=ReasoningCapabilities.options(currentPolicy.endpoint,model.text.toString().trim(),currentPolicy.modelCatalog)
            reasoning.adapter=ArrayAdapter(this,android.R.layout.simple_spinner_dropdown_item,reasoningChoices.map { it.label })
            reasoning.setSelection(reasoningChoices.indexOfFirst { it.value==previous }.takeIf { it>=0 } ?: reasoningChoices.lastIndex)
        }
        model.addTextChangedListener(object:android.text.TextWatcher {
            override fun beforeTextChanged(s:CharSequence?,start:Int,count:Int,after:Int)=Unit
            override fun onTextChanged(s:CharSequence?,start:Int,before:Int,count:Int)=Unit
            override fun afterTextChanged(s:android.text.Editable?) { refreshReasoning() }
        })
        val speed = picker("速度模式", BenchmarkEntry.speedOptions, entry.speed)
        val error = text(panel, "")
        val dialog = AlertDialog.Builder(this).setTitle("第 ${index + 1} 组配置").setView(ScrollView(this).apply { addView(panel) })
            .setPositiveButton("保存", null).setNegativeButton("取消", null).create()
        dialog.setOnShowListener { dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            try {
                val updated = BenchmarkEntry(model.text.toString().trim(), reasoningChoices[reasoning.selectedItemPosition].value, BenchmarkEntry.speedOptions[speed.selectedItemPosition].value,
                    api = ApiRouting.api(policies[policyPicker.selectedItemPosition].endpoint),
                    policyId = policies[policyPicker.selectedItemPosition].id, provider = provider.text.toString().trim()).validate()
                val next = draft().copy(entries = config.entries.mapIndexed { i, old -> if (i == index) updated else old }).validate()
                saved.save(next); config = next; results.clear(); dialog.dismiss(); render(); status.text = "第 ${index + 1} 组已保存"
            } catch (e: IllegalArgumentException) { error.text = e.message }
            catch (e: IllegalStateException) { error.text = e.message }
            catch (_: Exception) { error.text = "保存失败，请重试" }
        } }; dialog.show()
    }
    private fun begin() {
        if (job != null) return
        val snapshot = try { draft().also { saved.save(it); config = it } } catch (_: Exception) { status.text = "请检查样例和超时参数后重试"; return }
        results.clear(); setRunning(true)
        job = lifecycleScope.launch(start = CoroutineStart.LAZY) {
            try {
                val configured=store.config.policies.filter { store.credentialsForPolicy(it.id).hasCredential() }.map { ApiRouting.api(it.endpoint) }.toSet()
                require(snapshot.entries.map { it.api }.toSet().containsAll(configured)) { "每个已配置 Key 的 API 至少保留一组" }
                val connections = snapshot.entries.associateWith { entry ->
                    val match = if (entry.policyId.isNotBlank()) store.config.policies.firstOrNull { it.id == entry.policyId }
                        else store.config.policies.firstOrNull { ApiRouting.api(it.endpoint) == entry.api }
                    require(match != null) { "请为 ${entry.api} 配置 Policy" }
                    val policy = store.configForPolicy(match.id)
                    require(ApiRouting.api(policy.endpoint) == entry.api) { "Policy 接口已变化，请重新选择测速 API" }
                    val key = withContext(Dispatchers.IO) { store.credentialsFor(policy).read(policy.endpoint) }
                    if (key == null) { status.text = "${match.name} 尚未配置 Key，请先在此 Policy 保存 Key。"; return@launch }
                    policy to key
                }
                BenchmarkRunner().run(snapshot, { entry, parameters ->
                    val (policy, key) = connections.getValue(entry)
                    val allowed=ReasoningCapabilities.options(policy.endpoint,entry.model,policy.modelCatalog).map { it.value }
                    require(entry.reasoning in allowed || (entry.reasoning=="none" && ReasoningCapabilities.known(policy.endpoint,entry.model)?.isEmpty()==true)) { "模型思考档位已变化，请重新选择" }
                    val request = AiRequest(RequestStamp(0, 0, 0, 0, policy.generation), AiInput(snapshot.sample), store.prompt(policy, snapshot.chinese), policy.completion, policy.candidateCount)
                    ChatCompletionsClient().request(policy.endpoint, key, entry.model, request, snapshot.timeoutMs, parameters, if(entry.api=="openrouter")entry.provider else "", store.preset(policy,snapshot.chinese))
                }, onStart = { index -> showResults("正在测试 ${index + 1}/${snapshot.entries.size}：${snapshot.entries[index].model}") },
                    onResult = { index, result -> results[index] = result; showResults("已完成 ${results.size}/${snapshot.entries.size}") })
                val fastest = results.filterValues { it.error == null }.minByOrNull { it.value.elapsedMs }
                val success = results.values.count { it.error == null }
                showResults("测速完成：$success/${snapshot.entries.size} 成功" + (fastest?.let { "\n本次最快：第 ${it.key + 1} 组 ${it.value.entry.model} · ${it.value.elapsedMs} ms" } ?: ""))
            } catch (cancelled: CancellationException) { showResults("已停止；完成 ${results.size}/${snapshot.entries.size} 组"); throw cancelled }
            catch (e: Exception) { showResults(e.message ?: "无法开始测速，请检查 Policy 配置") }
            finally { job = null; setRunning(false) }
        }.also { it.start() }
    }
    private fun showResults(heading: String) {
        status.text = heading + results.entries.joinToString("", prefix = "\n") { (i, r) ->
            "\n${i + 1}. ${r.entry.model} · ${r.elapsedMs} ms\n${r.error ?: r.output}\n${r.usage?.summary().orEmpty()}\n"
        }
    }
    private fun setRunning(running: Boolean) {
        start.isEnabled = !running; stop.isEnabled = running
        controls.forEach { it.isEnabled = !running }
        fun enable(view: View) { view.isEnabled = !running; if (view is ViewGroup) for (i in 0 until view.childCount) enable(view.getChildAt(i)) }
        enable(cards)
        if (!running) {
            // Restore the 1–5 limits after temporarily disabling every configuration control.
            for (i in 0 until cards.childCount) {
                val row = (cards.getChildAt(i) as LinearLayout).getChildAt(2) as LinearLayout
                row.getChildAt(1).isEnabled = config.entries.size > 1
            }
            controls.filterIsInstance<Button>().firstOrNull { it.text.startsWith("添加一组") }?.isEnabled = config.entries.size < 5
        }
    }
    override fun onSaveInstanceState(outState: Bundle) {
        if (::sample.isInitialized) runCatching { outState.putString("draft", Json.encodeToString(draft())) }
        super.onSaveInstanceState(outState)
    }
    override fun onStop() { super.onStop(); job?.cancel() }
}
