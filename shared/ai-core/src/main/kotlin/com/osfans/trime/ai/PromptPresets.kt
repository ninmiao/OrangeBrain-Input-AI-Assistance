// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import kotlinx.serialization.Serializable

@Serializable
data class PromptPresets(
    val chinese: String = "@preset/zephyr-zh-hans",
    val traditional: String = "@preset/zephyr-zh-hant",
    val english: String = "@preset/zephyr-en",
    val enabled: Boolean = false,
) {
    fun selected(chineseMode: Boolean, traditionalMode: Boolean): String {
        if (!enabled) return ""
        return (when {
            !chineseMode -> english
            traditionalMode -> traditional
            else -> chinese
        }).also { if (it.isBlank()) throw ApiPresetException() }
    }
    fun withDefaults(): PromptPresets {
        val defaults = PromptPresets()
        return copy(chinese=chinese.ifBlank { defaults.chinese },
            traditional=traditional.ifBlank { defaults.traditional }, english=english.ifBlank { defaults.english })
    }
    fun validate() {
        if (enabled) listOf(chinese, traditional, english).forEach { ApiRouting.validatePreset(it) }
    }
}
