// SPDX-License-Identifier: GPL-3.0-or-later
package input.zephyr.windows

import kotlinx.coroutines.*

internal suspend fun <T> whileClientConnected(connected:()->Boolean,request:suspend ()->T):T = coroutineScope {
    val owner=currentCoroutineContext().job
    val monitor=launch(Dispatchers.IO) {
        while(isActive) {
            delay(25)
            if(!connected()) { owner.cancel(CancellationException("Input client disconnected"));break }
        }
    }
    try { request() } finally { monitor.cancel() }
}
