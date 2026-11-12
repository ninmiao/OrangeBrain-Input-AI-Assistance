# Zephyr Input · 微风输入法

[下载 Windows 版](dist/Zephyr-Input-Windows-1.5.5-Setup-x64.exe) · [下载 Android 版](dist/Zephyr-Input-1.4.0-arm64-v8a-demo.apk) · [GPL-3.0-or-later](LICENSE)

我想要一个打字快、隐私设置清楚、也能看懂手滑拼音的输入法，于是做了 Zephyr，自己日常用。欢迎来当小白鼠，遇到问题提个 Issue 就好。

Zephyr 是基于 **Rime** 的中文拼音输入法，目前有 **Windows 和 Android** 两个版本。离线用雾凇词库，联网后用 **LLM 和提示词**补足词库匹配：修正漏输、重复、错序和邻键误触，处理长拼音和中英文混输，也可以按描述生成颜表情。

中文模式下，拼音转汉字，英语保留并纠错；英文模式下，优先纠正英语，把中文、拼音或混输转成英文。两种模式都有候选区，每次请求返回一个 AI 候选，由你选中上屏。

云端支持 **OpenAI 和 OpenRouter**。模型、思考强度、速度和供应商都可以自己选，也可以保存成多个 Policy 随时切换。纠错能有多强、等待有多短，取决于模型的能力，以及你的钱包（笑）。

本地输入可离线使用。开启云端 AI 后，输入及设置范围内的前后文会发送给所选 API 服务，Key 加密保存在设备上。

### English

I built Zephyr for my own daily typing: fast pinyin input, clear privacy controls, and some tolerance for clumsy fingers. You're welcome to be a guinea pig too—open an issue when something feels off.

**Zephyr Input** is a **Rime-based pinyin keyboard for Windows and Android**. It uses Rime Ice dictionaries offline and adds **LLM assistance** for missing letters, repeated characters, swapped letters, nearby-key mistakes, long pinyin, and mixed Chinese–English input. It can also turn a short description into a kaomoji.

Chinese mode converts pinyin to Chinese while keeping and correcting English. English mode corrects English and translates Chinese, pinyin, or mixed input into English. Both modes show candidates; each AI request returns one suggestion for you to select.

Cloud assistance supports **OpenAI and OpenRouter**, with separate policies for models, reasoning effort, speed, and provider routing. The quality depends on the model—and your wallet. Local typing works offline; cloud AI sends your input and configured surrounding context to your chosen API service. Keys are encrypted on your device.

## 输入示例 · Examples

下面展示想要的纠错和混输效果，具体措辞随模型与上下文变化。

These examples show the intended corrections. Wording varies with the model and context.

| 输入 / Input | 模式 / Mode | 候选示例 / Example candidate |
| --- | --- | --- |
| `fanfaxisizhazheng` | 中文 / Chinese | 反法西斯战争 |
| `nihoa shijie` | 中文 / Chinese | 你好世界 |
| `I wnated to recieve teh package` | EN | I wanted to receive the package |
| `I reallly loce this` | EN | I really love this |
| `wo jintian you meeting` | 中文 / Chinese | 我今天有 meeting |
| `wo jintian you meeting` | EN | I have a meeting today |
| `hanbaowang haochi` | 中文，空格分词 / Chinese, phrase boundaries | 汉堡王好吃 |
| `颜表情 笑死` | 中文 / Chinese | („ಡωಡ„) |

Windows 还可以用 `颜 笑死` 或 `表情 笑死` 生成颜表情。Android 1.4.0 使用 `颜表情` 开头的写法。

Windows also accepts the shorter `颜` and `表情` prefixes. Use `颜表情` with Android 1.4.0.

## 安装 · Installation

| 平台 / Platform | 安装包 / Download |
| --- | --- |
| Windows x64 | [1.5.5 Setup EXE](dist/Zephyr-Input-Windows-1.5.5-Setup-x64.exe) |
| Android ARM64 | [1.4.0 APK](dist/Zephyr-Input-1.4.0-arm64-v8a-demo.apk) |

