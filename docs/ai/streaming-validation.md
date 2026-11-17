# 单请求流式候选 · 2026-11-17

Windows 1.12.0 / Android 1.10.0 保持同一个提示词和一次请求，输出仍是 `["纠错","助手"]`。第一个完整字符串到达立即显示；助手占据第二位，等待期间不可选择。仅纠错模式仍只需要一个字符串。

## 实现

- 三 API 开启 `stream`：OpenAI Responses 的 `response.output_text.delta`，OpenRouter Chat 的 `choices[0].delta.content`，Gemini Interactions 的 `model_output` 步骤及 `step.delta`。思考、工具调用和心跳不进入候选。
- 共享 C++ SSE 解析处理分包 UTF-8、CRLF、JSON 转义和完整字符串恢复；传输最多 1 MiB，模型可见文本最多 32 KiB。普通 JSON 网关响应仍兼容，在 EOF 解析，不发送额外请求。
- Windows WinHTTP 先查询可读字节，避免大缓冲等待填满；Z4 管道请求支持多次候选刷新。旧 Z1/Z2 请求仍只收最终结果。Android 通过主线程协调器发布增量结果。
- 新输入、会话和配置变化会作废旧响应。用户可以在助手生成期间选择纠错；迟到助手不能再上屏。流中断时只保留已经闭合的字符串，不拼接半句话，不自动重试。
- Policy、凭据、提示词和超时设置保持不变。

## 检查

- 共享 C++：738 项检查，含三协议每个字节分割点、中文/emoji、转义引号和 surrogate、思考过滤、流中错误，以及每个协议 12 类截断尾部。
- Windows：85 项配置/网络/格式检查，含本地服务延迟 1.5 秒返回第二段时，第一段必须在 1 秒内送达；16 项普通管道集成；102 项候选组合、2705 项文本范围、42 项快捷键、6 项流式管道检查。
- Android JVM 适配层：77 项通过，含 TLS 分段响应提前发布、总超时后保留纠错、取消及迟到回调过滤。MockWebServer 的限速同时影响请求体读取，测试用 SSE 注释填充，避免把请求上传限速误判成流式读取失败。
- Android 模拟器：最终 12 项通过，覆盖纠错先出现、助手等待状态、助手随后出现并上屏、三 API 普通响应兼容、共享解析和分段选词。“助手未完成时选择纠错”的设备检查通过，等待结束后旧助手不会再显示或追加。
- Windows 设置界面烟测通过：49 控件、5 页、保存提示及列表状态。第一次 UAC 未完成；用户再次授权后 1.12.0 安装成功，程序及两种架构 TSF 哈希与发布镜像一致，原配置和加密凭据未变。安装后首轮输入服务测试未响应，重启输入服务后，中英文长句输入、双候选和数字键选择助手正文通过；该测试直接使用已安装输入服务 IPC，不代表所有应用文本框兼容性验收。

## 真实 API 小样本

通过实际 Windows Broker、WinHTTP 和流式命名管道，每个平台各请求一次相同的合成长输入，使用现有 Policy 的模型参数和 10 秒超时。没有改动用户配置，也没有批量上传语料。

| 平台/模型 | 纠错完整 | 助手完整 | 最终帧 |
| --- | ---: | ---: | ---: |
| OpenAI / gpt-6.1-terra | 1787 ms | 1845 ms | 1946 ms |
| Gemini / gemini-3.8-flash | 1333 ms | 1597 ms | 1625 ms |
| OpenRouter / qwen/qwen3.8-27b | 1218 ms | 1500 ms | 1529 ms |

这是一次样例的时序，不是稳定延迟或准确率评估。思考耗时仍会发生在首个纠错输出之前；服务端如果合并发送两个候选，客户端不会人为延迟第二项。原始合成结果见 `tests/prompts/stream-results-2026-11-17.json`。

首次实测发现 WinHTTP 旧读取方式将事件合并到响应末尾，修正后才得到表中的分段时序。Android 初次构建还清理了回滚留下的 KSP 缓存；源码、生成语料和用户数据未删除。

协议依据：[OpenAI Streaming](https://developers.openai.com/api/docs/guides/streaming-responses)、[Gemini Streaming](https://ai.google.dev/gemini-api/docs/streaming)、[OpenRouter Streaming](https://github.com/OpenRouterTeam/docs/blob/main/api_reference/streaming.mdx)、[WinHttpQueryDataAvailable](https://learn.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpquerydataavailable)。
