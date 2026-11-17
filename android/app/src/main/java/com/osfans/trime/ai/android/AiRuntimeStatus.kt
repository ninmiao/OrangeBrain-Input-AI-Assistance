package com.osfans.trime.ai.android

import kotlinx.coroutines.flow.MutableStateFlow

/** In-memory status only; no input text, API key or network probe. */
object AiRuntimeStatus {
    val state = MutableStateFlow("待请求（尚未验证连接）")
}
