# Zephyr Input · 微风输入法

[Windows 1.12.5 x64](dist/Zephyr-Input-Windows-1.12.5-Setup-x64.exe) · [Android 1.10.3 ARM64](dist/Zephyr-Input-1.10.3-arm64-v8a-demo.apk) · [SHA-256](dist/SHA256SUMS) · [GPL-3.0-or-later](LICENSE)

我想要一个打字快、隐私设置清楚、也能看懂手滑拼音的输入法，于是做了 Zephyr，自己日常用。欢迎来当小白鼠，遇到问题提个 Issue 就好。

**目前还是原型，请谨慎使用。** 虽然我已经在日常使用，但还有不少地方要打磨。已精简提示词和候选输出，但长输入和模型思考的 token 消耗仍可能比较大，建议先用小型模型试试。我用 Luna 和 Qwen3.8 27B 测下来效果还不错。

Zephyr 是基于 **Rime** 的中文拼音输入法，目前有 **Windows 和 Android** 两个版本。自带万象和雾凇两套离线词表，默认使用万象，支持从 GitHub 一键更新及单独下载万象语法模型；联网后调用 **在线 LLM API**，通过提示词补足词库匹配：修正漏输、重复、错序和邻键误触，处理长拼音和中英文混输，还能在候选栏里给出简短答案、建议、续写、术语和颜表情。

在线 AI 的中文模式将拼音转为汉字，英语保留并纠错；英文模式优先纠正英语，把中文、拼音或混输转成英文。自动纠错给出一个候选，助手模式还会给出第二个候选。你也可以只在需要时手动召唤助手。

云端支持 **OpenAI、OpenRouter 和 Google Gemini**。可以把接口、Key、模型和参数保存成多个 Policy 随时切换；OpenRouter 支持供应商路由。纠错能有多强、等待有多短，取决于模型的能力，以及你的钱包（笑）。

**LLM 功能需要联网，模型在 OpenAI、OpenRouter 或 Google Gemini 的远程服务端运行，不在手机或电脑本地运行。** 离线输入使用 Rime 和本地词库。开启云端 AI 后，当前输入及已启用的前后文会发送给所选 API 服务，Key 加密保存在设备上。

### English

I built Zephyr for my own daily typing: fast pinyin input, clear privacy controls, and some tolerance for clumsy fingers. You're welcome to be a guinea pig too—open an issue when something feels off.

**This is still a prototype; please use it with care.** I use it daily, but there is plenty left to improve. Prompts and output are now shorter, but long input and model reasoning can still use plenty of tokens. Start with a smaller model; Luna and Qwen3.8 27B have worked fairly well in my own testing.

**Zephyr Input** is a **Rime-based pinyin keyboard for Windows and Android**. It bundles Wanxiang (the default) and Rime Ice dictionaries for offline typing, updates them from GitHub, offers a separate grammar-model download, and calls **online LLM APIs** for missing letters, repeated characters, swapped letters, nearby-key mistakes, long pinyin, and mixed Chinese–English input. Its assistant can also suggest a brief answer, advice, a continuation, a term, or a kaomoji directly in the candidate bar.

For online AI, Chinese mode converts pinyin to Chinese while keeping and correcting English. English mode corrects English and translates Chinese, pinyin, or mixed input into English. Auto correction offers one candidate. Assistant mode adds a second candidate, and you can also invoke it on demand.

Cloud assistance supports **OpenAI, OpenRouter, and Google Gemini**, with separate policies for keys, models, and parameters. OpenRouter also supports provider routing. The quality depends on the model—and your wallet. **LLM features require an internet connection: models run on remote services accessed through OpenAI, OpenRouter, or Google Gemini, not locally on your phone or computer.** Offline typing uses Rime and local dictionaries. Cloud AI sends your current input and enabled surrounding context to your chosen API service. Keys are encrypted on your device.


## Quickstart · 快速开始

