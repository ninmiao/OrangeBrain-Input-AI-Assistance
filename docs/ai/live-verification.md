# 真实 API 验证记录

测试日期：2026-11-06；原始报告时间：2026-11-06T22:54:40.548442+00:00。使用用户授权的临时 Key，直连 `https://api.openai.com/v1`。测试正文均为固定合成样例，不读取用户输入历史。

## 最终结果

- 内置提示词 **1.2.2**，SHA-256 `538a24c446f6c0b757da7a6ae7c3f1f01ecfac00801388047a4da58d689b62f2`，与交付源码/资源一致。
- **16 个样例 × 5 种风格 = 80 次正文请求，80/80 HTTP 成功，80/80 严格 JSON 校验通过。** 这不是全部语言质量满分的声明。
- **8 个有效参数组合成功，2 个故意不兼容组合按预期返回 HTTP 400。** 普通档位返回 `default`，Fast 返回 `priority`。
- 最终 Android 实测用例通过：真实模型发现、中文/英文请求、priority、low 推理、Rime 拼音候选上屏一次、英文片段替换、密码隐私状态。17 项 JVM 测试及 8 项固定响应 Android 回归仍通过。
- 设备测试密文与 Keystore 别名已删除，AI 关闭；临时本机凭据通道只允许读取一次。源码、APK、报告不包含 Key。

## 参数实测

| 参数场景 | 模型 | HTTP | 实际档位 | 单次秒数 |
|---|---|---:|---|---:|
| omitted | gpt-4.1-mini | 200 | default | 0.618 |
| normal | gpt-4.1-mini | 200 | default | 0.6 |
| fast | gpt-4.1-mini | 200 | priority | 0.575 |
| temperature | gpt-4.1-mini | 200 | default | 0.864 |
| top-p | gpt-4.1-mini | 200 | default | 0.744 |
| reasoning-minimal | gpt-5-mini | 200 | default | 0.974 |
| reasoning-low | gpt-5-mini | 200 | default | 2.207 |
| reasoning-none | gpt-5.4-mini | 200 | default | 0.571 |
| invalid-reasoning | gpt-4.1-mini | 400 | — | 0.183 |
| invalid-temperature | gpt-5-mini | 400 | — | 0.127 |

普通/Fast 是服务档位，推理强度是独立参数。HTTP 400 场景分别为给 gpt-4.1-mini 发送 reasoning_effort，以及给 gpt-5-mini 发送 temperature=0.2；应用不会暗中改参数重试。[官方 Fast 文档](https://developers.openai.com/api/docs/guides/fast-mode)、[Chat Completions 参数](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)。

可导入的 `models-openai-tested.json` 包含本轮用过的参数子集。枚举按观察结果筛选；数值范围是便于使用的保守配置，未逐个测试全部取值。它不是 OpenAI 自动提供的完整能力清单，也不是账户权限承诺。

## 质量与修复

最初 v1.1.0 发现同音错字凑候选、重复候选、错误语言、错误补全；初轮还出现一次服务端 HTTP 500。保留 `live-results-initial.json` 作为原始记录。修订提示词后，优先返回一个可靠候选，强化英文输出、错拼纠正、候选去重、截止日期语义和补全规则。原始失败没有从报告中抹去。

已人工检查正文输出中的拼音纠错、英文语法、翻译问题而不回答、否定、may 等不确定性、金额、专有名词、emoji，以及输入中的指令仅作为待译文本。补全样例缺少讨论对象，最终允许返回空补全，避免补造主题。

仍需注意：

- style-long/minimal: 仍保留赘词，风格强度不足
- style-long/formal: 仍保留赘词，风格强度不足
- style-long/academic: 仍保留赘词，风格强度不足
- GPT-4.1 mini 的风格强度不稳定；长文本的极简/正式/学术仍可能保留口头赘词。GPT-5.4 mini 的 5 条对照中，极简输出更短，但这不是完整模型排名或全场景评测。
- 短句可能在五种风格下完全相同，这是保留原意的可接受结果；不能靠制造错误候选体现差异。
- 合成小样本不能保证未来输入、其他模型、其他服务或第三方编辑器全部正确，采用前仍由用户预览决定。

## 延迟与用量

最终 80 次正文请求（主机 HTTPS、最多两个并发）中位数 **0.679 秒**，P95 **0.900 秒**，最大 **11.035 秒**。这不含键盘防抖和设备渲染；Fast/普通各一次的结果不足以证明稳定加速比例。主机与 Android 真实测试使用 45 秒上限；应用默认仍按设计使用 10 秒，可在设置中改为 30 秒以容纳长尾请求。因此本报告不表示所有样例都在默认超时内完成。

全部保留的主机批量报告合计 **310 次 POST**；成功响应报告输入 **148,254 tokens**、输出 **7,284 tokens**（推理 token 计入模型返回用量）。另外有首次连通性请求和两轮 Android 真实集成请求；其 token 未纳入此主机汇总。这里不推测账单金额，实际计费以服务账单为准。

## 复现与证据

- `live-results-release.json`：最终 90 个 API 场景的完整合成结果、HTTP、模型快照、参数、服务档位和用量。
- `live-results-*.json`：各次修复前后报告；`live-results-style-gpt5.4-mini.json` 为 5 条模型对照。
- `android-live-test-results.txt`、`live-android-report.txt`：最终模拟器真实调用记录。
- `android-test-results.txt`：8 项本机 HTTPS 固定响应回归。
- `screenshots/live-chinese.png`、`screenshots/live-english.png`：最终真实候选截图。

真实测试工具 `script/live-api-session.py` 使用隐藏输入读取 Key，不接受命令行明文 Key。启动后输入 `{"suite":true,"suffix":"my-run"}` 会执行有费用的固定测试；`{"exit":true}` 退出并关闭本机通道。`{"bridge":true}` 创建一次性本机 TLS 通道，输出的通道编号传给 Android 测试参数 `live_bridge_token`，它不是 API Key。仅在专用模拟器使用；不要在含个人凭据的 debug 应用运行。默认常规测试不执行 `AiLiveTest`，没有通道编号时该用例跳过。

尚未完成：真机、Android 6–14、其他厂商系统/第三方编辑器矩阵、其他云服务，以及发布签名/商店分发。Android 开发环境已经安装在项目 `.tools/`，无需另外安装 Android Studio 才能构建。
