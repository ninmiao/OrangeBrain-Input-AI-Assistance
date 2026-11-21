// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import android.view.animation.OvershootInterpolator
import android.view.animation.PathInterpolator
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/** The function keys at the right end of the AI bar. The user picks 0–5 of them and their order. */
enum class FunctionKey(val id: String, val title: String) {
    CLIPBOARD("clipboard", "剪贴板"),
    SCRIPT("script", "简繁"),
    EMOJI("emoji", "AI 表情"),
    ASSISTANT("assistant", "AI 助手"),
    SETTINGS("settings", "AI 设置"),
    HIDE("hide", "收起键盘"),
    ;

    companion object {
        const val MAX = 5
        val DEFAULT_IDS = listOf(CLIPBOARD, SCRIPT, EMOJI, ASSISTANT).map { it.id }
        fun of(id: String) = entries.firstOrNull { it.id == id }
        fun parse(ids: List<String>) = ids.mapNotNull(::of).distinct().take(MAX)
    }
}

/**
 * Base for every function key: the same footprint, a 24-unit drawing box that fills 80 % of the
 * shorter side (capped at 26 dp), a round ripple and the same press bounce. Subclasses draw in
 * 0..24 units, like a Material icon.
 */
abstract class FunctionGlyphView(context: Context) : View(context) {
    protected val density = resources.displayMetrics.density
    protected val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    protected val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    protected val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
    }

    init {
        isClickable = true; isFocusable = true
        val mask = android.graphics.drawable.ShapeDrawable(android.graphics.drawable.shapes.OvalShape())
        background = android.graphics.drawable.RippleDrawable(
            android.content.res.ColorStateList.valueOf(0x24565CC6), null, mask)
    }

    /** Immediate tactile feedback for a tap. */
    open fun nudge() {
        animate().cancel()
        animate().scaleX(0.82f).scaleY(0.82f).setDuration(80).withEndAction {
            animate().scaleX(1f).scaleY(1f).setDuration(240).setInterpolator(OvershootInterpolator(3f)).start()
        }.start()
    }

    override fun onDetachedFromWindow() {
        animate().cancel()
        super.onDetachedFromWindow()
    }

    final override fun onDraw(canvas: Canvas) {
        val box = min(min(width, height) * 0.80f, 26f * density)
        if (box <= 0f) return
        canvas.save()
        canvas.translate((width - box) / 2f, (height - box) / 2f)
        canvas.scale(box / 24f, box / 24f)
        drawGlyph(canvas)
        canvas.restore()
    }

    protected abstract fun drawGlyph(canvas: Canvas)

    companion object {
        val INDIGO = 0xff565CC6.toInt()
        val SLATE = 0xff525966.toInt()
        val ORANGE = 0xffE0761B.toInt()
        val AMBER = 0xffB87900.toInt()
        val GREEN = 0xff267348.toInt()
        val RED = 0xffB3261E.toInt()

        fun create(context: Context, key: FunctionKey): FunctionGlyphView = when (key) {
            FunctionKey.ASSISTANT -> AiStatusButton(context, AiStatusButton.Glyph.SPARKLE)
            FunctionKey.EMOJI -> AiStatusButton(context, AiStatusButton.Glyph.SMILE)
            FunctionKey.SCRIPT -> ScriptToggleButton(context)
            FunctionKey.CLIPBOARD -> ClipboardGlyph(context)
            FunctionKey.SETTINGS -> SettingsGlyph(context)
            FunctionKey.HIDE -> HideKeyboardGlyph(context)
        }
    }
}

