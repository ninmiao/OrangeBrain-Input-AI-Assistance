package com.osfans.trime.ai

import kotlin.test.*

class EditorRangeTest {
    @Test fun emojiOffsetsRemainUtf16() {
        val text = "hello 🙂 world"
        val range = EditorRanges.capture(text, 6, 8, 300, true)!!
        assertEquals("🙂", range.original)
        assertEquals(2, range.end - range.start)
        assertNull(EditorRanges.capture(text, 7, 8, 300, true))
    }
    @Test fun combiningMarkMustNotBeSeparated() {
        assertNull(EditorRanges.capture("e\u0301!", 0, 1, 300, true))
        assertEquals("e\u0301", EditorRanges.capture("e\u0301!", 0, 2, 300, true)!!.original)
    }
    @Test fun selectionIsManualAndNeverSilentlyTruncated() {
        assertNull(EditorRanges.capture("hello", 0, 5, 300, false))
        assertNull(EditorRanges.capture("hello", 0, 5, 4, true))
        assertNull(EditorRanges.capture("hello", -1, 5, 300, true))
        assertEquals("hello", EditorRanges.capture("hello", 5, 0, 300, true)!!.original)
    }
    @Test fun currentSentenceKeepsMixedLanguageAndFacts() {
        val text = "Done. This model 的 latency 有点高"
        assertEquals("This model 的 latency 有点高", EditorRanges.capture(text, text.length, text.length, 300, false)!!.original)
    }
}
