/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * SPDX-FileCopyrightText: Copyright 2021-2023 Fcitx5 for Android Contributors
 */
package com.osfans.trime.ime.bar.ui

import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.text.TextUtils
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import com.osfans.trime.ai.android.ClipboardGlyph
import com.osfans.trime.ai.android.FunctionGlyphView
import com.osfans.trime.data.theme.ColorManager
import splitties.dimensions.dp
import splitties.views.dsl.constraintlayout.centerInParent
import splitties.views.dsl.constraintlayout.constraintLayout
import splitties.views.dsl.constraintlayout.lParams
import splitties.views.dsl.core.Ui
import splitties.views.dsl.core.add
import splitties.views.dsl.core.wrapContent

/** The paste bar shown after a copy: one rounded pill with the clipboard icon, one line of text and "粘贴". */
class ClipboardSuggestionUi(
    override val ctx: Context,
) : Ui {
    private val textColor = ColorManager.getColor("candidate_text_color")

    /** The full copied text; the pill shows it collapsed to one line. */
    var content: String = ""
        private set

    val text =
        TextView(ctx).apply {
            isSingleLine = true
            maxWidth = dp(220)
            ellipsize = TextUtils.TruncateAt.END
            textSize = 14f
            setTextColor(textColor)
        }

    private val icon = ClipboardGlyph(ctx).apply {
        color = FunctionGlyphView.INDIGO; isClickable = false; isFocusable = false; background = null
        contentDescription = null; importantForAccessibility = android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val action =
        TextView(ctx).apply {
            text = "粘贴"
            textSize = 12f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            setTextColor(android.graphics.Color.WHITE)
            setPadding(dp(9), dp(2), dp(9), dp(2))
            background = GradientDrawable().apply { setColor(FunctionGlyphView.INDIGO); cornerRadius = dp(10).toFloat() }
        }

    private val pill =
        LinearLayout(ctx).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), 0, dp(5), 0)
            val shape = { GradientDrawable().apply { setColor((textColor and 0x00ffffff) or 0x14000000); cornerRadius = dp(16).toFloat() } }
            background = RippleDrawable(android.content.res.ColorStateList.valueOf(0x24565CC6), shape(), shape())
            addView(icon, LinearLayout.LayoutParams(dp(22), dp(22)))
            addView(text, LinearLayout.LayoutParams(wrapContent, wrapContent).apply { marginStart = dp(4); marginEnd = dp(8) })
            addView(action)
        }

    override val root =
        constraintLayout {
            add(pill, lParams(wrapContent, dp(32)) { centerInParent() })
        }

    fun setContent(value: String) {
        content = value
        text.text = value.replace(Regex("\\s+"), " ").trim()
        pill.contentDescription = "粘贴：" + value.take(200)
        icon.nudge()
    }

    fun setOnPaste(listener: () -> Unit) {
        pill.setOnClickListener { listener() }
        root.setOnClickListener { listener() }
    }
}