/** 简 / 繁 as one rounded tile. Simplified is outlined, traditional is filled; switching flips the tile. */
class ScriptToggleButton(context: Context) : FunctionGlyphView(context) {
    private var traditional = false
    private var shownTraditional = false
    private var flip = 1f
    private val tile = RectF(3f, 3f, 21f, 21f)
    private val flipper = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 360
        interpolator = PathInterpolator(0.4f, 0f, 0.2f, 1f)
        addUpdateListener {
            flip = it.animatedValue as Float
            if (flip >= 0.5f) shownTraditional = traditional
            invalidate()
        }
    }

    fun setTraditional(value: Boolean, animate: Boolean = true) {
        if (value == traditional) return
        traditional = value
        if (animate && isAttachedToWindow) { flipper.cancel(); flipper.start() }
        else { shownTraditional = value; flip = 1f; invalidate() }
        contentDescription = if (value) "繁体输出，点击切换简体" else "简体输出，点击切换繁体"
    }

    override fun onDetachedFromWindow() {
        flipper.cancel(); flip = 1f; shownTraditional = traditional
        super.onDetachedFromWindow()
    }

    override fun drawGlyph(canvas: Canvas) {
        // A card turning around its vertical axis: width follows |cos|, the face swaps at the middle.
        val sx = abs(cos(PI * flip)).toFloat().coerceAtLeast(0.04f)
        canvas.save()
        canvas.scale(sx, 1f, 12f, 12f)
        if (shownTraditional) {
            fill.style = Paint.Style.FILL; fill.color = INDIGO; fill.alpha = 255
            canvas.drawRoundRect(tile, 5f, 5f, fill)
            text.color = android.graphics.Color.WHITE
        } else {
            line.strokeWidth = 1.8f; line.color = INDIGO; line.alpha = 255
            canvas.drawRoundRect(RectF(3.9f, 3.9f, 20.1f, 20.1f), 4.5f, 4.5f, line)
            text.color = INDIGO
        }
        text.textSize = 12.5f
        val baseline = 12f - (text.descent() + text.ascent()) / 2f
        canvas.drawText(if (shownTraditional) "繁" else "简", 12f, baseline, text)
        canvas.restore()
    }

    init { contentDescription = "简体输出，点击切换繁体" }
}

/** Clipboard board with a clip that hops when tapped. */
class ClipboardGlyph(context: Context) : FunctionGlyphView(context) {
    var color = SLATE
    private var hop = 0f
    private val hopper = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 420
        addUpdateListener { hop = it.animatedValue as Float; invalidate() }
    }

    init { contentDescription = "剪贴板" }

    override fun nudge() { super.nudge(); hopper.cancel(); hopper.start() }

    override fun onDetachedFromWindow() { hopper.cancel(); hop = 0f; super.onDetachedFromWindow() }

    override fun drawGlyph(canvas: Canvas) {
        line.color = color; line.alpha = 255; line.strokeWidth = 1.9f
        canvas.drawRoundRect(RectF(5f, 4.6f, 19f, 21f), 2.8f, 2.8f, line)
        line.strokeWidth = 1.7f
        canvas.drawLine(8.6f, 11.6f, 15.4f, 11.6f, line)
        canvas.drawLine(8.6f, 15.6f, 13.2f, 15.6f, line)
        val lift = -2.2f * sin(PI * hop).toFloat()
        fill.style = Paint.Style.FILL; fill.color = color; fill.alpha = 255
        canvas.drawRoundRect(RectF(8.4f, 2.4f + lift, 15.6f, 7f + lift), 1.8f, 1.8f, fill)
    }
}

/** Three sliders; the knobs slide when tapped. */
class SettingsGlyph(context: Context) : FunctionGlyphView(context) {
    private var slide = 0f
    private val slider = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 520
        addUpdateListener { slide = it.animatedValue as Float; invalidate() }
    }

    init { contentDescription = "AI 设置" }

    override fun nudge() { super.nudge(); slider.cancel(); slider.start() }

    override fun onDetachedFromWindow() { slider.cancel(); slide = 0f; super.onDetachedFromWindow() }

    override fun drawGlyph(canvas: Canvas) {
        val wave = sin(PI * slide).toFloat()
        line.color = SLATE; line.alpha = 255; line.strokeWidth = 1.8f
        for ((y, x) in listOf(6.5f to 9f + 4f * wave, 12f to 15f - 4f * wave, 17.5f to 7.5f + 5f * wave)) {
            canvas.drawLine(4f, y, 20f, y, line)
            fill.style = Paint.Style.FILL; fill.color = android.graphics.Color.WHITE; fill.alpha = 255
            canvas.drawCircle(x, y, 2.4f, fill)
            canvas.drawCircle(x, y, 2.4f, line)
        }
    }
}

/** Keyboard outline over a down chevron. */
class HideKeyboardGlyph(context: Context) : FunctionGlyphView(context) {
    init { contentDescription = "收起键盘" }

    override fun drawGlyph(canvas: Canvas) {
        line.color = SLATE; line.alpha = 255; line.strokeWidth = 1.7f
        canvas.drawRoundRect(RectF(3.5f, 3.5f, 20.5f, 14.5f), 2.5f, 2.5f, line)
        fill.style = Paint.Style.FILL; fill.color = SLATE; fill.alpha = 255
        for (x in listOf(7f, 10.3f, 13.7f, 17f)) canvas.drawCircle(x, 7.4f, 0.95f, fill)
        canvas.drawLine(8f, 11f, 16f, 11f, line)
        line.strokeWidth = 1.9f
        canvas.drawLine(8.5f, 17.5f, 12f, 21f, line)
        canvas.drawLine(12f, 21f, 15.5f, 17.5f, line)
    }
}
