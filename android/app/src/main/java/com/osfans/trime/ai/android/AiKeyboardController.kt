// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.content.Intent
import android.text.InputType
import android.view.ContextThemeWrapper
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedText
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection
import android.widget.*
import androidx.appcompat.app.AlertDialog
import androidx.lifecycle.lifecycleScope
import com.osfans.trime.ai.*
import com.osfans.trime.core.RimeMessage
import com.osfans.trime.daemon.RimeSession
import com.osfans.trime.ime.core.TrimeInputMethodService
import kotlinx.coroutines.*

class AiKeyboardController(private val service: TrimeInputMethodService, private val rime: RimeSession) {
    private val store = AiStore.get(service)
    private val scope = service.lifecycleScope
    private var session = 0L
    private var revision = 0L
    private var keyboardGeneration = 0L
    private var chinese = true
    private var active = false
    private var sensitive = true
    private var directTarget: Target? = null
    private var observedSelection: Selection? = null
    private var suppress = false
    private var applying = false
    private var target: Target? = null
    private var ready: AiState.Ready? = null
    private var panel: LinearLayout? = null
    private var candidateRow: LinearLayout? = null
    private var candidateScroll: HorizontalScrollView? = null
    private var renderedCandidates: AiState.Ready? = null
    private var label: TextView? = null
    private var statusButton: AiStatusButton? = null
    // True from a manual tap until the request is visible as Loading, so the button reacts at once.
    private var awaitingStart = false
    private var scriptToggle: LinearLayout? = null
    private var simplifiedSegment: TextView? = null
    private var traditionalSegment: TextView? = null
    private var candidateTextSize = 18.15f
    private var candidateHeightDp = 28
    private var state: AiState = AiState.Idle
    private var captureJob: Job? = null
    private val clipboard = KeyboardClipboard(service,scope)
    private val client = ChatCompletionsClient()
    private val coordinator = AiRequestCoordinator(scope, { request ->
        val config = store.config
        require(config.generation == request.stamp.apiGeneration)
        val key = withContext(Dispatchers.IO) { store.credentialsFor(config).read(config.endpoint) } ?: error("Missing credential")
        client.request(config.endpoint, key, config.model, request, config.timeoutMs, store.parameters(config), config.provider)
    }, { update -> state = update; ready = update as? AiState.Ready; if (update !is AiState.Idle) awaitingStart = false; render() })
    private val configJob = scope.launch {
        store.changes.collect { changed ->
            revision++
            coordinator.invalidate()
            if (active) syncScript()
            if (active && !suppress) refresh(false)
            render()
        }
    }

    private data class Selection(val start: Int, val end: Int)
    private data class Target(val input: AiInput, val composing: Boolean, val start: Int, val end: Int,
        val selection: Selection, val documentHash: Int, val manual: Boolean)

