// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import com.osfans.trime.ai.*
import com.osfans.trime.data.prefs.AppPrefs
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

class AiSettingsActivity : AppCompatActivity() {
    private enum class AiMode(val title: String) {
        NONE("无"), CORRECTION("仅纠错"), ASSISTANT("AI 助手＋纠错")
    }

    private val feedbackPreview = com.osfans.trime.ime.keyboard.KeyboardFeedbackPreview()
    private lateinit var store: AiStore
    private lateinit var page: LinearLayout
    private lateinit var status: TextView
    private var authenticated: (() -> Unit)? = null
    private var latencyJob: Job? = null
    private val policyId get() = intent.getStringExtra("policy")
    private val auth = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        val action = authenticated; authenticated = null
        if (it.resultCode == RESULT_OK) action?.invoke() else report("验证已取消")
    }
    private var serviceStatusView:TextView?=null
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN or WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        title = "OrangeCell"
        lifecycleScope.launch { AiRuntimeStatus.state.collect { value -> serviceStatusView?.text="AI 状态：$value" } }
        setContentView(TextView(this).apply { text = "加载设置…" })
        lifecycleScope.launch { store = withContext(Dispatchers.IO) { AiStore.get(this@AiSettingsActivity) }; render() }
    }
    override fun onResume() { super.onResume(); if (::store.isInitialized) render() }
    override fun onPause() { flushPending();feedbackPreview.close(); super.onPause() }
    private fun render() {
        flushPending()
        page = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; isFocusableInTouchMode = true; setPadding(dp(16), dp(12), dp(16), dp(24)) }
        val scroll = ScrollView(this).apply { addView(page) }
        ViewCompat.setOnApplyWindowInsetsListener(scroll) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom); insets
        }
        setContentView(scroll)
        if (policyId != null) renderPolicy(policyId!!) else renderMain()
    }
    private fun renderMain() {
        val c = store.config
        label("AI 云端候选", 25f)
        serviceStatusView=label("AI 状态：${AiRuntimeStatus.state.value}")
        button("重置 AI 请求 / Reset AI") {
            store.update { it };AiRuntimeStatus.state.value="已重置，待请求"
            report("已取消旧请求并重新加载 AI 配置；无需重启键盘")
        }
        status = label("当前 Policy：${c.policies.first { it.id == c.selectedPolicyId }.name}")
        button("词库与语法模型（万象 / 雾凇）") { startActivity(Intent(this, com.osfans.trime.rime.android.WanxiangActivity::class.java)) }
        button("一键测速（最多 5 组）") { startActivity(Intent(this, BenchmarkActivity::class.java)) }
        fun allowCloud(enabled: Boolean, update: (AiConfig) -> AiConfig) {
            if (enabled && !c.consent) AlertDialog.Builder(this).setTitle("允许发送到云端 AI")
                .setMessage("AI 会把当前输入及已启用的前后文发送到所选 Policy，可能产生 API 费用。")
                .setPositiveButton("允许") { _, _ -> save { update(it).copy(consent = true) } }
                .setNegativeButton("取消") { _, _ -> render() }.setOnCancelListener { render() }.show()
            else save(update)
        }
        val mode = when {
            !c.automatic -> AiMode.NONE
            c.assistantEnabled -> AiMode.ASSISTANT
            c.enabled -> AiMode.CORRECTION
            else -> AiMode.NONE
        }
        button("AI 增强（自动）：${mode.title}") {
            val modes = AiMode.entries
            AlertDialog.Builder(this).setTitle("AI 增强（自动）")
                .setSingleChoiceItems(modes.map { it.title }.toTypedArray(), mode.ordinal) { dialog, index ->
                    dialog.dismiss()
                    val selected = modes[index]
                    val automatic = selected != AiMode.NONE
                    if (selected != mode || (automatic && !c.consent)) {
                        allowCloud(automatic) {
                            it.copy(enabled = automatic, automatic = automatic,
                                assistantEnabled = selected == AiMode.ASSISTANT)
                        }
                    }
                }.setNegativeButton("取消", null).show()
        }
        label("选「无」时只在点星光后请求助手。")
        toggle("允许使用云端 AI（含手动请求）", c.consent) { value -> allowCloud(value) { it.copy(consent = value) } }
        toggle("空格分词（中文键盘）", c.wordSegmentation) { value -> save { it.copy(wordSegmentation = value) } }
        label("开启时，拼音保留在键盘候选区；空格只标记词组边界，点击候选后才上屏。英文键盘仍正常输入空格。")
        val debounce = field("停手等待（毫秒，50–2000）", c.debounceMs.toString(), numeric = true)
        val timeout = field("请求超时（秒，1–60）", (c.timeoutMs / 1000).toString(), numeric = true)
        val target = field("当前输入上限（字符，1–300）", c.targetLimit.toString(), numeric = true)
        toggle("参考前后文",c.contextEnabled) { value -> save { it.copy(contextEnabled=value) } }
        val before=field("前文字符数（0–500）",c.beforeLength.toString(),numeric=true)
        val after=field("后文字符数（0–500）",c.afterLength.toString(),numeric=true)
        val budget=field("输出 token 软预算（1–65536）",c.outputTokenBudget.toString(),numeric=true)
        label("默认前 50、后 0；只改当前输入。预算不足时优先保留完整候选，必要时在同一超时内重试一次。")
        autoSave(listOf(debounce,timeout,target,before,after,budget)) {
            store.update { it.copy(debounceMs=debounce.text.toString().toLong(),timeoutMs=timeout.text.toString().toInt()*1000,
                targetLimit=target.text.toString().toInt(),beforeLength=before.text.toString().toInt(),afterLength=after.text.toString().toInt(),outputTokenBudget=budget.text.toString().toInt()) }
        }
        label("键盘", 20f)
        label("空格左侧的中/EN 切换中文与英文；候选栏的简/繁同时控制本地和 AI 汉字。")
        val prefs = AppPrefs.defaultInstance().keyboard
        toggle("字母键盘顶部数字行", prefs.numberRowEnabled.getValue()) { prefs.numberRowEnabled.setValue(it); report("数字行设置已保存，下次打开键盘生效") }
        toggle("按键震动", prefs.vibrateOnKeyPress.getValue()) { enabled ->
            prefs.vibrateOnKeyPress.setValue(enabled)
            if (enabled) feedbackPreview.vibrate(page)
            report(if (enabled) "按键震动已开启，已触发预览" else "按键震动已关闭")
        }
        toggle("按键音", prefs.soundOnKeyPress.getValue()) { enabled ->
            prefs.soundOnKeyPress.setValue(enabled)
            if (enabled) feedbackPreview.sound() else feedbackPreview.close()
            report(if (enabled) "按键音已开启，已触发试听" else "按键音已关闭")
        }
        toggle("按键放大弹出动画", prefs.popupKeyPressEnabled.getValue()) { prefs.popupKeyPressEnabled.setValue(it) }
        val heightLabel = label("键盘高度：${prefs.keyboardHeightDp.getValue()} dp")
        page.addView(SeekBar(this).apply {
            contentDescription = "键盘高度"; max = 160; progress = prefs.keyboardHeightDp.getValue() - 180
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar, value: Int, fromUser: Boolean) { heightLabel.text = "键盘高度：${value + 180} dp" }
                override fun onStartTrackingTouch(bar: SeekBar) {}
                override fun onStopTrackingTouch(bar: SeekBar) { prefs.keyboardHeightDp.setValue(bar.progress + 180); report("键盘高度已保存，下次打开键盘生效") }
            })
        })
        label("Policy", 20f)
        label("勾选一个使用。每个 Policy 分别保存接口、加密 Key、模型参数及提示词。")
        val group = RadioGroup(this)
        c.policies.forEach { policy ->
            group.addView(RadioButton(this).apply {
                id = android.view.View.generateViewId(); text = "${policy.name}\n${policy.model}${if (ApiRouting.isOpenRouter(policy.endpoint)) " · 供应商：${policy.provider.ifBlank { "自动" }}" else ""}\n${store.policyParameterSummary(policy)}"
                isChecked = policy.id == c.selectedPolicyId; contentDescription = "选择 Policy ${policy.name}"
                setOnClickListener { work { withContext(Dispatchers.IO) { store.selectPolicy(policy.id) }; render() } }
            })
            group.addView(Button(this).apply { text = "编辑 ${policy.name}"; isAllCaps = false; setOnClickListener { openPolicy(policy.id) } })
            group.addView(Button(this).apply { text = "复制 Policy（含 Key） · ${policy.name}"; isAllCaps = false; setOnClickListener { duplicatePolicy(policy.id) } })
            group.addView(Button(this).apply { text="测试延迟 · ${policy.name}"; isAllCaps=false; setOnClickListener { testPolicyLatency(policy.id,this) } })
        }
        page.addView(group)
        button("新增 Policy") { work { val id = withContext(Dispatchers.IO) { store.addPolicy("Policy ${store.config.policies.size + 1}") }; openPolicy(id) } }
    }
    private fun duplicatePolicy(id: String) {
        val action: () -> Unit = { work {
            val copied = withContext(Dispatchers.IO) { store.duplicatePolicy(id) }
            render(); openPolicy(copied)
        } }
        if (store.credentialsForPolicy(id).hasCredential()) verify(action) else action()
    }
    private fun openPolicy(id: String) { startActivity(Intent(this, AiSettingsActivity::class.java).putExtra("policy", id)) }
    private fun renderPolicy(id: String) {
        val policy = store.config.policies.firstOrNull { it.id == id } ?: run { finish(); return }
        val c = store.configForPolicy(id); val pack = store.effective(c)
        label("Policy · ${policy.name}", 24f)
        status = label(if (id == store.config.selectedPolicyId) "正在使用" else "尚未选用；返回列表勾选即可切换")
        val name = field("Policy 名称", policy.name)
        button("复制此 Policy（含 Key）") { duplicatePolicy(id) }
        autoSave(listOf(name)) { store.renamePolicy(id,name.text.toString()) }
        label("连接与模型", 20f)
        label("接口：${c.endpoint}\n模型：${c.model}${if (ApiRouting.isOpenRouter(c.endpoint)) "\n供应商：${c.provider.ifBlank { "自动路由" }}" else ""}\nKey：${if (store.credentialsFor(c).hasCredential()) "已加密保存" else "尚未配置"}")
        button("测试当前 Policy 延迟") { testPolicyLatency(id) }
        button("一键测速（OpenAI / OpenRouter / Gemini）") { startActivity(Intent(this, BenchmarkActivity::class.java).putExtra("policy", id)) }
        button("验证身份并配置连接 / 密钥") { verify { editConnection(id) } }
        button("模型与参数（速度 / 推理强度）") { startActivity(Intent(this, ModelSettingsActivity::class.java).putExtra("policy", id)) }
        button("验证身份并清除本 Policy 密钥") { verify { work {
            withContext(Dispatchers.IO) { store.credentialsForPolicy(id).clear(); if (store.config.selectedPolicyId == id) store.update { it.copy(enabled = false) } }
            render(); report("本 Policy 密钥已清除")
        } } }
        label("提示词", 20f)
        label("版本 ${pack.version}。本 Policy 的修改独立保存；繁简随键盘切换，模型输出紧凑 JSON 候选数组。")
        button("编辑中英短提示词") {
            val edit = EditText(this).apply { setText(Json { prettyPrint = true; encodeDefaults = true }.encodeToString(pack)); minLines = 10; maxLines = 18; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE; isSaveEnabled = false }
            val dialog = AlertDialog.Builder(this).setTitle("${policy.name} · 提示词").setView(ScrollView(this).apply { addView(edit) }).setPositiveButton("保存", null).setNegativeButton("取消", null).create()
            dialog.setOnShowListener { dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { work {
                val changed = withContext(Dispatchers.Default) { PromptPackage.parse(edit.text.toString().toByteArray(Charsets.UTF_8)) }
                withContext(Dispatchers.IO) { store.updatePolicyConfig(id) { it.copy(localOverride = changed) } }
                dialog.dismiss(); render(); report("本 Policy 提示词已保存")
            } } }; dialog.show()
        }
        button("恢复本 Policy 内置提示词") { work { withContext(Dispatchers.IO) { store.updatePolicyConfig(id) { it.copy(active = null, localOverride = null) } }; render() } }
        label("样例与预览", 20f)
        val chinese = Switch(this).apply { text = "中文键盘（关闭为英文）"; isChecked = true }; page.addView(chinese)
        val sample = field("输入样例", LatencySamples.chinese, multiline = true)
        val output = label("")
        button("填入长输入测试样例") { sample.setText(if(chinese.isChecked) LatencySamples.chinese else LatencySamples.english) }
        label("测试使用本 Policy 的实际模型、参数、提供商和超时设置；填入样例后点击发送。")
        button("预览实际请求（不含 Key）") { work {
            val current = store.configForPolicy(id)
            val request=AiRequest(RequestStamp(0,0,0,0,0),Protocol.context(sample.text.toString(),LatencySamples.before(chinese.isChecked),LatencySamples.after(chinese.isChecked),current.contextEnabled,current.beforeLength,current.afterLength),store.prompt(current,chinese.isChecked),false,outputTokenBudget=current.outputTokenBudget,assistantEnabled=current.assistantEnabled)
            output.text=ChatCompletionsClient().payload(current.model,request,store.parameters(current),current.endpoint,current.provider).toString()
        } }
        button("连接测试 / 发送此样例") { work {
            val current = store.configForPolicy(id)
            val key = withContext(Dispatchers.IO) { store.credentialsFor(current).read(current.endpoint) } ?: error("Missing key")
            val request = AiRequest(RequestStamp(0, 0, current.generation, 0, current.generation), Protocol.context(sample.text.toString(),LatencySamples.before(chinese.isChecked),LatencySamples.after(chinese.isChecked),current.contextEnabled,current.beforeLength,current.afterLength), store.prompt(current, chinese.isChecked), current.completion, current.candidateCount,current.outputTokenBudget,current.assistantEnabled)
            val start = android.os.SystemClock.elapsedRealtime()
            val result = ChatCompletionsClient().request(current.endpoint, key, current.model, request, current.timeoutMs, store.parameters(current), current.provider)
            output.text = "${android.os.SystemClock.elapsedRealtime() - start} ms\n" + result.candidates.joinToString("\n\n") + if (result.completion.isNotBlank()) "\n补全：${result.completion}" else ""
            report("测试完成 · ${current.model}")
        } }
        if (store.config.policies.size > 1) button("删除此 Policy") {
            AlertDialog.Builder(this).setTitle("删除 ${policy.name}？").setMessage("将删除本 Policy 及其加密 Key。")
                .setPositiveButton("删除") { _, _ -> verify { work { withContext(Dispatchers.IO) { store.deletePolicy(id) }; finish() } } }
                .setNegativeButton("取消", null).show()
        }
    }
    private fun testPolicyLatency(id:String, source:Button?=null) {
        if(latencyJob?.isActive==true) { report("已有延迟测试正在进行"); return }
        val c=store.configForPolicy(id)
        val name=c.policies.first { it.id==id }.name
        source?.isEnabled=false
        latencyJob=lifecycleScope.launch {
            val start=android.os.SystemClock.elapsedRealtime()
            report("正在测试 $name…（一次请求）")
            try {
                val key=withContext(Dispatchers.IO) { store.credentialsFor(c).read(c.endpoint) } ?: error("请先为 $name 保存 Key")
                val request=AiRequest(RequestStamp(0,0,c.generation,0,c.generation),LatencySamples.input(true,c.contextEnabled,c.beforeLength,c.afterLength),store.prompt(c,true),c.completion,c.candidateCount,c.outputTokenBudget,c.assistantEnabled)
                val sent=android.os.SystemClock.elapsedRealtime()
                val result=ChatCompletionsClient().request(c.endpoint,key,c.model,request,c.timeoutMs,store.parameters(c),c.provider)
                val message="$name · ${c.model} · ${store.policyParameterSummary(c.policies.first { it.id==id })}\n${android.os.SystemClock.elapsedRealtime()-sent} ms（完整候选返回）\n${result.candidates.firstOrNull().orEmpty()}\n${result.usage?.summary().orEmpty()}"
                report(message);source?.text=message
            } catch(e:CancellationException) { throw e
            } catch(e:Exception) {
                val reason=when(e) { is ApiHttpException -> "HTTP ${e.status}"; is IllegalStateException -> e.message; else -> (e as? ApiTimeoutException)?.phase?.label ?: AiFailure.from(e).label }
                val message="$name · 测试失败：$reason（${android.os.SystemClock.elapsedRealtime()-start} ms）"
                report(message);source?.text=message
            } finally { source?.isEnabled=true }
        }
    }
    override fun onStop() { super.onStop(); latencyJob?.cancel() }
    private fun editConnection(id: String) {
        val c = store.configForPolicy(id)
        val container = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), 0, dp(16), 0) }
        fun input(name: String, value: String, password: Boolean = false): EditText {
            container.addView(TextView(this).apply { text = name; setPadding(0, dp(8), 0, 0) })
            return EditText(this).apply {
                hint = name; contentDescription = name; setText(value); isSingleLine = true; isSaveEnabled = false
                inputType = if (password) InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD else InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                imeOptions = EditorInfo.IME_FLAG_FORCE_ASCII or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
                container.addView(this)
            }
        }
        val endpoint = input("完整 HTTPS API 地址（Responses / Chat / Interactions）", c.endpoint)
        val key = input("新 API Key（同域名留空保留）", "", true)
        val dialog = AlertDialog.Builder(this).setTitle("连接配置").setView(ScrollView(this).apply { addView(container) }).setPositiveButton("保存", null).setNegativeButton("取消", null).create()
        dialog.setOnShowListener { dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { work {
            val url = endpoint.text.toString().trim()
            CredentialStore.origin(url)
            val secret = key.text.toString()
            withContext(Dispatchers.IO) {
                val credentials = store.credentialsForPolicy(id)
                require(secret.isNotBlank() || credentials.read(url) != null)
                if (secret.isNotBlank()) credentials.save(url, secret)
                store.updatePolicyConfig(id) { it.copy(endpoint = url) }
            }
            key.text.clear(); dialog.dismiss(); render(); report("连接配置已加密保存")
        } } }
        dialog.setOnDismissListener { key.text.clear() }; dialog.show()
    }
    private fun verify(action: () -> Unit) {
        val manager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!manager.isDeviceSecure) { report("请先设置系统锁屏 PIN、图案或密码"); return }
        authenticated = action
        auth.launch(manager.createConfirmDeviceCredentialIntent("OrangeCell 凭据", "验证身份以修改 Policy 密钥") ?: return)
    }
    private fun label(text: String, size: Float = 14f) = TextView(this).apply { this.text = text; textSize = size; setPadding(0, dp(8), 0, dp(8)); page.addView(this) }
    private fun field(name: String, value: String, numeric: Boolean = false, multiline: Boolean = false): EditText {
        val caption = label(name)
        return EditText(this).apply {
            id = android.view.View.generateViewId(); caption.labelFor = id; contentDescription = name; hint = name
            setText(value); isSaveEnabled = false
            inputType = if (numeric) InputType.TYPE_CLASS_NUMBER else InputType.TYPE_CLASS_TEXT or if (multiline) InputType.TYPE_TEXT_FLAG_MULTI_LINE else InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            page.addView(this)
        }
    }
    private fun button(text: String, action: () -> Unit) { page.addView(Button(this).apply { this.text = text; isAllCaps = false; setOnClickListener { action() } }) }
    private fun toggle(text: String, checked: Boolean, action: (Boolean) -> Unit) { page.addView(Switch(this).apply { this.text = text; isChecked = checked; setPadding(0, dp(8), 0, dp(8)); setOnCheckedChangeListener { _, value -> action(value) } }) }
    private var autoSaveJob:Job?=null
    private var pendingSave:(()->Unit)?=null
    private fun flushPending() { autoSaveJob?.cancel();val pending=pendingSave;pendingSave=null;if(pending!=null)try { pending() }catch(_:Exception) { if(::status.isInitialized)report("输入未完成或无效，保留原设置") } }

    private fun autoSave(fields:List<EditText>,save:()->Unit) {
        val watcher=object:android.text.TextWatcher {
            override fun beforeTextChanged(s:CharSequence?,start:Int,count:Int,after:Int){}
            override fun onTextChanged(s:CharSequence?,start:Int,before:Int,count:Int){}
            override fun afterTextChanged(s:android.text.Editable?) {
                pendingSave=save;autoSaveJob?.cancel();autoSaveJob=lifecycleScope.launch {
                    delay(350)
                    try { save();pendingSave=null;report("已自动保存并生效") }
                    catch(e:CancellationException){throw e}
                    catch(_:Exception) { report("尚未保存：请完成输入并检查数值范围；原设置仍有效") }
                }
            }
        };fields.forEach { it.addTextChangedListener(watcher) }
    }
    private fun report(text: String) { status.text = text }
    private fun save(transform: (AiConfig) -> AiConfig) = work { withContext(Dispatchers.IO) { store.update(transform) }; render() }
    private fun work(action: suspend () -> Unit) { lifecycleScope.launch {
        report("处理中…")
        try { action() } catch (e: CancellationException) { throw e } catch (e: Exception) {
            report(when (e) {
                is ApiHttpException -> "API HTTP ${e.status}，请检查模型、参数及 Key"
                is java.io.InterruptedIOException, is ApiProviderException, is ApiTruncatedException, is ApiResponseException -> (e as? ApiTimeoutException)?.phase?.label ?: AiFailure.from(e).label
                is java.io.IOException -> "网络或文件访问失败"
                else -> "未保存：请检查地址、数字范围及内容格式"
            })
        }
    } }
}
