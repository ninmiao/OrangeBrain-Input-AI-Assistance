# Zephyr Input · 微风输入法

**License: [GPL-3.0-or-later](LICENSE)** · [授权范围与第三方例外 / Scope and third-party exceptions](LICENSE-NOTICE.md)

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

## 看看它能做什么 · See it in action

下面是用于说明功能的输入与**预期候选示例**，不是每个模型、每次请求都能复现的实测承诺。结果受模型、上下文和设置影响；请先用你选定的 Policy 测试。

These are **illustrative inputs and intended candidates**, not guaranteed outputs or benchmark results. Try them with your chosen policy; models, context, and settings affect the result.

| 场景 / Scenario | 模式 / Mode | 你输入 / You type | 预期候选 / Intended candidate |
| --- | --- | --- | --- |
| 不完美的长拼音 / Imperfect pinyin | 中文 / Chinese | `fanfaxisizhazheng` | `反法西斯战争` |
| 字母错序 / Transposed letters | 中文 / Chinese | `nihoa shijie` | `你好世界` |
| 漏输与错序 / Missing and swapped letters | EN | `I wnated to recieve teh package` | `I wanted to receive the package` |
| 重复与邻键误触 / Repeated letters and adjacent-key errors | EN | `I reallly loce this` | `I really love this` |
| 中文里保留英语 / Keep English inside Chinese | 中文 / Chinese | `wo jintian you meeting` | `我今天有 meeting` |
| 混输统一成英文 / Turn mixed input into English | EN | `wo jintian you meeting` | `I have a meeting today` |
| 用空格标出词组 / Mark phrase boundaries | 中文 / Chinese | `hanbaowang haochi` | `汉堡王好吃` |
| 描述生成颜表情 / Describe a kaomoji | 中文 / Chinese | `颜 笑死` | `(„ಡωಡ„)` |

空格分词示例需要开启相应设置；颜表情短触发词适用于 Windows 1.5.5，当前 Android 1.4.0 安装包使用较早的触发规则，可输入 `颜表情 笑死`。模型可能生成不同但语义相近的表情。**候选由你确认后上屏**，不会把纠错当作自动改写已经提交的文字。

The phrase-boundary example requires that setting to be enabled. The short kaomoji trigger is available in Windows 1.5.5; the current Android 1.4.0 package uses the earlier trigger, such as `颜表情 笑死`. Equivalent expressions may vary. **You choose the candidate before committing it**; this is not automatic rewriting of text you have already submitted.

## 快速上手 · Quick start

### 1. 安装并切换输入法 · Install and select the keyboard

**Windows**

1. 下载 [Windows 1.5.5 安装包](dist/Zephyr-Input-Windows-1.5.5-Setup-x64.exe)，双击并允许 UAC 管理员授权。无需另装 Java 或 Kotlin。
2. 安装后注销再登录，通过系统输入法切换菜单选择 **Zephyr Input**。没有出现时，在 Windows 的“中文（简体，中国）→ 语言选项”中添加它。
3. 从开始菜单打开 **Zephyr Input** 设置。默认轻按 `Shift` 切换中英文，`Ctrl+Shift+T` 切换繁简；数字键选候选，`Enter` 默认提交原文。更多操作见 [Windows 使用说明](windows/README.md)。

Download and run the Windows installer, approve UAC, sign out and back in, then select Zephyr Input from the system input-method menu. Open settings from the Start menu. Tap `Shift` for Chinese/English, use number keys to select candidates, or `Enter` to commit the original input by default. Java is bundled.

**Android**

1. 下载 [Android 1.4.0 ARM64 APK](dist/Zephyr-Input-1.4.0-arm64-v8a-demo.apk)，允许浏览器或文件管理器安装该 APK。
2. 打开 Zephyr Input，按引导在系统中启用并选择输入法；首次词库部署请耐心等待。
3. 进入应用设置中的 **AI 辅助** 页面配置云端。只使用本地 Rime 输入时，不需要 API Key。

Install the ARM64 APK, enable and select Zephyr Input in Android's keyboard settings, and let the initial dictionary deployment finish. Open **AI 辅助 / AI assistance** for cloud configuration. Local Rime input does not require an API key.

### 2. 准备 API Key 与模型 · Set up an API key and model

**一个 Policy 就是一套“接口 + Key + 模型 + 参数 + 提示词”。** OpenAI 和 OpenRouter 的 Key 不通用；填写自己账号有权限、余额或配额可用的模型，不能只写显示昵称。内置默认值也不保证你的账号有权限调用。

**A policy bundles an endpoint, key, model, parameters, and prompts.** OpenAI and OpenRouter keys are not interchangeable. Use the exact model ID available to your API account, with sufficient quota or credit; a friendly display name is not a model ID. Preset defaults do not guarantee account access.

