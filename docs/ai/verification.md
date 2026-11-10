# 验证记录

最新 `3.3.7-ai.3` 键盘、Policy 与简繁改版见 [本次记录](redesign-v3.md)。以下 ai.2 真机和旧模型结果为历史记录。

日期：2026-11-06。基座 Trime v3.3.7，commit `ac13dd4790523c1a9778cfb70234fe485fd3c526`。

## 简体词库更新

最新版 `3.3.7-ai.2` 默认改为雾凇简体词库与 `rime_ai_simp` 方案。17 项核心测试、10 项 Android 测试通过（含首次词库部署共 211.346 秒）。字词候选、迁移、来源和安装包说明见 [词库验证记录](dictionary.md)。下文 8 项固定响应和真实 API 记录为此前基线；本次 10 项覆盖原有 8 项并新增词库/迁移测试。

## Samsung S26 真机

ARM64 Demo `3.3.7-ai.2` 已安装至 Samsung S26（SM_S942U1 / Android 17 / API 37）。实际 Demo 的全拼、简拼、点击上屏和重启后退格验证通过；同机 ARM64 debug 的 10 项集成测试全部通过，耗时 114.155 秒。网络测试使用本地 HTTPS 固定响应与假 Key。临时测试应用已卸载，Demo 保留并设为当前输入法。详见 [真机验证记录](s26-verification.md)。

## 构建

- Windows 项目内 JDK 17、SDK/API 35、Build Tools 35.0.0、NDK 28.0.13004108、CMake 3.31.6。
- Gradle 8.14.1、Android Gradle Plugin 8.11.0、Kotlin 2.2.0。
- `assembleDebug`、`assembleDebugAndroidTest`、`assembleDemo` 构建成功。
- Demo：`com.osfans.trime.ai.demo`，minSdk 23，targetSdk 35，ARM64 和 x86_64 两种 APK。
- Android 调试签名供本地安装，v1/v2 签名校验通过；Demo 不启用 debuggable，不包含调试网络配置或测试证书。
- APK 和 SHA-256 校验文件位于 `dist/`。原 GPL 及上游依赖许可证保留。

## 核心测试

17 项 JVM 测试通过，0 失败，0 错误：

- 三字段请求、严格响应格式、候选数量/重复项、关闭补全。
- 200 ms 防抖、关闭或敏感字段不请求、会话结束取消。
- 不可取消的旧响应不覆盖新结果；会话、文本、提示词、语言和 API 五个代数变化。
- 提示词 schema、包大小、旧语言规则回退和语言规则优先级。
- 可靠选区、句子范围、UTF-16、emoji/ZWJ 和过长目标拒绝。

- 模型参数默认省略、参数类型与保留字段保护、可变枚举、清单校验和模型发现来源约束。

报告：`ai-core/build/reports/tests/test/index.html`。

## Android 模拟器

Android 15 / API 35 / Google APIs / x86_64，Windows Hypervisor Platform。使用测试应用中的 Android EditText 和真实 Trime InputMethodService；网络使用本机 HTTPS 固定响应服务，API Key 为测试假值。

**8 项固定响应集成测试全部通过。** 原始日志：`android-test-results.txt`。该固定响应测试已在最终交付源代码上重新通过，最新耗时见下方原始日志。

测试覆盖：

1. Keystore 加密落盘、密文不含明文、HTTPS 来源绑定和清除。
2. 提示词落盘重载、本地覆盖、远程升级限制、历史回滚和恢复内置。
3. 实际 HTTPS Chat Completions 请求、中英文语言规则、独立远程提示词下载。
4. 设置页滚动、最终提示词与三字段用户消息预览。
5. 拼音组合串和本地候选存在、AI 中文候选点击上屏一次且不循环、ASCII 状态替换完整中英混合句子、密码字段不增加请求、HTTP 401 后本地候选仍可上屏。

6. 模型参数持久化、模型间隔离、端点切换清理、清单更新剔除无效选择。
7. HTTPS 模型列表获取、能力清单下载不附带 Key、可选参数实际发送正确。
8. 模型设置界面选择 Fast、轻度推理和输出上限，保存后发送的 HTTPS 请求与界面值一致；未选择的 Temperature 不发送。

Demo 变体已安装并成功打开。首次启用曾发现主题文件尚未部署导致崩溃，已增加内置主题回退和引擎就绪后的重新加载；修复后启动无新崩溃。Windows Git 符号链接资源也已转换为真实词典内容打包。

`screenshots/chinese-mock.png` 和 `english-mock.png` 为固定响应截图；`live-chinese.png` 和 `live-english.png` 来自真实 OpenAI 请求，仅代表所示样例。调试版使用 `/sdcard/rime-ai-debug`，Demo 使用 `/sdcard/rime-ai`，均与原版 Trime 默认目录分离。

## 真实 OpenAI 测试

已经使用临时 Key 完成真实 API 及模拟器验证，并删除测试凭据。最终正文矩阵为 16 个样例 × 5 风格，80/80 HTTP 与 JSON 格式通过；8 个有效参数组合成功、2 个不兼容组合按预期拒绝。1 项多步骤真实 Android 集成测试通过。提示词据失败样例更新为 v1.2.2，风格质量仍有边界。见 [完整真实报告](live-verification.md)。

## 尚未验收

- 模型与参数能力由用户维护；本次仅验证三个 OpenAI 模型的所列参数组合，非全部账户/模型能力保证。未独立核验账单。
- 其他云服务和更广泛真实输入尚未验收；轻量模型的极简/正式风格仍可能保留赘词，详见真实质量记录。
- 未完成 Android 6–14、Android 16、S26 以外真机或第三方编辑器矩阵测试。无法取得完整可靠编辑范围时实现会放弃直接替换。
- 未完成商店发布、发布签名管理和公开分发前的完整许可证清单审计。
- iOS 属于设计中的后续阶段，本项目交付为 Android Demo。

本记录不将模拟器通过扩大为全部设备、编辑器和真实模型均通过。
