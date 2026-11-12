# Zephyr Input · 微风输入法

**Rime 的离线底座，LLM 的理解力：让拼音、英文和手滑一起被读懂。**

**Rime underneath, LLM assistance on top—for pinyin, English, and the typos in between.**

做好中文拼音输入法并不容易，尤其当你既想打得快，又在意隐私，还不想每天和词库、选词以及手滑斗智斗勇。于是，我做了 **Zephyr Input**，先解决自己的日常输入需求，也欢迎你来当一位友善的“小白鼠”——一起试用、挑毛病，让微风吹得更顺一点。

Zephyr 基于 **Rime**，目前提供 **Android 和 Windows** 客户端。它保留本地词库与离线候选，再通过 **LLM + 精简 prompts** 理解输入意图，补足传统词库匹配的局限：拼音不必每次都敲得完美，中英文也不必总是分开输入。云端目前支持 **OpenAI 与 OpenRouter API**，可以通过独立 Policy 配置模型、Key、思考强度、速度和 OpenRouter 供应商。

- **LLM 拼音匹配与纠错**：结合上下文处理漏输、错输、重复字符、字母错序和邻键误触，尽量还原你原本想说的话，而不只是寻找字面完全匹配的词条。
- **中英文混输**：中文模式将拼音转为汉字，并保留、纠正英文；英文模式优先纠正英文，将明确的中文、拼音或中英混输转成英文。两种模式都使用候选界面。
- **少选词，少打断**：每次请求只返回一个最可能的 AI 候选，控制输出 token；本地 Rime 候选仍然可用。
- **不止打字，还有颜表情**：用描述让 LLM 生成 kaomoji，例如 `颜 笑死` → `(„ಡωಡ„)`。触发规则以客户端版本为准，见下方安装包说明。
- **模型由你选，预算由你定**：支持多 Policy、延迟测试及模型参数配置。纠错和拼音匹配究竟能有多强？取决于模型的本事，也取决于你的钱包愿不愿意配合（笑）。不同模型的准确率、速度和费用会有差异。

**关于隐私：**本地 Rime 候选不需要云端模型。启用云端 AI 后，输入内容及所配置的前后文会发送到你选择的 API 服务；Key 在设备本地加密保存。你可以关闭云端 AI，继续使用离线输入。这是可选择的取舍，不是“用了云端也绝不上传输入”的承诺。

### English

Building a good Chinese pinyin input method is surprisingly hard—especially when you care about both speed and privacy, and would rather write than wrestle with dictionaries, candidate lists, and typos. I built **Zephyr Input** for my own daily use. You are welcome to join as a friendly test pilot, too: bring your imperfect typing and help make the breeze a little smoother.

Built on **Rime**, Zephyr currently runs on **Android and Windows**. It keeps local dictionaries and offline candidates, then adds **LLMs and concise prompts** to interpret what you meant beyond exact dictionary matches. Pinyin does not have to be perfect, and Chinese and English do not have to stay in separate boxes. Cloud assistance supports the **OpenAI and OpenRouter APIs**, with independent policies for models, keys, reasoning effort, speed, and OpenRouter provider routing.

- **LLM-assisted pinyin matching and correction:** use context to recover missing or wrong letters, repetitions, swapped letters, and nearby-key mistakes—not just look up an exact spelling.
- **Mixed Chinese–English input:** Chinese mode converts pinyin to Chinese while preserving and correcting English. English mode prioritizes English correction and translates recognizable Chinese, pinyin, or mixed input into English. Both modes offer a candidate interface.
- **Less candidate hunting:** each AI request returns one likely result to limit output tokens, while local Rime candidates remain available.
- **A little personality:** describe an expression and let the model produce a kaomoji, such as `颜 笑死` → `(„ಡωಡ„)`. Trigger support depends on the client release; see the package notes below.
- **Your model, your budget:** multiple policies, latency tests, and model controls let you choose your trade-offs. How strong is the correction? That depends on your model—and how cooperative your wallet feels. Accuracy, latency, and cost vary.

**Privacy:** local Rime candidates do not require a cloud model. Enabling cloud AI sends your input and configured surrounding context to the API service you choose; API keys are encrypted locally on your device. You can turn cloud assistance off and continue typing offline. Cloud assistance is an explicit trade-off, not a promise that your input never leaves your device.

### 开源致谢与引用 · Open-source acknowledgements

Zephyr 建立在以下项目的工作之上。感谢原作者、维护者和词库贡献者；本项目的 AI 辅助与平台改动并不替代他们的署名。

