// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class AiInput(val input: String, val before: String = "", val after: String = "")

@Serializable
data class AiResult(val candidates: List<String>, val completion: String)

object Protocol {
    private val json = Json { encodeDefaults = true }
    fun encode(input: AiInput): String {
        require(input.input.isNotBlank())
        require(input.input.length <= 300 && input.before.length <= 200 && input.after.length <= 50)
        return json.encodeToString(input)
    }

    fun decode(text: String, completionEnabled: Boolean, candidateCount: Int = 1): AiResult {
        require(candidateCount in 1..5)
        require(text.toByteArray(Charsets.UTF_8).size <= 32768) { "Response too large" }
        val result = json.decodeFromString<AiResult>(text)
        require(result.candidates.size <= 5)
        require(result.candidates.all { it.isNotBlank() && it.length <= 2000 })
        require(result.completion.length <= 2000)
        return result.copy(candidates = result.candidates.distinctBy { it.trim() }.take(1), completion = "")
    }
}
