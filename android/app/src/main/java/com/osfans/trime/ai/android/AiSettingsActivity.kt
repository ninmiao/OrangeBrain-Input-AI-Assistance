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
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN or WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        title = "Zephyr Input"
        setContentView(TextView(this).apply { text = "加载设置…" })
        lifecycleScope.launch { store = withContext(Dispatchers.IO) { AiStore.get(this@AiSettingsActivity) }; render() }
    }
    override fun onResume() { super.onResume(); if (::store.isInitialized) render() }
    override fun onPause() { feedbackPreview.close(); super.onPause() }
    private fun render() {
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
        val pack = store.effective(c)
        label("AI 云端候选", 25f)
        status = label("当前 Policy：${c.policies.first { it.id == c.selectedPolicyId }.name}")
        button("一键测速（最多 5 组）") { startActivity(Intent(this, BenchmarkActivity::class.java)) }
        label("开启后发送当前输入；候选仅在点击后上屏。密码及隐私字段不请求。")
        toggle("启用 AI", c.enabled) { enabled ->
            if (enabled && !c.consent) AlertDialog.Builder(this).setTitle("开启云端 AI")
                .setMessage("输入内容会发送到所选 Policy 的 API 服务，可能产生费用。是否开启？")
                .setPositiveButton("开启") { _, _ -> save { it.copy(enabled = true, consent = true) } }
                .setNegativeButton("取消") { _, _ -> render() }.setOnCancelListener { render() }.show()
            else save { it.copy(enabled = enabled) }
        }
        toggle("空格分词（中文键盘）", c.wordSegmentation) { value -> save { it.copy(wordSegmentation = value) } }
        label("开启时，拼音保留在键盘候选区；空格只标记词组边界，点击候选后才上屏。英文键盘仍正常输入空格。")
        toggle("停手自动请求", c.automatic) { value -> save { it.copy(automatic = value) } }
        toggle("发送有限前后文", c.contextEnabled) { value -> save { it.copy(contextEnabled = value) } }
        label("AI 仅返回一个最佳候选，不生成额外补全。")
        val debounce = field("停手等待（毫秒，50–2000）", c.debounceMs.toString(), numeric = true)
        val timeout = field("请求超时（秒，1–60）", (c.timeoutMs / 1000).toString(), numeric = true)
        val before = field("发送前文上限（字符，0–200）", c.beforeLimit.toString(), numeric = true)
        val after = field("发送后文上限（字符，0–50）", c.afterLimit.toString(), numeric = true)
        val target = field("当前输入上限（字符，1–300）", c.targetLimit.toString(), numeric = true)
        button("保存触发与长度设置") { work {
            val values = listOf(debounce, timeout, before, after, target).map { it.text.toString().toInt() }
            withContext(Dispatchers.IO) { store.update { it.copy(debounceMs = values[0].toLong(), timeoutMs = values[1] * 1000,
                beforeLimit = values[2], afterLimit = values[3], targetLimit = values[4]) } }
            report("已保存触发与长度设置")
        } }
        label("表达风格", 20f)
        button("当前：${if (c.style == "custom") "自定义" else pack.styles.firstOrNull { it.id == c.style }?.name ?: "原样"} · 切换") {
            AlertDialog.Builder(this).setTitle("表达风格").setItems((pack.styles.map { it.name } + "自定义").toTypedArray()) { _, index ->
                save { it.copy(style = if (index == pack.styles.size) "custom" else pack.styles[index].id) }
            }.show()
        }
        val custom = field("自定义风格指令", c.customStyle, multiline = true)
        button("保存自定义风格") { work {
            val text = custom.text.toString(); require(text.isNotBlank() && text.length <= 8192)
            withContext(Dispatchers.IO) { store.update { it.copy(customStyle = text, style = "custom") } }; render()
        } }
        label("键盘", 20f)
        label("空格左侧的中/EN 切换中文与英文；候选栏的简/繁同时控制本地和 AI 汉字。")
        val prefs = AppPrefs.defaultInstance().keyboard
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
                id = android.view.View.generateViewId(); text = "${policy.name}\n${policy.model}\n${store.policyParameterSummary(policy)}"
                isChecked = policy.id == c.selectedPolicyId; contentDescription = "选择 Policy ${policy.name}"
                setOnClickListener { work { withContext(Dispatchers.IO) { store.selectPolicy(policy.id) }; render() } }
            })
            group.addView(Button(this).apply { text = "编辑 ${policy.name}"; isAllCaps = false; setOnClickListener { openPolicy(policy.id) } })
            group.addView(Button(this).apply { text="测试延迟 · ${policy.name}"; isAllCaps=false; setOnClickListener { testPolicyLatency(policy.id,this) } })
        }
        page.addView(group)
        button("新增 Policy") { work { val id = withContext(Dispatchers.IO) { store.addPolicy("Policy ${store.config.policies.size + 1}") }; openPolicy(id) } }
    }
    private fun openPolicy(id: String) { startActivity(Intent(this, AiSettingsActivity::class.java).putExtra("policy", id)) }
    private fun renderPolicy(id: String) {
        val policy = store.config.policies.firstOrNull { it.id == id } ?: run { finish(); return }
        val c = store.configForPolicy(id); val pack = store.effective(c)
        label("Policy · ${policy.name}", 24f)
        status = label(if (id == store.config.selectedPolicyId) "正在使用" else "尚未选用；返回列表勾选即可切换")
        val name = field("Policy 名称", policy.name)
        button("保存名称") { work { withContext(Dispatchers.IO) { store.renamePolicy(id, name.text.toString()) }; render() } }
        label("连接与模型", 20f)
        label("接口：${c.endpoint}\n模型：${c.model}\nKey：${if (store.credentialsFor(c).hasCredential()) "已加密保存" else "尚未配置"}")
        button("测试当前 Policy 延迟") { testPolicyLatency(id) }
        button("一键测速（OpenAI + OpenRouter）") { startActivity(Intent(this, BenchmarkActivity::class.java).putExtra("policy", id)) }
        button("验证身份并配置连接 / 密钥") { verify { editConnection(id) } }
        button("模型与参数（速度 / 推理强度）") { startActivity(Intent(this, ModelSettingsActivity::class.java).putExtra("policy", id)) }
        button("验证身份并清除本 Policy 密钥") { verify { work {
            withContext(Dispatchers.IO) { store.credentialsForPolicy(id).clear(); if (store.config.selectedPolicyId == id) store.update { it.copy(enabled = false) } }
            render(); report("本 Policy 密钥已清除")
        } } }
        label("提示词", 20f)
        label("版本 ${pack.version}。本 Policy 的修改独立保存；繁简与风格自动填入短提示词。旧版长规则不再拼接。")
        button("编辑提示词（风格 / 中英短提示词）") {
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
        val sample = field("输入样例", "wojintianyoumeeting", multiline = true)
        val output = label("")
        button("填入 100 字符长输入测试样例") { sample.setText("jintianwomenyilaitaolunzhongwenheyingwenshurufadecuowenjiuzhenggongnengxiwangkeyigengkuaisu".repeat(2).take(100)) }
        label("测试使用本 Policy 的实际模型、参数、提供商和超时设置；填入样例后点击发送。")
        button("预览最终系统提示词") {
            val current = store.configForPolicy(id)
            output.text = store.prompt(current, chinese.isChecked) + "\n\n" + Protocol.encode(AiInput(sample.text.toString())) + "\n\n" + ApiRouting.wire(current.endpoint, store.parameters(current), current.provider)
        }
        button("连接测试 / 发送此样例") { work {
            val current = store.configForPolicy(id)
            val key = withContext(Dispatchers.IO) { store.credentialsFor(current).read(current.endpoint) } ?: error("Missing key")
            val request = AiRequest(RequestStamp(0, 0, current.generation, 0, current.generation), AiInput(sample.text.toString()), store.prompt(current, chinese.isChecked), current.completion, current.candidateCount)
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
                val request=AiRequest(RequestStamp(0,0,c.generation,0,c.generation),AiInput("nihao"),store.prompt(c,true),c.completion,c.candidateCount)
                val sent=android.os.SystemClock.elapsedRealtime()
                val result=ChatCompletionsClient().request(c.endpoint,key,c.model,request,c.timeoutMs,store.parameters(c),c.provider)
                val message="$name · ${android.os.SystemClock.elapsedRealtime()-sent} ms（完整候选返回）\n${result.candidates.firstOrNull().orEmpty()}"
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
        val endpoint = input("完整 HTTPS Chat Completions 地址", c.endpoint)
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
        auth.launch(manager.createConfirmDeviceCredentialIntent("Zephyr Input 凭据", "验证身份以修改 Policy 密钥") ?: return)
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