Zephyr builds on the projects below. Credit belongs to their authors, maintainers, and dictionary contributors; our AI integration and platform changes do not replace their attribution.

| 项目 / Project | 在 Zephyr 中的作用 / Role | 许可证及本地说明 / License & local notices |
| --- | --- | --- |
| [Rime / librime](https://github.com/rime/librime) | 两端离线输入引擎 / Offline input engine | BSD-3-Clause · [LICENSE](android/app/src/main/jni/librime/LICENSE) |
| [同文 / Trime](https://github.com/osfans/trime) | Android 输入法前端与项目基础 / Android IME foundation | GPL-3.0-or-later · 保留原始源码署名 / Original source headers retained · [LICENSE](LICENSE) |
| [小狼毫 / Weasel](https://github.com/rime/weasel) | Windows TSF 前端与输入服务 / Windows TSF frontend and service | GPL-3.0-or-later · [LICENSE](windows/native/LICENSE.txt) · 上游快照 / Snapshot: `f96ed24a8a535961b6ffc7160d98851a69cee4f8` |
| [雾凇拼音 / Rime Ice](https://github.com/iDvel/rime-ice) | 简体拼音词库与方案规则 / Simplified Chinese dictionaries and spelling rules | GPL-3.0-only（上游声明 / upstream declaration）· [LICENSE](android/app/src/main/assets/shared/licenses/rime-ice/LICENSE.txt) · [来源与快照 / NOTICE](android/app/src/main/assets/shared/licenses/rime-ice/NOTICE.txt) |
| [OpenCC](https://github.com/BYVoid/OpenCC) | 简繁转换 / Simplified–traditional conversion | Apache-2.0 · [LICENSE](android/app/src/main/jni/OpenCC/LICENSE) |
| [Boost](https://www.boost.org/) | 原生 C++ 依赖 / Native C++ dependencies | BSL-1.0 · [LICENSE](android/app/src/main/jni/boost/LICENSE_1_0.txt) |
| [Kotlin](https://github.com/JetBrains/kotlin), [Coroutines](https://github.com/Kotlin/kotlinx.coroutines), [Serialization](https://github.com/Kotlin/kotlinx.serialization) | 共享 AI 逻辑、异步任务与 JSON / Shared AI logic, asynchronous work and JSON | Apache-2.0 · [共享模块依赖 / Shared dependencies](shared/ai-core/build.gradle.kts) |
| [OkHttp](https://github.com/square/okhttp) / [Okio](https://github.com/square/okio) | HTTPS 请求与 I/O / HTTPS transport and I/O | Apache-2.0 · [组件说明 / Component notes](windows/THIRD-PARTY.md) |
| [JNA](https://github.com/java-native-access/jna) | Windows 原生 API 互操作 / Windows native API access | Apache-2.0 / LGPL-2.1-or-later 双许可，本项目选用 Apache-2.0 / Apache-2.0 option used |
| [OpenJDK](https://openjdk.org/) | Windows 内置 Java 运行时与 Swing / Bundled Windows runtime and Swing UI | GPLv2 with Classpath Exception · 运行时法律声明随安装包提供 / Runtime legal notices included in the package |

雾凇使用快照为 `99662ba01e3affa6a0f009174ca530b887bac3b6`，包含 `8105`、`base`、`ext`、`tencent`、`others` 等词表；各词表原始来源保留在文件头中。本项目并未移植雾凇的完整 Lua、emoji 和反查功能包。

The Rime Ice snapshot above includes the `8105`, `base`, `ext`, `tencent`, and `others` dictionaries, with original word-source attribution retained in their headers. Zephyr does not ship the complete upstream Lua, emoji, and reverse-lookup feature bundle.

更多直接、间接及构建依赖见 [Windows 组件说明](windows/THIRD-PARTY.md)、[Android 依赖清单](gradle/libs.versions.toml)、[Android 原生源码](android/app/src/main/jni) 和 [Windows 依赖配置](windows/build.gradle.kts)。此表是主要组件索引，不替代各组件的 LICENSE、NOTICE 和源码署名；项目沿用 GPL-3.0-or-later，第三方组件按各自许可证提供。OpenAI 与 OpenRouter 是可选 API 服务，并非本项目包含的开源模型或官方背书。

For further direct, transitive, and build dependencies, see the linked manifests and component notices. This table is an index, not a replacement for individual licenses, notices, or source attribution. Zephyr retains GPL-3.0-or-later licensing, with third-party components under their respective terms. OpenAI and OpenRouter are optional API services, not bundled open-source models or endorsements of this project.

## 项目结构与使用 · Project structure and usage

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
