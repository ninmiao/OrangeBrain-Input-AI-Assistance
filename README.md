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

Android 当前版本 1.3.4 位于 `android/`，应用标识及用户配置保持兼容。Windows 1.4.2 为开发预览，基于开源 Weasel、librime、雾凇词库与 OpenCC；设置使用 Kotlin/JVM + Swing，安装包内置 Java 运行时。

Windows **中英文都先组合输入、显示候选，再选择上屏**。支持空格分词、固定一个 AI 候选、可设置回车/空格原文提交、候选翻页、简繁转换、独立 Policy 与双 API 测速。中文修复拼音并保留英文；英文修正英语并将混输转换为英语。API 请求在单独进程执行。

- [Android 1.3.4：提供商路由设置位置](docs/ai/zephyr-1.3.4.md)
- [Windows 使用、安装和快捷键](windows/README.md)
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
./windows/scripts/package.ps1
```

开发工具、下载依赖、生成语料和构建缓存不提交仓库；它们保存在被忽略的 `.tools/`、构建目录和 `tests/corpus/generated/`。`dist/` 只提交最新版 Android APK 与 Windows ZIP，旧发布包和解压目录不保留。实际 API Key 仅保存在设备加密凭据中。许可证及开源来源说明必须随源码和发布包保留。

## 最新安装包

- [Android 1.3.4 ARM64](dist/Zephyr-Input-1.3.4-arm64-v8a-demo.apk)
- [Windows 1.4.2 preview x64](dist/Zephyr-Input-Windows-1.4.2-preview-x64.zip)

Windows ZIP 解压后运行 `Install.cmd`。后续更新版本时同步 `.gitignore` 的两个文件名，并删除 `dist/` 中的旧版本。
