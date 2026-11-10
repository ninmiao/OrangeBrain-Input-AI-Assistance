// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import androidx.test.platform.app.InstrumentationRegistry

/** Only the emulator host or an adb-reversed loopback fixture is permitted. */
internal object TestNetwork {
    val baseUrl: String
        get() {
            val host = InstrumentationRegistry.getArguments().getString("apiHost") ?: "10.0.2.2"
            require(host == "10.0.2.2" || host == "127.0.0.1")
            return "https://$host:8443"
        }
}
