# 雾凇简体词库集成

ai.3 更新：方案显示名为“雾凇拼音”；默认仍简体，键盘简/繁按钮可通过 OpenCC s2t 切换繁体。AI 同步遵循当前字形。详见 [改版记录](redesign-v3.md)。以下为 ai.2 初次接入记录。

日期：2026-11-06。版本：`3.3.7-ai.2`，versionCode `20261106`。

## 默认行为

默认输入方案改为 **雾凇简体拼音**，方案 ID `rime_ai_simp`。使用雾凇直接收录的简体字词，不通过繁体词库再做繁转简。本地候选、简拼、自造词与词频学习离线运行，不需要 AI 或 API Key。

本次接入的是雾凇的中文词库与本项目全拼方案，保留 Trime 键盘和 AI 候选区；不是完整的雾凇 Lua、英文词库、Emoji、拆字反查或语法模型功能包。默认启用全拼、声母简拼和常见 ü/v 写法。原有朙月文件仍保留，默认不再启用。

## 来源与版本

- 上游：[iDvel/rime-ice](https://github.com/iDvel/rime-ice)。
- 固定提交：`99662ba01e3affa6a0f009174ca530b887bac3b6`。
- 原样复制 `rime_ice.dict.yaml` 和 `cn_dicts/{8105,base,ext,tencent,others}.dict.yaml`。
- 共 **1,873,813 行有效字词条**，包括多音、重复或不同来源条目；不是去重后的词语数。词典源码约 47.9 MB，APK 约 29 MB。
- 各文件 SHA-256、大小和行数见 `dictionary-snapshot.json`；两个 ABI 的 APK 内词典与该快照逐项一致。
- 上游声明 GPL-3.0-only。完整许可和集成说明随 APK 打包在 `assets/shared/licenses/rime-ice/`，词库原始文件头中的各来源说明保留。Trime/Rime 及其他依赖继续适用原许可证。

## 安装、升级与用户数据

直接覆盖安装新版 APK，无需卸载。新安装默认启用新方案。已有安装若仍使用本项目原样生成的双朙月方案列表，会自动切换到新默认列表，并在用户目录留下 `default.custom.before-ice.yaml` 备份。

如果已有 `default.custom.yaml` 包含用户修改，程序保持原文件不变；请在输入方案管理中启用“雾凇简体拼音”。旧用户词库文件保留，新方案使用独立的学习记录，旧朙月学习记录不会自动合并。API 设置和凭据不因词库切换而重置。

首次部署需编译大词库，本次模拟器整个 10 项测试（含首次部署）耗时 **211.346 秒**。这一过程有较高内存占用，首次启用请等待几分钟，不要连续点击重新部署；后续正常启动复用编译结果。S26 上最终编译主词表约 58 MiB，设备空间还需容纳源码和其他数据；编译过程中可能出现更大的临时分配。

默认 Demo 数据目录 `/sdcard/rime-ai`，debug 为 `/sdcard/rime-ai-debug`，与原版 Trime 分离。

## 本轮验证

- 17 项核心测试通过。
- Samsung S26 / Android 17 / ARM64 的 10 项集成测试通过，耗时 114.155 秒；另在实际 Demo 中验证点击上屏、重启后输入及删除。见 [真机验证记录](s26-verification.md)。
- 10 项 Android 15 模拟器集成测试通过：原有 8 项 AI/参数/存储测试改用新默认拼音方案，并增加 2 项词库与迁移测试。
- AI 关闭时，`ruanjian/fazhan/houmian/shujuku/shurufa/rengongzhineng/zhongguo/nihao/lvse/rgzn` 均能得到对应简体目标；本次首选分别为软件、发展、后面、数据库、输入法、人工智能、中国、你好、绿色、人工智能。
- 验证新安装默认列表、原默认配置迁移及备份、用户修改保留、旧用户数据不被删除。
- 原始记录：`android-dictionary-test-results.txt`、`dictionary-test-report.txt`。

本轮没有重新调用收费模型 API；前一轮真实 API 记录仍见 `live-verification.md`，API 适配器与提示词未因更换词库而改变。目前已验证 Android 15 模拟器和 Samsung S26 / Android 17；其他设备和编辑器尚未全面验证。
