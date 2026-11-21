// SPDX-FileCopyrightText: 2015 - 2024 Rime community
//
// SPDX-License-Identifier: GPL-3.0-or-later

pluginManagement {
    includeBuild("android/build-logic")
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
    }
}

rootProject.name = "OrangeCell"
include(":app")
include(":codegen")
include(":ai-core")

project(":app").projectDir = file("android/app")
project(":codegen").projectDir = file("android/codegen")
project(":ai-core").projectDir = file("shared/ai-core")
