# 开发环境与工具

本仓库只提交应用/core 源码、测试、词库、构建脚本、Gradle wrapper、必要的原生依赖源码及许可证。开发工具安装在本机，不随仓库上传。

## 环境版本

| 工具 | 项目要求 |
| --- | --- |
| JDK | 17（可使用 Temurin 17） |
| Android SDK Platform | android-35 |
| Android Build Tools | 35.0.0 |
| Android NDK | 28.0.13004108 |
| CMake | 3.31.6 |
| Python | Python 3，加入 PATH |
| Git | 原生构建使用 git apply 应用补丁 |
| Gradle | 使用仓库中的 gradlew / gradlew.bat，不需全局安装 |
| Boost | 1.89.0，由 CMake 下载并校验 SHA256 |

版本来源：app/build.gradle.kts、build-logic/convention/src/main/kotlin/Versions.kt、gradle/wrapper/gradle-wrapper.properties 和 app/src/main/jni/cmake/Boost.cmake。

## 安装和构建（Windows）

1. 安装 JDK 17、Git、Python 3。通过 Android Studio 的 SDK Manager 或 Android command-line tools 安装 SDK。
2. 配置 `JAVA_HOME` 为 JDK 根目录，`ANDROID_HOME` 为 SDK 根目录；将 Python、Git、SDK platform-tools 放入 PATH。
3. SDK command-line tools 可执行：

```powershell
sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;28.0.13004108" "cmake;3.31.6"
./script/build-zephyr.ps1 -Variant demo -Abis 'arm64-v8a,x86_64'
```

也可以使用本地 `.tools/jdk/<JDK目录>/` 与 `.tools/android-sdk/`，构建脚本会自动识别。首次构建需联网下载 Gradle/Maven 依赖与 Boost。脚本会重新生成原生插件 junction，勿将这些本机链接提交到仓库。

APK 位于 `app/build/outputs/apk/demo/`。`dist/` 用于本地整理发布包，应作为 Release 附件上传，不提交 Git。

## 模拟器和测试

在 Android Studio Device Manager 创建 API 35 x86_64 模拟器并启动。运行核心测试：`./gradlew.bat :ai-core:test`。

```powershell
python -m pip install cryptography
./script/test-android.ps1
```

现有模拟器脚本使用 `.tools/android-sdk/` 中的 adb，以及默认 serial `emulator-5554`。若使用外部 SDK，请调整脚本路径或在 `.tools/android-sdk` 配置本地目录链接。`start-emulator.ps1` 仅适用于 `.tools/avd` 中已创建的 `RimeAI_Test` AVD；不会自动创建模拟器。

本地 HTTPS 测试证书/私钥由 setup-test-server.py 重新生成，测试服务只使用假凭据。真实 API Key 在手机设置中保存，不放入源码、文档或安装包。真机安装使用 ARM64 demo APK；不要对日常手机运行会改写测试配置的模拟器回归。

## 上传范围

`.gitignore` 排除 SDK/JDK/AVD、Boost 下载目录、IDE 状态、构建缓存、APK、日志与密钥。本机文件保留，因此可继续开发。其余原生依赖源码必须随仓库提交，不能把整个 jni 或 librime/deps 排除。AUTHOR/LICENSE 及各依赖许可证一并保留。
