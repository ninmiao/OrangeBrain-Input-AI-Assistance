# Zephyr Input 隐私说明 / Privacy

本地 Rime 输入不发送输入内容。万象、雾凇和已下载的万象语法模型都在设备上运行。点击词表或模型更新时，客户端连接对应项目的 GitHub 下载地址。

云端 AI 默认关闭。开启后，当前输入和已启用的前后文发送到所选 Policy 的 API 地址。上下文功能默认开启，前 50 / 后 0 个 Unicode 字符，可单独关闭或改为 0–500。请求不会接续先前的 API 会话；服务商对请求的保存与计费遵循其政策。密码和被平台标记为敏感的输入字段不自动请求 AI。

Key 保存在 Android Keystore 保护的凭据或 Windows DPAPI 加密文件中，不随安装包发布。诊断不记录输入正文、前后文、完整响应或 Key。测速会发送界面中的人工样例及按设置截取的样例上下文。

剪贴板在用户打开相应入口时读取；标记为敏感的剪贴板不加入历史。词库与设置存储在本机。系统语音输入按所选系统语音服务的规则工作。

Offline Rime typing, dictionaries and the downloaded grammar model run on your device. Explicit data updates connect to the upstream GitHub releases.

Cloud AI is off by default. When enabled, it sends current input and enabled surrounding context to the policy's API endpoint. Context defaults to 50 Unicode characters before and 0 after; it can be disabled or set to 0–500 independently. Requests do not chain previous API conversations. Provider retention and billing policies still apply. Password and platform-marked sensitive fields do not trigger automatic AI requests.

Keys are encrypted using Android Keystore-backed credentials or Windows DPAPI. Diagnostics exclude input, context, response bodies and keys. Benchmarks send synthetic sample text and its enabled context. Clipboard access follows the user-opened clipboard feature; sensitive clips are excluded from history.

Updated 2026-11-16. Upstream Trime copyright notices remain in source files.
