# Zephyr Input 1.1.0

## 1.1.0：空格光标与双 API

- 长按空格后左右拖动移动光标，松手不会多输入空格；短按仍输入空格。遵循键盘震动设置。
- 默认两套独立 Policy：OpenAI / gpt-6-luna / none / default；OpenRouter / deepseek/deepseek-v4-flash-0731 / wafer/us / 无思考。
- OpenRouter 无思考发送 `reasoning.enabled=false`；固定提供商发送 `provider.only=["wafer/us"]`、`allow_fallbacks=false`。普通速度不加排序，Fast 使用延迟优先排序，仍受提供商限制。
- 两家分别配置加密 Key，升级保留已有 OpenAI 凭据；不共享或迁移 Key 到其他 API。
- 一键测速总计 2–5 组，两家各至少 1 组；默认 4 个 OpenAI 小型模型和 1 个 DeepSeek Flash。每组可修改 Policy、模型、思考、速度和 OpenRouter 提供商。开始前验证所有组的凭据，无 Key 时不发送请求。
- 25 项 JVM 测试与 17 项模拟器回归通过，包括左右移动、松手/取消不插入空格、密码保护、Policy 迁移和双 API 凭据预检。本次未执行真实云端测速。

核对日期：2026-11-07。[OpenRouter 模型端点](https://openrouter.ai/api/v1/models/deepseek/deepseek-v4-flash-0731/endpoints)、[reasoning 文档](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)。

