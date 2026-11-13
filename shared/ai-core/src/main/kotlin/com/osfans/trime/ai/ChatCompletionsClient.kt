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

/** Stateless HTTPS adapters for OpenAI Responses, OpenRouter/chat and Gemini Interactions. Cancellation closes the underlying call, including body reads.
 * Reuses connections; does not redirect, retry, log or change provider/model settings.
 */
class ChatCompletionsClient internal constructor(private val http: OkHttpClient) {
    constructor() : this(sharedHttp)
    companion object {
        private val sharedHttp = OkHttpClient.Builder()
            .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
    }

    fun payload(model: String, request: AiRequest, parameters: Map<String, JsonPrimitive> = emptyMap(), endpoint: String = "", provider: String = "", preset: String = ""): JsonObject {
        ModelParameters.validateWire(parameters)
        ApiRouting.validatePreset(preset)
        require(preset.isEmpty() || ApiRouting.isOpenRouter(endpoint)) { "Presets require OpenRouter" }
        val input = Protocol.encode(request.input)
        return buildJsonObject {
            put("model", model)
            when {
                ApiRouting.isGemini(endpoint) -> {
                    parameters["reasoning_effort"]?.let { effort ->
                        ReasoningCapabilities.known(endpoint,model)?.let { levels -> require(effort.content in levels) { "Unsupported thinking for $model" } }
                    }
                    put("input", input)
                    put("system_instruction", request.systemPrompt)
                    put("generation_config", ApiRouting.wire(endpoint, parameters, provider))
                    put("store", false)
                }
                ApiRouting.isResponses(endpoint) -> {
                    put("input", input); put("stream", false); put("store", false)
                    if(preset.isEmpty()) put("instructions", request.systemPrompt) else put("preset", preset)
                    ApiRouting.wire(endpoint, parameters, provider).forEach { (k,v) -> put(k,v) }
                }
                else -> {
                    put("stream", false)
                    if(preset.isNotEmpty()) put("preset", preset)
                    putJsonArray("messages") {
                        if(preset.isEmpty()) add(buildJsonObject { put("role", "system"); put("content", request.systemPrompt) })
                        add(buildJsonObject { put("role", "user"); put("content", input) })
                    }
                    ApiRouting.wire(endpoint, parameters, provider).forEach { (k,v) -> put(k,v) }
                }
            }
        }
    }
    suspend fun request(endpoint: String, key: String, model: String, request: AiRequest, timeoutMs: Int = 10000, parameters: Map<String, JsonPrimitive> = emptyMap(), provider: String = "", preset: String = ""): AiResult {
        val url = URI(endpoint)
        require(url.scheme == "https" && url.host != null && url.userInfo == null && url.query == null && url.fragment == null)
        require(key.isNotBlank() && !key.contains('\r') && !key.contains('\n') && model.isNotBlank())
        require(timeoutMs in 1000..60000)
        val body = payload(model, request, parameters, endpoint, provider, preset).toString()
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
        val builder = Request.Builder().url(ApiRouting.requestUrl(endpoint)).post(body)
        if (ApiRouting.isGemini(endpoint)) builder.header("x-goog-api-key", key).header("Api-Revision", "2026-05-20")
        else builder.header("Authorization", "Bearer $key")
        val call = client.newCall(builder.build())
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
                                if (!it.isSuccessful) {
                                    if (preset.isNotEmpty() && ApiRouting.isOpenRouter(endpoint)) {
                                        val bytes = runCatching { it.peekBody(65536).bytes() }.getOrNull()
                                        if (bytes != null && presetFailure(bytes)) throw ApiPresetException()
                                    }
                                    throw ApiHttpException(it.code)
                                }
                                val stream = it.body?.byteStream() ?: throw ApiResponseException()
                                val output = java.io.ByteArrayOutputStream()
                                val buffer = ByteArray(4096)
                                while (true) {
                                    val size = stream.read(buffer)
                                    if (size < 0) break
                                    if (output.size() + size > 65536) throw ApiResponseException()
                                    output.write(buffer, 0, size)
                                }
                                decodeEnvelope(output.toByteArray(), request, endpoint, preset)
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


    internal fun decodeEnvelope(bytes: ByteArray, request: AiRequest, endpoint: String = "", preset: String = ""): AiResult {
        try {
            if (preset.isNotEmpty() && ApiRouting.isOpenRouter(endpoint) && presetFailure(bytes)) throw ApiPresetException()
            val envelope = Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
            (envelope["error"] as? JsonObject)?.let { error ->
                throw ApiProviderException((error["code"] as? JsonPrimitive)?.content?.toIntOrNull())
            }
            val text = when {
                ApiRouting.isGemini(endpoint) -> {
                    when(envelope["status"]?.jsonPrimitive?.content) {
                        "incomplete" -> throw ApiTruncatedException()
                        "failed", "cancelled" -> throw ApiProviderException(null)
                    }
                    val step = envelope.getValue("steps").jsonArray.last { it.jsonObject["type"]?.jsonPrimitive?.content == "model_output" }.jsonObject
                    step.getValue("content").jsonArray.filter { it.jsonObject["type"]?.jsonPrimitive?.content == "text" }
                        .joinToString("") { it.jsonObject.getValue("text").jsonPrimitive.content }
                }
                ApiRouting.isResponses(endpoint) -> {
                    when(envelope["status"]?.jsonPrimitive?.content) {
                        "incomplete" -> throw ApiTruncatedException()
                        "failed", "cancelled" -> throw ApiProviderException(null)
                    }
                    envelope.getValue("output").jsonArray.filter { it.jsonObject["type"]?.jsonPrimitive?.content == "message" }
                        .flatMap { it.jsonObject.getValue("content").jsonArray }
                        .filter { it.jsonObject["type"]?.jsonPrimitive?.content == "output_text" }
                        .joinToString("") { it.jsonObject.getValue("text").jsonPrimitive.content }
                }
                else -> {
                    val choice = envelope.getValue("choices").jsonArray.first().jsonObject
                    when ((choice["finish_reason"] as? JsonPrimitive)?.content) {
                        "length" -> throw ApiTruncatedException()
                        "error", "content_filter" -> throw ApiProviderException(null)
                    }
                    val content = choice.getValue("message").jsonObject.getValue("content").jsonPrimitive
                    require(content.isString)
                    content.content
                }
            }
            return Protocol.decode(text).copy(usage = usage(envelope, endpoint))
        } catch (e: ApiPresetException) { throw e
        } catch (e: ApiProviderException) { throw e
        } catch (e: ApiTruncatedException) { throw e
        } catch (_: Exception) { throw ApiResponseException() }
    }

    private fun presetFailure(bytes: ByteArray): Boolean = runCatching {
        val error = Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject["error"] as? JsonObject
        val metadata = error?.get("metadata") as? JsonObject
        val code = (metadata?.get("presetErrorCode") as? JsonPrimitive)?.content.orEmpty()
        val message = (error?.get("message") as? JsonPrimitive)?.content.orEmpty().lowercase()
        code in setOf("preset_not_found", "preset_access_denied", "preset_disabled") ||
            ("preset" in message && listOf("not found", "access denied", "not accessible", "disabled").any { it in message })
    }.getOrDefault(false)

    private fun usage(envelope: JsonObject, endpoint: String): TokenUsage? {
        val u = envelope["usage"] as? JsonObject ?: return null
        fun number(obj: JsonObject?, key: String) = (obj?.get(key) as? JsonPrimitive)?.intOrNull?.takeIf { it >= 0 }
        if(ApiRouting.isGemini(endpoint)) return TokenUsage(number(u,"total_input_tokens"),number(u,"total_output_tokens"),number(u,"total_thought_tokens"),number(u,"total_cached_tokens"))
        val responses = ApiRouting.isResponses(endpoint)
        val thinking = number(u[if(responses) "output_tokens_details" else "completion_tokens_details"] as? JsonObject,"reasoning_tokens")
        val total = number(u,if(responses) "output_tokens" else "completion_tokens")
        return TokenUsage(number(u,if(responses) "input_tokens" else "prompt_tokens"),total?.let { (it-(thinking ?: 0)).coerceAtLeast(0) },thinking,
            number(u[if(responses) "input_tokens_details" else "prompt_tokens_details"] as? JsonObject,"cached_tokens"))
    }
}
