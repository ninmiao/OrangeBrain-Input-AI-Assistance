# 一键测速 · 3.3.7-ai.4

日期：2026-11-07。入口：AI 设置顶部 → **一键测速（最多 5 组）**；也可从任意 Policy 的编辑页进入。

## 使用方式

1. 使用所选 Policy 已保存的接口和加密 Key。测速不会切换正在使用的 Policy，也不会改变输入法模型或启用 AI。
2. 默认五组；可删除至一组或添加至五组。每组点击“修改”可手填模型 ID，或从本地模型列表选择；推理强度、速度模式分别选择。
3. 修改共同输入样例、中英文模式、每组超时后，点“保存测速配置”或直接“一键开始测速”。每组只请求一次，顺序执行，没有重试。
4. 页面显示每组完整候选返回时间、首个候选或失败原因，以及本次成功组中最快的一组。失败后继续下一组。
5. “停止后续测试”停止队列；当前连接会在设定超时前结束。离开页面同样取消，回来不会自动发起请求。

配置按 Policy 单独保存；删除 Policy 时一并删除测速配置。测速结果仅保留在本次页面内。API Key 不写入测速配置、日志或测试报告。

## 默认模型与参数

| 模型 | 推理 | 速度 | 实际参数 |
|---|---|---|---|
| gpt-6-luna | 无推理 | 普通 | reasoning_effort=none, service_tier=default |
| gpt-5.6-luna | 无推理 | 普通 | reasoning_effort=none, service_tier=default |
| gpt-5.4-nano | 无推理 | 普通 | reasoning_effort=none, service_tier=default |
| gpt-4.1-mini | 无推理 | 普通 | 省略 reasoning_effort, service_tier=default |
| gpt-4o-mini | 无推理 | 普通 | 省略 reasoning_effort, service_tier=default |

按小型、低成本系列预填，不代表官方参数量排名，也不保证当前账号或第三方接口开放这些模型。部分旧型号已进入弃用期。关闭推理与省略参数是不同选择：对推理模型省略参数可能使用服务端的默认推理档位。GPT-5 / mini / nano 初代不支持 none，选择关闭会明确失败，不会暗中降级为 minimal。GPT-4.1 / GPT-4o 系列是无推理模型，选择推理档位同样明确失败。

手动选项包括 none / minimal / low / medium / high / xhigh / max / 跟随服务端，以及 default / priority / auto / flex / 跟随服务端。并非每个模型支持所有值；API 不接受时显示 HTTP 状态，不回退、不重试。Fast 表示请求 priority 服务档位，可能额外计费，不保证固定加速倍数。

官方依据（2026-11-07 核对）：[GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)、[GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna)、[GPT-5.4 nano](https://developers.openai.com/api/docs/models/gpt-5.4-nano)、[GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini)、[GPT-4o mini](https://developers.openai.com/api/docs/models/gpt-4o-mini)。

## 测量口径

使用单调时钟测量完整非流式请求的端到端时间，包含连接、网络传输、服务端处理和候选协议解析。不是首 Token 延迟或 tokens/s。每组使用相同输入、所选 Policy 提示词、表达风格、繁简及补全设置；只覆盖本组模型、推理和速度，不继承 Policy 中额外的模型参数。

单次结果受网络、缓存、输出长度、服务端排队影响。只有有效候选的成功组参与“本次最快”比较；错误、空候选、超时均不算成功。不自动读取编辑器内容。

## 验证

- 22 项 JVM 核心测试：新增五项覆盖默认参数、1–5 上限、禁止无声参数回退、顺序和耗时、失败后继续、取消后不发送下一组、错误信息不泄露服务端正文。
- 16 项模拟器集成测试：新增两项覆盖配置持久化及 Policy 隔离，以及实际页面修改推理/速度、五次 HTTPS 请求的参数校验、HTTP 400、超时和活动 Policy 保持。
- 集成测试使用本机 HTTPS 固定响应与假 Key；另在 S26 正式版使用已有 Key 完成五模型真实测速，5/5 成功。
- ARM64 与 x86_64 构建；模拟器和 S26 均覆盖安装。S26 的 16 项真机回归通过，耗时 37.798 秒；手机原有 Key、Policy 和词库保留。

完整集成结果见 `android-benchmark-test-results.txt`，安装包 SHA256 见 `../../dist/SHA256SUMS.txt`。


## S26 真实云端测速

手机正式版通过页面一键发送，所有组使用相同样例 `wojintianyoumeeting`，无推理、普通速度。

| 模型 | 完整响应耗时 | 结果 |
|---|---:|---|
| gpt-6-luna | 1277 ms | 我今天有 meeting |
| gpt-5.6-luna | 1232 ms | 我今天有 meeting |
| gpt-5.4-nano | 1013 ms | 我今天有 meeting |
| gpt-4.1-mini | 601 ms | 我今天有 meeting |
| gpt-4o-mini | 816 ms | 我今天有 meeting |

本次 4.1 mini 最快；只是一轮测量，未据此修改输入法默认模型，仍为 gpt-6-luna。

真机测试发现下拉菜单动画需要等待，测试脚本已修正；正式页面另修复异步加载后的状态栏留白，重新构建并安装。

记录：`benchmark-s26-test-results.txt`、`benchmark-s26-live-results.txt`。