**Windows：**运行安装包并允许管理员授权，程序安装到 `C:\Program Files\Zephyr Input`，已包含 Java 运行时。安装后注销再登录，从系统输入法菜单选择 Zephyr Input；也可以到“中文（简体，中国）→ 语言选项”添加。开始菜单中的 Zephyr Input 打开设置。更新时运行新版安装包，卸载使用系统“已安装的应用”入口。

**Android：**安装 APK，打开应用，按引导启用并选择 Zephyr Input。首次启动会部署词库。API 配置在设置中的“AI 辅助”页面。

**Windows:** run Setup and approve UAC. Java is included. Sign out and back in, select Zephyr Input from the system input-method menu, and open settings from the Start menu. Run a newer installer to update; uninstall through Windows Settings.

**Android:** install the APK, open the app, and follow the keyboard setup. Let the initial dictionary deployment finish. Cloud settings are under **AI 辅助 / AI assistance**.

## 配置 API 和模型 · API and model setup

一个 **Policy** 保存一套接口、Key、模型、参数和提示词。先配置一套能正常调用的，再按需要复制、调整。

A **policy** holds an endpoint, key, model, parameters, and prompts. Set up one working policy first, then copy or adjust it as needed.

| 配置 / Setting | OpenAI | OpenRouter |
| --- | --- | --- |
| API Key | [创建 Key / Create a key](https://platform.openai.com/api-keys) | [创建 Key / Create a key](https://openrouter.ai/settings/keys) |
| 完整接口地址 / Endpoint | `https://api.openai.com/v1/chat/completions` | `https://openrouter.ai/api/v1/chat/completions` |
| 模型 / Model | 选择或输入账号可用的完整模型 ID / Exact model ID available to your account | 选择或输入完整 ID，通常为 `作者/模型` / Full ID, usually `author/model` |
| 供应商 / Provider | 留空 / Leave blank | Auto，或刷新列表后指定 / Auto, or select from the refreshed list |

两家平台各用自己的 Key。思考强度按模型可用选项选择，速度可以先用普通模式。`omit` 表示交给服务端决定；关闭思考需要模型支持相应选项。提示词可以直接用内置版本。

Each service needs its own key. Choose a supported reasoning setting and start with normal speed. `omit` leaves the parameter to the server; disabling reasoning requires model support. The built-in prompts are ready to use.

### Windows

1. 在顶部列表选择 Policy，进入 **Policies / 策略** 页，填写接口、模型和 Key，点击 **Save policy / 保存 Policy**。
2. 点击 **Update models / 更新模型列表**，选择或手填完整模型 ID，检查思考、速度及供应商，再保存。
3. 点击顶部 **Apply policy / 应用此 Policy**。绿色“正在使用”标记表示当前实际配置；选中其他项可以单独编辑。
4. 在 **Input / 输入** 页开启 **Enable cloud AI / 启用云端 AI**，保存设置。
5. 点击 **Test latency / 测试当前 Policy**，确认连接后开始输入。测试会发送一次 API 请求，按服务商规则计费。

Key 保存后输入框会清空，之后在同一接口下留空即可保留。顶部也可以删除 Policy，或在策略页复制一份连同 Key 一起调整。

Select a policy, enter its endpoint, model, and key in **Policies**, then **Save policy**. Use **Update models** to refresh the list or enter a full ID, check the parameters, and save. Click **Apply policy** to activate it—the active row is green. Enable cloud AI in **Input**, save settings, and run **Test latency**. Saved keys are hidden; leaving the key field empty keeps the existing key for that endpoint. Latency tests make a real request billed by the API service.

### Android

1. 进入 **AI 辅助 → 编辑 Policy → 验证身份并配置连接 / 密钥**，用手机锁屏验证后保存地址和 Key。
2. 打开该 Policy 的模型参数设置，填写模型，调整思考强度、速度和供应商。
3. 返回列表，勾选这个 Policy，开启云端 AI。
4. 点击 **测试延迟** 检查连接，之后就可以在键盘里使用。

Open **AI assistance → Edit policy**, authenticate with your device screen lock, and save the endpoint and key. Configure the model and parameters, select the policy in the list, enable cloud AI, and run its latency test.

连接失败时，依次检查 Key、账号额度、完整模型 ID 和参数；OpenRouter 固定供应商连接失败时，可以切回 Auto 测试。

If a request fails, check the key, account quota, model ID, and parameters. Try Auto routing if a pinned OpenRouter provider is unavailable.

## 日常使用 · Typing

Windows 默认轻按 `Shift` 切换中英文，`Ctrl+Shift+T` 切换繁简；数字键选择候选，`Enter` 提交原文。快捷键和原文提交方式都可以在设置中修改。Android 使用键盘上的中英、繁简切换键，点击候选上屏。

On Windows, tap `Shift` for Chinese/English and use `Ctrl+Shift+T` for simplified/traditional Chinese. Number keys select candidates; `Enter` commits the original input. These controls are configurable. On Android, use the keyboard's language and script buttons and tap a candidate to commit it.

完整操作见 [Windows 使用说明](windows/README.md)。两端均支持 Policy 复制和延迟测试。

See the [Windows guide](windows/README.md) for more controls. Both clients support policy copying and latency tests.

## 开发 · Development

Android 前端基于同文，Windows 前端基于小狼毫，两端通过 Kotlin 共享 AI 请求、提示词和模型参数逻辑。

The Android frontend builds on Trime and the Windows frontend on Weasel. The Kotlin module shares AI requests, prompts, and model configuration between them.

| 目录 / Directory | 内容 / Contents |
| --- | --- |
| `android/` | Android 应用、原生引擎、词库和测试 / Android app, native engine, dictionaries, and tests |
| `windows/` | TSF 输入法、AI Broker、设置界面和安装器 / TSF frontend, AI broker, settings, and installer |
| `shared/ai-core/` | 共享 AI 逻辑与提示词 / Shared AI logic and prompts |
| `tests/corpus/` | 中英文错输语料与生成工具 / Chinese–English typo corpus and generator |
| `dist/` | 当前安装包 / Current installers |

- [开发环境与构建 / Build instructions](docs/DEVELOPMENT.md)
- [Windows 测试记录 / Windows validation](docs/windows/VALIDATION.md)
- [Android 测试记录 / Android validation](docs/ai/number-row-providers-1.4.0.md)
- [纠错测试语料 / Correction corpus](tests/corpus/README.md)
- [发布说明 / Publishing](docs/PUBLISHING.md)

## 开源致谢 · Acknowledgements

感谢 Rime、同文、小狼毫和各个词库及依赖项目的作者。Zephyr 的输入引擎、平台接入和离线词库来自这些项目。

Thanks to the authors and maintainers of Rime, Trime, Weasel, and the dictionaries and libraries below.

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

雾凇词库快照为 `99662ba01e3affa6a0f009174ca530b887bac3b6`，词表来源署名保留在各文件头中。接入范围和修改见 [NOTICE](android/app/src/main/assets/shared/licenses/rime-ice/NOTICE.txt)。其他组件及依赖详见 [Windows 组件说明](windows/THIRD-PARTY.md)、[Android 依赖](gradle/libs.versions.toml) 和各组件的 LICENSE 文件。

The Rime Ice snapshot is `99662ba01e3affa6a0f009174ca530b887bac3b6`; dictionary headers retain their original source credits. See the [integration notice](android/app/src/main/assets/shared/licenses/rime-ice/NOTICE.txt), [Windows component notes](windows/THIRD-PARTY.md), and [Android dependencies](gradle/libs.versions.toml) for details.

## 许可证 · License

Zephyr 原创代码与文档采用 **GPL-3.0-or-later**，允许使用、修改、商用和分发。分发受 GPL 覆盖的版本时，须按许可证提供对应源码并保留声明。第三方组件按各自许可证提供，雾凇词库为 **GPL-3.0-only**。

Zephyr's original code and documentation use **GPL-3.0-or-later**, permitting use, modification, commercial use, and redistribution. Distribution of GPL-covered works carries corresponding-source and notice obligations. Third-party components retain their own licenses; Rime Ice dictionaries use **GPL-3.0-only**.

[许可证正文 / License text](LICENSE) · [授权范围 / Licensing details](LICENSE-NOTICE.md)