1. **Windows**：下载安装器，运行并允许 UAC。选择 **Zephyr Input** 输入法，从开始菜单打开设置。
2. **Android**：下载 ARM64 APK，先按引导授予存储权限，再启用键盘，等待首次词库部署。
3. **在线 AI**：在 Policy 中填 API Key 并选模型，在 **AI 增强（自动）** 里选模式。Windows 点 **保存并生效**，Android 允许使用云端 AI。组字时按 **F8**（Windows）或点 **星光**（Android）也可手动请求。

Run Setup and approve UAC on **Windows**, or install the ARM64 APK, grant storage access, and enable the keyboard on **Android**. For online AI, add a key and model to your policy and choose a mode under **Automatic AI**. Save on Windows and grant cloud permission on Android. While composing, press **F8** or tap the **sparkle** for help on demand.

## 词表、本地模型与在线 AI · Local data and online AI

三者分别配置，可以配合使用。**不填 API Key 也能离线打字；下载后的万象语法模型同样离线工作。**

| 功能 / Feature | 用途 / Role | 获取与运行 / Installation and runtime |
| --- | --- | --- |
| **万象 / 雾凇词表 · Dictionaries** | 字词、拼音、词频，生成本地候选 / Words, readings and frequencies for local candidates | 两套内置，本机运行，各有 GitHub 更新按钮；无 Key、无 API token / Both bundled, local, independently updated; no API key or tokens |
| **万象语法模型 · Grammar model** | 用词语搭配统计改善万象候选排序 / Collocation statistics improve Wanxiang ranking | 约 **407 MB**，单独下载，本机运行；下载后离线、无 API token / Separate download, local and offline; no API tokens |
| **在线 AI · Online AI** | 纠错、中英混输、回答与续写 / Correction, mixed input, answers and continuation | 远程 LLM，配置 Key 与在线模型；需联网，按服务商规则计费 / Remote LLM; requires a key, internet and provider usage charges |

**万象语法模型是本地 n-gram 统计模型，不是本地 LLM。** 它只搭配万象词表；在线 AI 可搭配任一词表，也可单独关闭。本地词库不会因为关闭云端 AI 而停用。

**The Wanxiang grammar model is a local n-gram model, not a local LLM.** It works with Wanxiang only. Online AI runs on a remote service and can complement either dictionary; turning it off leaves local typing available.

## 输入预览 · Typing preview

这些实图展示纠错与本地候选；当前版本另外标注“纠错 / 助手”角色。 / These captures show correction alongside local candidates; current builds also label correction and assistant roles.

### Windows

<img src="docs/images/windows-input.png" alt="Windows 实际输入：错序拼音 nihoa，AI 候选为你好，下面保留 Rime 本地候选" width="860">

`nihoa` → **你好**。**AI / Rime** 标明在线与本地候选来源。

Real TSF input: online AI corrects `nihoa` to “你好” (hello), alongside local Rime candidates.

### Android

<img src="docs/images/android-keyboard.png" alt="真实在线 AI 纠错：输入 woyaochihuogu，本地候选为我要吃货古，下方 AI 候选为我要吃火锅" width="360">

模拟器实图：`woyaochihuogu`，本地“我要吃货古”，在线 AI“我要吃火锅”；点击候选上屏。

Real emulator capture: for `woyaochihuogu`, online AI suggests “我要吃火锅” (I want hotpot). Tap to commit.

## 输入示例 · Examples

候选示例，措辞随模型变化。 / Example suggestions; wording varies by model.

| 输入 / Input | 模式 / Mode | 候选示例 / Example candidate |
| --- | --- | --- |
| `wo yao chi huo gu` | 中文 / Chinese | 我要吃火锅 |
| `nihoa shijie` | 中文 / Chinese | 你好世界 |
| `I wnated to recieve teh package` | EN | I wanted to receive the package |
| `wo jintian you meeting` | 中文 / Chinese | 我今天有 meeting |
| `wo jintian you meeting` | EN | I have a meeting today |
| `hanbaowang haochi` | 中文，空格分词 / Chinese, phrase boundaries | 汉堡王好吃 |

### AI 助手 · Assistant

