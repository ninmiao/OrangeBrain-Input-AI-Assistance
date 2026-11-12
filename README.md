# Zephyr Input

微风输入法 · Zephyr。Android 与 Windows 共用 AI 协议、提示词、模型能力和纠错回归数据；平台输入前端各自实现。

```text
Zephyr-Input/
├─ android/            Android 输入法、构建逻辑、原生源码、词库与测试脚本
├─ windows/            Windows TSF、输入服务、Kotlin AI Broker、桌面设置与安装脚本
├─ shared/ai-core/     双端共享 AI 核心及提示词
├─ tests/corpus/       中英文错输语料生成器与回归参考集
├─ docs/               开发环境、发布范围和当前版本验证
├─ gradle/             共用 Gradle wrapper 与 Android 版本目录
└─ script/             根目录构建入口
```

Android 当前版本 1.4.0 位于 `android/`，应用标识及用户配置保持兼容。Windows 1.5.5 提供一键安装、更新和卸载程序，基于开源 Weasel、librime、雾凇词库与 OpenCC；设置使用 Kotlin/JVM + Swing，安装包内置 Java 运行时。

Windows **中英文都先组合输入、显示候选，再选择上屏**。支持空格分词、固定一个 AI 候选、可设置回车/空格原文提交、候选翻页、简繁转换、独立 Policy 与双 API 测速。中文修复拼音并保留英文；英文修正英语并将混输转换为英语。API 请求在单独进程执行。

- [Android 1.4.0：数字行、数字混输和供应商列表](docs/ai/number-row-providers-1.4.0.md)
- [Windows 1.5.5：模型下拉选择与更新](docs/windows/model-picker-1.5.1.md)
- [Windows 1.5.0：正式安装程序与供应商列表](docs/windows/installer-providers-1.5.0.md)
- [Windows 使用、安装和快捷键](windows/README.md)
- [Windows 1.4.4：可配置语言快捷键](docs/windows/1.4.4-shortcuts.md)
- [Windows 1.4.3：候选窗崩溃修复](docs/windows/1.4.3-candidate-crash.md)
- [Windows 1.4.2 / Android 1.3.3：短提示词与原文提交](docs/windows/1.4.2-short-prompts.md)
- [开发环境及可复现构建](docs/DEVELOPMENT.md)
- [本次 Windows 测试结果与未验收项](docs/windows/VALIDATION.md)
- [中英文纠错测试库](tests/corpus/README.md)
- [源码发布范围](docs/PUBLISHING.md)

```powershell
# Android：JDK 17 + SDK / NDK
./script/build-android.ps1 -Variant demo -Abis arm64-v8a
# Windows：JDK 17 + VS 2022 C++ / ATL；首次先准备依赖
python windows/scripts/prepare-deps.py
./windows/scripts/build-native.ps1
./windows/scripts/package.ps1 -Destination ./.tools/release-image
./windows/scripts/build-installer.ps1 -Image ./.tools/release-image/ZephyrSettings
```

开发工具、下载依赖、生成语料和构建缓存不提交仓库；它们保存在被忽略的 `.tools/`、构建目录和 `tests/corpus/generated/`。`dist/` 只提交最新版 Android APK 与 Windows Setup EXE，旧发布包和解压目录不保留。实际 API Key 仅保存在设备加密凭据中。许可证及开源来源说明必须随源码和发布包保留。

## 最新安装包

Windows 1.5.5 新增可输入的模型下拉框与更新按钮，并包含提示词包 3.1.1 的“颜/表情/颜表情”触发规则；Android 1.4.0 安装包尚未包含这条提示词修改。

- [Android 1.4.0 ARM64](dist/Zephyr-Input-1.4.0-arm64-v8a-demo.apk)
- [Windows 1.5.5 一键安装版 x64](dist/Zephyr-Input-Windows-1.5.5-Setup-x64.exe)

Windows 双击 Setup EXE 并允许管理员授权，自动安装到系统 Program Files；后续运行新版 Setup 覆盖更新，在系统“已安装的应用”中卸载。后续更新版本时同步 `.gitignore` 的两个文件名，并删除 `dist/` 中的旧版本。
