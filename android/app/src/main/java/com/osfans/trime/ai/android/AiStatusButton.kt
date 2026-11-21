// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import androidx.core.graphics.PathParser
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * An AI function key with a visible request state:
 * idle glyph, waiting (amber ring spinning, glyph breathing), streaming (faster ring in the key's
 * colour), done (green check pops in, then settles back to the glyph) and failed (red glyph with a badge).
 * [Glyph.SPARKLE] is the assistant, [Glyph.SMILE] the emoticon key (a face that bobs while it waits).
 * The view only draws; the controller decides the phase and what a tap does.
 */
class AiStatusButton(context: Context, val glyph: Glyph = Glyph.SPARKLE) : FunctionGlyphView(context) {
    enum class Phase { IDLE, WAITING, STREAMING, DONE, FAILED }
    enum class Glyph { SPARKLE, SMILE }

    private var requested = Phase.IDLE
    private var shown = Phase.IDLE
    private val base = if (glyph == Glyph.SMILE) ORANGE else INDIGO

    private val sparkle = PathParser.createPathFromPathData(SPARKLE)
    private val star = PathParser.createPathFromPathData(STAR)
    private val checkPath = Path().apply { moveTo(7.2f, 12.4f); lineTo(10.6f, 15.8f); lineTo(16.8f, 8.6f) }
    private val checkMeasure = PathMeasure(checkPath, false)
    private val work = Path()
    private val oval = RectF(1.5f, 1.5f, 22.5f, 22.5f)
    private val mouth = RectF(7.6f, 9.4f, 15.4f, 16.6f)

    private var spin = 0f      // 0..1, loops while waiting or streaming
    private var ring = 0f      // 0 = no ring, 1 = full ring; drives the glyph shrinking inside it
    private var pop = 0f       // done badge growth, overshoots slightly
    private var fade = 1f      // done badge fade-out before it settles

