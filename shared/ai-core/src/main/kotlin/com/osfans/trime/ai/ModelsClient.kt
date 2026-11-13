// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import java.net.URI
import javax.net.ssl.HttpsURLConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*

class ModelsClient {
    companion object {
        fun listUrl(endpoint: String): String {
            val uri = URI(endpoint)
            require(uri.scheme == "https" && uri.host != null && uri.userInfo == null && uri.query == null && uri.fragment == null)
            val suffix = when {
                ApiRouting.isGemini(endpoint) && uri.path.endsWith("/interactions") -> "interactions"
                uri.path.endsWith("/responses") -> "responses"
                uri.path.endsWith("/chat/completions") -> "chat/completions"
                else -> error("Use a standard responses, interactions or chat/completions endpoint")
            }
            return URI(uri.scheme, null, uri.host, uri.port, uri.path.removeSuffix(suffix) + "models", null, null).toASCIIString()
        }
        fun decode(bytes: ByteArray, gemini: Boolean = false): List<String> {
            require(bytes.size <= 8 * 1024 * 1024)
            val data = Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject.getValue(if (gemini) "models" else "data").jsonArray
            require(data.size <= 2000)
            return data.filter { item -> !gemini || (item.jsonObject["supportedGenerationMethods"] as? JsonArray)?.any { it.jsonPrimitive.content == "generateContent" } == true }.map {
                val id = it.jsonObject.getValue(if (gemini) "name" else "id").jsonPrimitive
                require(id.isString && id.content.isNotBlank() && id.content.length <= 256 && id.content.none { c -> c.isISOControl() })
                if (gemini) id.content.removePrefix("models/") else id.content
            }.distinct().sorted()
        }
    }
    data class Discovery(val ids:List<String>,val definitions:List<ModelDefinition>)
    suspend fun fetch(endpoint:String,key:String):List<String> = discover(endpoint,key).ids
    suspend fun discover(endpoint: String, key: String): Discovery = withContext(Dispatchers.IO) {
        require(key.isNotBlank() && key.none { it == '\r' || it == '\n' })
        val gemini=ApiRouting.isGemini(endpoint)
        val base=listUrl(endpoint)
        val rows=mutableListOf<JsonElement>();val seen=mutableSetOf<String>()
        var page="";var totalBytes=0
        do {
            val url=base+if(page.isEmpty()) "" else "?pageToken="+java.net.URLEncoder.encode(page,"UTF-8")
            val connection=URI(url).toURL().openConnection() as HttpsURLConnection
            try {
                connection.instanceFollowRedirects=false
                connection.connectTimeout=10000;connection.readTimeout=10000
                if(gemini)connection.setRequestProperty("x-goog-api-key",key) else connection.setRequestProperty("Authorization","Bearer $key")
                if(connection.responseCode!=200)throw ApiHttpException(connection.responseCode)
                val bytes=connection.inputStream.use { input ->
                    val output=java.io.ByteArrayOutputStream();val buffer=ByteArray(4096)
                    while(true) {
                        val size=input.read(buffer);if(size<0)break
                        totalBytes+=size;require(totalBytes<=8*1024*1024)
                        output.write(buffer,0,size)
                    }
                    output.toByteArray()
                }
                if(!gemini)return@withContext Discovery(decode(bytes),if(ApiRouting.isOpenRouter(endpoint))ReasoningCapabilities.fromModels(bytes) else emptyList())
                val obj=Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
                rows.addAll(obj.getValue("models").jsonArray);require(rows.size<=2000)
                page=(obj["nextPageToken"] as? JsonPrimitive)?.content.orEmpty()
                require(page.length<=4096)
                if(page.isNotEmpty())require(seen.add(page) && seen.size<=20) { "Invalid model pagination" }
            } finally { connection.disconnect() }
        } while(page.isNotEmpty())
        Discovery(decode(buildJsonObject { put("models",JsonArray(rows)) }.toString().toByteArray(Charsets.UTF_8),true),emptyList())
    }
}

class ApiHttpException(val status: Int) : java.io.IOException("API HTTP $status")
