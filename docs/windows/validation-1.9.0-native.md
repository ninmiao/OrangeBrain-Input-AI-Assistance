# Windows 1.9.0 原生版安装与输入验证

日期：2026-11-16。最终版本已安装到本机 `C:\Program Files\Zephyr Input`，输入服务和 AI 后台正在运行；本轮未提交或推送 GitHub。测试系统为 Windows 11 build 26300，Windows 10 仍是构建兼容目标，本轮没有在 Windows 10 上实测。

## 安装与本轮修复

从旧版 1.7.1 开始执行正式安装器测试，发现旧 JVM 的 `app`、`runtime` 目录未清理。修复后用最终安装包完成以下六项检查：升级、同版本覆盖、卸载、重装、用户数据保留、活动 TSF DLL 不在待删除列表。结束时保留 1.9.0，无需重启。

安装清理只处理本应用 Program Files 目录内的两个旧运行目录，检查目标边界并拒绝重解析点。原 AppData、词库、Policy 和 Key 保留；3 份 DPAPI 加密凭据的 SHA-256 与备份相同。模型、思考强度、速度及所选 Policy 与测试前一致。新上下文设置为开启，前 50 / 后 0 个字符。

真实模型验证还发现并修复了 OpenAI 的 `error: null` 被当成错误的问题。成功响应现在读取最终消息内容，忽略 reasoning 项；真实错误对象和失败状态仍被拒绝。此改动在共享 C++ 源码中，已进入本轮 Windows 包，尚未进入现有 Android APK。

设置窗口的模型下拉框另有滚轮误改问题：下拉框关闭时改为滚动页面，展开时才滚动模型选项。自动自测和实际窗口操作均确认模型保持不变。

## 自动检查

| 检查 | 实际结果 |
| --- | --- |
| Windows 原生配置、DPAPI、HTTP 超时/取消、响应限制、ZIP | 84 项通过 |
| 原生命名管道，含延迟读取、无效请求、重新连接 | 16 项通过 |
| 共享 C++ 截断、JSON 格式与 API 响应 | 27 项通过，包含新增 3 项 `error: null` 回归 |
| 组合输入状态 | 94 项通过 |
| 文字高亮范围 | 2705 项通过 |
| 快捷键 | 42 项通过 |
| 真实 Rime / 输入服务 IPC | 338 次断言通过 |
| 逐键输入语料 | 331 条、31,873 次断言、10,526 次按键通过 |
| 已注册 TSF | x86 / x64 均完成系统 Profile 激活及 5 个候选快捷键检查 |
| 原生设置窗口自测 | 4 页、47 个控件；小窗口滚动、Tab 聚焦滚动、自动保存、即时切换 Policy、模型滚轮保护通过 |
| 词库部署 | 万象→雾凇→万象、缓存的 407 MB 语法模型加载、用户文件保留通过 |
| 原生 HTTPS | 公开 GitHub Release 元数据与摘要读取通过 |

331 条语料来自保留的生成库与人工回归库，含邻键、漏输、重复、字母换位、复合错误、中英混输、空格边界和长输入。其中 30 条输入超过 50 字符，并重复 20 次历史崩溃串 `tianjianfajianhezhongyingwen`。IPC 耗时 p50 为 0.6592 ms、p95 为 44.4716 ms，包含服务响应与解析，不含屏幕绘制和模型请求。这组结果验证输入状态及文本保留，不代表 331 条 LLM 纠错答案全部正确。

分段选词检查覆盖选择前缀候选后保留剩余输入；还检查数字选词、中文模式回车提交原英文、Tab 候选、繁简切换、空格分词、单按 Shift、光标编辑、失焦、小键盘数字及候选翻页。

## 实际窗口与完整 AI 链路

在 Zephyr TSF Test Host 中用实际按键输入：Win32 Edit 的 `nihao` 显示“你好”，数字 `1` 上屏；单按 Shift 切英文，再输入 `hi` 并回车，输入框得到“你好hi”。RichEdit 中原文回车上屏也正常。这部分使用离线后台，没有将用户文档发到云端。

