# 纠错 + AI 助手提示词实验

2026-11-16 开始实验，2026-11-17 整理审核稿。**供用户审核，尚未修改两端的产品提示词、界面或默认模式。** Windows 仍为 1.9.1，Android 仍为 1.7.1；本轮未构建、未安装、未提交或推送。

## 推荐与提示词全文

推荐 **E_roles_aliases，无语义示例**。它使用两个有固定角色的字符串，不增加对象字段：`["纠错结果","助手候选"]`。第一项保持原意；第二项可以回答、建议、续写、找词或生成颜表情。

中文简体模式实际测试的系统提示词：

```text
i is input; b/a context. Return only JSON ["correction","assistant"]. First fix pinyin, missing/repeated/swapped letters and nearby-key errors into Simplified Chinese; keep and correct English; preserve meaning, negation, numbers and names, without answering or continuing. Second infer intent for a brief insertable answer, suggestion, continuation or term; 颜/表情 requests in any spelling mean kaomoji only. Clarify if unsure. Use Simplified Chinese unless requested otherwise.
```

英文模式只替换纠错规则与默认语言，实际测试版本如下：

```text
i is input; b/a context. Return only JSON ["correction","assistant"]. First correct and polish English; translate Chinese, pinyin or mixed input into English; preserve meaning, negation, numbers and names, without answering or continuing. Second infer intent for a brief insertable answer, suggestion, continuation or term; 颜/表情 requests in any spelling mean kaomoji only. Clarify if unsure. Use English unless requested otherwise.
```

繁体模式把 `Simplified Chinese` 换为 `Traditional Chinese`。`i` 是当前输入，`b/a` 是前文/后文；每次只发当前输入和设置允许的上下文。实验里有前文的样例取末尾 50 字符，未使用历史会话。

英文指令是本轮测量后的选择，不是界面语言要求。简短中文 A 版也参加了筛选，但在术语和颜表情上出现更多漏判。较短的 D 版补回角色边界、颜表情别名后得到 E 版；再加一条“法国首都 / 巴黎”的 F 版没有带来整体检查结果提升，因此不推荐为这条示例付出额外输入。

## 实际输出

以下都是 E 版、Terra / low 的原始候选，标点未人为改写：

| 输入 | 第一项：纠错 | 第二项：助手 |
| --- | --- | --- |
| `gaoxiongshizhang` | 高雄市长 | 陈其迈 |
| 前文为斐波那契数列，输入 `zhejiushi` | 这就是 | 斐波那契数列。 |
| `yougezhuanyecihui o kaitoude  骨科医生相关` | 有个专业词汇，O开头的，和骨科医生相关。 | Orthopedist（骨科医生） |
| `yanbiaoqing xiaosi` | 颜表情，笑死 | `(≧▽≦)` |
| `whats teh capital of Japna`（英文模式） | What's the capital of Japan? | Tokyo. |
| `17 chengyi 8` | 17乘以8 | 136 |

