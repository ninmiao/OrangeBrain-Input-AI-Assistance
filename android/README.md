# Android

从项目首页下载 ARM64 APK，安装并启用 Zephyr Input。键盘顶部显示中英文尚未上屏的输入。填好 Policy 并允许使用云端 AI 后，点候选栏左侧的星光可手动召唤助手。

从项目根运行 `./android/script/build-zephyr.ps1 -Variant demo -Abis arm64-v8a`。输出在 `android/app/build/outputs/apk/demo/`。应用模块在 `app/`，Gradle 逻辑在 `build-logic/`。构建环境和依赖准备见 [开发说明](../docs/DEVELOPMENT.md)。
