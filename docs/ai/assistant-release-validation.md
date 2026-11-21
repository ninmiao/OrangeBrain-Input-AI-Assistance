# 双候选实装验证 · 2026-11-17

目标版本：Windows 1.10.0 / Android 1.8.0。采用 `tests/prompts/assistant-proposal-v7.json` 的 `L_no_info_en`，不修改已审核的英文正文。

## 行为

- 输入设置的 AI 开关旁增加“纠错＋助手”，默认开启；关闭后为原仅纠错模式。
- 第一项纠错，第二项按意图提供简短答案、建议、续写、术语或颜表情。中文模式允许中英文混输；英文模式输出英文。
- 两端显示纠错/助手标签，点击只上屏候选正文；同文双候选保留角色位置。
- 旧配置未包含新字段时启用助手；保留已有 Policy、Key、前后文与参数。Windows 仍需手动保存设置，Android 沿用现有保存方式。
- 第二项被服务端截断时保留完整第一项；没有完整候选的重试仍受原总超时约束。
- Gemini 实测会给 JSON 添加 Markdown 外壳。仅在助手模式兼容包住整个 JSON 的完整代码块，不从解释或思考中搜索/提取数组。

## 已完成

- Windows C++ 测试：核心格式、解析、截断；WinHTTP/管道接口；候选组合和选择；文本范围及快捷键回归。
- Windows 界面自测：模式切换在保存前不写盘，保存后生效；保留默认尺寸不滚动、Policy 复制、手动保存和多选测速检查。
- 真实 Windows C++ 请求：Gemini 3.8 Flash / low、GPT-6 Luna / medium、GPT-6.1 Terra / low，普通速度，每个模型两条样例（带前文续写与英文模式术语）。
- 首轮 4/6 成功，Gemini 两次格式错误；检查发现完整 JSON 代码块。修复后复测 6/6 均返回两个可解析候选，延迟 1326–7922 ms。三个模型均从数列前文给出斐波那契数列；术语回答有的较长，不将协议通过率当作语义准确率。
- 原中英文完整提示词对照的 276 次请求仍保存在实验记录中；本轮针对真实客户端接入补测，不替代此前结果。

## Android 模拟器

13 项针对性回归均有通过结果：`AssistantModeTest` 5 项、`AssistantKeyboardTest` 1 项、`NativeCoreAndroidTest` 3 项、`NativeApiTransportTest` 1 项、`CandidateCountTest` 2 项、`SegmentedCandidateTest` 1 项。

首轮 10/13 通过：旧模拟服务抢占同一端口，导致双候选测试拿到旧单候选；设置开关测试未等待异步保存。停止旧服务并修正测试等待后，相关两个测试类共 6 项全部通过，包括三 API × 中英文模式和助手候选正文点击上屏。这些是本地 TLS 模拟响应测试，真实模型抽测在上方 Windows C++ 请求链路完成。

## 状态

Windows 1.10.0 已覆盖安装到 `C:\Program Files\OrangeCell`，文件哈希与构建一致，三个 Policy 的 Key 保留，无需重启；32/64 位注册与系统激活检查通过。Android 1.8.0 ARM64 与 x86_64 APK 已构建，模拟器调试版已更新至 1.8.0；未更新手机，未推送 GitHub。

SHA-256：

- Windows Setup（含静默安装启动修复）：`358b5e414dcabe45a1a4ea21c52ab13142b61f253c10127d501c411297cf35f5`
- Android ARM64 APK：`ee8f81a40cf5181bed666d0c6968c8eff2745451831d0cf2a8facc9206d999b7`
