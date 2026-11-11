// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import java.net.URI
import java.io.IOException
import java.io.InterruptedIOException
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

/** HTTPS chat adapter. Cancellation closes the underlying call, including body reads.
 * Reuses connections; does not redirect, retry, log or change provider/model settings.
 */
class ChatCompletionsClient internal constructor(private val http: OkHttpClient) {
    constructor() : this(sharedHttp)
    companion object {
        private val sharedHttp = OkHttpClient.Builder()
            .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
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
    suspend fun request(endpoint: String, key: String, model: String, request: AiRequest, timeoutMs: Int = 10000, parameters: Map<String, JsonPrimitive> = emptyMap(), provider: String = ""): AiResult {
        val url = URI(endpoint)
        require(url.scheme == "https" && url.host != null && url.userInfo == null && url.query == null && url.fragment == null)
        require(key.isNotBlank() && !key.contains('\r') && !key.contains('\n') && model.isNotBlank())
        require(timeoutMs in 1000..60000)
        val body = payload(model, request, parameters, endpoint, provider).toString()
            .toRequestBody("application/json; charset=utf-8".toMediaType())
        val phase = AtomicReference(RequestPhase.QUEUED)
        val listener = object : EventListener() {
            override fun dnsStart(call:Call, domainName:String) { phase.set(RequestPhase.DNS) }
            override fun connectStart(call:Call, address:java.net.InetSocketAddress, proxy:java.net.Proxy) { phase.set(RequestPhase.CONNECT) }
            override fun secureConnectStart(call:Call) { phase.set(RequestPhase.TLS) }
            override fun requestHeadersStart(call:Call) { phase.set(RequestPhase.SENDING) }
            override fun requestBodyEnd(call:Call, byteCount:Long) { phase.set(RequestPhase.WAITING) }
            override fun responseHeadersEnd(call:Call, response:Response) { phase.set(RequestPhase.RECEIVING) }
        }
        val client = http.newBuilder().eventListener(listener).callTimeout(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            .connectTimeout(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            .readTimeout(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            .writeTimeout(timeoutMs.toLong(), TimeUnit.MILLISECONDS).build()
        val call = client.newCall(Request.Builder().url(endpoint).header("Authorization", "Bearer $key").post(body).build())
        // Coroutine deadline also covers a queued call. The cancellation hook below
        // cancels its socket/HTTP2 stream even while the body is still being read.
        return try { withTimeoutOrNull(timeoutMs.toLong()) {
            suspendCancellableCoroutine { continuation ->
                continuation.invokeOnCancellation { call.cancel() }
                call.enqueue(object : Callback {
                    override fun onFailure(call: Call, e: IOException) {
                        continuation.resumeWith(Result.failure(e))
                    }
                    override fun onResponse(call: Call, response: Response) {
                        val result = runCatching {
                            response.use {
                                if (!it.isSuccessful) throw ApiHttpException(it.code)
                                val stream = it.body?.byteStream() ?: throw ApiResponseException()
                                val output = java.io.ByteArrayOutputStream()
                                val buffer = ByteArray(4096)
                                while (true) {
                                    val size = stream.read(buffer)
                                    if (size < 0) break
                                    if (output.size() + size > 65536) throw ApiResponseException()
                                    output.write(buffer, 0, size)
                                }
                                decodeEnvelope(output.toByteArray(), request)
                            }
                        }
                        continuation.resumeWith(result)
                    }
                })
            }
        } ?: throw ApiTimeoutException(phase.get())
        } catch (cancelled:CancellationException) { throw cancelled
        } catch (timeout:InterruptedIOException) { throw ApiTimeoutException(phase.get()) }
    }

    internal fun decodeEnvelope(bytes: ByteArray, request: AiRequest): AiResult {
        try {
            val envelope = Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
            // OpenRouter can send HTTP 200 before a provider later fails.
            (envelope["error"] as? JsonObject)?.let { error ->
                throw ApiProviderException((error["code"] as? JsonPrimitive)?.content?.toIntOrNull())
            }
            val choice = envelope.getValue("choices").jsonArray.first().jsonObject
            when ((choice["finish_reason"] as? JsonPrimitive)?.content) {
                "length" -> throw ApiTruncatedException()
                "error", "content_filter" -> throw ApiProviderException(null)
            }
            val content = choice.getValue("message").jsonObject.getValue("content").jsonPrimitive
            require(content.isString)
            return Protocol.decode(content.content, request.completionEnabled, request.candidateCount)
        } catch (e: ApiProviderException) { throw e
        } catch (e: ApiTruncatedException) { throw e
        } catch (_: Exception) { throw ApiResponseException() }
    }
}
