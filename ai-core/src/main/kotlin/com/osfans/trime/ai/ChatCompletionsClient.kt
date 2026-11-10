// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import java.net.URL
import javax.net.ssl.HttpsURLConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*

/** Explicit adapter for non-streaming chat/completions with textual message.content.
 * endpoint is the complete HTTPS URL. No redirects, retries, logging or model defaults.
 */
class ChatCompletionsClient {
    companion object {
        private val deadlines = java.util.concurrent.ScheduledThreadPoolExecutor(1) { task ->
            Thread(task, "ai-http-deadline").apply { isDaemon = true }
        }.apply { removeOnCancelPolicy = true }
    }
    fun payload(model: String, request: AiRequest, parameters: Map<String, JsonPrimitive> = emptyMap(), endpoint: String = "", provider: String = ""): JsonObject {
        ModelParameters.validateWire(parameters)
        return buildJsonObject {
            put("model", model)
            put("stream", false)
            putJsonArray("messages") {
                add(buildJsonObject { put("role", "system"); put("content", request.systemPrompt) })
                add(buildJsonObject { put("role", "user"); put("content", Protocol.encode(request.input)) })
            }
            ApiRouting.wire(endpoint, parameters, provider).forEach { (name, value) -> put(name, value) }
        }
    }
    suspend fun request(endpoint: String, key: String, model: String, request: AiRequest, timeoutMs: Int = 10000, parameters: Map<String, JsonPrimitive> = emptyMap(), provider: String = ""): AiResult =
        withContext(Dispatchers.IO) {
            val url = URL(endpoint)
            require(url.protocol == "https" && url.userInfo == null && url.query == null && url.ref == null)
            require(key.isNotBlank() && !key.contains('\r') && !key.contains('\n') && model.isNotBlank())
            require(timeoutMs in 1000..60000)
            val payload = payload(model, request, parameters, endpoint, provider).toString().toByteArray(Charsets.UTF_8)
            val connection = url.openConnection() as HttpsURLConnection
            val deadline = deadlines.schedule({ connection.disconnect() }, timeoutMs.toLong(), java.util.concurrent.TimeUnit.MILLISECONDS)
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = timeoutMs
                connection.readTimeout = timeoutMs
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Authorization", "Bearer $key")
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.setFixedLengthStreamingMode(payload.size)
                connection.outputStream.use { it.write(payload) }
                if (connection.responseCode !in 200..299) throw ApiHttpException(connection.responseCode)
                val bytes = connection.inputStream.use { stream ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= 65536) { "API response too large" }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
                val envelope = Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
                val content = envelope.getValue("choices").jsonArray.first().jsonObject
                    .getValue("message").jsonObject.getValue("content").jsonPrimitive
                require(content.isString)
                Protocol.decode(content.content, request.completionEnabled, request.candidateCount)
            } finally {
                deadline.cancel(false)
                connection.disconnect()
            }
        }
}
