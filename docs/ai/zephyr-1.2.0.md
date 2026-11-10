# Zephyr Input 1.2.0

## 1.2.0：Policy 延迟、模型能力与空格分词

- Policy 列表与详情页均有延迟快捷测试。每次只使用该 Policy 的接口、Key、模型、提供商与参数发出一次固定样例请求，显示完整候选返回耗时；不切换当前 Policy，也不依赖另一 API 的 Key。
- 思考强度按模型适配。DeepSeek V4 Flash 0731 为 none / low / high / max；GPT-6 Luna 为 none / low / medium / high / xhigh / max；GPT-5.4 nano 不显示 max；GPT-4.1/4o 不发送思考参数。未知模型不套用通用档位，可刷新 OpenRouter 能力元数据或维护对应能力 JSON。
- OpenRouter 刷新模型列表同时读取 reasoning.supported_efforts 与 mandatory；强制思考模型不会显示关闭项。测速修改模型后会刷新思考选项。
- “空格分词（中文键盘）”默认开启：拼音留在键盘顶部，空格标记词组边界。例如 hanbaowang haochi 不提前写入应用文本栏，点击本地或 AI 候选后才上屏。长按空格拖动光标仍可用；关闭开关恢复原空格选词行为；英文和密码输入不受影响。
- 验证：27 项核心测试、19 项模拟器回归通过。延迟测试使用本地 HTTPS 测试服务，本次未调用真实云端模型。S26 未连接，手机尚未更新。

能力核对日期：2026-11-09。[OpenAI 模型目录](https://developers.openai.com/api/docs/models)、[OpenRouter reasoning 元数据](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)、[DeepSeek 思考档位](https://api-docs.deepseek.com/guides/thinking_mode/)。