候选栏显示 AI 当前状态，关闭、等待、请求、生成及断线可区分；Windows 设置页可查看后台与最近请求，并一键重启服务（保留配置和 Key，取消未上屏文字）。Android 点击 AI 小圆点查看状态，设置页可重置请求。

The candidate area shows AI request status. Windows settings show background services and the last request, with a restart button that preserves settings and keys but cancels uncommitted text. On Android, tap the AI dot for details or reset requests in settings.

组字时，Windows 按 **F8**，Android 点候选栏左侧的星光图标，即可取消上一条请求并重新请求助手。Windows 可换成 F9、F10、Ctrl+Shift+F8 或关闭快捷键。Android 首次使用请在设置里允许云端 AI。

在 **AI 增强（自动）** 中选择 **无**、**仅纠错** 或 **AI 助手＋纠错**。选 **无** 时只响应手动触发。**仅纠错** 返回一个修正候选。**AI 助手＋纠错** 通过一次流式请求先显示纠错，再显示助手。Windows 修改后点击 **保存并生效**。

While composing, press **F8** on Windows or tap the sparkle on Android to cancel the previous request and request the assistant. **Automatic AI** offers **None**, **Correction only**, and **Assistant + correction**. **None** keeps manual requests available. In assistant mode, a single streaming request shows correction first and the assistant suggestion second. Windows also offers F9, F10, Ctrl+Shift+F8, and a disabled shortcut option.

| 当前输入 / Input | 前文 / Context | 助手候选示例 / Assistant example |
| --- | --- | --- |
| `zhejiushi` | `1 1 2 3 5 8 13 21 34 55 89 144…` | 斐波那契数列 |
| `o kaitoude 骨科医生相关专业词汇` | — | Orthopedist |
| `颜表情 笑死` | — | („ಡωಡ„) |

示例展示用途，具体答案和长度取决于模型。只有请求表情时才引导生成颜表情。中文模式允许中英混输；英文模式将两项都输出为英文（表情请求可生成颜表情）。模型未完整返回第二项时，仍保留完整的纠错候选。

Examples illustrate the feature; answers and length depend on the model. Kaomoji are requested only for emoticon requests. Chinese mode allows mixed Chinese–English output; English mode uses English, with kaomoji for emoticon requests. A complete correction remains available if the second item is truncated.

## 安装与更新 · Installation and updates

Windows 支持 Windows 10/11 x64，含 32 位应用使用的 TSF 组件；本机验证使用 Windows 11。安装到 `C:\Program Files\Zephyr Input`。运行新版 Setup 覆盖更新，卸载从系统“已安装的应用”进入，用户设置、Key 和学习词库保留。Android 当前提供 ARM64 APK，安装后在系统输入法设置启用；首次部署词库需稍等。

Windows targets Windows 10/11 x64 and includes x86 TSF support for 32-bit apps; testing used Windows 11. Setup installs to Program Files. Run a newer Setup to update, or uninstall through Windows Settings; user settings, keys and learned words are retained. Android provides an ARM64 APK; enable it in system keyboard settings and allow the initial dictionary deployment to finish.

## 更新词表和本地模型 · Updating local data

Windows：**词库 / Dictionary**；Android：**设置 → 词库与语法模型**。

1. **切换词表：**万象和雾凇均已内置，新安装默认万象，升级保留已有选择。Windows 选择后点击保存；Android 自动应用。
2. **更新词表：**点击各自的 **更新万象词表 / 更新雾凇词表**，从官方 GitHub 下载、校验并部署；保留当前词表选择，不顺带下载语法模型。
3. **下载或更新模型：**选择万象，点击 **下载 / 更新语法模型**。约 407 MB，安装包不内置；开关默认开启，下载完成后才生效，未下载时仍能正常输入。
4. **开关与适配：**万象语法模型只在万象模式生效。切到雾凇会停用模型，保留下载文件及偏好；切回万象恢复。Windows 修改开关后保存。

三个更新按钮可反复使用，无需重装输入法。摘要识别内容更新，`LTS` / `nightly` 标签不变也能更新；支持暂停续传，Android 有进度通知。首次部署可能需几分钟，建议预留约 1.5 GB 空间。学习词库保留，Windows 更新本地数据无需 UAC。