安装后的设置窗口实际检查了滚动、Policy 信息、当前 Policy 测速以及从现有 Policy 多选的一键测速；单 Policy 长句测速显示 OpenAI 1958 ms。完整输入链路另用长中文拼音与长英文验证：逐键输入→原生后台→真实模型→AI 候选→Tab 上屏均成功。

本轮没有在 VS Code、浏览器、密码框或所有第三方编辑器中逐一复测；上述真实窗口结果限于 Win32 Edit 和 RichEdit。测试结束关闭隔离窗口，保留正常安装的输入服务运行。

## 真实模型结果

使用已有加密 Key 和合成测试文本。隔离测试目录采用 30 秒总超时、前 50 / 后 20 字符，样例为人工库中的长中文、长英文（均超过 80 字符）及颜表情。没有把生成库全量发送到在线模型。表中是修复后的最后一轮有效结果；Gemini 三条评估在共享解析器修复前已成功，该修复针对 OpenAI 空错误字段。

| 已有 Policy | 长中文 | 长英文 | 颜表情 |
| --- | --- | --- | --- |
| OpenAI · gpt-6.1-terra · low / priority | 3090 ms | 1419 ms | 1691 ms |
| OpenRouter · qwen/qwen3.8-27b · none / default · wafer/fp8 | 1199 ms | 413 ms | 1349 ms |
| Gemini · gemini-3.8-flash · low / default | 1474 ms | 1386 ms | 2034 ms |

以上请求均解析出了完整候选，但“返回成功”与“答案正确”分别计量。OpenAI、OpenRouter 的精确参考匹配均为 2/3，Gemini 为 1/3；中文同义词或英文句尾标点也会造成精确匹配失败，不能将此比例当成通用纠错准确率。

仍存在模型质量问题：OpenRouter 初次长中文返回格式错误，被拒绝且未导致崩溃；复测虽然格式正确，却将“还有会议”改成“好像有会议”。初次颜表情也曾返回普通文字，后续复测成功。这些失败保留在本地原始结果中。

最终一键测速用同一个长句样例选择三家已有 Policy，界面完成并显示：OpenAI 1855 ms、OpenRouter 667 ms、Gemini 17018 ms。前两者保留 `123`，Gemini 将“123 test results”改写成“latest test results”，此条内容质量未通过。一次延迟不能代表稳定性能；17 秒也超过日常配置的 10 秒总超时。本轮未擅自提高用户日常超时或更改所用模型。

## 构建与文件保留

Windows 使用 MSVC v143 / Visual Studio 2022、C++17、Win32、静态 CRT；安装目录检查无 JVM、JAR、Kotlin 文件。安装后的 Settings、Broker、Server 与最终发布镜像 SHA-256 一致。

- 安装包：`dist/Zephyr-Input-Windows-1.9.0-Setup-x64.exe`
- 大小：38,742,117 字节。
- SHA-256：`bd871c79b0631ca59c49fa331c4c923393bba77135cd4bb8767f00351e524c01`。
- 生成语料 `tests/corpus/generated/typos.jsonl` 保持 464,693 条，SHA-256 `d1a3d880eb3ca85d2a204b100b77b7d884817c31752294cf6ecdf1722d777e5d`；未删除、覆盖或上传。
- Android 1.7.1 ARM64 APK 未修改，SHA-256 `c8d9a0d95d57ac47f14f4f010ae2b8e91e9fe60e7df9038d5ca2bc1fd70e0b4d`；本轮未重跑 Android。

原始本机结果保留在忽略的 `.tools/`：`windows-1.9-final-summary.json`、`windows-1.9-installer-validation.json`、`windows-1.9-full-native.log`、`windows-1.9-installed-input.log`、`windows-1.9-wheel-ui/ui-smoke.json`、`windows-1.9-final-dictionary.log`、`windows-1.9-final-live-pipeline.log`、`windows-1.9-live/`。加密凭据备份仅保留本地，不提交 Git。
