plugins {
    kotlin("jvm") version "2.2.0"
    kotlin("plugin.serialization") version "2.2.0"
    application
}
kotlin { jvmToolchain(17) }
dependencies {
    implementation(project(":ai-core"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
    implementation("net.java.dev.jna:jna-platform:5.19.1")
    testImplementation(kotlin("test-junit5"))
    testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.12.2")
}
application { mainClass.set("input.zephyr.windows.MainKt") }
tasks.test { useJUnitPlatform() }

// Keep Windows outputs separate from the Android Gradle root.
project(":ai-core") {
    layout.buildDirectory.set(rootProject.layout.buildDirectory.dir("ai-core"))
}