    private val ticker = ValueAnimator.ofFloat(0f, 1f).apply {
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener { spin = it.animatedValue as Float; invalidate() }
    }
    private val ringAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 220
        addUpdateListener { ring = it.animatedValue as Float; invalidate() }
    }
    private val popAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 360
        interpolator = OvershootInterpolator(2.2f)
        addUpdateListener { pop = it.animatedValue as Float; invalidate() }
    }
    private val fadeAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
        duration = 280
        addUpdateListener { fade = it.animatedValue as Float; invalidate() }
        addListener(object : AnimatorListenerAdapter() {
            private var cancelled = false
            override fun onAnimationStart(animation: Animator) { cancelled = false }
            override fun onAnimationCancel(animation: Animator) { cancelled = true }
            override fun onAnimationEnd(animation: Animator) {
                if (!cancelled && shown == Phase.DONE) { shown = Phase.IDLE; invalidate() }
            }
        })
    }
    private val settle = Runnable { if (shown == Phase.DONE) fadeAnimator.start() }

    init { contentDescription = if (glyph == Glyph.SMILE) "AI 表情" else "AI 助手" }

    /** Idempotent: repeated render() calls with the same phase never restart an animation. */
    fun setPhase(phase: Phase) {
        if (phase == requested) return
        val from = requested
        requested = phase
        shown = phase
        removeCallbacks(settle)
        fadeAnimator.cancel()
        fade = 1f
        when (phase) {
            Phase.IDLE -> { stopTicker(); animateRing(0f) }
            Phase.WAITING -> { startTicker(1100); animateRing(1f); if (from == Phase.IDLE || from == Phase.DONE || from == Phase.FAILED) nudge() }
            Phase.STREAMING -> { startTicker(700); animateRing(1f) }
            Phase.DONE -> {
                stopTicker(); animateRing(0f)
                pop = 0f; popAnimator.cancel(); popAnimator.start()
                postDelayed(settle, 1600)
            }
            Phase.FAILED -> { stopTicker(); animateRing(0f); refuse() }
        }
        invalidate()
    }

    /** Tap ignored because a request is already running. */
    fun refuse() {
        ObjectAnimator.ofFloat(this, TRANSLATION_X, 0f, -3f * density, 3f * density, -2f * density, 2f * density, 0f)
            .setDuration(260).start()
    }

    private fun startTicker(ms: Long) {
        ticker.duration = ms
        if (!ticker.isStarted) ticker.start()
    }

    private fun stopTicker() { ticker.cancel() }

    private fun animateRing(target: Float) {
        ringAnimator.cancel()
        ringAnimator.setFloatValues(ring, target)
        ringAnimator.start()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (requested == Phase.WAITING) startTicker(1100) else if (requested == Phase.STREAMING) startTicker(700)
    }

    override fun onDetachedFromWindow() {
        stopTicker(); ringAnimator.cancel(); popAnimator.cancel(); fadeAnimator.cancel(); removeCallbacks(settle)
        super.onDetachedFromWindow()
    }

    override fun drawGlyph(canvas: Canvas) {
        val pulse = 0.5f + 0.5f * sin(2 * PI * spin).toFloat()
        when (shown) {
            Phase.IDLE -> drawIcon(canvas, base, 1f, 0f)
            Phase.WAITING -> {
                drawRing(canvas, AMBER, 110f)
                drawIcon(canvas, AMBER, 0.55f + 0.45f * pulse, sin(2 * PI * spin).toFloat())
            }
            Phase.STREAMING -> {
                drawRing(canvas, base, 250f)
                drawIcon(canvas, base, 0.7f + 0.3f * (0.5f + 0.5f * sin(4 * PI * spin).toFloat()), sin(4 * PI * spin).toFloat())
            }
            Phase.DONE -> {
                drawIcon(canvas, base, 1f - min(1f, pop) * 0.9f, 0f)
                drawDone(canvas)
            }
            Phase.FAILED -> {
                drawIcon(canvas, RED, 1f, 0f)
                drawBadge(canvas)
            }
        }
    }

    /** [wobble] in -1..1 tilts the face or nothing for the sparkle. */
    private fun drawIcon(canvas: Canvas, color: Int, alpha: Float, wobble: Float) {
        val s = 1f - 0.38f * ring
        val a = (255 * alpha.coerceIn(0f, 1f)).toInt()
        canvas.save()
        canvas.scale(s, s, 12f, 12.5f)
        if (glyph == Glyph.SPARKLE) {
            fill.style = Paint.Style.FILL; fill.color = color; fill.alpha = a
            canvas.drawPath(sparkle, fill)
        } else {
            canvas.rotate(10f * wobble, 11.5f, 13f)
            line.color = color; line.alpha = a; line.strokeWidth = 1.9f
            canvas.drawCircle(11.5f, 13f, 8.2f, line)
            fill.style = Paint.Style.FILL; fill.color = color; fill.alpha = a
            canvas.drawCircle(8.7f, 11.4f, 1.25f, fill)
            canvas.drawCircle(14.3f, 11.4f, 1.25f, fill)
            line.strokeWidth = 1.7f
            canvas.drawArc(mouth, 25f, 130f, false, line)
            canvas.drawPath(star, fill)
        }
        canvas.restore()
    }

    private fun drawRing(canvas: Canvas, color: Int, sweep: Float) {
        line.strokeWidth = 2.2f
        line.color = color
        line.alpha = (0x26 * ring).toInt()
        canvas.drawOval(oval, line)
        line.alpha = (255 * ring).toInt()
        canvas.drawArc(oval, spin * 360f - 90f, sweep, false, line)
    }

    private fun drawDone(canvas: Canvas) {
        val r = 11f * max(0f, pop)
        fill.style = Paint.Style.FILL
        fill.color = GREEN
        fill.alpha = (255 * fade).toInt()
        canvas.drawCircle(12f, 12f, r, fill)
        val progress = ((pop - 0.35f) / 0.65f).coerceIn(0f, 1f)
        if (progress > 0f) {
            work.reset()
            checkMeasure.getSegment(0f, checkMeasure.length * progress, work, true)
            line.strokeWidth = 2.4f
            line.color = android.graphics.Color.WHITE
            line.alpha = (255 * fade).toInt()
            canvas.drawPath(work, line)
        }
    }

    private fun drawBadge(canvas: Canvas) {
        fill.style = Paint.Style.FILL
        fill.color = android.graphics.Color.WHITE
        fill.alpha = 255
        canvas.drawCircle(19f, 19f, 5.6f, fill)
        fill.color = RED
        canvas.drawCircle(19f, 19f, 4.6f, fill)
        line.strokeWidth = 1.7f
        line.color = android.graphics.Color.WHITE
        line.alpha = 255
        canvas.drawLine(19f, 16.6f, 19f, 19.4f, line)
        canvas.drawPoint(19f, 21.2f, line)
    }

    private companion object {
        const val SPARKLE = "M10,2.5L12.25,8.75L18.5,11L12.25,13.25L10,19.5L7.75,13.25L1.5,11L7.75,8.75ZM19.5,2L20.4,4.6L23,5.5L20.4,6.4L19.5,9L18.6,6.4L16,5.5L18.6,4.6ZM19,15L20,18L23,19L20,20L19,23L18,20L15,19L18,18Z"
        // A small four-point star at the top right of the face: the "AI" mark.
        const val STAR = "M20.2,0.8L21,3L23.2,3.8L21,4.6L20.2,6.8L19.4,4.6L17.2,3.8L19.4,3Z"
    }
}
