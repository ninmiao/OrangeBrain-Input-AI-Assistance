plugins {
    kotlin("jvm") version "2.2.0"
    kotlin("plugin.serialization") version "2.2.0"
}
kotlin {
    jvmToolchain(17)
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11) }
}
java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}
dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("com.squareup.okhttp3:okhttp-tls:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
    testImplementation(kotlin("test-junit5"))
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.12.2")
}
tasks.test { useJUnitPlatform() }

val nativeRoot = projectDir.resolve("../native-core")
val nativeOut = layout.buildDirectory.dir("native-core")
val nativeResources = layout.buildDirectory.dir("native-resources")
val buildNativeCore by tasks.registering(Exec::class) {
    inputs.dir(nativeRoot.resolve("third_party")); inputs.dir(nativeRoot.resolve("src")); inputs.dir(nativeRoot.resolve("tests")); inputs.file(nativeRoot.resolve("CMakeLists.txt"))
    outputs.file(nativeOut.map { it.file("Release/orangecell_core.dll") })
    commandLine("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", projectDir.resolve("../../script/build-core.ps1"), "-BuildDir", nativeOut.get().asFile)
}
val copyNativeCore by tasks.registering(Copy::class) {
    dependsOn(buildNativeCore)
    from(nativeOut.map { it.file("Release/orangecell_core.dll") }); into(nativeResources.map { it.dir("native") })
}
sourceSets.main { resources.srcDir(nativeResources) }
tasks.processResources { dependsOn(copyNativeCore) }
