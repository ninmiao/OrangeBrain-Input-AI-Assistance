# Samsung S26 真机验证

日期：2026-11-06。设备：Samsung Galaxy S26（SM_S942U1），Android 17 / API 37，ARM64，1080 × 2340。仅操作主用户的 Demo 和专用测试应用。

## 已安装的 Demo

- 应用：`com.osfans.trime.ai.demo`，版本 `3.3.7-ai.2`，versionCode `20261106`。
- 安装包：`dist/Rime-AI-Demo-arm64-v8a.apk`，29,032,040 字节。
- SHA-256：`9b7b22de0d6c03992a0dd377cadac7ba3ae448d9ebb49166415fe43d7dc43890`。
- 已启用并设为当前输入法；雾凇简体词库部署完成。主词表最终约 58 MiB，后续启动复用编译结果。
- 在独立测试输入框中，全拼 `shurufa` 和简拼 `rgzn` 的候选分别为“输入法”和“人工智能”，点击上屏后的文本为“输入法人工智能”。
- 停止并重新启动 Demo 后，输入 `shurufa`、空格、退格、`nihao`、空格，最终文本为“输入你好”，验证重启后词库可用、空格上屏和删除正常。
- 留在手机上的 Demo 使用默认关闭的 AI，未填入真实 API Key。

实际 Demo 截图：[简体候选](screenshots/s26-demo-candidate.png)。上述断言和安装信息另存于 [Demo 检查记录](s26-demo-smoke.json)。

## ARM64 集成测试

在同一部 S26 临时安装 ARM64 debug 及 instrumentation APK，**10 / 10 通过，耗时 114.155 秒**。网络经 USB `adb reverse` 连接电脑上的本地 HTTPS 固定响应服务，使用假 Key。

覆盖 Keystore 加密与来源绑定、提示词保存与更新、模型与参数设置、HTTPS 请求内容、AI 中文候选点击上屏一次、英文替换、密码输入框零请求、HTTP 401 后本地输入仍可用，以及简体词库和配置迁移。

离线词库测试验证 10 组全拼与简拼，包括“软件、发展、后面、数据库、输入法、人工智能、中国、你好、绿色”。

- [完整 instrumentation 原始日志](android-s26-test-results.txt)
- [离线词库候选原始记录](s26-dictionary-test-report.txt)
- [AI 中文固定响应截图](screenshots/s26-ai-candidate-mock.png)
- [AI 英文固定响应截图](screenshots/s26-ai-english-mock.png)

本轮没有在手机上调用真实云模型。此前真实 OpenAI 测试使用电脑和 Android 模拟器，见 [独立记录](live-verification.md)。

## 测试清理与复现

已清除测试凭据，卸载主用户下的临时 debug 和测试 APK，停止本地 HTTPS 服务并移除 USB 端口转发；保持唤醒设置恢复为测试前的值。手机仅保留本项目的 Demo 应用，并选为当前输入法。共享目录中的测试词库缓存未作递归删除。

复现需要手机已解锁且授权 USB 调试，以及可用的 Python 环境：

```powershell
.\script\test-phone.ps1 -Device <adb设备编号>
# 已构建 ARM64 debug 和测试 APK 时可增加 -SkipBuild
```

脚本只连接指定设备、操作主用户，使用独立 debug 数据目录。默认拒绝复用已有 debug 安装，以免覆盖其中的测试设置；测试结束恢复输入法和临时系统设置，并卸载新装的测试应用。

本次首次收集报告时，Windows PowerShell 将 `adb pull` 的成功进度输出误当错误；10 项测试及文件传输实际成功，清理逻辑已执行。脚本现按进程退出码判断传输结果，修正后通过语法检查；未因此重复运行整套测试。

## 验证范围

本次验证 Android 标准 EditText、Samsung 系统上的键盘显示及上述输入链路。未覆盖微信、浏览器和各第三方编辑器，未做长时间耗电、压力或横竖屏矩阵测试；不能据此推断所有机型与编辑器均通过。