高雄市长参考答案按 2026-11-16 的[高雄市政府介绍](https://www.kcg.gov.tw/cp.aspx?Create=1&n=59C096A5BBC7AFB1)核对；本轮 API 请求没有联网搜索工具，模型对时效性问题的答案可能落后。

## 比较结果

下面三版在同一组 46 条样例上各请求三个模型，共 138 次/版。D、E 无示例；F 在 E 后增加一条极短问答示例。token 是服务端返回的平均用量，输入包含提示词、输入文本及上下文。

| 版本 | 合法双字符串数组 | 第一项规则匹配 | 第二项规则匹配 | 输入 token | 可见输出 token | 思考 token | 合计 token |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D · 最短角色版 | 138/138 | 131/138 | 124/138 | 112.3 | 23.2 | 89.5 | 225.0 |
| E · 无示例，推荐 | 138/138 | 133/138 | 131/138 | 120.7 | 24.5 | 63.0 | 208.2 |
| F · 一条示例 | 138/138 | 132/138 | 131/138 | 133.5 | 23.2 | 55.6 | 212.4 |

E 的平均输入比 F 少约 9.6%，本轮平均总 token 少约 2.0%。思考用量会波动，这一次的差异不能证明固定的费用或延迟降幅。D 虽然提示词更短，平均思考用量却更高；只数提示词字数不足以比较成本。

E 版按模型分组：

| 模型与思考设置 | 合法数组 | 输入 / 可见输出 / 思考 token（平均） | 延迟中位数 | P90 |
| --- | --- | --- | --- | --- |
| Gemini 3.8 Flash · low | 46/46 | 114.3 / 22.2 / 0.0 | 1.26 s | 1.92 s |
| GPT-6 Luna · medium | 46/46 | 123.9 / 26.5 / 147.0 | 2.25 s | 3.56 s |
| GPT-6.1 Terra · low | 46/46 | 123.9 / 24.9 / 42.0 | 2.00 s | 2.88 s |

Gemini 的请求确实设置 `low`，这一组响应的服务端用量报告中思考 token 为 0；不能把它解释为客户端改成了无思考。三组均为普通速度。

**规则匹配不是正确率。** 正则会漏掉同义表达（如 `HTTP 404 meaning` 被润色成 `What does HTTP 404 mean?`），也会放过表面包含关键词的坏输出。语料由 Zephyr 编写，未做独立人工标注；开发过程中反复查看过样例，不能当作独立盲测。

逐条检查 E 版还发现：

- Gemini 和 Luna 对 `Could you please` 偶尔会在第一项提前续写，违反角色边界；Terra 在该样例保留了原文。
- Luna 的一次 `gaoxiongshizhang` 返回追问；同批繁体和空格变体返回了姓名。加示例版这一次三模型都返回姓名，但其他检查没有整体提升。
- Luna 的英文颜表情样例返回了 emoji；Gemini 在一个空格变体中给颜表情附带了汉字。仅靠提示词不能保证每次都是纯颜表情。
- Gemini 偶尔把一个术语候选写成多个备选词，或在长句的助手项中承诺发送文件；这不是已执行的操作。`yan shengqi` 也有同音歧义，第一项仍有误判。
- 自动检查没有抓住 Gemini 某个长句里“但是说明天天”的错误。因此本报告不将 133/138 或 131/138 写成准确率。

结构在这轮较稳定，内容仍取决于模型。推荐 E 是当前已测版本的输入成本、角色表现和无示例偏好的折中，并非宣称找到全局最短、完全可靠的提示词。

## 测试范围与复现

新增独立语料 [assistant-intent-v1.jsonl](../../tests/corpus/assistant-intent-v1.jsonl)：66 条记录，50 个原始场景、16 个边界派生记录；其中 `57/63` 因原输入无空格而与源记录完全相同，不算新的语言现象。原有 60 条重点纠错集和 464,693 条生成库保留。

本次真实发送的是其中 46 条：40 个基础场景、4 个首尾空格变体、2 个格式边界场景。覆盖中英拼写、中英混输、翻译、繁体、术语、问答、数列、单位换算、续写、建议、颜表情和信息不足；也包含超过 50 字符的长输入。未测试的 20 条仍保存在本地测试库，不冒充已通过。

- 模型：`gemini-3.8-flash / low`、`gpt-6-luna / medium`、`gpt-6.1-terra / low`。用户的 `median` 按 `medium` 执行。
- API：Gemini Interactions、OpenAI Responses；速度为 default，单请求输出上限 1024 token，连接超时 10 秒，读取超时 60 秒，不自动重试。每个模型按顺序发请求，最多同时三个请求。**这与产品的输出软预算 256、默认超时设置不同，不是设备端速度验收。**
- 3 次连通性；72 次初筛；90 次追加筛选；D/E 各 120 次扩展验证；F 138 次验证，总计 **543 次请求**。
- 追加筛选原本只应运行 E，但脚本忽略了显式版本选择，额外重复了 A–D 的 72 次请求。已修正筛选逻辑；这些结果保留，计入请求和 token 总数。46 条对齐比较采用每模型/样例单个指定结果，不混入重复轮次。
- 542 次 HTTP 成功，均为合法双字符串数组；另 1 次 Gemini 503。该失败保留，没有自动重试后改写为成功。成功响应报告的 token 总量：输入 67,456，可见输出 13,285，思考 37,977，合计 118,718。503 未返回 token 用量，不计入这个合计。
- 只使用合成输入；Key 从已有 Windows DPAPI 凭据读取，不写入源码、报告、命令参数或安装包。

候选定义在 [assistant-candidates-v1.json](../../tests/prompts/assistant-candidates-v1.json)，阶段与选例在 [assistant-experiment-v1.json](../../tests/prompts/assistant-experiment-v1.json)，统计及 E 版全部输出在 [assistant-results-v1.json](../../tests/prompts/assistant-results-v1.json)。原始逐次报告保留在本地忽略目录 `.tools/assistant-experiments-v1/`，公开结果记录了各报告 SHA256。

复测会产生 API 费用，需已保存相应平台的 Key。以下命令只运行指定版本，并可选择单个模型；`--run-tag` 使用新目录保留旧结果：

```powershell
$cases = (Get-Content tests/prompts/assistant-experiment-v1.json -Raw | ConvertFrom-Json).matched_cases
python script/evaluate-assistant-prompts.py --phase validate --variant E_roles_aliases --cases $cases --models gemini-3.8-flash --run-tag review2
```

## 审核后两端的实现范围

- 在 AI 增强开关旁增加“仅纠错 / 纠错 + AI 助手”，默认后者；仅纠错保留当前单候选行为。本轮没有新增或测试仅纠错模式的产品逻辑。
- 双候选显示“纠错 / 助手”角色，正常响应生成两项；不把助手答案混作第一项纠错。可保留当前语言与繁简选项。
- C++ 生成提示词与解析协议供 Android JNI、Windows 共同使用；请求生成器当前自动追加的“默认一个候选”规则必须按模式调整，不能直接叠加两条冲突规则。
- 解析先保留槽位身份再去重，避免相同字符串造成角色移位；为未来多个助手候选保留数组扩展能力。
- 严格区分模型的文本与思考字段。格式异常不直接上屏；截断时只保留已闭合的完整字符串，第二项不完整时不显示半截助手候选。已存在的截断测试库继续使用，并补充双角色案例。

这些是待审核实现方案，不能以本轮独立 HTTP 实验代替 Windows/Android 集成、UI、取消请求和截断回归。