Open **Dictionary** on Windows or **设置 → 词库与语法模型** on Android. Select either bundled dictionary (Wanxiang is the new-install default); click **Save** on Windows, while Android applies it automatically. Use each dictionary's update button to download, verify and deploy its official GitHub data without changing your selection or downloading the grammar model.

For Wanxiang, **Download / update grammar model** fetches the separate ~407 MB file. Its switch defaults to on and takes effect after download; dictionary-only typing works beforehand. Rime Ice deactivates the model while retaining its file and preference; returning to Wanxiang restores them. Save switch changes on Windows.

Updates use file digests, including when release tags stay unchanged, and support pause/resume. Android shows download progress. Initial deployment may take minutes; allow ~1.5 GB free space. Learned words are retained; Windows data updates need no UAC. [来源与许可 / Sources and licenses](docs/rime/wanxiang-updates.md).

## 配置在线 AI · Online AI setup

一个 **方案 / Policy** 保存接口、Key、模型、参数和附加提示词；可复制（含 Key）或删除。三家服务各用自己的 Key。**更新模型列表只刷新远程模型 ID，不下载模型权重，也不更新本地词表。**

A **policy** holds an endpoint, key, model, parameters and extra instructions; it can be copied with its key or deleted. Each service needs its own key. **Update models refreshes remote model IDs, not local model weights or dictionaries.**

