# Android 1.3.7：复制 Policy

AI 设置列表和 Policy 编辑页新增“复制 Policy（含 Key）”。复制接口、模型、提供商、思考及速度参数、提示词和已加密保存的 API Key；不切换当前选用的 Policy。

副本使用独立 ID 和 Android Keystore 密钥重新加密，自动命名为“原名称 副本”，重名时追加编号。含 Key 时沿用系统身份验证；不向剪贴板、日志、配置 JSON 或安装包写入密钥。

复制前验证 20 项上限和源凭据可读性；失败不留下半成品 Policy。无 Key 的配置可以正常复制。修改、清除或删除副本不影响原 Policy。

回归测试：`PolicyCopyTest`，覆盖参数完整性、加密凭据复制、接口域绑定、独立修改与删除、重名、无 Key 和不可读 Key。
验证结果：Android 模拟器 PolicyCopyTest 两项测试通过；共享核心测试通过，无真实 API 请求。