    fun createView(): View {
        val context = ContextThemeWrapper(service, android.R.style.Theme_Material_Light)
        val style = com.osfans.trime.data.theme.ThemeManager.activeTheme.generalStyle
        candidateTextSize = style.candidateTextSize
        candidateHeightDp = style.candidateViewHeight.coerceAtLeast(28)
        fun dp(n: Int) = (n * service.resources.displayMetrics.density).toInt()
        val root = LinearLayout(context).apply { id = View.generateViewId(); orientation = LinearLayout.HORIZONTAL; gravity = android.view.Gravity.CENTER_VERTICAL; setBackgroundColor(0xffd1d3d9.toInt()) }
        // Segmented switch: both scripts stay visible and the active one is filled.
        fun segment(text: String) = TextView(context).apply {
            this.text = text; textSize = 13f; gravity = android.view.Gravity.CENTER
            includeFontPadding = false; isSingleLine = true
            typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
        }
        simplifiedSegment = segment("简"); traditionalSegment = segment("繁")
        scriptToggle = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = android.view.Gravity.CENTER_VERTICAL
            setPadding(dp(2), dp(2), dp(2), dp(2))
            val track = android.graphics.drawable.GradientDrawable().apply {
                setColor(0x26525966); cornerRadius = dp(13).toFloat()
            }
            val mask = android.graphics.drawable.GradientDrawable().apply {
                setColor(android.graphics.Color.WHITE); cornerRadius = dp(13).toFloat()
            }
            background = android.graphics.drawable.RippleDrawable(
                android.content.res.ColorStateList.valueOf(0x30525966), track, mask)
            isClickable = true; isFocusable = true
            addView(simplifiedSegment, LinearLayout.LayoutParams(0, -1, 1f))
            addView(traditionalSegment, LinearLayout.LayoutParams(0, -1, 1f))
            setOnClickListener { scope.launch { withContext(Dispatchers.IO) { store.update { it.copy(traditional = !it.traditional) } } } }
        }
        val content = LinearLayout(context).apply { gravity = android.view.Gravity.CENTER_VERTICAL }
        statusButton = AiStatusButton(context).apply {
            setPadding(dp(4), dp(2), dp(4), dp(2))
            background = android.graphics.drawable.RippleDrawable(
                android.content.res.ColorStateList.valueOf(0x24565CC6), null,
                android.graphics.drawable.ColorDrawable(android.graphics.Color.WHITE))
            isClickable = true; isFocusable = true
            setOnClickListener {
                when {
                    !active || sensitive -> notice("此输入框不允许发送到 AI")
                    !store.config.consent -> {
                        notice("请先在设置里允许使用云端 AI")
                        openSettings()
                    }
                    // A running request keeps running; pressing again used to cancel and resend it.
                    requestBusy() -> { refuse(); notice("AI 请求中，请稍候（长按可取消）") }
                    else -> {
                        nudge(); awaitingStart = true
                        postDelayed({ if (awaitingStart) { awaitingStart = false; render() } }, 2500)
                        revision++; refresh(true); render()
                    }
                }
            }
            setOnLongClickListener {
                if (!requestBusy()) return@setOnLongClickListener false
                awaitingStart = false; captureJob?.cancel(); coordinator.invalidate()
                notice("已取消 AI 请求")
                true
            }
        }
        root.addView(statusButton, LinearLayout.LayoutParams(dp(36), dp(candidateHeightDp)))
        label = TextView(context).apply { gravity = android.view.Gravity.CENTER; setPadding(0, 0, dp(5), 0); textSize = 9f }
        root.addView(label,LinearLayout.LayoutParams(-2,dp(candidateHeightDp)))
        candidateRow = LinearLayout(context)
        content.addView(candidateRow, LinearLayout.LayoutParams(-2, -1))
        candidateScroll = HorizontalScrollView(context).apply {
            contentDescription = "AI 候选列表，可左右滑动"
            isHorizontalScrollBarEnabled = false
            isHorizontalFadingEdgeEnabled = true; setFadingEdgeLength(dp(12))
            addView(content, FrameLayout.LayoutParams(-2, -1))
        }
        root.addView(candidateScroll, LinearLayout.LayoutParams(0, dp(candidateHeightDp), 1f))
        root.addView(View(context).apply { setBackgroundColor(0x309098a0) }, LinearLayout.LayoutParams(dp(1), dp(14)))
        root.addView(ImageButton(context).apply {
            contentDescription="剪贴板";setImageResource(com.osfans.trime.R.drawable.ic_clipboard_24)
            imageTintList=android.content.res.ColorStateList.valueOf(0xff525966.toInt())
            background=android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x24525966),null,android.graphics.drawable.ColorDrawable(android.graphics.Color.WHITE))
            setPadding(dp(8),dp(3),dp(8),dp(3));setOnClickListener {openClipboard()}
        },LinearLayout.LayoutParams(dp(36),dp(candidateHeightDp)))
        root.addView(FrameLayout(context).apply {
            addView(scriptToggle, FrameLayout.LayoutParams(dp(52), dp(26), android.view.Gravity.CENTER))
        }, LinearLayout.LayoutParams(dp(60), dp(candidateHeightDp)))
        panel = root
        render()
        return root
    }

    private fun openClipboard() {
        val expected=session;val connection=service.currentInputConnection ?: return
        clipboard.open({active && session==expected && connection===service.currentInputConnection}) { text ->
            suppress = true; directTarget = null; captureJob?.cancel(); coordinator.invalidate(); revision++
            applying=true
            service.postRimeJob {
                try {
                    if(rawInputCached.isNotEmpty())commitComposition()
                    withContext(Dispatchers.Main.immediate) {
                        if(active && session==expected && connection===service.currentInputConnection) {
                            connection.finishComposingText();connection.commitText(text,1)
                        }
                    }
                } finally {withContext(Dispatchers.Main.immediate) {applying=false;target=null;revision++}}
            }
        }
    }
    private fun openSettings() { service.startActivity(Intent(service, AiSettingsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    private fun notice(message: String) = Toast.makeText(service, message, Toast.LENGTH_SHORT).show()
    private fun requestBusy() = awaitingStart || state is AiState.Loading || ready?.result?.streaming == true
    private fun render() {
        val c = store.config
        fun style(segment: TextView?, selected: Boolean) {
            segment ?: return
            segment.setTextColor(if (selected) android.graphics.Color.WHITE else 0xff525966.toInt())
            segment.background = if (selected) android.graphics.drawable.GradientDrawable().apply {
                setColor(0xff565CC6.toInt()); cornerRadius = 11 * segment.resources.displayMetrics.density
            } else null
        }
        style(simplifiedSegment, !c.traditional); style(traditionalSegment, c.traditional)
        scriptToggle?.contentDescription = if (c.traditional) "繁体输出，点击切换简体" else "简体输出，点击切换繁体"
        val indicator = when {
            sensitive -> "隐私字段"
            !c.consent -> "未授权"
            state is AiState.Loading -> "请求中…"
            state is AiState.Failed -> (state as AiState.Failed).detail
            ready?.result?.streamError?.isNotEmpty() == true -> "部分返回"
            ready?.result?.streaming == true -> "生成中…"
            ready != null -> "已返回"
            !c.automatic || (!c.enabled && !c.assistantEnabled) -> "手动触发"
            else -> "待请求"
        }
        statusButton?.setPhase(when {
            sensitive || !c.consent -> AiStatusButton.Phase.IDLE
            state is AiState.Failed || ready?.result?.streamError?.isNotEmpty() == true -> AiStatusButton.Phase.FAILED
            state is AiState.Loading || awaitingStart -> AiStatusButton.Phase.WAITING
            ready?.result?.streaming == true -> AiStatusButton.Phase.STREAMING
            ready != null -> AiStatusButton.Phase.DONE
            else -> AiStatusButton.Phase.IDLE
        })
        statusButton?.contentDescription = "AI 助手，状态：$indicator。" + if (requestBusy()) "长按取消请求" else "点击重试或召唤助手"
        label?.text = "●"
        label?.contentDescription = "AI 状态：$indicator"
        label?.setTextColor(when {
            state is AiState.Failed || ready?.result?.streamError?.isNotEmpty()==true -> 0xffb3261e.toInt()
            state is AiState.Loading || ready?.result?.streaming==true -> 0xff986500.toInt()
            ready!=null -> 0xff267348.toInt()
            else -> 0xff626872.toInt()
        })
        label?.setOnClickListener { android.widget.Toast.makeText(service,"AI：$indicator",android.widget.Toast.LENGTH_SHORT).show() }
        AiRuntimeStatus.state.value=indicator
        if (renderedCandidates?.request?.stamp != ready?.request?.stamp) {
            candidateScroll?.scrollTo(0, 0)
            renderedCandidates = ready
        }
        candidateRow?.removeAllViews()
        label?.visibility = View.VISIBLE
        ready?.let { result ->
            fun add(text: String, completion: Boolean, role: String = "") {
                candidateRow?.addView(Button(panel!!.context).apply {
                    isAllCaps = false
                    contentDescription = (if (completion) "AI 补全：" else if (role.isNotEmpty()) "AI $role：" else "AI 候选：") + text
                    this.text = (if (completion) "补全：" else if (role.isNotEmpty()) "$role：" else "") + text.take(45) + if (text.length > 45) "…" else ""
                    textSize = candidateTextSize
                    setTextColor(0xff151515.toInt())
                    elevation = 0f; stateListAnimator = null
                    val pressMask = android.graphics.drawable.GradientDrawable().apply {
                        setColor(android.graphics.Color.WHITE)
                        cornerRadius = 4 * resources.displayMetrics.density
                    }
                    background = android.graphics.drawable.RippleDrawable(
                        android.content.res.ColorStateList.valueOf(0x24525966), null, pressMask)
                    typeface = com.osfans.trime.data.theme.FontManager.getTypeface("candidate_font")
                    minHeight = 0; minimumHeight = 0; includeFontPadding = false; isSingleLine = true
                    setPadding((8 * resources.displayMetrics.density).toInt(), 0, (8 * resources.displayMetrics.density).toInt(), 0)
                    layoutParams = LinearLayout.LayoutParams(-2, -1)
                    setOnClickListener {
                        if (text.length > 45) service.showDialog(AlertDialog.Builder(context).setTitle(if (completion) "补全" else "AI 候选")
                            .setMessage(text).setPositiveButton("采用") { _, _ -> adopt(result, text) }.setNegativeButton("取消", null).create())
                        else adopt(result, text)
                    }
                })
            }
            result.result.candidates.forEachIndexed { index, text -> add(text, false, if (result.request.assistantEnabled) (if (index == 0) "纠错" else "助手") else "") }
            if (result.request.assistantEnabled && result.result.candidates.size == 1) {
                candidateRow?.addView(android.widget.TextView(panel!!.context).apply {
                    text = if (result.result.streaming) "助手：生成中…" else "助手：未完成"
                    textSize = candidateTextSize;setTextColor(0xff777777.toInt());gravity=android.view.Gravity.CENTER
                    setPadding(12,0,12,0);layoutParams=LinearLayout.LayoutParams(-2,-1)
                })
            }
            if (result.result.completion.isNotBlank()) add(result.result.completion, true)
        }
    }

    fun start(info: EditorInfo) {
        session++; revision++; active = true; suppress = false; applying = false
        directTarget = null; target = null; captureJob?.cancel()
        observedSelection = Selection(info.initialSelStart, info.initialSelEnd).takeIf { it.start >= 0 && it.end >= 0 }
        chinese = !rime.run { statusCached.isAsciiMode }
        syncScript()
        keyboardGeneration++
        val kind = info.inputType and InputType.TYPE_MASK_CLASS
        val variation = info.inputType and InputType.TYPE_MASK_VARIATION
        sensitive = kind != InputType.TYPE_CLASS_TEXT || variation in setOf(InputType.TYPE_TEXT_VARIATION_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD, InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD) ||
            info.imeOptions and EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING != 0 || info.packageName == service.packageName
        coordinator.invalidate()
        render()
    }

    fun finish() {
        clipboard.close()
        active = false; session++; revision++
        captureJob?.cancel(); coordinator.invalidate()
        target = null; directTarget = null; observedSelection = null
    }
    fun destroy() { finish(); configJob.cancel() }
    private fun syncScript() {
        val traditional = store.config.traditional
        service.postRimeJob {
            if (getRuntimeOption("traditionalization") != traditional) setRuntimeOption("traditionalization", traditional)
        }
    }
    fun userInput() {
        // A key can be navigation or a modifier. Only a successful text commit arms direct mode.
        suppress = false; directTarget = null; revision++
        captureJob?.cancel(); coordinator.invalidate()
    }

    fun textCommitted(connection: InputConnection, text: String) {
        directTarget = null
        val config = store.config
        if (!active || sensitive || !config.consent || suppress || applying || !config.automatic ||
            (!config.enabled && !config.assistantEnabled) ||
            connection !== service.currentInputConnection || text.isEmpty()) return
        directTarget = captureDirect(readEditor(connection), connection, manual = false)
            ?.takeIf { it.input.input.endsWith(text) }
        if (directTarget != null) {
            revision++
            refresh(false)
        }
    }

    fun selectionChanged(start: Int, end: Int, composingStart: Int, composingEnd: Int) {
        val selection = Selection(start, end)
        if (selection == observedSelection) return
        observedSelection = selection
        if (selection == target?.selection || selection == directTarget?.selection) return
        directTarget = null
        revision++
        captureJob?.cancel(); coordinator.invalidate()
        // An IME preedit update can report its caret after the Rime event that
        // scheduled it. Refresh only while the caret still belongs to that preedit.
        if (!suppress && !applying && start == end && composingStart >= 0 &&
            end in composingStart..composingEnd && rime.run { rawInputCached.isNotEmpty() }) {
            refresh(false)
        }
    }
    fun rimeChanged(message: RimeMessage<*>) {
        if (applying || !active) return
        if (message is RimeMessage.CompositionMessage || message is RimeMessage.StatusMessage ||
            message is RimeMessage.CommitTextMessage || message is RimeMessage.OptionMessage) {
            val language = !rime.run { statusCached.isAsciiMode }
            if (language != chinese) {
                chinese = language; keyboardGeneration++; suppress = false; directTarget = null
            }
            revision++; coordinator.invalidate()
            if (!suppress) refresh(false)
        }
    }

    private fun capture(manual: Boolean, requireCurrentSelection: Boolean = false): Target? {
        val c = store.config
        if (!active || sensitive || !c.consent ||
            (!manual && !c.enabled && !c.assistantEnabled)) return null
        val connection = service.currentInputConnection ?: return null
        val raw = rime.run { rawInputCached }
        if (raw.isNotEmpty()) {
            if (raw.length > c.targetLimit) return null
            // Confirmed segments are part of this composition, not surrounding editor text.
            val preedit = rime.run { compositionCached.preedit }.orEmpty()
            val input = if (chinese && preedit.any { it in '\u3400'..'\u9fff' }) preedit else raw
            val textBefore=if(c.contextEnabled && c.beforeLength>0)connection.getTextBeforeCursor(c.beforeLength*2+maxOf(preedit.length,raw.length),0)?.toString().orEmpty() else ""
            val suffix=listOf(preedit,raw).filter { it.isNotEmpty() }.firstOrNull { textBefore.endsWith(it) }
            // Trime keeps a displayed preedit in the editor; never send it twice as context.
            val before=if(suffix!=null) textBefore.removeSuffix(suffix) else textBefore
            val after=if(c.contextEnabled && c.afterLength>0)connection.getTextAfterCursor(c.afterLength*2,0)?.toString().orEmpty() else ""
            val snapshot=Protocol.context(if(c.wordSegmentation && chinese) input.replace('\'', ' ') else input,before,after,c.contextEnabled,c.beforeLength,c.afterLength)
            val currentSelection = readEditor(connection)?.let {
                Selection(it.startOffset + it.selectionStart, it.startOffset + it.selectionEnd)
                    .takeIf { _ -> it.startOffset >= 0 && it.selectionStart >= 0 && it.selectionEnd >= 0 }
            }
            // A delayed selection callback cannot establish the live caret for a write.
            val selection = currentSelection ?: if (requireCurrentSelection) return null
                else observedSelection ?: return null
            return Target(snapshot, true, 0, 0, selection, 0, manual)
        }
        if (!manual && directTarget == null) return null
        val direct = captureDirect(readEditor(connection), connection, manual) ?: return null
        return direct.takeIf { manual || it == directTarget }
    }

    private fun readEditor(connection: InputConnection): ExtractedText? = try {
        connection.getExtractedText(ExtractedTextRequest().apply { hintMaxChars = 2048 }, 0)
    } catch (_: RuntimeException) {
        null
    }

    private fun captureDirect(extracted: ExtractedText?, connection: InputConnection, manual: Boolean): Target? {
        extracted ?: return null
        val c = store.config
        // Fail closed for partial windows: absolute offsets are otherwise ambiguous across editors.
        if (extracted.startOffset != 0 || extracted.partialStartOffset != -1) return null
        val text = extracted.text?.toString() ?: return null
        val a = extracted.selectionStart
        val b = extracted.selectionEnd
        if (a !in 0..text.length || b !in 0..text.length) return null
        val end = maxOf(a, b)
        val range = EditorRanges.capture(text, a, b, c.targetLimit, manual) ?: return null
        val start = range.start
        val input = range.original
        if (a != b && connection.getSelectedText(0)?.toString() != input) return null
        val snapshot = Protocol.context(input, text.substring(0, start), text.substring(end),
            c.contextEnabled, c.beforeLength, c.afterLength)
        return Target(snapshot, false, start, end, Selection(a, b), text.hashCode(), manual)
    }

    private fun refresh(manual: Boolean) {
        captureJob?.cancel()
        coordinator.invalidate()
        captureJob = scope.launch {
            yield() // let the corresponding editor commit and cached Rime state settle
            val c = store.config
            if (!manual && !c.automatic) return@launch
            target = capture(manual)
            val snapshot = target?.takeIf { it.input.input.isNotBlank() } ?: run {
                if (manual && active) notice("请先输入或选中文字")
                awaitingStart = false; render()
                return@launch
            }
            val assistant = manual || c.assistantEnabled
            val request = AiRequest(RequestStamp(session, revision, c.generation, keyboardGeneration, c.generation), snapshot.input,
                store.prompt(c, chinese, assistant), c.completion, c.candidateCount,c.outputTokenBudget,assistant)
            coordinator.submit(request, true, sensitive, if (manual) 0L else c.debounceMs)
        }
    }

    private fun valid(result: AiState.Ready, snapshot: Target): Boolean = active && !sensitive && store.config.consent &&
        result.request.stamp == RequestStamp(session, revision, store.config.generation, keyboardGeneration, store.config.generation) &&
        capture(snapshot.manual, requireCurrentSelection = true) == snapshot

    private fun adopt(result: AiState.Ready, text: String) {
        val snapshot = target ?: return
        if (ready?.request?.stamp != result.request.stamp || !valid(result, snapshot)) { coordinator.invalidate(); return }
        val connection = service.currentInputConnection ?: return
        if (snapshot.composing) {
            service.postRimeJob {
                // The editor operation replaces its composing span in one write. Recheck the
                // snapshot on Main, after waiting for Rime, and before touching the editor.
                var attempted = false
                try {
                    val committed = withContext(Dispatchers.Main.immediate) {
                        if (!valid(result, snapshot) || connection !== service.currentInputConnection) return@withContext false
                        attempted = true
                        applying = true; suppress = true; directTarget = null
                        revision++; target = null; coordinator.invalidate()
                        try {
                            connection.commitText(text, 1)
                        } catch (_: RuntimeException) {
                            false
                        }
                    }
                    if (committed && withContext(Dispatchers.Main.immediate) {
                            session == result.request.stamp.editorSession && connection === service.currentInputConnection
                        }) clearComposition()
                } finally {
                    if (attempted) withContext(NonCancellable + Dispatchers.Main.immediate) {
                        if (session == result.request.stamp.editorSession) applying = false
                    }
                }
            }
        } else {
            applying = true; suppress = true; directTarget = null; coordinator.invalidate()
            connection.beginBatchEdit()
            try {
                if (connection.setSelection(snapshot.start, snapshot.end)) {
                    if (connection.getSelectedText(0)?.toString() == snapshot.input.input) connection.commitText(text, 1)
                    else connection.setSelection(snapshot.selection.start, snapshot.selection.end)
                }
            } finally { connection.endBatchEdit(); applying = false; revision++; target = null }
        }
    }
}