| 配置 / Setting | OpenAI | OpenRouter | Google Gemini |
| --- | --- | --- | --- |
| 创建 Key / Get a key | [OpenAI](https://platform.openai.com/api-keys) | [OpenRouter](https://openrouter.ai/settings/keys) | [Google AI Studio](https://aistudio.google.com/apikey) |
| 完整接口 / Full endpoint | `https://api.openai.com/v1/responses` | `https://openrouter.ai/api/v1/chat/completions` | `https://generativelanguage.googleapis.com/v1beta/interactions` |
| 初始模型 / Initial model | `gpt-6.1-terra` | `deepseek/deepseek-v4-flash-0731` | `gemini-4-hydrogen` |
| 思考 / Thinking | `low` | `none` | `low` |
| 速度 / Speed | `priority`（快速 / Fast） | `default` | `default` |
| 供应商 / Provider | — | `wafer/us`，留空自动 / blank for Auto | — |

以上为客户端初始值。更新模型列表时，OpenRouter 同步服务端提供的思考档位。OpenAI 和 Gemini 的具体档位按已核实型号显示。Gemini 明确标记不支持思考时隐藏档位。`omit` 使用服务端默认，`none` 请求关闭思考。`low` 仍可能消耗思考 token。OpenRouter 的供应商可在模型参数中选择或手填。

These are app defaults. Refreshing the model list reads OpenRouter's reported reasoning levels. OpenAI and Gemini levels follow known model rules. Gemini hides thinking levels when the service reports that a model does not support thinking. Choose `omit` for the server default or `none` to request no reasoning. On OpenRouter you can also choose or enter a model's provider.

### Windows

在 **方案 / Policy** 页填写接口与 Key，选择模型和参数，点击 **保存并生效**。在 **输入 / Input** 页可设置自动模式和手动快捷键，修改后也需保存。Key 字段留空会保留原凭据。附加提示词在 **提示词 / Prompts** 页。

Under **Policy**, enter the endpoint and key, choose the model and parameters, then click **Save**. Configure automatic modes and the manual shortcut under **Input** and save. Leaving the key field blank keeps the saved key. Add extra instructions in the **Prompts** tab.

### Android

在 **AI 辅助 → 编辑 Policy → 验证身份并配置连接 / 密钥** 保存接口和 Key，在 **模型与参数** 选择或填写模型并设置参数。回到列表选中方案，允许使用云端 AI，并在 **AI 增强（自动）** 里选模式。Android 选择后立即保存。

Open **AI assistance → Edit policy**, authenticate, and save the endpoint and key. Choose a model and its parameters under **Model and parameters**. Select the policy, allow cloud AI, and choose an **Automatic AI** mode. Android saves the selection immediately.

### Gemini 与测速 · Gemini and benchmarks

Gemini 使用原生 **Interactions** 接口，选择内置 Gemini 方案并保存 AI Studio Key 即可；它没有供应商路由。Key 所属项目决定权限、配额和计费。

Gemini uses the native **Interactions** API: choose its built-in policy and save an AI Studio key. There is no provider routing; the key's project supplies permissions, quota and billing.

每个方案可单独测试延迟；**一键测速**勾选 1–5 个已有方案，一次运行逐项追加全部结果（含失败），使用各自保存的模型、参数和 Key。样例为含前后文的长句，显示耗时、候选及可用的 token 统计，测试会产生 API 用量。Windows 先保存修改再测试。

Test one policy or check **1–5 existing policies** and run them together. Each uses its saved configuration; results, including failures, are appended separately. Long samples include context and show latency, candidates and available token counts. Tests consume API usage; save Windows edits first.

连接失败时先检查 Key、额度、模型 ID 和参数。固定供应商失败时可刷新列表或改用自动路由。Windows 会区分后台忙、连接或发送超时、等待响应头超时、读取输出超时及模型截断。GPT‑6.2 Sol 支持 `low` 至 `max` 的五个档位，`omit` 使用服务端默认。

For failures, check the key, quota, model ID, and parameters. Refresh a failed provider route or try Auto. Windows distinguishes a busy broker, connection or send timeouts, header timeouts, output timeouts, and truncated responses. GPT‑6.2 Sol exposes five reasoning levels from `low` through `max`, plus `omit` for the server default.

### LLM 提示词 · Prompts

每次请求发送当前提示词与输入；`i` 是输入，`b` / `a` 是前后文，空字段省略。例如：

Each request sends the current prompt and input. `i` is input, with optional `b` / `a` context:

```json
{"i":"woxianghekafe","b":"午饭后我有点困，"}
```

助手提示词的第一项保持原意并修正输入，第二项根据意图给出简短答案、建议、续写、术语或颜表情。纠错提示词只修正输入。

The assistant prompt returns a faithful correction first, followed by a brief answer, suggestion, continuation, term or kaomoji. The separate correction prompt only edits the input.

**中文模式 / Chinese (Simplified)**

```text
i is input; b/a context. Return only JSON ["correction","assistant"]. First fix missing/repeated/swapped letters and nearby-key errors; convert pinyin to Simplified Chinese, preserving and correcting English; preserve meaning, negation, numbers and names, without answering or continuing. Second infer intent for a brief insertable answer, suggestion, continuation or term. No requests for more info; Give your best result directly. When asked for an emoticon, output a kaomoji, e.g. („ಡωಡ„). Allow mixed Chinese and English; use Simplified Chinese for Chinese text.
```

**英文模式 / English**

```text
i is input; b/a context. Return only JSON ["correction","assistant"]. First correct and polish English; translate Chinese, pinyin or mixed input into English; preserve meaning, negation, numbers and names, without answering or continuing. Second infer intent for a brief insertable answer, suggestion, continuation or term. No requests for more info; Give your best result directly. When asked for an emoticon, output a kaomoji, e.g. („ಡωಡ„). Both candidates use English only.
```

输出 **`["纠错","助手"]`**，候选标明角色。仅纠错模式输出 **`["结果"]`**。上下文默认前 50 / 后 0 个字符，可关闭或调整。默认 256 token 软预算会按输入长度预留空间，Gemini 思考模型另有思考额度。第二项截断时保留完整第一项，失败时本地候选仍可用。

Output is **`["correction","assistant"]`**, with labelled roles, or **`["result"]`** in correction-only mode. Context defaults to 50 characters before and 0 after. The default 256-token soft budget reserves space based on input length and adds room for Gemini thinking models. A complete correction remains available if the second item is truncated. Local candidates remain available on errors.

[C++ 协议 / Protocol](shared/native-core/README.md) · [提示词源码 / Prompt source](shared/native-core/src/core.cpp)

## 日常使用 · Typing

Windows 单按 **Shift** 切中英，**Ctrl+Shift+T** 切繁简，数字选词，**Enter** 默认提交原文。选择 Rime 前缀词后可继续分段选词。Android 的中英文模式都在键盘顶部用小字显示尚未上屏的输入，退格同步更新，提交后收起。

On Windows, tap **Shift** for Chinese/English, **Ctrl+Shift+T** for script, numbers for candidates, and **Enter** to commit raw input by default. Selecting a Rime prefix keeps the remaining pinyin for continued selection. Android shows uncommitted Chinese and English input in a small line above the keyboard that updates as you edit and clears after commit.

## 技术与开发 · Architecture and development

**Windows 全部使用原生 C++17。** 基于 Weasel 的 TSF 组件接入系统输入法，Rime 处理本地输入；设置窗口使用 Win32 标准控件，独立 AI Broker 通过命名管道通信、WinHTTP 发起 HTTPS、DPAPI 加密 Key，词库下载更新也在 C++ 中完成。静态链接 C++ 运行库，安装包不带 JVM、Kotlin、Qt 或 WebView，不需要 Java、.NET 桌面运行时或额外 VC++ Redistributable。

Android 基于 Trime，保留 Kotlin 界面和系统、网络适配，通过 JNI 调用共享 C++ AI 核心。两端共用提示词生成、请求构造、模型参数与响应解析。

**Windows is native C++17 throughout:** Weasel TSF integration and Rime local input, Win32 settings, a separate AI broker over named pipes, WinHTTP HTTPS, DPAPI keys and a C++ dictionary updater. Its statically linked runtime needs no JVM, Kotlin, Qt, WebView, Java, .NET desktop runtime or separate VC++ Redistributable. Android builds on Trime with Kotlin platform adapters and JNI; both clients share C++ AI payloads, prompts, model parameters and response parsing.

| 目录 / Directory | 内容 / Contents |
| --- | --- |
| `android/` | Android 应用、引擎与测试 / App, engine and tests |
| `windows/` | 原生 TSF、设置、Broker 和安装器 / Native TSF, settings, broker and installer |
| `shared/native-core/` | 共享 C++ AI 核心及 JNI / Shared C++ AI core and JNI |
| `shared/ai-core/` | Android 适配和共享资源 / Android adapters and shared resources |
| `tests/corpus/` | 中英错输语料与生成器 / Typo corpus and generator |
| `dist/` | 最新两端云构建安装包及校验值 / Current cloud-built installers and checksums |

[开发环境与构建 / Build instructions](docs/DEVELOPMENT.md)

## 开源致谢 · Acknowledgements

感谢 Rime、同文、小狼毫和各个词库及依赖项目的作者。Zephyr 的输入引擎、平台接入和离线词库来自这些项目。

Thanks to the authors and maintainers of Rime, Trime, Weasel, and the dictionaries and libraries below.

| 项目 / Project | 在 Zephyr 中的作用 / Role | 许可证及本地说明 / License & local notices |
| --- | --- | --- |
| [Rime / librime](https://github.com/rime/librime) | 两端离线输入引擎 / Offline input engine | BSD-3-Clause · [LICENSE](android/app/src/main/jni/librime/LICENSE) |
| [同文 / Trime](https://github.com/osfans/trime) | Android 输入法前端与项目基础 / Android IME foundation | GPL-3.0-or-later · 保留原始源码署名 / Original source headers retained · [LICENSE](LICENSE) |
| [小狼毫 / Weasel](https://github.com/rime/weasel) | Windows TSF 前端与输入服务 / Windows TSF frontend and service | GPL-3.0-or-later · [LICENSE](windows/native/LICENSE.txt) · 上游快照 / Snapshot: `f96ed24a8a535961b6ffc7160d98851a69cee4f8` |
| [万象拼音 / Wanxiang](https://github.com/amzxyz/rime-wanxiang) · [语法模型 / Grammar](https://github.com/amzxyz/rime-wanxiang-data) | 内置字词表与全拼规则，可下载的本地语法模型 / Bundled dictionaries and pinyin rules; downloadable local grammar | CC BY 4.0 · [完整许可 / License](shared/ai-core/src/main/resources/rime/wanxiang-CC-BY-4.0.txt) · [接入说明 / Integration](docs/rime/wanxiang-updates.md) |
| [雾凇拼音 / Rime Ice](https://github.com/iDvel/rime-ice) | 简体拼音词库与方案规则 / Simplified Chinese dictionaries and spelling rules | GPL-3.0-only（上游声明 / upstream declaration）· [LICENSE](android/app/src/main/assets/shared/licenses/rime-ice/LICENSE.txt) · [来源与快照 / NOTICE](android/app/src/main/assets/shared/licenses/rime-ice/NOTICE.txt) |
| [OpenCC](https://github.com/BYVoid/OpenCC) | 简繁转换 / Simplified–traditional conversion | Apache-2.0 · [LICENSE](android/app/src/main/jni/OpenCC/LICENSE) |
| [Boost](https://www.boost.org/) | 原生 C++ 依赖 / Native C++ dependencies | BSL-1.0 · [LICENSE](windows/licenses/Boost-BSL-1.0.txt) |
| [Kotlin](https://github.com/JetBrains/kotlin), [Coroutines](https://github.com/Kotlin/kotlinx.coroutines), [Serialization](https://github.com/Kotlin/kotlinx.serialization) | Android 界面、系统适配、异步任务与配置 / Android UI, system adapters, asynchronous work and configuration | Apache-2.0 · [共享模块依赖 / Shared dependencies](shared/ai-core/build.gradle.kts) |
| [nlohmann/json](https://github.com/nlohmann/json) | C++ 协议解析 / Native protocol parsing | MIT · [LICENSE](shared/native-core/third_party/nlohmann/LICENSE.MIT) |
| [OkHttp](https://github.com/square/okhttp) / [Okio](https://github.com/square/okio) | Android HTTPS 与 I/O / Android HTTPS and I/O | Apache-2.0 · [组件说明 / Component notes](windows/THIRD-PARTY.md) |
| [miniz 3.0.2](https://github.com/richgel999/miniz/tree/3.0.2) | Windows 词库 ZIP 解压 / Native Windows dictionary ZIP decompression | MIT · [License](windows/app/third_party/miniz/LICENSE) |

雾凇内置词表来自官方 `nightly` 的 `cn_dicts.zip`（SHA-256 `2e682bf965577b113eebf69ab6f5a936d16e8b4a9ca2117e212ad34361cbc453`），词表来源署名保留在各文件头中。接入范围和修改见 [NOTICE](android/app/src/main/assets/shared/licenses/rime-ice/NOTICE.txt)。其他组件及依赖详见 [Windows 组件说明](windows/THIRD-PARTY.md)、[Android 依赖](gradle/libs.versions.toml) 和各组件的 LICENSE 文件。

The bundled Rime Ice tables come from the official `nightly` release’s `cn_dicts.zip` (SHA-256 `2e682bf965577b113eebf69ab6f5a936d16e8b4a9ca2117e212ad34361cbc453`); dictionary headers retain their original source credits. See the [integration notice](android/app/src/main/assets/shared/licenses/rime-ice/NOTICE.txt), [Windows component notes](windows/THIRD-PARTY.md), and [Android dependencies](gradle/libs.versions.toml) for details.

## 许可证 · License

Zephyr 原创代码与文档采用 **GPL-3.0-or-later**，允许使用、修改、商用和分发。分发受 GPL 覆盖的版本时，须按许可证提供对应源码并保留声明。第三方组件按各自许可证提供，雾凇词库为 **GPL-3.0-only**。

Zephyr's original code and documentation use **GPL-3.0-or-later**, permitting use, modification, commercial use, and redistribution. Distribution of GPL-covered works carries corresponding-source and notice obligations. Third-party components retain their own licenses; Rime Ice dictionaries use **GPL-3.0-only**.

[许可证正文 / License text](LICENSE) · [授权范围 / Licensing details](LICENSE-NOTICE.md)
