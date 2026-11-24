// SPDX-License-Identifier: GPL-3.0-or-later
package com.osfans.trime.ai.android

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe

class AppUpdaterTest :
    StringSpec({
        val a = "a".repeat(64)
        val b = "b".repeat(64)
        val w = "c".repeat(64)
        val sums = "$w  OrangeCell-Windows-1.14.2-Setup-x86-arm64.exe\n" +
            "$a  OrangeCell-1.12.2-arm64-v8a-demo.apk\r\n" +
            "$b  OrangeCell-1.12.10-arm64-v8a-demo.apk\n"

        "versions compare numerically" {
            (AppUpdater.compare("1.12.10", "1.12.9") > 0) shouldBe true
            AppUpdater.compare("1.12.2", "1.12.2") shouldBe 0
            (AppUpdater.compare("1.9.0", "1.12.0") < 0) shouldBe true
        }

        "newest Android APK is chosen from SHA256SUMS" {
            val u = AppUpdater.parse(sums, "1.12.2")
            u.newer shouldBe true
            u.version shouldBe "1.12.10"
            u.sha256 shouldBe b
            u.url shouldBe "https://raw.githubusercontent.com/ninmiao/OrangeBrain-Input-AI-Assistance/main/dist/OrangeCell-1.12.10-arm64-v8a-demo.apk"
        }

        "no update when the installed version is newest" {
            AppUpdater.parse(sums, "1.12.10").newer shouldBe false
            AppUpdater.parse(sums, "2.0.0").newer shouldBe false
        }

        "a list without an APK is rejected" {
            shouldThrow<IllegalStateException> { AppUpdater.parse("$w  OrangeCell-Windows-1.14.2-Setup-x86-arm64.exe\n", "1.0.0") }
        }
    })
