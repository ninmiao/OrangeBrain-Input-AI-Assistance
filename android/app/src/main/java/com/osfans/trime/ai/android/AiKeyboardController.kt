// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.content.Intent
import android.text.InputType
import android.view.ContextThemeWrapper
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.ExtractedTextRequest
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
    private var directEligible = false
    private var suppress = false
    private var applying = false
    private var target: Target? = null
    private var ready: AiState.Ready? = null
    private var panel: LinearLayout? = null
    private var candidateRow: LinearLayout? = null
    private var candidateScroll: HorizontalScrollView? = null
    private var renderedCandidates: AiState.Ready? = null
    private var label: TextView? = null
    private var scriptButton: Button? = null
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
    }, { update -> state = update; ready = update as? AiState.Ready; render() })
    private val configJob = scope.launch {
        store.changes.collect { changed ->
            revision++
            coordinator.invalidate()
            if (active) syncScript()
            if (active && !suppress) refresh(false)
            render()
        }
    }

    private data class Target(val input: AiInput, val composing: Boolean, val start: Int, val end: Int,
        val selectionStart: Int, val selectionEnd: Int, val documentHash: Int, val manual: Boolean)

    fun createView(): View {
        val context = ContextThemeWrapper(service, android.R.style.Theme_Material_Light)
        val style = com.osfans.trime.data.theme.ThemeManager.activeTheme.generalStyle
        candidateTextSize = style.candidateTextSize
        candidateHeightDp = style.candidateViewHeight.coerceAtLeast(28)
        fun dp(n: Int) = (n * service.resources.displayMetrics.density).toInt()
        val root = LinearLayout(context).apply { id = View.generateViewId(); orientation = LinearLayout.HORIZONTAL; gravity = android.view.Gravity.CENTER_VERTICAL; setBackgroundColor(0xffd1d3d9.toInt()) }
        scriptButton = Button(context).apply {
            textSize = 14f; isAllCaps = false; minWidth = 0; minimumWidth = 0
            setTextColor(0xff525966.toInt())
            typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
            elevation = 0f; stateListAnimator = null
            val mask = android.graphics.drawable.GradientDrawable().apply {
                setColor(android.graphics.Color.WHITE); cornerRadius = dp(6).toFloat()
            }
            background = android.graphics.drawable.RippleDrawable(
                android.content.res.ColorStateList.valueOf(0x24525966), null, mask)
            minHeight = 0; minimumHeight = 0; includeFontPadding = false; isSingleLine = true
            setPadding(0, 0, 0, 0)
            setOnClickListener { scope.launch { withContext(Dispatchers.IO) { store.update { it.copy(traditional = !it.traditional) } } } }
        }
        val content = LinearLayout(context).apply { gravity = android.view.Gravity.CENTER_VERTICAL }
        label = TextView(context).apply { setPadding(dp(8), 0, dp(8), 0); textSize = 12f }
        content.addView(label)
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
        root.addView(scriptButton, LinearLayout.LayoutParams(dp(48), dp(candidateHeightDp)))
        panel = root
        render()
        return root
    }

    private fun openClipboard() {
        val expected=session;val connection=service.currentInputConnection ?: return
        clipboard.open({active && session==expected && connection===service.currentInputConnection}) { text ->
            suppress=true;directEligible=false;captureJob?.cancel();coordinator.invalidate();revision++
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
    private fun render() {
        val c = store.config
        scriptButton?.text = if (c.traditional) "繁" else "简"
        scriptButton?.contentDescription = if (c.traditional) "繁体输出，点击切换简体" else "简体输出，点击切换繁体"
        label?.text = "AI · " + when {
            sensitive -> "隐私字段"
            !c.enabled -> "关闭"
            state is AiState.Loading -> "请求中…"
            state is AiState.Failed -> (state as AiState.Failed).detail
            else -> "就绪"
        }
        if (renderedCandidates !== ready) {
            candidateScroll?.scrollTo(0, 0)
            renderedCandidates = ready
        }
        candidateRow?.removeAllViews()
        label?.visibility = if (ready == null) View.VISIBLE else View.GONE
        ready?.let { result ->
            fun add(text: String, completion: Boolean) {
                candidateRow?.addView(Button(panel!!.context).apply {
                    isAllCaps = false
                    contentDescription = (if (completion) "AI 补全：" else "AI 候选：") + text
                    this.text = (if (completion) "补全：" else "") + text.take(45) + if (text.length > 45) "…" else ""
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
            result.result.candidates.forEach { add(it, false) }
            if (result.result.completion.isNotBlank()) add(result.result.completion, true)
        }
    }

    fun start(info: EditorInfo) {
        session++; revision++; active = true; suppress = false; applying = false; directEligible = false
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

    fun finish() { clipboard.close();active = false; session++; revision++; captureJob?.cancel(); coordinator.invalidate(); target = null }
    fun destroy() { finish(); configJob.cancel() }
    private fun syncScript() {
        val traditional = store.config.traditional
        service.postRimeJob {
            if (getRuntimeOption("traditionalization") != traditional) setRuntimeOption("traditionalization", traditional)
        }
    }
    fun userInput() {
        // Called synchronously before a real key action, including local candidate taps.
        suppress = false; directEligible = true; revision++; coordinator.invalidate()
    }
    fun selectionChanged() {
        if (applying) return
        revision++; coordinator.invalidate()
        if (!suppress) refresh(false)
    }
    fun rimeChanged(message: RimeMessage<*>) {
        if (applying || !active) return
        if (message is RimeMessage.CompositionMessage || message is RimeMessage.StatusMessage ||
            message is RimeMessage.CommitTextMessage || message is RimeMessage.OptionMessage) {
            val language = !rime.run { statusCached.isAsciiMode }
            if (language != chinese) { chinese = language; keyboardGeneration++; suppress = false; directEligible = true }
            revision++; coordinator.invalidate()
            if (!suppress) refresh(false)
        }
    }

    private fun capture(manual: Boolean): Target? {
        val c = store.config
        if (!active || sensitive || !c.enabled || !c.consent) return null
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
            return Target(snapshot, true, 0, 0, 0, 0, 0, manual)
        }
        if (!manual && !directEligible) return null
        val extracted = connection.getExtractedText(ExtractedTextRequest().apply { hintMaxChars = 2048 }, 0) ?: return null
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
        return Target(Protocol.context(input,text.substring(0,start),text.substring(end),c.contextEnabled,c.beforeLength,c.afterLength), false, start, end, a, b, text.hashCode(), manual)
    }

    private fun refresh(manual: Boolean) {
        captureJob?.cancel()
        coordinator.invalidate()
        captureJob = scope.launch {
            yield() // let the corresponding editor commit and cached Rime state settle
            val c = store.config
            if (!manual && !c.automatic) return@launch
            target = capture(manual)
            val snapshot = target ?: return@launch
            val request = AiRequest(RequestStamp(session, revision, c.generation, keyboardGeneration, c.generation), snapshot.input,
                store.prompt(c, chinese), c.completion, c.candidateCount,c.outputTokenBudget)
            coordinator.submit(request, c.enabled, sensitive, c.debounceMs)
        }
    }

    private fun valid(result: AiState.Ready, snapshot: Target): Boolean = active && !sensitive && store.config.enabled &&
        result.request.stamp == RequestStamp(session, revision, store.config.generation, keyboardGeneration, store.config.generation) &&
        capture(snapshot.manual) == snapshot

    private fun adopt(result: AiState.Ready, text: String) {
        val snapshot = target ?: return
        if (ready != result || !valid(result, snapshot)) { coordinator.invalidate(); return }
        val connection = service.currentInputConnection ?: return
        if (snapshot.composing) {
            service.postRimeJob {
                val allowed = withContext(Dispatchers.Main.immediate) {
                    if (!valid(result, snapshot) || connection !== service.currentInputConnection) false
                    else { applying = true; suppress = true; coordinator.invalidate(); true }
                }
                if (!allowed) return@postRimeJob
                try {
                    clearComposition()
                    withContext(Dispatchers.Main.immediate) {
                        if (session == result.request.stamp.editorSession && revision == result.request.stamp.inputRevision &&
                            connection === service.currentInputConnection && store.config.generation == result.request.stamp.apiGeneration) {
                            connection.beginBatchEdit()
                            try { connection.setComposingText("", 1); connection.finishComposingText(); connection.commitText(text, 1) }
                            finally { connection.endBatchEdit() }
                        }
                    }
                } finally { withContext(Dispatchers.Main.immediate) { applying = false; revision++; target = null } }
            }
        } else {
            applying = true; suppress = true; coordinator.invalidate()
            connection.beginBatchEdit()
            try {
                if (connection.setSelection(snapshot.start, snapshot.end)) {
                    if (connection.getSelectedText(0)?.toString() == snapshot.input.input) connection.commitText(text, 1)
                    else connection.setSelection(snapshot.selectionStart, snapshot.selectionEnd)
                }
            } finally { connection.endBatchEdit(); applying = false; revision++; target = null }
        }
    }
}
