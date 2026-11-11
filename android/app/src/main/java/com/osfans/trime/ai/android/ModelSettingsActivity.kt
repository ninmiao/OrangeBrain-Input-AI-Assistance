// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.os.Bundle
import android.text.InputType
import android.view.WindowManager
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.osfans.trime.ai.*
import kotlinx.coroutines.*
import kotlinx.serialization.json.*

class ModelSettingsActivity : AppCompatActivity() {
    private lateinit var store: AiStore
    private lateinit var page: LinearLayout
    private lateinit var status: TextView
    private val policyId get() = intent.getStringExtra("policy") ?: store.config.selectedPolicyId
    private fun current() = store.configForPolicy(policyId)
    private var importEndpoint = ""
    private var exported = ""
    private val importFile = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) work {
            val endpoint = importEndpoint
            val bytes = withContext(Dispatchers.IO) {
                contentResolver.openInputStream(uri)!!.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= ModelCatalog.MAX_BYTES)
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
            }
            val catalog = withContext(Dispatchers.Default) { ModelCatalog.parse(bytes) }
            withContext(Dispatchers.IO) { store.replaceModelCatalog(catalog, endpoint, policyId) }
            render(); report("列表已导入；不再有效的旧参数已清除，其他选择保留")
        }
    }
    private val exportFile = registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) work {
            val text = exported
            require(text.isNotBlank())
            withContext(Dispatchers.IO) { contentResolver.openOutputStream(uri, "wt")!!.use { it.write(text.toByteArray(Charsets.UTF_8)) } }
            report("已导出模型和参数列表，不含 Key、连接地址或输入文字")
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "模型与参数"
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN or WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        setContentView(TextView(this).apply { text = "加载模型设置…" })
        lifecycleScope.launch { store = withContext(Dispatchers.IO) { AiStore.get(this@ModelSettingsActivity) }; render() }
    }
    private fun render() {
        val c = current()
        page = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; isFocusableInTouchMode = true; setPadding(24, 48, 24, 48) }
        setContentView(ScrollView(this).apply { addView(page) })
        label("模型与参数", 24f)
        status = label("当前模型：${c.model.ifBlank { "未配置" }} · 列表 ${c.modelCatalog.version}")
        label("支持非流式 Chat Completions。OpenRouter 刷新列表时同步模型思考能力；OpenAI 使用已核实的型号规则。未知模型不会自动套用全部档位。")
        if (c.endpoint.isBlank()) { label("请返回 AI 设置，先验证身份并配置连接和密钥。"); return }
        val model = field("模型 ID（可直接填写新模型）", c.model)
        button("保存模型 ID") { work {
            val id = model.text.toString().trim()
            require(id.isNotBlank() && id.length <= 256 && id.none { it.isISOControl() })
            withContext(Dispatchers.IO) { store.updatePolicyConfig(policyId) { require(it.endpoint == c.endpoint); it.copy(model = id) } }
            render(); report("模型已切换；每个模型保留自己的参数选择")
        } }
        button("从列表选择模型") {
            val ids = (c.modelCatalog.models.map { it.id } + c.discoveredModels + listOf(c.model)).filter { it.isNotBlank() }.distinct().sorted()
            val names = ids.map { id -> c.modelCatalog.models.firstOrNull { it.id == id }?.let { "${it.name} · $id" } ?: id }
            AlertDialog.Builder(this).setTitle("选择模型（名称不等于能力验证）").setItems(names.toTypedArray()) { _, index ->
                work { withContext(Dispatchers.IO) { store.updatePolicyConfig(policyId) { require(it.endpoint == c.endpoint); it.copy(model = ids[index]) } }; render() }
            }.setNegativeButton("取消", null).show()
        }
        button("刷新模型列表（GET /models）") { work {
            val count = store.refreshModels(policyId)
            render(); report("已刷新 $count 个模型；OpenRouter 思考档位同步自服务端，OpenAI 已知型号使用核实规则")
        } }

        if (ApiRouting.isOpenRouter(c.endpoint)) {
            label("提供商路由", 20f)
            label("留空由 OpenRouter 自动路由；指定提供商时只使用该提供商。请填写当前模型支持的提供商 ID，例如 wafer/us。")
            val provider = field("OpenRouter 提供商（留空自动路由）", c.provider)
            button("保存提供商") { work {
                val route = provider.text.toString().trim()
                ApiRouting.wire(c.endpoint, emptyMap(), route)
                withContext(Dispatchers.IO) {
                    store.updatePolicyConfig(policyId) {
                        require(it.endpoint == c.endpoint && it.model == c.model)
                        it.copy(provider = route)
                    }
                }
                render(); report("提供商已保存；下次请求生效")
            } }
        }

        label("当前模型参数", 20f)
        label("Temperature 与 Top P 通常只调一项；部分推理模型不支持采样参数。输出上限只能使用服务支持的一个字段。")
        label("OpenAI 默认 6.1 Terra、低思考、Fast 快速模式。OpenRouter 默认 DeepSeek Flash、无思考、Wafer US；普通速度保持默认路由，Fast 优先低延迟，固定提供商时不会切换其他端点。可用参数取决于模型与服务。")
        label("GPT-6 Sol 支持无思考；GPT-6.1 Sol 最低为轻度，不支持无思考。以完整模型 ID 为准。")
        val definition = store.definition(c)
        val selected = store.parameters(c)
        if (ApiRouting.isOpenRouter(c.endpoint)) {
            label("服务端默认不等于无思考：DeepSeek Flash 默认开启思考。更新能力会保留已有选择；更换接口或主动清除参数后，请重新检查。")
            if (definition?.parameters?.any { it.key == "reasoning_effort" && it.choices.any { choice -> choice.value == "none" } } == true)
                button("设为无思考（保留其他参数）") { work {
                    withContext(Dispatchers.IO) {
                        store.updatePolicyConfig(policyId) { current ->
                            require(current.endpoint == c.endpoint && current.model == c.model)
                            val values = store.parameters(current) + ("reasoning_effort" to JsonPrimitive("none"))
                            current.copy(modelValues = current.modelValues + (current.model to values))
                        }
                    }
                    render(); report("已显式关闭当前模型思考；提供商与其他参数保留")
                } }
        }
        if (definition == null || definition.parameters.isEmpty()) label("尚未维护此模型的参数能力。可更新能力后编辑，或导入服务商对应的列表。")
        definition?.parameters?.forEach { parameter ->
            val value = selected[parameter.key]
            val display = value?.let { v -> parameter.choices.firstOrNull { it.value == v.content }?.label ?: v.content } ?: "服务端默认（不发送）"
            button("${parameter.label}：$display") { chooseParameter(c, parameter) }
        }
        button("清除当前模型参数（全部不发送）") { work {
            withContext(Dispatchers.IO) { store.updatePolicyConfig(policyId) { require(it.endpoint == c.endpoint && it.model == c.model); it.copy(modelValues = it.modelValues - c.model) } }
            render()
        } }
        button("更新当前模型的已知参数能力") {
            AlertDialog.Builder(this).setTitle("更新模型能力")
                .setMessage("载入当前模型已核实的思考档位。未知型号请先刷新 OpenRouter 模型列表，或手动维护能力 JSON；不会添加未经确认的通用档位。保留仍受支持的已选参数，包括无思考；仅移除不再有效的参数。")
                .setPositiveButton("更新能力") { _, _ -> work {
                    require(c.model.isNotBlank())
                    withContext(Dispatchers.IO) { store.refreshKnownCapabilities(policyId) }
                    render(); report("已更新模型能力；仍有效的参数选择已保留")
                } }.setNegativeButton("取消", null).show()
        }
        button("预览实际模型参数") { AlertDialog.Builder(this).setTitle("请求中实际发送的参数")
            .setMessage("模型：${c.model}\n" + ApiRouting.wire(c.endpoint, store.parameters(c), c.provider).toString() + "\n空对象表示全部使用服务端默认；Key 不在此处显示。")
            .setPositiveButton("关闭", null).show() }

        label("手动更新模型和参数列表", 20f)
        label("列表与当前接口绑定。可改模型 ID、显示名、推理/速度枚举与数值范围，保存立即生效。切换接口会清除列表与参数，避免跨服务误用。更新列表不改接口、Key 或当前模型，也不会自动开启新参数。")
        button("编辑模型与参数列表 JSON") {
            val edit = EditText(this).apply { setText(c.modelCatalog.export()); minLines = 12; maxLines = 20; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE; isSaveEnabled = false }
            val dialog = AlertDialog.Builder(this).setTitle("模型能力列表（最多 512 KiB）")
                .setView(ScrollView(this).apply { addView(edit) }).setPositiveButton("保存", null).setNegativeButton("取消", null).create()
            dialog.setOnShowListener { dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { work {
                val content = edit.text.toString().toByteArray(Charsets.UTF_8)
                val catalog = withContext(Dispatchers.Default) { ModelCatalog.parse(content) }
                withContext(Dispatchers.IO) { store.replaceModelCatalog(catalog, c.endpoint, policyId) }
                dialog.dismiss(); render(); report("列表已更新；无效旧参数已清除")
            } } }
            dialog.show()
        }
        button("导入模型与参数列表 JSON") { importEndpoint = c.endpoint; importFile.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) }
        button("导出模型与参数列表 JSON") { exported = c.modelCatalog.export(); exportFile.launch("zephyr-input-models.json") }

    }

    private fun chooseParameter(c: AiConfig, p: ModelParameter) {
        fun apply(value: JsonPrimitive?) = work {
            withContext(Dispatchers.IO) {
                val current = current()
                require(current.endpoint == c.endpoint && current.model == c.model)
                val values = store.parameters(current).toMutableMap()
                if (value == null) values.remove(p.key) else values[p.key] = value
                store.saveParameters(c.endpoint, c.model, values, policyId)
            }
            render(); report("参数已保存；旧候选已失效，下次请求使用新参数")
        }
        if (p.type == "enum" || p.type == "boolean") {
            val values = if (p.type == "boolean") listOf(JsonPrimitive(false), JsonPrimitive(true)) else p.choices.map { JsonPrimitive(it.value) }
            val labels = listOf("服务端默认（不发送）") + if (p.type == "boolean") listOf("关闭", "开启") else p.choices.map { it.label }
            AlertDialog.Builder(this).setTitle(p.label).setItems(labels.toTypedArray()) { _, i -> apply(if (i == 0) null else values[i - 1]) }.show()
        } else {
            val edit = EditText(this).apply {
                hint = "留空不发送；${p.min} ～ ${p.max}"
                setText(store.parameters(c)[p.key]?.content.orEmpty())
                inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_SIGNED or if (p.type == "number") InputType.TYPE_NUMBER_FLAG_DECIMAL else 0
                isSaveEnabled = false
            }
            val dialog = AlertDialog.Builder(this).setTitle(p.label).setView(edit).setPositiveButton("保存", null).setNegativeButton("取消", null).create()
            dialog.setOnShowListener { dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val raw = edit.text.toString().trim()
                val value = if (raw.isEmpty()) null else if (p.type == "integer") raw.toLongOrNull()?.let { JsonPrimitive(it) } else raw.toDoubleOrNull()?.let { JsonPrimitive(it) }
                if ((raw.isNotEmpty() && value == null) || (value != null && !p.accepts(value))) edit.error = "请输入允许范围内的数字"
                else { dialog.dismiss(); apply(value) }
            } }
            dialog.show()
        }
    }
    private fun label(text: String, size: Float = 14f) = TextView(this).apply { this.text = text; textSize = size; setPadding(0, 12, 0, 12); page.addView(this) }
    private fun field(hint: String, text: String): EditText { label(hint); return EditText(this).apply { this.hint = hint; contentDescription = hint; setText(text); isSingleLine = true; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI; isSaveEnabled = false; page.addView(this) } }
    private fun button(text: String, action: () -> Unit) { page.addView(Button(this).apply { this.text = text; isAllCaps = false; setOnClickListener { action() } }) }
    private fun report(text: String) { status.text = text }
    private fun work(action: suspend () -> Unit) { lifecycleScope.launch {
        report("处理中…")
        try { action() } catch (e: CancellationException) { throw e } catch (e: Exception) {
            report(when (e) {
                is ApiHttpException -> "API HTTP ${e.status}：请检查 Key、模型、参数及服务权限"
                is java.io.IOException -> "网络或文件访问失败，已保留原设置"
                else -> "配置或列表无效，已保留原设置；请检查格式、范围与当前连接"
            })
        }
    } }
}
