// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import java.text.BreakIterator
import java.util.Locale

data class EditorRange(val start: Int, val end: Int, val original: String)

object EditorRanges {
    /** UTF-16 offsets, as used by Android InputConnection. Never truncate a target. */
    fun capture(text: String, selectionStart: Int, selectionEnd: Int, limit: Int, allowSelection: Boolean): EditorRange? {
        if (selectionStart !in 0..text.length || selectionEnd !in 0..text.length) return null
        val end = maxOf(selectionStart, selectionEnd)
        val start = if (selectionStart != selectionEnd) {
            if (!allowSelection) return null
            minOf(selectionStart, selectionEnd)
        } else {
            val prefix = text.substring(0, end)
            val sentence = BreakIterator.getSentenceInstance(Locale.ROOT).apply { setText(prefix) }
            sentence.preceding(end).coerceAtLeast(0)
        }
        val chars = BreakIterator.getCharacterInstance(Locale.ROOT).apply { setText(text) }
        if (!chars.isBoundary(start) || !chars.isBoundary(end)) return null
        // BreakIterator versions differ for ZWJ emoji: reject any boundary touching a joiner.
        if ((start > 0 && text[start - 1] == '\u200d') || (start < text.length && text[start] == '\u200d') ||
            (end > 0 && text[end - 1] == '\u200d') || (end < text.length && text[end] == '\u200d')) return null
        val value = text.substring(start, end)
        if (value.isBlank() || value.length > limit) return null
        return EditorRange(start, end, value)
    }
}
