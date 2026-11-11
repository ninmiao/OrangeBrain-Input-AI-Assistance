pluginManagement { repositories { gradlePluginPortal(); mavenCentral() } }
dependencyResolutionManagement { repositories { mavenCentral() } }
rootProject.name = "Zephyr-Windows"
include(":ai-core")
project(":ai-core").projectDir = file("../shared/ai-core")
