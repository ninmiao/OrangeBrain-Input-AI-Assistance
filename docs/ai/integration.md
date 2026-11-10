# Rime AI Android 接入

基于 Trime v3.3.7 (`ac13dd4790523c1a9778cfb70234fe485fd3c526`)，保留上游键盘、Rime 引擎、词典、本地候选、主题和启用流程。修改代码遵循仓库 GPL-3.0-or-later 声明。

## 实际接入位置

- `TrimeInputMethodService` 创建 `AiKeyboardController`，转发会话开始/结束、选区、组合串、状态和上屏消息。
- `InputView` 在原 QuickBar 下加入独立 AI 工具栏和候选区。原本地候选的排序和选择路径保持不变。
- `CommonKeyboardActionListener`、本地候选点击入口和物理按键入口，在操作前立即废弃 AI 结果。
- `Rime.rawInputCached` 提供原始组合串；`Status.isAsciiMode` 决定系统提示词的语言规则。
- `PrefMainActivity` 菜单和键盘工具栏打开 `AiSettingsActivity`。

## 请求和采用

`AiRequestCoordinator` 在主线程串行调度，作用域绑定输入法生命周期。每次请求包含不可变输入、最终系统提示词、补全开关以及会话/文本/配置/语言代数。网络取消仅为优化，结果显示与采用均再次检查代数。

Rime 组合串采用时先串行清除 Rime 组合状态，然后清除编辑器 composing 区域并提交 AI 文本；不会通过本地候选学习路径写入词库。直接文本采用时核对 ExtractedText 全文快照、光标/选区和原目标文字，然后只替换已核实范围。编辑器不提供完整可靠范围时放弃增强。提交标记禁止自身再触发 AI。

`EditorRanges` 使用 UTF-16 偏移，检查字符边界、emoji/ZWJ 和句子范围。超过目标限制直接放弃，不截断目标。组合串上下文留空，避免重复发送 preedit。

## 配置和网络

`AiStore` 用 AtomicFile 保存配置并在成功落盘后发布 StateFlow。生效优先级为本地整包覆盖、当前激活包、内置包。远程更新保留本地覆盖、自定义风格及最近五个历史版本。来源变化不会自动激活；自动检查默认关闭，间隔 24 小时。

`CredentialStore` 使用 Android Keystore AES-GCM，密文绑定 HTTPS origin，位于 no-backup 私有目录。修改和清除凭据需系统身份验证。设置页禁止截图，秘密字段不恢复视图状态。输入法后台读取密文不要求每次弹出系统验证。

API 仅支持非流式 Chat Completions 的文本 `message.content`，HTTPS、禁止重定向、禁止自动重试、严格三字段输入和 JSON 响应校验。连接/读取超时之外有总截止时间断开连接。提示词下载使用独立请求，不附带 API Key 或输入文字。

## 构建差异

Android 最低版本 23，适配 Keystore AES-GCM。独立 applicationId，demo 变体禁止调试并排除本地测试证书。Windows 构建通过生成资源目录解析 Git 符号链接，避免把链接文本装成词典；插件 junction 和 Lua 补丁准备为幂等脚本。

核心和模拟器测试、已知边界见 `verification.md`。真实模型效果及第三方编辑器兼容性不能由固定响应服务证明。


## 模型与参数扩展

`ModelCatalog` 定义可维护的模型能力清单，`ModelsClient` 只发现模型 ID。`ModelSettingsActivity` 提供模型切换、推理/服务档位、数值参数及 JSON 编辑/导入/导出/HTTPS 手动更新。清单不覆盖连接或凭据。

`AiStore` 在配置原子提交时校验清单、剔除无效选择并递增统一配置代数。参数按模型保存、按精确 endpoint 隔离。`ChatCompletionsClient.payload` 将已校验参数加入请求顶层，用户消息依然只有 input/before/after。默认空参数字典完全省略可选字段。设置页测试和键盘使用同一组参数。

模型枚举和现有参数取值可通过清单更新。新增请求字段或原生供应商协议需要代码适配，不能通过清单任意覆盖 transport/messages。