| 配置 / Setting | OpenAI | OpenRouter |
| --- | --- | --- |
| Key 管理 / Key management | [OpenAI API Keys](https://platform.openai.com/api-keys) | [OpenRouter Keys](https://openrouter.ai/settings/keys) |
| 完整接口地址 / Full endpoint | `https://api.openai.com/v1/chat/completions` | `https://openrouter.ai/api/v1/chat/completions` |
| 模型 / Model | 从更新后的列表选择或填完整模型 ID / Select or enter the exact model ID | 从列表选择或复制目录中的完整 ID，通常为 `作者/模型` / Full catalog ID, usually `author/model` |
| 提供商 / Provider | 留空 / Leave blank | 可选 Auto；也可刷新后选择该模型的供应商 / Auto, or refresh and select a provider for that model |
| 思考 / Reasoning | 使用该模型支持的选项 / Use a supported value | 使用该模型与路由支持的选项 / Use a value supported by the model and route |
| 速度 / Speed | `default` 为普通速度；`priority` 仅在支持时使用 / Default, or priority if supported | 默认路由先验证可用，再按需要调整 / Verify the default route before tuning |

此客户端使用 **Chat Completions**：请填完整地址，不是网站首页、只有 `/v1` 的根地址或 `/responses`。接口参考：[OpenAI Chat API](https://developers.openai.com/api/reference/resources/chat)、[OpenRouter Chat Completions](https://openrouter.ai/docs/api-reference/chat-completion)。`omit` / 服务端默认表示“不发送该参数”，**不等于无思考**；选项不可用时不要强行填写。提示词已有内置默认值，初次配置不需要修改。

This client uses **Chat Completions**: enter the full endpoint, not the website URL, a bare `/v1` base URL, or `/responses`. `omit` / server default means the parameter is not sent; **it does not mean reasoning is disabled**. Keep the built-in prompts for your first setup.

### 3. 保存、应用、测试 · Save, apply, and test

**Windows**

1. 在顶部 Policy 列表选一项，到 **Policies / 策略** 页填写接口、模型和 API Key。
2. 点击 **Save policy / 保存 Policy**。Key 输入框保存后会清空，这是正常行为；相同接口下留空会保留已存 Key。
3. 点击 **Update models / 更新模型列表**，选择模型并检查思考、速度、供应商设置，再保存。列表也允许手动输入完整模型 ID。
4. 点击顶部 **Apply policy / 应用此 Policy**，确认目标项出现绿色“正在使用”标记。**仅选中或保存，不会切换正在使用的 Policy。**
5. 在 **Input / 输入** 勾选 **Enable cloud AI / 启用云端 AI**，点击 **Save settings / 保存设置**。然后到 Policy 页点击 **Test latency / 测试当前 Policy**，通过后在文本框试输上面的示例。

On Windows, edit the endpoint, model, and key in **Policies**, then **Save policy**. A cleared key field after saving is normal. Use **Update models** or type an exact ID, check parameters, and save again. Click **Apply policy** to switch—the active row turns green. Enable cloud AI in **Input**, save settings, and run **Test latency**. Selecting or saving a policy alone does not activate it.

**Android**

1. 打开 **AI 辅助 → 编辑目标 Policy**，点击 **验证身份并配置连接 / 密钥**。先设置手机锁屏密码或 PIN，按系统提示验证后保存地址和 Key。
2. 打开该 Policy 的模型参数设置，选择或填写模型，并检查思考强度、速度及 OpenRouter 供应商，保存修改。
3. 返回 Policy 列表，**勾选要使用的 Policy**；开启云端 AI 并确认输入会发送到所选 API 的提示。
4. 点击 **测试当前 Policy 延迟** 或列表里的 **测试延迟**；确认成功后再开始输入。

On Android, open **AI assistance → Edit policy**, authenticate to save the endpoint and key, then configure the model and parameters. Return to the policy list, select the policy, enable cloud AI with consent, and run its latency test. Device screen-lock authentication is required for credential configuration.

**第一次没成功？** 先确认已开启云端 AI、正确 Policy 已应用，再检查 Key 是否属于对应平台、完整模型 ID 是否可用、参数是否受支持。OpenRouter 固定供应商不可用时可改为 Auto 再测。延迟测试会发送真实请求，可能产生费用；离线候选正常并不表示云端连接已成功。

**Not working yet?** Check cloud AI is enabled, the intended policy is active, and the key, exact model ID, and parameters are valid for that service. If a pinned OpenRouter provider is unavailable, try Auto. Latency tests make real API requests and may incur charges; working offline candidates do not prove the cloud connection is working.

## 许可证 · License

Zephyr 原创代码与文档采用 **GPL-3.0-or-later**，允许商用、修改和分发；分发受 GPL 覆盖的修改版或安装包时，应按许可证提供对应源码并保留署名。第三方组件继续遵循原许可证，特别是雾凇词库的 **GPL-3.0-only**。完整正文见 [LICENSE](LICENSE)，详细适用范围见 [LICENSE-NOTICE.md](LICENSE-NOTICE.md)。

Zephyr's original code and documentation use **GPL-3.0-or-later**. Commercial use, modification, and redistribution are permitted; distribution of GPL-covered works requires complying with corresponding-source and notice obligations. Third-party licenses remain intact, including **GPL-3.0-only** for the bundled Rime Ice dictionaries. See the [license text](LICENSE) and [scope notice](LICENSE-NOTICE.md).

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
