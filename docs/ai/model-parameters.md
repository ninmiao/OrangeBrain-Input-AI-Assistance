# 模型与参数设置

本次增加模型发现、模型选择、可维护的能力列表和按模型保存的请求参数。当前适配器使用非流式 Chat Completions，可连接满足相同请求/响应格式及 Bearer 鉴权的 HTTPS 服务；不限制域名为 OpenAI。尚未实现 Anthropic Messages、Gemini 原生协议或 OpenAI Responses 协议适配。

## 使用方法

1. 在「AI 设置」的 Policy 列表中编辑对应 Policy，再验证身份并填写接口、Key 和模型 ID。每个 Policy 独立保存。
2. 打开「模型与参数（模型列表 / Fast / 推理强度）」。可以直接填写模型 ID、从本地列表选择，或点「刷新模型列表」。
3. 刷新会将标准路径 `/chat/completions` 替换为 `/models`，保留 HTTPS 来源、端口和前缀。例如 `/api/v1/chat/completions` 对应 `/api/v1/models`。只向同一来源发送已有 Key，不跟随重定向。不支持该接口的服务仍可手填模型。
4. 为当前模型添加常用参数模板，然后根据该模型的官方文档删除不支持的参数或枚举。模板不会开启参数，也不代表服务或模型全部支持这些能力。
5. 选择服务档位、推理强度或数值参数。新建 Policy 的 gpt-6-luna 默认显式发送 reasoning_effort=none、service_tier=default；其他参数初始不发送。参数按模型保存；切换接口地址会清空模型列表和参数，避免跨服务误用。
6. 用「预览实际模型参数」检查将发送的字段，再在 AI 设置中发送测试样本。HTTP 错误只显示状态码，不展示响应中的敏感内容，不自动改参重试。

## 两个独立的设置

| 设置 | Chat Completions 字段 | 含义 |
|---|---|---|
| 普通 / Fast | `service_tier` | 请求处理服务档位。模板中普通为 `default`，Fast 为 `priority`。 |
| 关闭 / 轻度 / 普通 / 深度等 | `reasoning_effort` | 推理投入；可选值由每个模型的能力列表决定。 |

Fast 不等于关闭推理。OpenAI 当前文档接受 `fast` 或 `priority` 请求 Fast；本轮 gpt-4.1-mini 实测响应档位为 `priority`；账户、模型可用性及价格仍需核对。推理可选值因模型而异，不能把 `none` 当作所有模型通用的关闭开关。[Chat Completions 参数文档](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)、[推理指南](https://developers.openai.com/api/docs/guides/reasoning)。查阅日期：2026-11-06。

## OpenAI 提供什么信息

`GET /v1/models` 提供模型 ID、创建时间、归属方和部分可用性信息，当前公开响应 schema 不包含各模型完整的参数范围、推理枚举或参数组合限制。因此本项目只把它用于更新模型名称，不从名称推断能力。[官方模型列表接口](https://developers.openai.com/api/reference/resources/models/methods/list)。

参数能力清单由用户根据模型文档维护，可在应用内编辑 JSON、导入/导出文件，远程 HTTPS JSON 地址入口已移除。列表更新无需重装 APK，且不会自动选中新模型或开启新参数；仍合法的已有参数保留，不再合法的选择删除，旧 AI 候选立即失效。

## 列表格式与范围

完整可导入示例见 `models-example.json`。其中 `your-model-id` 必须改为实际模型 ID。示例只是格式说明，不是任何具体模型的能力承诺。

根字段：`schema_version: 1`、展示版本 `version`、数组 `models`。每个模型含 `id`、`name`、`parameters`。参数含 `key`、`label`、`type`；枚举使用 `choices: [{"label":"轻度","value":"low"}]`，数值使用 `min` 和 `max`。

可维护的字段：

- 枚举：`reasoning_effort`、`service_tier`。枚举值可随模型能力变化手动增删，无需重编 APK。
- 数值：`temperature`（0–2）、`top_p`（0–1）、`presence_penalty` / `frequency_penalty`（-2–2）。清单可进一步收窄范围。Temperature 和 Top P 通常只调一项；部分推理模型不接受这些参数。
- 整数：`max_completion_tokens` 或 `max_tokens`，只能发送其中一个，具体字段和上限按服务维护。推理模型的输出预算可能包含推理 token。
- 布尔：`enable_thinking`，仅用于明确支持该字段的兼容服务；不是 OpenAI 通用参数。

参数只允许以上已适配的字段。新增字段名称或嵌套请求格式需要代码适配；现有字段的新枚举值、模型 ID 和范围可以只更新清单。禁止通过清单覆盖 `model`、`messages`、`stream`、API 地址、请求头或密钥。

清单最多 512 KiB；未知 schema、重复模型/参数/枚举、不合法类型和范围会被拒绝并保留原配置。导出文件不含连接地址、密钥、参数使用记录或输入正文。

## 验证边界

模型参数已通过核心、本机 HTTPS 模拟器以及真实 OpenAI 测试。普通/Fast、gpt-5-mini 的 minimal/low、gpt-5.4-mini 的 none、温度及 Top P 等实际结果见 [真实测试报告](live-verification.md)。已验证本次账户的 Fast 请求返回 priority，不据一次请求推断长期延迟或费用。其他云服务尚未实测。可导入 [实测参数子集](models-openai-tested.json)；这不是服务端完整能力探测接口，数值范围也未穷举。
