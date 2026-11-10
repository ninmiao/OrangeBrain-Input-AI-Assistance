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
            require(uri.path.endsWith("/chat/completions")) { "模型列表仅能从标准 chat/completions 路径推导" }
            return URI(uri.scheme, null, uri.host, uri.port, uri.path.removeSuffix("chat/completions") + "models", null, null).toASCIIString()
        }
        fun decode(bytes: ByteArray): List<String> {
            require(bytes.size <= 8 * 1024 * 1024)
            val data = Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject.getValue("data").jsonArray
            require(data.size <= 2000)
            return data.map {
                val id = it.jsonObject.getValue("id").jsonPrimitive
                require(id.isString && id.content.isNotBlank() && id.content.length <= 256 && id.content.none { c -> c.isISOControl() })
                id.content
            }.distinct().sorted()
        }
    }
    data class Discovery(val ids:List<String>,val definitions:List<ModelDefinition>)
    suspend fun fetch(endpoint:String,key:String):List<String> = discover(endpoint,key).ids
    suspend fun discover(endpoint: String, key: String): Discovery = withContext(Dispatchers.IO) {
        require(key.isNotBlank() && key.none { it == '\r' || it == '\n' })
        val connection = URI(listUrl(endpoint)).toURL().openConnection() as HttpsURLConnection
        try {
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 10000; connection.readTimeout = 10000
            connection.setRequestProperty("Authorization", "Bearer $key")
            if (connection.responseCode != 200) throw ApiHttpException(connection.responseCode)
            val bytes = connection.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                while (true) {
                    val size = input.read(buffer)
                    if (size < 0) break
                    require(output.size() + size <= 8 * 1024 * 1024)
                    output.write(buffer, 0, size)
                }
                output.toByteArray()
            }
            Discovery(decode(bytes), if(ApiRouting.isOpenRouter(endpoint)) ReasoningCapabilities.fromModels(bytes) else emptyList())
        } finally { connection.disconnect() }
    }
}

class ApiHttpException(val status: Int) : java.io.IOException("API HTTP $status")
