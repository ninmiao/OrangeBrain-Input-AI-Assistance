# Zephyr Input

微风输入法 · Zephyr

Android 输入法，基于完整 Trime v3.3.7，默认词库为雾凇拼音。最新版 **1.3.0**；项目位于桌面 `Zephyr-Input`，上游许可证及设计文档保留。

## 1.3.0：多候选与排序

- AI 候选数量可选 1–5 个，默认 3 个，合理候选按可能性排序；不足时不强凑。
- 横向滑动查看全部候选，新结果回到首项；点击候选上屏。
- 数量约束同步用于键盘、Policy 样例与测速，旧配置无需迁移。
- 详情见 [1.3.0 说明](docs/ai/zephyr-1.3.0.md)。

## 1.2.0：Policy 延迟、模型能力与空格分词

- Policy 列表与详情页均有延迟快捷测试。每次只使用该 Policy 的接口、Key、模型、提供商与参数发出一次固定样例请求，显示完整候选返回耗时；不切换当前 Policy，也不依赖另一 API 的 Key。
- 思考强度按模型适配。DeepSeek V4 Flash 0731 为 none / low / high / max；GPT-6 Luna 为 none / low / medium / high / xhigh / max；GPT-5.4 nano 不显示 max；GPT-4.1/4o 不发送思考参数。未知模型不套用通用档位，可刷新 OpenRouter 能力元数据或维护对应能力 JSON。
- OpenRouter 刷新模型列表同时读取 reasoning.supported_efforts 与 mandatory；强制思考模型不会显示关闭项。测速修改模型后会刷新思考选项。
- “空格分词（中文键盘）”默认开启：拼音留在键盘顶部，空格标记词组边界。例如 hanbaowang haochi 不提前写入应用文本栏，点击本地或 AI 候选后才上屏。长按空格拖动光标仍可用；关闭开关恢复原空格选词行为；英文和密码输入不受影响。
- 验证：27 项核心测试、19 项模拟器回归通过。延迟测试使用本地 HTTPS 测试服务，本次未调用真实云端模型。S26 未连接，手机尚未更新。

