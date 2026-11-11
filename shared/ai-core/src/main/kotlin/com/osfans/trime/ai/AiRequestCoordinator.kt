// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

data class RequestStamp(
    val editorSession: Long,
    val inputRevision: Long,
    val promptGeneration: Long,
    val keyboardGeneration: Long,
    val apiGeneration: Long,
)

data class AiRequest(val stamp: RequestStamp, val input: AiInput, val systemPrompt: String, val completionEnabled: Boolean, val candidateCount: Int = 1)

sealed interface AiState {
    data object Idle : AiState
    data object Loading : AiState
    data class Ready(val request: AiRequest, val result: AiResult) : AiState
    data class Failed(val reason: AiFailure, val detail:String=reason.label) : AiState
}

/** All methods and callbacks must run on the same dispatcher (Android main thread).
 * Transport must move network and parsing work off that dispatcher.
 * Adoption still requires the editor adapter to revalidate text and selection.
 */
class AiRequestCoordinator(
    private val scope: CoroutineScope,
    private val transport: suspend (AiRequest) -> AiResult,
    private val publish: (AiState) -> Unit,
) {
    private var generation = 0L
    private var current: AiRequest? = null
    private var job: Job? = null

    fun invalidate() {
        generation++
        current = null
        job?.cancel()
        job = null
        publish(AiState.Idle)
    }

    fun submit(request: AiRequest?, enabled: Boolean, sensitive: Boolean, debounceMs: Long = 200) {
        require(debounceMs in 50..2000)
        invalidate()
        if (!enabled || sensitive || request == null || request.input.input.isBlank()) return
        Protocol.encode(request.input) // Reject invalid snapshots before network access.
        current = request
        val token = generation
        job = scope.launch {
            delay(debounceMs)
            if (token != generation) return@launch
            publish(AiState.Loading)
            try {
                val result = transport(request)
                if (token == generation && current == request) publish(AiState.Ready(request, result))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (token == generation) publish(AiState.Failed(AiFailure.from(error), (error as? ApiTimeoutException)?.phase?.label ?: AiFailure.from(error).label))
            }
        }
    }
}
