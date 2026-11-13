// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import kotlinx.serialization.Serializable

@Serializable
data class AiInput(val input: String)

@Serializable
data class TokenUsage(val input: Int? = null, val output: Int? = null, val reasoning: Int? = null, val cached: Int? = null) {
    fun summary() = "tokens · in ${input ?: "–"} · out ${output ?: "–"} · think ${reasoning ?: "–"} · cached ${cached ?: "–"}"
}

// The list is an internal candidate-bar type. Model-generated content is plain text.
@Serializable
data class AiResult(val candidates: List<String>, val completion: String = "", val usage: TokenUsage? = null)

object Protocol {
    fun encode(input: AiInput): String {
        require(input.input.isNotBlank() && input.input.length <= 300)
        return input.input
    }

    fun decode(text: String, completionEnabled: Boolean = false, candidateCount: Int = 1): AiResult {
        require(text.toByteArray(Charsets.UTF_8).size <= 32768) { "Response too large" }
        // Preserve quotes, punctuation, newlines and JSON-like text that the user actually typed.
        val candidate = text.trim()
        require(candidate.isNotBlank() && candidate.length <= 2000)
        require(candidate.none { it == '\u0000' })
        return AiResult(listOf(candidate))
    }
}
