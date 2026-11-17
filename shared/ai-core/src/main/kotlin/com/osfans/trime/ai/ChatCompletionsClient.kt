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
 * Reuses connections; does not redirect, log or change provider/model settings. Retries truncation once within the original deadline.
 */
class ChatCompletionsClient internal constructor(private val http: OkHttpClient) {
    constructor() : this(sharedHttp)
    companion object {
        private val sharedHttp = OkHttpClient.Builder()
            .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
    }

    fun payload(model:String,request:AiRequest,parameters:Map<String,JsonPrimitive> = emptyMap(),endpoint:String="",provider:String=""):JsonObject =
        NativeCore.invoke("payload",buildJsonObject {
            put("model",model);put("endpoint",endpoint);put("provider",provider);put("parameters",JsonObject(parameters))
            putJsonObject("request") { put("input",Json.encodeToJsonElement(AiInput.serializer(),request.input));put("systemPrompt",request.systemPrompt);put("assistantEnabled",request.assistantEnabled);put("outputTokenBudget",request.outputTokenBudget) }
        }).jsonObject
    suspend fun request(endpoint:String,key:String,model:String,request:AiRequest,timeoutMs:Int=10000,parameters:Map<String,JsonPrimitive> = emptyMap(),provider:String=""):AiResult {
        val deadline=System.nanoTime()+timeoutMs*1_000_000L
        return try { send(endpoint,key,model,request,timeoutMs,parameters,provider) }
        catch(e:ApiTruncatedException) {
            val left=((deadline-System.nanoTime())/1_000_000).toInt()
            if(left<1000)throw e
            val old=parameters["max_completion_tokens"]?.intOrNull ?: parameters["max_tokens"]?.intOrNull ?: request.outputTokenBudget
            val raised=NativeCore.invoke("retryBudget",buildJsonObject {put("budget",old);put("input",request.input.input);put("remainingMs",left)}).jsonPrimitive.int
            if(raised<=old)throw e
            send(endpoint,key,model,request.copy(outputTokenBudget=raised),left,parameters.filterKeys { it!="max_tokens" && it!="max_completion_tokens" },provider)
        }
    }
    private suspend fun send(endpoint: String, key: String, model: String, request: AiRequest, timeoutMs: Int = 10000, parameters: Map<String, JsonPrimitive> = emptyMap(), provider: String = ""): AiResult {
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
                                decodeEnvelope(output.toByteArray(), request, endpoint)
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


    internal fun decodeEnvelope(bytes:ByteArray,request:AiRequest,endpoint:String=""):AiResult {
        if(bytes.size>65536)throw ApiResponseException()
        return try { Json { ignoreUnknownKeys=true }.decodeFromJsonElement(AiResult.serializer(),NativeCore.invoke("envelope",buildJsonObject {
            put("endpoint",endpoint);put("assistantEnabled",request.assistantEnabled);put("body",bytes.toString(Charsets.UTF_8))
        })) } catch(e:ApiTruncatedException) { throw e } catch(e:ApiProviderException) {throw e} catch(_:Exception) {throw ApiResponseException()}
    }
}
