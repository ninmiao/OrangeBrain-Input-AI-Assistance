# 橘脑一颗 iOS 版：蓝图与执行方案

> 状态：M0 已在 CI 里跑通（2026-11-24，分支 `ios`；真机 SideStore 验证推迟到 M2 之后），详见第 15 节。基线：Android 1.12.2、Windows 1.14.1。
> 约束：没有 Mac，iOS 的编译、测试、打包全部在 GitHub Actions 的 macOS 托管机器上完成；功能与 Android 基本一致；尽量复用现有开源方案。
> **分发（已定）**：有 iPhone，不办付费开发者账号；用免费 Apple ID 通过 SideStore 侧载，7 天自动续签。
> 本文经过三轮评审，并按「免费账号侧载」做了第四轮修订评审（见第 12 节），结论已并入正文。标注「M0 验证」的条目在第一个里程碑实测确认，不确认不往下走。

## 0. 结论速览

| 问题 | 结论 |
| --- | --- |
| 走哪条路线 | **自建薄壳 + 复用部件**：Swift 主应用（SwiftUI）+ 键盘扩展（UIKit），不整体 fork 现有 iOS 输入法 |
| Rime 引擎 | 直接用 [fcitx5-prebuilder](https://github.com/fcitx-contrib/fcitx5-prebuilder)（MIT）发布的 **iOS 静态库**：librime 1.17.0，真机 / arm64 模拟器 / x86_64 模拟器三份，已内置 lua、octagram（语法模型）、predict、qjs 模块，与 Android 用到的插件一致。不自己交叉编译 librime |
| AI 部分 | **原样复用 `shared/native-core`**（C++17，协议、提示词、模型参数、流式解码都在里面），加一个 C 接口给 Swift 调用；HTTP 用 iOS 自带 URLSession 流式读取。Android / Windows 的 AI 行为天然一致 |
| 键盘 UI | 参考并按需移植 [仓输入法 Hamster](https://github.com/imfuxiao/Hamster)（v2.1.0 起 MIT）的 RimeKit 桥接与键盘布局 / 手势代码；外观按 Android 现有设计重画 |
| 词库 | 在 CI 里用**同版本 librime** 预编译万象词库，直接打进安装包；键盘扩展从不做大规模部署 |
| 构建测试 | GitHub Actions `macos-26`（Xcode 26.6），XcodeGen 由 YAML 生成工程；模拟器跑单元测试、键盘界面测试、系统级端到端测试、内存采样，截图和日志作为产物下载到 Windows 上看 |
| 安装到 iPhone | **免费 Apple ID + SideStore 侧载**：CI 产出未签名 IPA 并发布一个 SideStore 源（source JSON），手机上在 SideStore 里一键安装 / 更新，SideStore 每 7 天自动续签。不需要任何 Apple 密钥进 CI |
| 免费账号的关键限制 | SideStore 会把 App Group 改名为「原组名.团队ID」，Bundle ID 也可能被改 → 代码运行时从安装包内的描述文件读出真实组名；Keychain 跨进程共享不保证 → Key 存储做两套后端（第 4.6 节）。M0 在你的 iPhone 上实测 |
| 最大风险 | 键盘扩展内存上限（实测约 77 MB）对万象词库和 373 MiB 语法模型的压力；模拟器不强制该上限，必须真机验收 |
| 周期估计 | 7 个里程碑，约 23–33 个工作日（含 CI 往返等待；不用等 Apple 处理）；M0 两到三天即可判断可行性 |

## 1. 目标与范围

### 1.1 目标

- 在 iPhone 上提供与 Android 1.12.x 基本相同的体验：Rime 拼音（万象 / 雾凇）、在线 AI 纠错 + 助手双候选（流式）、AI 表情、功能键区、剪贴板、简繁切换、Policy / Key / 模型 / 提示词管理、测速。
- AI 请求协议、提示词、候选解析与 Android、Windows 完全一致（同一份 C++ 代码）。
- 没有 Mac 也能日常开发：在 Windows 上改代码 → 推送 → CI 编译测试 → 下载截图 / 测试报告 / 安装包。

### 1.2 不在 v1 范围

- iPad 专用布局（v1 仅 iPhone 布局，iPad 上按 iPhone 尺寸运行或暂不支持，M6 再定）。
- 手写、语音、云同步（iCloud）、皮肤编辑器、Wi-Fi 传文件。
- App Store 公开上架和 TestFlight（都需要付费账号；v1 只做免费侧载。将来若改主意，第 7 节保留了付费路线的做法，第 10 节列了上架合规工作）。

## 2. 功能对等矩阵

| Android 功能 | iOS 实现 | 与 Android 的差异 / 平台限制 | 里程碑 |
| --- | --- | --- | --- |
| Rime 拼音、候选、组字 | librime 静态库 + Swift 封装；候选栏、组字栏自绘；`setMarkedText` 可选内联组字 | 无 | M1 |
| 万象 / 雾凇切换 | 两套预编译词库，主应用切换并部署 | 雾凇为 GPL-3.0 数据，上架时改为用户自行下载（第 10 节） | M1 / M4 |
| 用户词库学习 | 用户词库放 App Group 共享目录 | 未开「完全访问」时键盘不能写共享目录，改用扩展私有目录（学习结果不与主应用共享） | M1 |
| 词表更新、语法模型下载 | 主应用里下载（URLSession 后台下载）并部署；复用 Windows `dictionary.cpp` 的发布解析与解压逻辑 | 语法模型 373 MiB，默认关闭，内存实测通过后才开放（第 11 节 R-1） | M4 |
| 在线 AI 纠错 / 助手（流式，双候选） | native-core + URLSession `bytes(for:)` 流式读取 | 需要「完全访问」才能联网；不开则 AI 按钮置灰并提示 | M2 |
| AI 表情（5 个） | 同一提示词，`slots = 5` | 无 | M3 |
| 表情键接管正在进行的请求（1.12.1 行为） | Swift 版请求协调器按同一规则实现：换键即取消旧请求、丢弃迟到回复、后台事件不触发自动请求 | 无；有单元测试锁定 | M2 / M3 |
| 功能键区 0–5 个可自定义 | UIKit 自绘按钮，含星光 / 笑脸动画（Core Animation 重写 `AiStatusButton` 动效） | 无 | M3 |
| 剪贴板面板、粘贴栏 | `UIPasteboard`（需完全访问） | iOS 不能在后台监听剪贴板：历史只记录键盘可见期间看到的内容和主应用里看到的内容 | M3 |
| 简繁切换 | Rime `traditionalization` 选项 | 无 | M3 |
| ⋯ 菜单（功能统一网格） | 键盘内面板 | 「设置」项：键盘扩展按审核规则只能打开系统设置，不能拉起主应用（iOS 26 上不开完全访问时直接失败），改为键盘内快捷设置 + 提示去主应用 | M3 |
| Policy / 模型 / 参数 / 提示词 / 测速 | SwiftUI 主应用；配置 JSON 与 Android `AiConfig` 同结构，支持导入导出 | 无 | M2 / M3 |
| Key 加密保存、编辑前验证身份 | 见第 4.6 节：优先 Keychain 共享组；侧载后共享不可用时，退到 App Group 内受系统文件保护的加密文件。编辑前 Face ID / 密码（LocalAuthentication，仅在主应用） | 键盘扩展里不做生物识别 | M2 |
| 隐私字段不发 AI | 系统对密码框自动切回系统键盘；另按 `textContentType`（密码、验证码、信用卡等）、`keyboardType`（数字、电话等）判定为隐私字段 | iOS 没有 `NO_PERSONALIZED_LEARNING` 对应项 | M3 |
| 前后文参考 | `documentContextBeforeInput` / `AfterInput` | 宿主应用可能只给当前段落，前文长度尽力而为 | M2 |
| 采用 AI 候选替换原文 | 组字中：清空组字后插入；已上屏：先核对光标前文本以原文结尾，再 `deleteBackward` × 字素数并 `insertText`；核对失败则放弃（对应 Android `valid()`） | 无选区 API，替换只能「删后插」 | M2 |
| 收起键盘、地球键 | `dismissKeyboard()`、`needsInputModeSwitchKey` | iOS 必须提供切换键盘入口 | M1 |
| 崩溃日志页 | MetricKit 诊断 + App Group 内文本日志，主应用里查看 / 导出 | 无 LogActivity 弹窗 | M5 |

## 3. 可复用开源方案调研（2026-11-24 实查）

| 项目 | 许可证 | 状态 | 拿什么 | 不拿什么 / 原因 |
| --- | --- | --- | --- | --- |
| [rime/librime](https://github.com/rime/librime) | BSD-3-Clause | 活跃 | 引擎本身（经 prebuilder） | — |
| [fcitx5-prebuilder](https://github.com/fcitx-contrib/fcitx5-prebuilder) | MIT | 活跃；`ios` 发布 2026-11-06 更新 | iOS 静态库：librime（1.17.0，含 lua / octagram / predict / qjs）、boost、opencc、leveldb、marisa、yaml-cpp、glog、lua、zstd；macOS 版 librime 用来在 CI 里编译词库 | 它的 `ios` 标签会滚动更新 → 我们镜像到自己的 Release 并锁定 SHA256 |
| [仓输入法 Hamster](https://github.com/imfuxiao/Hamster) | MIT（v2.1.0 起） | 开源版停在 2025-05；作者表示后续不再开源 | `Packages/RimeKit`（librime Swift 封装）、`HamsterKeyboardKit`（KeyboardKit 早期 MIT 分支：布局、手势、按键回调）作参考与按需移植 | 整体 fork：工程停在 Xcode 15 时代，依赖的 LibrimeKit 仓库和预编译包已 404，直接编译不过；功能面远大于我们需要的 |
| [fcitx5-ios](https://github.com/fcitx-contrib/fcitx5-ios) | GPL-3.0 | 活跃（2026-11-14），开发者测试版 | 工程经验：GitHub Actions 上编模拟器 + 真机 IPA、Appium 端到端测试、键盘扩展实测 77 MB 内存上限、无开发者账号时 App Group 不可用 | 代码不直接拷入（Fcitx5 框架层太重；同时保持 iOS 代码不含第三方 GPL 代码，给将来上架留余地） |
| [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit) | 新版非纯开源（NOASSERTION，核心为二进制分发） | 活跃 | 不用 | 许可不清晰；Hamster 里的早期 MIT 分支已够用 |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | MIT | 活跃 | 用 YAML 生成 `.xcodeproj` | 没有 Mac 时无法手改 `project.pbxproj`，这是必需品 |
| 本仓库 `shared/native-core` | GPL-3.0-or-later（作者本人） | — | 全部 AI 协议逻辑、语料测试 | — |
| 本仓库 `windows/app/dictionary.cpp` | GPL-3.0-or-later（作者本人） | — | 发布信息解析、选文件、zip 解压（与 WinHTTP 解耦后共用） | WinHTTP 网络部分 |

**为什么不用 Kotlin Multiplatform 复用 `shared/ai-core`**：要把 OkHttp 换成 Ktor、改动 Android 全链路，Kotlin/Native 运行时还会吃掉键盘扩展本就紧张的内存；而真正有分量的逻辑早已下沉到 C++。iOS 只需用 Swift 重写很薄的一层（请求协调、传输、配置读写）。

### 3.1 路线比较

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| A. fork Hamster | UI 与功能最完整 | 编不过（依赖 404）、停更 18 个月、885 个文件的维护面、风格需整体改 | 否 |
| B. fork fcitx5-ios | CI 现成、活跃 | 多一层 Fcitx5 框架（内存、复杂度），GPL 代码影响上架，UI 体系需大改 | 否 |
| **C. 自建薄壳 + 复用部件** | 依赖都是 MIT / BSD 或自有代码；体积和内存可控；直接贴合 Android 设计 | 键盘 UI 需要自己写（有 Hamster 代码可参考） | **采用** |

## 4. 总体架构

```
┌──────────────────────── OrangeCell.app（主应用，SwiftUI）─────────────────────────┐
│ 首次引导（启用键盘 / 完全访问说明） · Policy / Key / 模型 / 提示词 · 测速             │
│ 词库与语法模型下载、部署 · 功能键设置 · 日志查看 · 试打区                               │
└───────────────┬──────────────────────────────────────────────────────┬───────────┘
                │ App Group 共享目录（配置 JSON、Rime 用户数据、部署戳、日志）            │ Keychain 共享组（Key）
┌───────────────┴────────── OrangeCellKeyboard.appex（键盘扩展，UIKit）──┴───────────┐
│ KeyboardViewController                                                            │
│  ├─ KeyboardView（26 键 / 数字 / 符号，Shift、地球键、手势）                          │
│  ├─ CandidateBar（Rime 候选 + 组字） · AIBar（状态点 · AI 候选 · 功能键区）             │
│  ├─ Panels（⋯ 菜单、剪贴板、快捷设置）                                                │
│  └─ Services：RimeSession（OCRime） · AiCoordinator → AiTransport（URLSession）      │
└───────────────┬───────────────────────────────────────────────────────────────────┘
                │ 静态链接
   OCRime（Swift ↔ librime C API） · OCCore（Swift 包：native-core C 接口 + 协调器 + 配置模型）
   librime.a / boost / opencc / leveldb / marisa / yaml-cpp / glog / lua / zstd（prebuilder）
```

### 4.1 目标与模块

| 目标 | 类型 | 内容 |
| --- | --- | --- |
| `OCCore` | SwiftPM 包（只依赖 Foundation） | native-core C++ 源码 + `oc_invoke` C 接口、`AiRequestCoordinator`（Swift actor）、`AiTransport` 协议、`AiConfig` 模型、`EditorRange` 计算、隐私字段判定。可在 Linux 上跑单元测试 |
| `OCRime` | SwiftPM 包 | librime C API 的 Swift 封装（参考 Hamster `RimeKit`）：启动 / 关闭、按键、候选、选项、部署、版本 |
| `OCKeyboardUI` | 框架 | 键盘 UI 组件；主应用的预览 / 试打区与键盘扩展共用 |
| `OrangeCell` | App | 主应用 |
| `OrangeCellKeyboard` | App Extension | 键盘 |
| `OCTestHost` | App（仅测试） | 只有一个文本框的宿主，给系统级端到端测试用 |

### 4.2 native-core 的 C 接口（唯一需要改的共享代码）

在 `shared/native-core/src/c_api.cpp` 新增：

```c
// 输入与输出都是 UTF-8 JSON；返回值由调用方用 oc_free 释放。
char* oc_invoke(const char* command);
void  oc_free(char* p);
```

内部直接调用现有 `orangecell::invoke`。Windows 和 Android 不受影响（可选择也改用它）。Swift 用 C 接口而不是 Swift–C++ 互操作：Linux / Windows 上的 Swift 测试也能编，接口稳定。

### 4.3 存储布局

| 位置 | 内容 | 谁写 |
| --- | --- | --- |
| 应用包内 `rime-shared/` | 预编译的万象词库（`build/*.bin`）、方案、opencc、lua | CI |
| App Group `rime-user/` | `default.custom.yaml`、用户词库（leveldb）、`installation.yaml` | 主应用（部署）、键盘（学习） |
| App Group `rime-user/build/` | 主应用部署出的产物（用户改方案、下载新词库后） | 主应用 |
| App Group `config/ai-config.json` | 与 Android `AiConfig` 同结构（不含 Key） | 主应用；键盘只读 |
| App Group `state/deploy-stamp` | 部署版本戳；键盘每次出现时比较，变化则重启 Rime 会话 | 主应用 |
| App Group `logs/` | 滚动日志、最近一次崩溃诊断 | 两者 |
| Keychain 访问组（或 App Group `secrets/`） | 每个 Policy 一条 Key，见第 4.6 节 | 主应用写；键盘读 |
| 扩展私有目录 | 未开完全访问时的用户词库 | 键盘 |

**App Group 的真实名字在运行时确定。** 工程里写的是 `group.io.github.ninmiao.orangecell`，但 SideStore 用免费账号重签时会改成 `group.io.github.ninmiao.orangecell.<团队ID>` 并重新注册。主应用和键盘各自启动时：

1. 读自己包内的 `embedded.mobileprovision`（开发签名的应用和扩展都有这个文件），取出其中 `Entitlements → com.apple.security.application-groups`，找以工程组名开头的那一项；
2. 用 `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` 打开，写入 / 读取一个探针文件确认两边是同一个目录；
3. 都失败时（例如重签工具丢了 App Group 能力）进入「无共享」模式：键盘只用包内词库和自己的私有目录，主应用提示「请在 SideStore 里刷新一次」，并提供第 4.7 节的手动同步。

这个解析器（`AppGroupLocator`）是纯函数，配一组样例描述文件做单元测试。

### 4.4 Rime 生命周期与部署

- **键盘从不做完整部署。** 默认词库在 CI 预编译进包；用户改配置、换词库、下载新版后，由主应用部署，写出新部署戳。
- **版本一致。** 预编译所用的 librime 必须与 iOS 静态库同一提交，否则设备上会触发重建（在键盘里极易超内存）。做法：CI 用 prebuilder 同批次的 macOS librime 链接一个 40 行的 `oc_deployer` 小工具来编译词库；两份库都从镜像 Release 按锁文件下载。启动时检查 `rime_get_api()->get_version()` 与包内记录是否一致，不一致只记录告警并使用包内产物。
- **用户词库锁。** Rime 的用户词库是 LevelDB，同一时刻只能被一个进程打开。规则：只有键盘打开用户词库；主应用部署时跳过用户词库相关任务（只部署方案和配置），用户词库的升级 / 备份在键盘下次空闲时做。M1 在模拟器里让两个进程同时运行来验证。
- **会话。** 键盘 `viewWillAppear` 初始化（已初始化则复用），`viewDidDisappear` 提交用户词库；收到内存警告时释放候选缓存并关闭预测。

### 4.5 AI 请求链路

1. 取上下文：组字内容（Rime）或光标前已上屏的文本；前后文来自 `textDocumentProxy`。
2. `oc_invoke({"op":"context"…})` → `prompt` → `payload`，得到与 Android 完全相同的请求体。
3. `URLSession.bytes(for:)` 流式读取，每块转十六进制交给 `oc_invoke({"op":"stream"…})`，只显示已闭合的候选字符串。
4. 协调器规则（照搬 Android 1.12.1）：同一时刻只有一个请求；手动键（助手 / 表情）接管时取消旧请求并丢弃迟到数据；后台事件不触发自动请求；按键、点候选、移动光标会清除这一保持状态。
5. 采用：见第 2 节「采用 AI 候选」行；采用前再次核对上下文。

### 4.6 Key 存储（为免费账号设计两套后端）

| 后端 | 条件 | 做法 |
| --- | --- | --- |
| Keychain 共享组（首选） | 签名里真的带有两边一致的 `keychain-access-groups` | 条目用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，不随备份迁移 |
| App Group 加密文件（侧载后的兜底） | 共享组不可用 | 每个 Key 用 AES-GCM 加密后写入 `secrets/`，文件设 `completeUntilFirstUserAuthentication` 保护；加密密钥本身也放在该目录（同样受系统数据保护），排除在 iCloud / 电脑备份之外。安全性与 Android 的「键盘可静默读取、编辑需验证身份」一致：只有本应用和本键盘的沙盒能读 |

启动时用一次「主应用写、键盘读」的自检决定用哪套，结果写进日志并在主应用的「诊断」页显示。编辑 / 查看 Key 前都要 Face ID 或锁屏密码。

### 4.7 无共享模式下的手动同步（兜底中的兜底）

如果某次重签后 App Group 也不可用：主应用把配置 JSON 和加密后的 Key 放进**同团队可见的命名剪贴板**（`UIPasteboard(name:)`，只有同一签名团队的程序能读），键盘在开启完全访问时点「同步配置」读入并存到自己的私有目录，读完立即清空该剪贴板。fcitx5-ios 在免费侧载下用的也是「完全访问 + 手动同步」的思路。只在 M0 实测 App Group 失败时才实现。

### 4.8 续签过期时的行为

SideStore 没能及时续签（例如 7 天内手机没连上它的本地 VPN）时，系统不再加载我们的键盘，会自动换回别的键盘；数据都还在，SideStore 刷新后恢复。主应用在剩余不足 2 天时（同样从 `embedded.mobileprovision` 读到期时间）提示去刷新。

## 5. 仓库与工程布局

```
ios/
  project.yml                 # XcodeGen 工程定义（.xcodeproj 不入库，CI 生成）
  Packages/OCCore/            # SwiftPM：native-core 桥接、协调器、配置、测试
  Packages/OCRime/            # SwiftPM：librime 封装
  OCKeyboardUI/
  OrangeCell/                 # 主应用
  OrangeCellKeyboard/         # 键盘扩展（Info.plist：RequestsOpenAccess=YES、PrimaryLanguage=zh-Hans）
  OCTestHost/
  Tests/                      # 单元、界面、端到端测试
  deps.lock.json              # 依赖镜像地址 + SHA256
  scripts/                    # fetch-deps.sh、build-rime-data.sh、measure-memory.sh、export-results.sh、make-source.py
  sidestore/source.json       # SideStore 源（CI 发布时更新版本号、下载地址、SHA256）
.github/workflows/
  ios-ci.yml                  # 推送 / PR：编译 + 全部测试 + 截图
  ios-release.yml             # 手动：未签名 IPA → GitHub Release → 更新 SideStore 源
  ios-deps.yml                # 手动：镜像 prebuilder 依赖并更新锁文件
```

- 最低系统 iOS 17.0（prebuilder 产物支持 16.3+，17 便于用新版 SwiftUI；如需 16 可再降）。
- Swift 6 编译器、Swift 5 语言模式起步，避免一开始被严格并发检查拖住。
- 版本号：iOS 从 0.1.0 起，真机验收通过后用 1.0.0；在 `UPDATE_LOG.md` 单独记一列「iOS」。
- Bundle ID：`io.github.ninmiao.orangecell`、`io.github.ninmiao.orangecell.keyboard`、`io.github.ninmiao.orangecell.testhost`（仅模拟器）；App Group `group.io.github.ninmiao.orangecell`。侧载后的实际名字可能带团队 ID 后缀，代码里一律通过 `AppGroupLocator` 取，不写死。
- 真机只装主应用 + 键盘两个 App ID；免费账号每 7 天最多注册 10 个 App ID，所以 Bundle ID 一旦定下不改，也不要反复卸载重装。

## 6. CI / CD 设计（GitHub Actions）

### 6.1 运行环境

- 托管机器 `macos-26`（arm64，镜像 20261117 带 Xcode 26.0.1–26.6，默认 26.6，模拟器含 iPhone 17 / iOS 26.x）。工作流里显式 `xcode-select` 到 26.6，避免镜像默认版本变化。
- 另设一个**不阻塞**的金丝雀任务跑 `xcode-27` 标签（公开预览），提前发现新 Xcode 问题。
- 仓库是公开的：标准托管机器免费；若改为私有，macOS 分钟按 10 倍计费，需先评估额度。
- 本仓库其他平台仍坚持本地编译；iOS 因没有 Mac 是唯一例外。

### 6.2 `ios-ci.yml`（推送到 `ios/**`、`shared/native-core/**` 或手动触发）

| 任务 | 机器 | 内容 | 约时 |
| --- | --- | --- | --- |
| `core-linux` | ubuntu | `swift test`（OCCore，含 native-core 语料契约测试）；clang 编 native-core 并跑原有 C++ 测试 | 3–5 分钟 |
| `rime-data` | macos-26 | 按锁文件取 macOS librime → 编 `oc_deployer` → 预编译万象（和雾凇）→ 产物缓存（按词库与库版本做缓存键） | 首次 10–15 分钟，命中缓存 1 分钟 |
| `build-test` | macos-26 | 取 iOS 依赖（缓存）→ XcodeGen → 模拟器编译 → 单元测试 → 键盘界面测试（截图，浅色 / 深色）→ 系统级端到端 → 内存采样 → 未签名真机编译（只验证能链接） | 15–25 分钟 |
| `report` | ubuntu | 汇总 JUnit、截图、内存曲线成一个 HTML 报告产物 | 1 分钟 |

- **在 Windows 上看结果**：`.xcresult` 需要 Xcode 才能打开，所以 CI 用 `xcresulttool` 导出 JUnit XML、失败截图、日志文本和 PNG 截图，打包成普通 zip 产物。
- **远程排错**：失败时可选开启 `action-tmate`，从 Windows 直接 SSH 进当次 macOS 机器查看（仅手动触发时启用，避免泄露）。
- **并发**：同一分支新推送自动取消旧运行。

### 6.3 `ios-release.yml`（仅手动、仅 `main`）

1. 版本号与构建号（构建号 = 运行序号，SideStore 靠它判断有无更新）。
2. 真机架构编译，`CODE_SIGNING_ALLOWED=NO`；对 `.app` 和 `.appex` 做临时签名（`codesign -s -`，带上工程里的 entitlements，SideStore 重签时据此申请 App Group 等能力）；打成 `OrangeCell-iOS-<版本>.ipa`。fcitx5-ios 和仓输入法的 CI 都是这样产出侧载包的。
3. 发布到 GitHub Release，同时写 SHA256。
4. 更新 `ios/sidestore/source.json`（版本、构建号、下载地址、大小、更新说明）并提交到 `main`；手机上 SideStore 添加一次这个源，以后在 SideStore 里点更新即可，不用再下文件。
5. **整个流程不需要任何 Apple 证书或密钥**，CI 里没有签名秘密需要保护。签名只发生在你手机上的 SideStore 里，用的是你自己的免费 Apple ID。
6. 发布包同样放进仓库 `dist/`（与 Android / Windows 一致），`SHA256SUMS` 加一行。

### 6.4 `ios-deps.yml`（手动）

下载 prebuilder 的 `ios` / `macos` 发布包 → 校验 → 上传到本仓库 Release `ios-deps-YYYYMMDD` → 提 PR 更新 `ios/deps.lock.json`。上游滚动更新不会悄悄改变我们的构建。

## 7. 签名与分发

**已定路线：免费 Apple ID + SideStore。**

| 项目 | 说明 |
| --- | --- |
| 一次性准备 | 在 Windows 上用 SideStore 官方推荐的安装工具（如 iloader）把 SideStore 装到 iPhone，并生成配对文件；iPhone 上安装 SideStore 需要的本地 VPN 应用；用你的 Apple ID 登录 SideStore；iPhone 打开「开发者模式」 |
| 安装 / 更新橘脑一颗 | SideStore 添加我们的源 → 安装。之后 CI 每发一版，SideStore 显示更新，点一下即可；也可以直接用 IPA 文件安装 |
| 续签 | SideStore 在后台用本地 VPN 自动续签（7 天有效）；不需要电脑。没续上时键盘暂停，数据不丢，刷新即恢复（第 4.8 节） |
| 免费账号额度 | 同时最多 3 个侧载应用（含 SideStore 本身，橘脑一颗占 1 个）；每 7 天最多 10 个新 App ID（我们用 2 个：主应用 + 键盘） |
| App Group | SideStore 会以「原组名.团队ID」重新注册并分配给主应用和键盘（已读其源码确认这一逻辑），代码运行时自动识别（第 4.3 节）。M0 在你的手机上实测 |
| Keychain 共享 | 免费账号允许的能力由 SideStore 按团队类型过滤，跨进程共享不保证 → 有兜底后端（第 4.6 节） |
| 不需要 | Apple 付费账号、证书、TestFlight、CI 里的签名密钥 |

备选（目前不用，留档）：付费 Apple Developer Program（99 美元 / 年）可走 TestFlight，没有 7 天续签、App Group 与 Keychain 共享都确定可用；App Store 上架另需第 10 节的合规工作。代码设计对两条路线都兼容，将来切换只需加一个发布工作流。

## 8. 测试策略

| 层级 | 工具 | 覆盖 |
| --- | --- | --- |
| C++ 契约 | 原有 `core_test` + `tests/corpus/truncated-output.jsonl` | 与 Android / Windows 共用，iOS 端在 Linux 与模拟器各跑一遍 |
| Swift 单元 | XCTest（Linux 与模拟器） | 协调器（含 1.12.1 表情接管规则的回归用例）、采用核对、上下文截取、隐私字段判定、配置读写与 Android JSON 互通 |
| 传输 | 自定义 `URLProtocol` 分块返回 | 流式拆包、断流、超时、取消、迟到数据丢弃；不访问真实 API |
| 键盘界面 | 测试宿主内嵌 `KeyboardViewController` + 假的 `textDocumentProxy` | 按键、候选、AI 栏、功能键、面板；浅色 / 深色截图 |
| 系统级端到端 | XCUITest（必要时 Appium，fcitx5-ios 已在 CI 跑通此路线） | 在模拟器里启用键盘、切到橘脑一颗、在 `OCTestHost` 里打字、出候选、上屏 |
| 内存 | 模拟器里的扩展进程就是 macOS 进程：用 `footprint` / `vmmap` 按进程采样 | 设预算线（初定无语法模型 ≤ 55 MB），超线标红；只是代理指标，真机为准 |
| 在线冒烟（可选） | 手动触发，使用专门的测试 Key（GitHub Secret，额度上限） | 三家各一次真实请求。不使用聊天里出现过的临时 Key |
| 侧载相关单元测试 | XCTest + 样例描述文件 | `AppGroupLocator`（原名、带团队 ID 后缀、缺失三种）、到期时间解析、Key 存储两套后端的切换 |
| 真机验收 | 你的 iPhone（SideStore 安装） | App Group 是否识别到同一目录、Key 用的是哪套后端（诊断页显示）、刷新续签后数据还在；内存警告、完全访问开 / 关、密码框、数字键盘、流式速度、表情接管、剪贴板、深色模式、横屏 |

**在模拟器里启用第三方键盘**是端到端测试的前提，M0 按顺序试：① 启动前改模拟器偏好里的已启用键盘列表；② XCUITest 驱动「设置」应用添加键盘并开启完全访问；③ Appium（fcitx5-ios 的做法）。至少一种跑通才进入 M1。

## 9. 里程碑与执行计划

每个里程碑结束都更新 `UPDATE_LOG.md`（「待发布 · iOS」），并在 CI 产物里留截图。

| 里程碑 | 内容 | 验收标准 | 估计 |
| --- | --- | --- | --- |
| **M0 可行性探针** | XcodeGen 空壳主应用 + 键盘扩展；链接 prebuilder librime，键盘里显示 `librime 1.17.0`；模拟器安装、启用键盘、截图；`oc_invoke` 在模拟器里跑通一次 `encode`；依赖镜像与锁文件；**未签名 IPA + SideStore 源，你在 iPhone 上装一次**：键盘能启用，诊断页显示识别到的 App Group 名、两边探针文件是否互通、Key 存储后端、描述文件到期时间 | CI 全绿（编译链接、系统键盘里出现我们的界面、截图可下载）；**你的 iPhone 上键盘能打出「librime 版本」字样，诊断页结果回传给我** | 2–3 天（真机一步需要你配合 10 分钟） |
| **M1 能打字** | `OCRime`；CI 预编译万象词库；26 键 + 数字 / 符号；候选栏、组字、Shift、删除、地球键；用户词库；部署戳 | 端到端：输入 `nihao` 出「你好」并上屏；两进程同时运行不损坏用户词库；内存采样在预算内 | 5–7 天 |
| **M2 AI 主链路** | C 接口；Swift 传输与协调器；AI 栏（状态点、纠错 / 助手候选、流式）；采用；主应用 Policy / Key（Keychain + 身份验证）/ 云端许可；配置与 Android 同结构 | 用 URLProtocol 模拟服务时，界面测试看到流式候选并能采用；协调器回归用例全过 | 5–7 天 |
| **M3 功能对齐** | 功能键 0–5 自定义；AI 表情；剪贴板面板 + 粘贴栏；简繁；⋯ 菜单与快捷设置；动画；隐私字段；未开完全访问模式；浅色 / 深色 | 第 2 节矩阵中 M3 行全部有界面测试与截图 | 5–7 天 |
| **M4 词库与模型** | 共享 C++ 词库更新逻辑（从 Windows 拆出）；主应用下载万象 / 雾凇、部署；语法模型实验开关 + 内存采样 | 下载 → 部署 → 键盘生效的端到端；开语法模型时的内存数据入报告 | 3–5 天 |
| **M5 发布流水线与真机** | `ios-release.yml`（未签名 IPA → Release → SideStore 源）；你在 iPhone 上按清单验收（每个里程碑也会给你一版尝鲜）；按内存数据调优；续签过期提示 | iPhone 通过真机清单；无内存终止；SideStore 里点更新能升级且数据保留 | 2–4 天 |
| **M6 发布整理** | README 加 iOS 小节与截图；`DEVELOPMENT.md` 写 iOS 工作流；版本 1.0.0；决定是否上架 | 文档与产物齐全 | 2 天 |

**判停点**：M0 任何一项失败 → 先按第 11 节备选方案处理，不进 M1。真机上 App Group 识别失败 → 先实现第 4.7 节手动同步再继续。M1 内存超预算 → 先换雾凇小词库验证，再决定是否给 iOS 做精简版万象。

从 M1 起，每个里程碑结束都发一版侧载包，你在 iPhone 上试用并反馈，不必等到 M5。

## 10. 合规与上架前提（v1 只做个人侧载，本节仅为将来留档，不阻塞开发）

侧载自用不经过 App Review，但以下隐私做法照样执行（云端许可、完全访问说明、隐私字段不发 AI）。

- **审核规则 4.4.1（键盘扩展）**：必须提供输入功能、切换键盘入口、不开完全访问也能用（我们的离线 Rime 满足）；不得拉起主应用以外的应用。设置键的设计已按此处理。
- **隐私**：键入内容发到云端前必须明示并取得同意（沿用 Android 的云端许可开关）；`PrivacyInfo.xcprivacy` 声明用到的「需说明理由的 API」；App 隐私标签如实填写。
- **许可证**：iOS 代码只用自有代码和 MIT / BSD / Apache 部件，不拷入第三方 GPL 代码；native-core 与 Windows 词库代码著作权在项目作者，可另行授权。词库数据：万象为 CC BY 4.0（可随包）；雾凇为 GPL-3.0，上架版不打包，改为用户在应用内自行下载。
- **完全访问说明页**：主应用首次引导写清：不开完全访问时只用离线输入；开启后才联网请求 AI，且只在用户同意云端 AI 后发送。

## 11. 风险登记

| 编号 | 风险 | 可能性 | 影响 | 对策 | 何时发现 |
| --- | --- | --- | --- | --- | --- |
| R-1 | 键盘扩展内存上限（约 77 MB）被万象词库 / 语法模型突破 | 中（词库）/ 高（语法模型） | 高 | 词库只读映射、键盘不部署；语法模型默认关闭；CI 内存采样设预算；备选雾凇或精简词库 | M1 模拟器采样，M5 真机 |
| R-2 | 模拟器里无法稳定启用第三方键盘 | 中 | 中 | 三种方法依次试；最差退回「测试宿主内嵌键盘」+ 真机手测 | M0 |
| R-3 | prebuilder 上游变更或下架 | 低 | 高 | 镜像 + 锁文件；必要时参照其脚本自建（MIT） | 持续 |
| R-4 | 两进程同时打开用户词库 | 中 | 中 | 只由键盘打开；主应用部署跳过用户词库任务；模拟器双进程测试 | M1 |
| R-5 | 宿主应用给的上下文很短或不准 | 高 | 低 | 前后文尽力而为；采用前核对，不一致则放弃 | M2 |
| R-6 | 没有 Mac，排错慢 | 高 | 中 | 产物全部导出为文本 / PNG；Linux 上先跑纯逻辑测试；必要时 tmate 远程进 CI 机器 | 全程 |
| R-7 | 托管镜像 Xcode 版本变化 | 中 | 低 | 显式选择 Xcode 版本；`xcode-27` 金丝雀任务 | 持续 |
| R-8 | 侧载重签后 App Group 名变化 / 能力被去掉 | 中 | 高 | 运行时从描述文件识别组名；探针互通自检；失败走手动同步（第 4.7 节） | M0 真机 |
| R-11 | Keychain 跨进程共享在免费签名下不可用 | 中 | 中 | Key 存储两套后端自动选择（第 4.6 节） | M0 真机 |
| R-12 | 7 天续签失败导致键盘暂停 | 中 | 低 | SideStore 后台续签；主应用到期前提醒；数据不丢 | 使用中 |
| R-13 | 免费账号额度（3 个应用 / 每周 10 个 App ID） | 低 | 中 | 只用 2 个 App ID；固定 Bundle ID；不反复卸载重装 | 持续 |
| R-14 | Apple 收紧免费签名或 SideStore 失效 | 低 | 高 | 代码与分发解耦：随时可切付费 TestFlight 路线，只需加一个工作流 | 持续 |
| R-9 | 键盘内拉起主应用在 iOS 26 受限 | 已确认 | 低 | 键盘内快捷设置 + 文字引导 | M3 |
| R-10 | 剪贴板历史不如 Android 完整 | 已确认 | 低 | 文档写明差异 | M3 |

## 12. 三轮评审记录

### 第一轮：架构与可行性

| # | 发现 | 处理 |
| --- | --- | --- |
| 1 | 初稿打算 fork Hamster。实查：开源版停在 2025-05，作者不再开源后续代码；它依赖的 LibrimeKit 仓库与预编译包均返回 404，原样编不过 | 改为方案 C，只借用其 MIT 代码作参考 |
| 2 | librime 是否要自己交叉编译 iOS（boost 等依赖最耗时） | 实查 fcitx5-prebuilder 的 `ios` 发布：真机 + 两种模拟器静态库齐全；解出 `librime.a` 确认含 `lua`、`octagram`、`grammar`、`predict`、`qjs` 模块注册符号 → 不自编 |
| 3 | 版本不一致：Android 用 librime 1.14.0，prebuilder 为 1.17.0 | iOS 词库必须用同批次 macOS librime 编译（`oc_deployer`），双包同锁；启动时比较版本 |
| 4 | 在键盘里部署万象会超内存 | 部署全部移到 CI（默认词库）和主应用（用户改动） |
| 5 | Swift 调 C++ 的方式 | 定为 C 接口 `oc_invoke` / `oc_free`，Linux 上也能测 |
| 6 | 是否用 KMP 复用 Kotlin | 否（见第 3 节） |
| 7 | LevelDB 用户词库跨进程锁 | 定下「只有键盘打开」规则，并安排 M1 双进程测试 |

### 第二轮：无 Mac 的构建、测试与签名

| # | 发现 | 处理 |
| --- | --- | --- |
| 8 | Windows 上无法编辑 `.xcodeproj` | XcodeGen，`.xcodeproj` 不入库 |
| 9 | `.xcresult` 在 Windows 打不开 | CI 导出 JUnit / PNG / 文本日志 |
| 10 | 系统级测试需要先启用第三方键盘，方法未知 | M0 列三种方法并设判停点；fcitx5-ios 已证明 Appium 路线可在 CI 跑 |
| 11 | 模拟器不强制扩展内存上限，测不出 R-1 | 用 `footprint` 采样扩展进程作代理指标；真机验收不可省 |
| 12 | prebuilder 的 `ios` 标签是滚动更新的 | 镜像到自有 Release + SHA256 锁 |
| 13 | 签名密钥在 CI 的安全性 | Secrets 只给手动运行的 `main`；PR / fork 不可见；日志不打印 |
| 14 | 免费账号路线没有 App Group（fcitx5-ios 文档证实） | 写明路线 A 的降级范围，推荐路线 B |
| 15 | 托管镜像默认 Xcode 会变 | 显式选择 Xcode 26.6，`xcode-27` 金丝雀不阻塞 |
| 16 | 实测确认托管机器信息 | `macos-26` arm64 镜像 20261117：Xcode 26.0.1–26.6、iOS 26.x 模拟器（iPhone 17 等）；`xcode-27` 为公开预览标签 |

### 第三轮：功能对等、合规与排期

| # | 发现 | 处理 |
| --- | --- | --- |
| 17 | 审核规则：键盘不得拉起主应用以外的应用；iOS 26 上不开完全访问时拉起主应用会失败 | ⋯ 菜单「设置」改为键盘内快捷设置 + 引导 |
| 18 | 不开完全访问时：无网络、共享目录只读 | 离线 Rime 照常；用户词库落扩展私有目录；AI 按钮置灰并说明 |
| 19 | iOS 不能后台监听剪贴板 | 剪贴板功能对等表写明差异 |
| 20 | 无选区替换 API | 采用逻辑定为「核对后删后插」，核对失败放弃 |
| 21 | 隐私字段判定缺 Android 那个标志位 | 改用 `textContentType` + `keyboardType` 规则表，有单元测试 |
| 22 | 万象语法模型实测 390,786,092 字节 | 默认关闭，M4 只做实验开关 + 内存数据 |
| 23 | GPL 与上架冲突（雾凇数据、第三方 GPL 代码） | iOS 代码不含第三方 GPL；雾凇改为用户下载；上架前单独评估 |
| 24 | 排期是否现实：每次 CI 往返 15–25 分钟 | 估计已含等待；纯逻辑先在 Linux 任务验证，减少 macOS 往返 |
| 25 | 测试 Key 来源 | 在线冒烟只用专门的、有额度上限的测试 Key（GitHub Secret） |

### 第四轮（修订）：改为免费 Apple ID + SideStore 侧载

决定：有 iPhone，不办付费账号，7 天续签侧载。重新审视受影响的部分：

| # | 发现 | 处理 |
| --- | --- | --- |
| 26 | 第一版认定「免费账号没有 App Group」（来自 fcitx5-ios 文档）。读 SideStore 源码 `FetchProvisioningProfilesOperation.swift`：它会把每个 App Group 改名为「原组名.团队ID」在 Apple 开发者后台注册，并分配给主应用和各扩展 → 共享目录**可能可用**，但名字和工程里写的不同 | 新增 `AppGroupLocator`：从包内 `embedded.mobileprovision` 读实际组名，探针文件确认互通；失败退到手动同步（第 4.3、4.7 节）。fcitx5-ios 的说法可能对应写死组名的情况，M0 真机定论 |
| 27 | SideStore 按团队类型过滤能力（`updateFeatures` 中的 `allowedFeatures`），Keychain 跨进程共享在免费签名下不确定 | Key 存储两套后端 + 启动自检（第 4.6 节） |
| 28 | Bundle ID 也可能被重签工具改写 | 代码里不依赖 Bundle ID 字面值；扩展与主应用之间只靠 App Group / 命名剪贴板通信 |
| 29 | 免费账号每 7 天最多 10 个 App ID、同时 3 个应用 | 只用 2 个 App ID（测试宿主只在模拟器）；固定 Bundle ID |
| 30 | 原 `ios-release.yml` 依赖 App Store Connect 密钥和证书 | 改为未签名 IPA + GitHub Release + SideStore 源；CI 不再有签名秘密（第 6.3 节）。第二轮 #13 的密钥保护措施因此不再需要，#14 的结论被本轮推翻 |
| 31 | 7 天过期后键盘被系统停用 | 主应用读到期时间提前提醒；数据不受影响（第 4.8 节） |
| 32 | 真机验证从 M5 提前 | M0 就让你在 iPhone 上装一次诊断版，App Group / Key 后端 / 到期时间当场看清；之后每个里程碑都发尝鲜版 |
| 33 | 排期 | 去掉等待 Apple 处理的时间，M5 缩短；总估计改为 23–33 个工作日 |

## 13. 开工前需要你决定或准备的事

已定：有 iPhone；不办付费账号，用免费 Apple ID + SideStore 7 天续签侧载；iOS 编译测试用 GitHub Actions（Android / Windows 仍只在本地编译）。

还需要你提供或准备：

1. **iPhone 型号和 iOS 版本**（设置 → 通用 → 关于本机）。决定最低系统版本和内存预期。
2. **SideStore 是否已装好**。没装的话，M0 出包前按 SideStore 官方文档在 Windows 上装一次（需要电脑和数据线，只做一次），iPhone 打开开发者模式。
3. **仓库保持公开**（macOS 运行时免费）；如需私有，先评估付费分钟。

## 14. 参考

- fcitx5-prebuilder iOS / macOS 发布：<https://github.com/fcitx-contrib/fcitx5-prebuilder/releases>
- fcitx5-ios（构建、测试、77 MB 内存与 App Group 说明）：<https://github.com/fcitx-contrib/fcitx5-ios>
- 仓输入法 Hamster（MIT 声明、RimeKit、HamsterKeyboardKit）：<https://github.com/imfuxiao/Hamster>
- GitHub 托管 macOS 镜像说明：<https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md>
- Apple：配置键盘的完全访问 <https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard>；创建自定义键盘 <https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard>；App 审核指南 <https://developer.apple.com/app-store/review/guidelines/>
- SideStore（免费账号侧载、7 天续签、3 个应用 / 10 个 App ID 限制）：<https://github.com/SideStore/SideStore>、<https://docs.sidestore.io/docs/faq>；App Group 改名逻辑见其源码 `SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift`
- fastlane 认证（仅付费路线备用）：<https://docs.fastlane.tools/getting-started/ios/authentication/>

## 15. 实施变更（执行中记录）

### M0（2026-11-24）

| # | 变更 | 原因 |
| --- | --- | --- |
| 1 | native-core 不复制进 Swift 包：`OCCore/Sources/CNativeCore/shim.cpp` 用相对路径 `#include` 共享目录里的 `core.cpp` 与 `c_api.cpp`，`private/nlohmann/json.hpp` 转发到共享的 json.hpp | SwiftPM 的 target 目录不能指向包外；复制会有两份协议代码。这样只有一份源码，Android / Windows / iOS 同源 |
| 2 | C 接口的测试写在 `core_test.cpp` 里，用宏 `OC_C_API_TEST` 开关，只有共享 CMake 的测试目标打开 | Windows 的 `orangecell_protocol_test` 也编译同一个 `core_test.cpp`，但不链接 `c_api.cpp`；不加开关会破坏 Windows 构建 |
| 3 | 发布流程并入 `ios-ci.yml` 的 `release` 任务，每次推送 `ios` 分支且构建全绿后刷新 `ios-nightly` 预发布；不再单独写 `ios-release.yml`，也不限定 `main` | 当前只有 `ios` 分支；单文件更简单。SideStore 源写到孤儿分支 `ci-results` 的 `sidestore/source.json`，不动 `main` |
| 3a | 依赖镜像 `ios-deps.yml` 除手动触发外，`ios/deps.lock.json` 变化时在 `ios` 分支自动运行 | `workflow_dispatch` 只对默认分支上的工作流文件生效，没有 API 令牌就无法手动触发 |
| 4 | 链接 librime 时对 `librime.a` 用 `-force_load`，并加 `-framework JavaScriptCore` | 各插件靠 `RIME_MODULE_INITIALIZER`（构造函数）注册，静态库里没人引用的目标文件会被丢掉；`libqjs.a` 在 Apple 平台用 JavaScriptCore 实现，符号分析确认它引用 `JS*` 系列函数。boost 只需 `container` / `iostreams` / `random` 三个库，头文件不必解压 |
| 5 | 打进 IPA 的权限文件只含 App Group，不含 `keychain-access-groups` | SideStore 重签时只依据二进制里的权限去注册能力；`$(AppIdentifierPrefix)` 在 CI 里没有团队 ID 可替换，写进去反而可能让安装后无法启动。Keychain 共享组改由诊断页在真机上用「团队 ID + 约定后缀」实测（第 4.6 节），结果决定后端 |
| 6 | Linux 任务在 `swift:6.2-noble` 容器里跑，用 apt 装 cmake / g++ / JDK 头文件；CMake 的 JNI 查找用缓存变量手工回答 AWT / JVM 库 | ubuntu 托管机没有 Swift 工具链；`default-jdk-headless` 不含 libjawt，FindJNI 会失败，而编 `jni.cpp` 只需要头文件 |
| 7 | 增加结果通道：每个 iOS 工作流最后的 `publish-results` 任务把状态、摘要、失败日志、截图写到孤儿分支 `ci-results`；`ios/scripts/ci_wait.py <sha>` 等待并取回 | 没有带令牌的 GitHub API，看不到日志与产物下载 |
| 8 | 模拟器启用键盘的方法①（启动前在模拟器全局偏好写入 `AppleKeyboards`，条目为扩展的 Bundle ID，如 `io.github.ninmiao.orangecell.keyboard`）直接可用；方法②（XCUITest 驱动「设置」）也跑通，用来打开「允许完全访问」。不需要 Appium | 第 8 节的三种方法按顺序试，前两种已足够；真机上没有这一步，仍由用户在设置里手动添加 |
| 9 | 键盘扩展里的按键用坐标点击，不用无障碍标识；键盘界面用固定高度保证按键位置稳定 | XCUITest 的 `app.keyboards` 看不到第三方键盘扩展（它是远程视图），只能看到宿主文本框；效果用宿主文本框的内容验证。M1 起键盘布局变化时要同步更新坐标，或改为进程内的界面测试（宿主内嵌 `KeyboardViewController`） |
| 10 | 工程里设 `ENABLE_DEBUG_DYLIB = NO` | Xcode 的 Debug 构建默认把二进制拆成桩 + `.debug.dylib`，会扭曲键盘进程的内存数字 |

### M0 实测结果（CI 运行 #5，提交 `f217293`，全部任务通过）

| 项目 | 结果 |
| --- | --- |
| 编译链接 | librime 1.17.0 + 8 个依赖静态库在 Xcode 26.6 下一次链接通过；真机（arm64，iOS 17.0+）与 arm64 模拟器都能构建；`-force_load` 后 lua / octagram / grammar / predict / qjs 模块全部注册；需要系统的 JavaScriptCore |
| 单元测试 | Linux：native-core 780 项（含 C 接口）、OCCore 28 项；macOS：OCCore 32 项；模拟器应用测试 6 项 |
| 系统里显示键盘 | 方法①，系统在 `OCTestHost` 里显示橘脑一颗键盘；点「你」「好」、删除键，宿主文本框得到「你好」→「你」 |
| IPA | 约 4.3 MB，主应用与扩展各带 App Group 权限的临时签名，`ios-nightly` 预发布可下载；SideStore 源在 `ci-results` 分支 `sidestore/source.json` |
| 键盘内存（模拟器） | 只初始化 Rime、不加载词库时 43 MB（`phys_footprint`，自报与 `footprint` 一致）；其中 dyld 私有内存 15 MB、MALLOC_SMALL 10 MB，模拟器的数字偏大，只作代理 |
| 跨进程共享（模拟器，开启完全访问） | 键盘看到主应用的探针文件；Key 存储「加密文件」后端跨进程读取成功，「Keychain 默认组」读不到（两个进程默认组不同，符合预期） |
| 未验证 | 真机：App Group 实际名字、Keychain 共享组是否可用、描述文件到期时间、内存上限、SideStore 安装本身 |

对 M1 的影响：
1. 键盘基线 43 MB（模拟器）已经超过「无语法模型 ≤ 55 MB」预算的七成，M1 加载万象词库前先分析内存构成（`vmmap -summary` 已随 CI 产出），优先查 MALLOC_SMALL 里 Rime 初始化和 JavaScriptCore / Lua 的占用；必要时只在需要时才初始化 qjs / lua 模块。
2. 模拟器里无法区分「真机共享目录权限」：未开完全访问时模拟器也能读写 App Group，真机可能不能；诊断页会显示真实结果。
3. 键盘界面测试改用坐标点击，布局变化要同步更新。

### M1（2026-11-24）

| # | 变更 | 原因 |
| --- | --- | --- |
| 11 | M0 的真机步骤推迟到 M2 之后的集中真机环节 | 编排者决定：用户要求在应用成熟前不被打断；接受的风险是 App Group 名、Keychain 共享组、描述文件到期、内存上限都还是模拟器推断。已知事实（SideStore 源码）：App Group 会变成 `<group>.<TEAMID>`，扩展的 Bundle ID 会变成 `<主应用 ID>.<TEAMID>.keyboard`。代码里没有任何地方依赖扩展的字面 Bundle ID（只有测试和 CI 脚本里有）；App Group 靠描述文件运行时识别（第 4.3 节）。键盘在读不到 App Group 时仍完整可用：词库随应用包提供，用户词典放扩展私有目录（阶段 A 的端到端测试就是这种状态）|
| 12 | 词库在 CI 里编译（`ios/tools/oc_deployer`，固定版本的 macOS 版 librime），随应用包提供；键盘里不做完整部署，主应用的「部署」只编译 `default.yaml`（含 iOS 的 `default.custom.yaml`）到 App Group 的 `rime-user/build` 并写 `state/deploy-stamp` | 键盘进程内存紧，完整部署（编译词典）在手机上既慢又占内存；部署产物与 Android 来自同一份源文件，所以结果相同。方案列表只含 `orangecell_wanxiang`，雾凇（GPL-3.0-only，体积大）不随 iOS 包，语法模型关闭 |
| 13 | Rime 运行时是进程唯一的单例，一个串行队列，各键盘控制器只创建 / 销毁会话；任何控制器的 `deinit` 都不会 `finalize`；传给 librime 的字符串（traits、模块名）进程生命周期内只分配一次，不释放 | 验证者指出：librime 与 glog 是进程全局的，系统可能在旧控制器释放前创建新的，旧控制器的 `deinit` 会拆掉新会话，LevelDB 用户词典有崩溃风险；glog 还会保存 `argv0` 指针 |
| 14 | 运行时只加载 `default` 模块（lua / octagram / predict / qjs 仍然链接、注册，但不为这套方案载入） | 实测引擎 + 词典在 Release 的 XCTest 进程里只比基线多 0.3 至 0.6 MB，载入全部模块与只载入最小集合的差别可以忽略（见 M1 实测结果表），而万象方案本身不用这些插件；以后需要 lua 过滤器时再切换 |
| 15 | 版本号 `0.2.<运行号>`，构建号 = 运行号 | SideStore 靠版本号严格递增判断更新；里程碑给出主、次版本，末位随运行递增 |
| 16 | 候选栏只在单字候选后面显示读音（你 nǐ），词组候选不显示 | 万象给每个候选都带带声调的读音，手机上候选栏会被长读音占满，且词组的读音和上面的输入串重复 |
| 17 | 加密文件密钥存储：读不出的密钥文件不再当作「没有密钥」去覆盖，创建用临时文件 + `link()` 原子完成，AES-GCM 把账户名放进附加认证数据；主应用启动时不再运行密钥自检，只在「诊断」页点按钮或 CI 用 `-OCRunSelfTest` 启动时运行 | 验证者指出：首次解锁前的瞬时读失败或首次创建的竞争会丢失所有密钥 |
| 18 | 许可证：随包带各组件许可证全文（`ios/Resources/licenses`，应用里「致谢与开源许可」页），根目录 `LICENSE-NOTICE.md` 加 iOS 行。OpenCC 上游没有 NOTICE，随包的是 Apache-2.0 `LICENSE`；marisa-trie 取 BSD-2-Clause，zstd 取 BSD-3-Clause | 验证者 A2；双许可组件取宽松一侧 |
| 19 | 系统级端到端测试拆成独立任务：`e2e`（Release，闸门）和 `e2e-debug`（只给 Debug 的内存数字）；XCUITest 通过「请求文件」让脚本去量内存、部署、杀键盘进程；按键位置用屏幕像素确定（键盘顶部、底行有没有地球键） | M0 的脚本只要第一个界面测试通过就退出 0，没有真正的闸门；XCUITest 在模拟器里无法自己量别的进程的内存或杀进程 |
| 20 | 验证者要求「用一个需要 lua / octagram 的方案证明它们真的载入」：随包的万象方案不用这些插件（语法模型关闭，见 12），所以改为两层证据：单元测试 `testLuaPluginRunsATranslatorFromASchema` 在临时用户目录里放一个用 `lua_translator@*oc_probe` 的小方案和一段 Lua 脚本，部署后输入 `luaprobe`，首选候选必须是脚本给出的 `LUA-OK`（CI 里通过，证明 Lua 插件在链接的 librime 里真的载入并运行）；端到端闸门检查键盘自己报告的已注册模块列表含 lua / octagram / predict / qjs。octagram 没有语法模型可用，只证明了注册 | 没有现成的、需要这些插件的方案；注册表里有这些模块说明静态构造函数没有被链接器丢掉（M0 已证实），Lua 的实际运行由探针方案证明 |
| 21 | 键盘的用户词典位置随「完全访问」变化：开启时在 App Group 的 `rime-user`，关闭时在扩展私有的 `Application Support/rime-user`，切换时不迁移 | 没有完全访问就读不到 App Group；用户在中途开关完全访问时之前学到的词会「消失」（还在另一个目录里），M2 前要决定是否迁移或提示 |

### M1 实测结果（CI 运行 #14，提交 `1c69509`，全部任务通过，发布了 `ios-nightly` 0.2.14）

| 项目 | 结果 |
| --- | --- |
| 测试 | 模拟器应用单元测试 15 项（真实词库：nihao → 你好 / 你号 / 拟好 …；woyaochihuoguo → 我要吃火锅；学词；Lua 探针）、OCCore macOS 40 项与 Linux 全过、进程内键盘界面测试 10 项（含深浅色、横屏截图）、系统级端到端（真键盘扩展）全过 |
| 键盘内存（模拟器，Release，`footprint` 从外部量） | 打完一句（含退格、EN 输入）后 **46.0 MB**；学词后 45.0 MB；进程被杀后重启再输入 44.0 MB。预算 55 MB，余量 9 MB。进程内 `phys_footprint` 自报 46.1 / 44.8 MB，与外部测量一致 |
| 键盘内存（模拟器，Debug，仅作比较） | 打完一句后 46.0 MB，与 Release 相同（`ENABLE_DEBUG_DYLIB = NO` 之后 Debug 不再被拆成桩加动态库，数字没有被扭曲） |
| 内存构成（打字后，Release） | dyld 私有内存 16 MB、MALLOC_SMALL 12 MB、`__DATA` 7.0 MB、`__DATA_CONST` 6.1 MB、页表 1.6 MB、CoreAnimation 1.4 MB。M0 不带词库的基线是 43 MB，所以词库、引擎和一次打字一共只多出约 3 MB：56 MB 的 `table.bin` 是内存映射，几乎不占脏页。dyld 私有的 16 MB 和 `__DATA` / `__DATA_CONST` 在 M0 就被判断为模拟器上偏大的部分（M0 的 15 MB 与此相近），真机上预计更小，但没有测过（真机步骤推迟，见第 11 行） |
| qjs / lua 的代价 | 在 Release 的 XCTest 进程里，引擎加词典加打完一句比基线多 0.3 MB（只载入 `default` 模块）或 0.6 MB（载入链接进来的全部模块）。键盘运行时只载入 `default`；插件虽然链接，注册表里有，但这套方案用不到，所以没有为它们付内存 |
| 用户词典与进程重启 | 选一次「拟好」后它升到首位（单元测试：1 轮）；主应用在键盘运行期间部署（`default.yaml` 重新编译，部署戳更新），键盘照常打字；杀掉键盘进程（`kill -9`）再启动新进程，「拟好」仍是第一候选，用户词典没有损坏 |
| 无完全访问 | 引擎照常运行，用户词典在键盘私有的 `Application Support/rime-user`，诊断报告 `userDataShared=false`（阶段 A） |
| 发布 | `ios-nightly` 预发布里的 `OrangeCell-iOS-0.2.14.ipa`，31 983 170 字节，SHA-256 与 `sidestore/source.json` 一致；两个 Info.plist 的 `UIDeviceFamily = [1]`，带 AppIcon，`licenses/` 与 `rime-shared/licenses/` 在包里；源里声明的 entitlements 与二进制带的一致（`com.apple.security.application-groups`） |
| CI 耗时 | `e2e`（Release，闸门）19 分钟，`e2e-debug` 15 分钟，`build-test` 17.5 分钟，三者并行，整次运行约 20 分钟 |
| 未验证 | 真机（App Group 实际名、Keychain 共享组、描述文件到期、真机内存、SideStore 安装）；键盘在引擎还没接上时就被点击的行为（模拟器里开启完全访问后的第一次启动，第一个字母曾以普通文本插入一次，没有查实原因，加了 `unhandledLetters` 计数和端到端检查，后续运行为 0）；候选栏中读音的长度对其他方案的影响 |

对 M2 的影响：
1. 内存余量足够，M2 做 AI 候选（网络请求、JSON、响应缓存）时每增加一项都要在 `e2e` 里看 `footprint` 的变化，预算保持 55 MB；超预算的停止规则仍按第 9 节。
2. 用户词典在「完全访问」开关两侧不互通（第 21 行）：M2 前要决定是否迁移，或在应用里提示。
3. 系统在扩展下面自己画了一条带地球键和麦克风的栏（iOS 26，这种机型 `needsInputModeSwitchKey` 为假，我们的底行没有地球键）；键盘高度 282 pt 不含这一条，系统级测试靠截图像素确定键盘顶部，不依赖它。
4. 系统级测试靠像素和布局规则点按键，键盘布局或配色变化时要同步 `KeyboardUITests` 里的度量（`Metrics` 与按键行权重），端到端里「教键盘」的候选序号（第三个，一次）由单元测试断言，词库更新后这个断言会提醒更新。
