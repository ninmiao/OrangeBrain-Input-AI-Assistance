# 纯文本候选与 Gemini 接入

日期：2026-11-13。Windows 1.6.3、Android 1.5.3，提示词 4.0.1 / revision 13。

## 请求协议

每次仅发送当前待纠错文本，空格保留词组边界；前后文、表达风格和候选数量设置均已移除。模型生成一个候选正文，不再生成 candidates/completion JSON。HTTP 服务自己的响应外壳由适配器解析；思考内容不会进入候选栏。

OpenAI 官方接口使用独立 Responses 请求：instructions + input + store:false。已有官方 Chat Completions 地址自动转到 Responses；自定义 Chat Completions 兼容接口保留原路径。Gemini 使用原生 Interactions：system_instruction + input + generation_config.thinking_level，store:false，不传 previous_interaction_id。默认模型 gemini-4-hydrogen，low thinking，普通速度。

所有请求继续复用连接池、使用总超时和取消机制；输入变更会取消旧请求。分段确认的汉字前缀属于当前组合，保留剩余拼音，不作为额外前文重复发送。

## OpenRouter Preset

1. 在 OpenRouter 后台分别建立简体、繁体、英文 Preset，复制 README 对应提示词，简体与繁体填入实际字形要求。
2. Windows 1.6.1 / Android 1.5.1 起，Policy 的 Preset 开关默认关闭，使用完整本地提示词。开启后显示三个默认引用：@preset/zephyr-zh-hans、@preset/zephyr-zh-hant、@preset/zephyr-en，可按需修改；该模式不发送本地系统提示词。
3. 客户端模型、思考、速度和供应商参数优先。使用 Preset 时，本地附加提示词不参与该模式的请求。
4. 更新后台 Preset 后，后续请求自动使用更新内容。普通推理密钥用于调用；API 创建和管理 Preset 需要独立管理密钥，不在客户端保存该管理密钥。

Preset 缩减客户端上传体积，模型仍处理并计费系统提示词。OpenAI 历史链接会计入先前输入 token；Gemini 4 不支持显式缓存，Hydrogen 隐式缓存最低 4096 tokens。本项目不填充提示词凑缓存门槛，不用不断增长的输入历史保存提示词。

## 配置迁移与测速

旧配置中的前后文和风格字段忽略，并在保存时移除。旧 JSON 提示词包使用新版纯文本规则；Policy ID、加密 Key、模型参数与用户词库保留。新 Gemini Policy 只在一次性迁移时补充，删除后不反复添加。

Windows 测试当前 Policy 时先保存编辑项，再捕获不可变快照；不改变正在使用的 Policy。每条 Policy 保留独立测试结果，供应商刷新不会覆盖它。结果列出模型、思考、速度、网络到完整候选返回的耗时和 token 用量。HTTP 401/429 等错误保留状态码。三种 API 一键测速合计最多五组，每种已配置 Key 的 API 至少一组。

输入、可见候选输出、思考和缓存 token 分别显示。OpenAI 的总输出 token 含思考部分，界面扣除该部分后显示可见输出，另列思考数；服务未提供的统计显示为破折号。

## 官方接口依据

- [OpenRouter Presets](https://openrouter.ai/docs/guides/features/presets)
- [OpenAI Responses](https://developers.openai.com/api/reference/resources/responses/methods/create)
- [OpenAI 会话计费](https://developers.openai.com/api/docs/guides/conversation-state)
- [OpenAI Prompt Objects 迁移](https://developers.openai.com/api/docs/guides/prompting/migrate-from-prompt-object)
- [Gemini Interactions](https://aistudio.google.com/docs/interactions-overview)
- [Gemini Thinking](https://aistudio.google.com/docs/thinking)
- [Gemini 缓存限制](https://aistudio.google.com/docs/caching)

## 本轮验证

- Windows 41 项通过、1 项可选检查跳过；共享核心 45 项通过；Android 模拟器 34 项回归通过。
- 真实 Windows Policy 按钮：Gemini Hydrogen / low / default，1611 ms。打包 JAR 的 OpenAI Terra 与 OpenRouter Qwen3.8 27B 分别约 3086 / 1403 ms 返回预期候选。
- Android Gemini 20 个合成样例均返回，测试超时 30 秒，中位 2011.5 ms，最大 20410 ms。1 条超过应用默认 10 秒超时；其补查为 1612 ms。应用默认超时不变。
- 4 条长输入、3 种颜表情触发写法均获得候选；17 条有参考文本的样例中，去标点和大小写后 15 条匹配。2 条长中文措辞存在差异；参考语料原样保留。
- 繁体补查返回实际繁体字形。原 464693 条生成语料未修改，哈希核对通过。
- Windows 1.6.0 安装包已生成，但安装 UAC 被取消；电脑仍安装 1.5.6。Android 调试版已更新模拟器，未更新 S26。两端安装包和源码均未推送。

详细状态与历史记录见根目录 UPDATE_LOG.md。