能力核对日期：2026-11-09。[OpenAI 模型目录](https://developers.openai.com/api/docs/models)、[OpenRouter reasoning 元数据](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)、[DeepSeek 思考档位](https://api-docs.deepseek.com/guides/thinking_mode/)。

## 1.1.0：空格光标与双 API

- 长按空格后左右拖动移动光标，松手不会多输入空格；短按仍输入空格。遵循键盘震动设置。
- 默认两套独立 Policy：OpenAI / gpt-6-luna / none / default；OpenRouter / deepseek/deepseek-v4-flash-0731 / wafer/us / 无思考。
- OpenRouter 无思考发送 `reasoning.enabled=false`；固定提供商发送 `provider.only=["wafer/us"]`、`allow_fallbacks=false`。普通速度不加排序，Fast 使用延迟优先排序，仍受提供商限制。
- 两家分别配置加密 Key，升级保留已有 OpenAI 凭据；不共享或迁移 Key 到其他 API。
- 一键测速总计 2–5 组，两家各至少 1 组；默认 4 个 OpenAI 小型模型和 1 个 DeepSeek Flash。每组可修改 Policy、模型、思考、速度和 OpenRouter 提供商。开始前验证所有组的凭据，无 Key 时不发送请求。
- 25 项 JVM 测试与 17 项模拟器回归通过，包括左右移动、松手/取消不插入空格、密码保护、Policy 迁移和双 API 凭据预检。本次未执行真实云端测速。

核对日期：2026-11-07。[OpenRouter 模型端点](https://openrouter.ai/api/v1/models/deepseek/deepseek-v4-flash-0731/endpoints)、[reasoning 文档](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)。

## 发布源码

新仓库发布与构建说明见 [PUBLISHING.md](docs/PUBLISHING.md)。开发工具、Boost 下载目录和安装包已由 `.gitignore` 排除。环境版本、工具安装与构建方法见 [DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 安装

手机安装 `dist/Zephyr-Input-arm64-v8a.apk`；模拟器安装 x86_64 版本。覆盖安装会保留词库、自定义配置和已有加密 Key。应用 ID 为 `com.osfans.trime.ai.demo`，新安装数据目录 `/sdcard/ZephyrInput`（已有安装沿用 `/sdcard/rime-ai`），与原版 Trime 分开。

首次安装打开应用，授予文件权限、启用并选择输入法，等待词库部署。改名版本支持直接覆盖升级，既有词库、Policy 和加密 Key 保留。

## 品牌与升级兼容

项目与应用统一命名 **Zephyr Input**，中文名 **微风输入法 · Zephyr**。应用安装标识、密钥别名、已有数据路径和 Rime 方案内部 ID 保留，以便覆盖安装及读取已有加密数据；它们不是对外产品名称。历史测试记录保留当时名称。上游资料位于 `docs/upstream`。

## ai.10 更新

候选栏上方增加 12 sp 小号原始输入提示，如 biru；输入清空或上屏后自动隐藏，密码框不显示。详见 [输入提示记录](docs/ai/raw-input-v10.md)。

## ai.9 更新

AI 候选和补全改为透明平面文字样式，去掉系统按钮背景和阴影，保留按压波纹。详见 [样式记录](docs/ai/candidate-v9.md)。

## ai.8 更新

繁简切换改为无凸起背景的灰色文字按钮，配细分隔线和轻微按压波纹，位置与点击范围保留。详见 [样式记录](docs/ai/script-button-v8.md)。

## ai.7 更新

顶部候选在 ai.6 基础上增大 10% 至 18.15 sp；AI 候选使用相同字号与字体，AI 行高降为 28 dp。详见 [字号与行高记录](docs/ai/candidate-v7.md)。

## ai.6 更新

设置首页新增 AI 辅助设置入口；繁简按钮移到右侧；本地候选字号缩小 25% 并隐藏顶部拼音；中英键文字缩小 15%。16 项模拟器回归通过，已更新 S26，详见 [修改与验证](docs/ai/keyboard-v6.md)。

## ai.5 更新

高度标题跟随界面语言；开启或修改按键震动、声音设置后即时预览。已在模拟器和 S26 覆盖安装并检查，详见 [本次修改与验证](docs/ai/feedback-v5.md)。下方 16 项整套回归与五模型真实测速为 ai.4 的记录。

## 键盘与输入

- iOS 英文键盘式四排 QWERTY：第一排 q–p，第二排 a–l 居中，第三排 Shift / z–m / 删除，第四排 123 / 中英 / space / return。数字和符号各有对应页面。
- 空格左侧的 **中 / EN** 只切换中文与英文，不切换系统输入法。
- AI 候选栏只有候选、状态和 **简 / 繁** 切换。繁简同时作用于本地 Rime 候选与 AI 输出。拼音词库仍以简体数据为基础，繁体通过 OpenCC s2t 转换。
- 中文模式：拼音纠错为汉字，英语纠错后仍为英语，中英混输自然保留；英文模式：先检查英语，中文或中英混输则翻译为英文。
- AI 设置中可开关按键震动、按键音和放大弹出动画；键盘高度可调 180–340 dp，下次打开键盘生效。

## AI 设置与 Policy

主界面第一项 **AI 辅助设置 / AI assistant settings** 直接进入，右上角菜单入口也保留。

1. 页面保留启用 AI、停手自动请求、有限前后文、独立补全与表达风格。
2. 数值框均有固定名称与单位：停手等待、请求超时、前文上限、后文上限、当前输入上限。
3. 下方 **Policy** 列表单选当前方案；点击编辑可分别设置接口、Key、模型参数和提示词。新增 Policy 不复制旧 Key。
4. 新建 Policy 默认 `https://api.openai.com/v1/chat/completions`、`gpt-6-luna`、`reasoning_effort=none`、`service_tier=default`。
5. 修改 Key 须验证设备身份。Key 以 Android Keystore 加密，保存在私有 no-backup 目录，与 Policy 及 HTTPS 来源隔离。
6. 在 Policy 内可手动编辑提示词、恢复内置提示词、预览请求或发送样例。模型名称可手填、刷新 `/models`；参数能力列表可本地编辑或导入/导出。
7. 返回列表勾选 Policy 即切换整套连接、密钥、参数和提示词；旧候选同时失效。

远程提示词 JSON 地址及远程模型能力 JSON 地址入口已移除，不再自动更新。此前单一配置与 Key 自动归入“默认 Policy”。已有用户提示词覆盖保留。

AI 默认关闭；未配置、无网或服务失败时仍能离线输入。适配的是非流式 Chat Completions 协议，不限制为 OpenAI。每个供应商、模型支持的参数需按其接口维护。

## 一键测速

AI 设置顶部或任意 Policy 编辑页进入。每次 1–5 组，可分别修改模型、推理强度、速度模式。默认 GPT-6 Luna、GPT-5.6 Luna、GPT-5.4 nano、GPT-4.1 mini、GPT-4o mini，均无推理、普通速度。配置按 Policy 保存。

点击一次后，所有组依次发送共同样例，显示完整响应耗时、候选或失败原因，并标出本次最快的成功组。可停止后续请求；失败不影响下一组。单次测速不是稳定性能排名，模型可用性以接口和账号为准。

## 构建与测试

本机已有项目内 JDK 17、SDK 35、NDK 28、CMake、adb 和 Android 15 模拟器，无需再装 Android Studio。

```powershell
.\script\test-zephyr.ps1
.\script\build-zephyr.ps1 -Variant demo -Abis arm64-v8a,x86_64
.\script\build-zephyr.ps1 -Variant debug -Abis arm64-v8a,x86_64 -IncludeTests
.\script\test-android.ps1 -SkipBuild
# 连接已授权且解锁的 ARM64 手机后：
.\script\test-phone.ps1 -Device <adb设备编号>
```

22 项核心测试与 16 项模拟器集成测试通过。固定响应测试使用假 Key 和本机 HTTPS 服务，覆盖输入、隐私、参数、Policy、词库和新测速页面。S26 的 16 项真机回归也已通过，并使用手机已有 Key 完成 5/5 真实云端测速。此前 ai.3 的 7 个真实 Luna 语言样例保留为历史验证。

详见 [一键测速与验证记录](docs/ai/benchmark-v4.md)、[键盘改版记录](docs/ai/redesign-v3.md)、[模型参数说明](docs/ai/model-parameters.md)。本次 S26 记录见测速验证文档。

APK 使用本机调试签名供测试安装，Demo 不启用 debuggable、不包含测试证书。第三方编辑器、长期稳定性、真实硬件声音/震动体验仍需后续验收；iOS 应用尚未实现。
