// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai

import java.io.IOException
import java.io.InterruptedIOException

// Only fixed categories/status codes escape the transport. No response bodies,
// credentials or user input are copied into diagnostic messages.
class ApiTimeoutException : InterruptedIOException("API request timeout")
class ApiResponseException : IOException("Invalid API response")
class ApiTruncatedException : IOException("API response truncated")
class ApiProviderException(val status: Int?) : IOException("API provider failure${status?.let { " $it" } ?: ""}")

enum class AiFailure(val label: String) {
    TIMEOUT("请求超时"), AUTHENTICATION("Key 无效"), CREDIT("额度不足"),
    RATE_LIMIT("请求受限"), PROVIDER("服务商失败"), TRUNCATED("返回被截断"),
    INVALID_RESPONSE("响应格式错误"), NETWORK("网络连接失败"), UNKNOWN("暂不可用");
    companion object {
        fun from(error: Exception): AiFailure {
            val status = when(error) { is ApiHttpException -> error.status; is ApiProviderException -> error.status; else -> null }
            return when {
                error is InterruptedIOException -> TIMEOUT
                status in listOf(401,403) -> AUTHENTICATION
                status == 402 -> CREDIT
                status == 429 -> RATE_LIMIT
                error is ApiProviderException || error is ApiHttpException -> PROVIDER
                error is ApiTruncatedException -> TRUNCATED
                error is ApiResponseException -> INVALID_RESPONSE
                error is IOException -> NETWORK
                else -> UNKNOWN
            }
        }
    }
}
