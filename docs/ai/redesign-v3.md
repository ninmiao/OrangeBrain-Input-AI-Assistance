# 键盘与 Policy 改版

日期：2026-11-06。版本：`3.3.7-ai.3`，versionCode `20261107`（递增安装版本号）。基于 Trime v3.3.7，保留 GPL 许可证。

## 本次实现

| 要求 | 实现 |
|---|---|
| iOS 英文键位 | 四排 QWERTY；第二排居中；Shift 和删除位于第三排两端；数字/符号独立页面 |
| 中英切换 | 空格左侧中 / EN，切换 Rime ascii_mode，保持相同键位 |
| 精简 AI 区 | 移除开关、风格、重试、设置四个操作按钮；只保留候选、状态和简/繁 |
| 同步繁简 | 雾凇方案增加 OpenCC s2t 开关；AI 请求末尾追加当前简体/繁体约束；切换立即使旧候选失效 |
| 中英文判断 | 中文键盘转换拼音、纠正英语但不把英语翻为中文；英文键盘优先英语纠错，然后识别中文/混输并译为英文 |
| 数字名称 | 五个输入参数增加常驻标签、单位和允许范围 |
| 删除远程地址 | 删除提示词和模型清单的远程 JSON 地址入口，迁移时关闭旧自动更新 |
| 默认模型 | 新建 Policy 使用 gpt-6-luna、推理 none、服务档位 default |
| 多 Policy | 列表单选；接口、加密 Key、模型清单/参数、提示词各自独立；可编辑未选用的 Policy |
| 反馈与高度 | 震动、按键音、放大动画开关；180–340 dp 高度滑块，打开键盘时重建尺寸 |

模型默认值依据 [OpenAI GPT-6 Luna 官方说明](https://developers.openai.com/api/docs/models/gpt-6-luna)：支持 none，而不传推理参数时默认为 medium。因此此版本显式发送 none，速度使用普通档位。

原始单配置自动迁入默认 Policy，沿用原有加密文件与 Keystore alias；新 Policy 使用独立文件和 alias，不复制旧 Key。切换 Policy 增加配置代数，使旧请求结果无法覆盖当前候选。编辑地址/Key 的字段强制 ASCII，避免中文拼音引擎改变 URL。

内置提示词升级为 2.0.0 / revision 6。用户已有本地覆盖继续保留；需要新语言规则时可在对应 Policy 内恢复内置提示词。

## 观察记录

- [实际 Demo 键盘](screenshots/redesign-demo.png)
- [开启放大动画后按下 q](screenshots/redesign-demo-popup.png)
- [繁体候选“輸入法”](screenshots/redesign-demo-traditional.png)

截图检查发现并修正了选中候选文字透明的问题，增加不透明文字的回归断言。模拟器上实际点击简/繁能更新本地候选，放大开关开启后显示字母弹出预览。

## 验证范围

17 项 JVM 核心测试通过；14 项模拟器集成测试覆盖原有 10 项及新增 4 项 Policy/几何/简繁/设置测试。原始结果见 `android-redesign-test-results.txt`。复测期间修正了测试隔离：简体词库用例显式选择简体，避免受到前一轮手动繁体截图状态影响。

另有 1 项真实 Luna 集成测试包含 **7 / 7 通过**的语言样例，总耗时 8.773 秒；每次请求 690–1937 ms，使用 `reasoning_effort=none`、`service_tier=default`、10 秒超时。临时 Key 仅经本机一次性 HTTPS 通道进入测试进程内存，未写入模拟器应用配置，测试后清除。见 [逐项结果](language-live-report.txt) 和 [instrumentation 日志](android-redesign-language-live-results.txt)。

| 模式 | 输入 | 实测首选 |
|---|---|---|
| 中文 | wojintianxiangquchaoshi | 我今天想去超市 |
| 中文，输入英语 | I has a meeting tomorow. | I have a meeting tomorrow. |
| 中文，混输 | wojintianyoumeeting | 我今天有 meeting |
| 繁体 | shurufazhichijianfanqiehuan | 輸入法支援簡繁切換 |
| 英文，英语优先 | I has a meeting tomorow. | I have a meeting tomorrow. |
| 英文，混输 | 我 tomorrow 有 meeting | I have a meeting tomorrow. |
| 英文，中文输入 | 我今天想去超市 | I want to go to the supermarket today. |

这些是固定样例的有限质量检查，不能保证所有歧义短词或混输均正确。

本次依用户要求只更新模拟器。ARM64 APK 已生成供手机覆盖安装；本版本尚未在 S26 验证。声音与震动开关已接入现有 Android 反馈实现，模拟器不代表真实手机的触感、响度或系统静音行为。字体、屏幕比例及系统导航区会与 iPhone 有差异。

远程 JSON 下载函数仅为旧配置和历史测试兼容保留，没有新界面入口或自动调度。快捷开关从键盘移到设置后，关闭“停手自动请求”时不会主动生成候选，可在 Policy 内发送样例。
