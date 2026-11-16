# 万象词库与语法模型

Zephyr 的 Windows 和 Android 安装包都自带万象、雾凇两套词表。新安装默认使用万象，旧安装保留原有词库选择。两套词表分别从官方 GitHub 更新；407 MB 的万象语法模型不内置。

## 使用方法

1. Windows 打开 **Settings → Dictionary / 词库**；Android 打开 **设置 → 词库与语法模型**（AI 设置也有入口）。
2. 选择万象或雾凇，点击 **应用选择（离线）**。这一步不需要联网。
3. 点击 **更新万象词表** 或 **更新雾凇词表** 更新对应数据，自动校验、部署。不会改变当前选择，也不会顺带下载模型。
4. 需要语法模型时，选择万象并应用，再点击 **下载 / 更新万象语法模型**。当前大小为 407,160,876 字节（约 407 MB / 388 MiB），实际大小以发布信息为准。模型开关默认开启，下载前显示“待下载”，离线输入照常使用词表。

万象词表与模型搭配工作，不是二选一。切换到雾凇时停用万象模型、禁用模型设置；切回万象恢复之前的开关。关闭模型后点击“应用选择”，仍保留下载文件，重新开启无需重下。

下载由按钮触发，支持暂停和续传；Android 后台显示进度通知。建议 Wi-Fi 和至少 1.5 GB 可用空间，第一次编译可能需要几分钟。三个更新按钮都检查 GitHub 上的新版本，不需要重装 APK / Setup。

模型是 **离线的 Rime n-gram 语法模型**，用于本地词句排序，并不是云端 LLM。这个下载功能不会上传输入文本或携带 API Key；现有在线 AI Policy 继续独立工作。

## 下载来源与版本

| 数据 | 官方来源 | 选择规则 |
| --- | --- | --- |
| 万象 Base | [rime-wanxiang](https://github.com/amzxyz/rime-wanxiang/releases/latest) | 最新正式版的 `rime-wanxiang-base.zip` |
| 雾凇字词表 | [rime-ice](https://github.com/iDvel/rime-ice/releases/latest) | `cn_dicts.zip`，当前为 nightly |
| 简体语法模型 | [rime-wanxiang-data / LTS](https://github.com/amzxyz/rime-wanxiang-data/releases/tag/LTS) | `wanxiang-lts-zh-hans.gram` |

LTS 和 nightly 标签会重复使用，因此更新器同时比较 **SHA-256**，不会只比较标签。下载使用 GitHub 返回的文件大小与摘要，支持 Range 续传；校验不通过不部署。不接受用户自定义下载源或第三方镜像。

万象只导入 `zi / jichu / cuoyin / duoyin / diming / mingren / yiren` 七份核心字词表及全拼转写规则。Zephyr 保留自己的布局、快捷键、繁简开关与分段选词逻辑，不加载万象的 Lua 工具、皮肤或更新程序。

雾凇导入 `8105 / base / ext / tencent / others` 五份词表，沿用 Zephyr 全拼方案与 `rime_ice` 学习词库。两套词表分别使用，不合并候选权重。

内置快照：万象 `v18.1.13` / `2a94c48aa51eab2de20b4fdc89e065c05c828875b2bb3336a680f7c140ef088d`；雾凇 `nightly` / `2e682bf965577b113eebf69ab6f5a936d16e8b4a9ca2117e212ad34361cbc453`。来源摘要保存在 `zephyr-dictionaries.json`，状态页显示已安装版本与摘要。

## 文件位置与恢复

- Windows：默认 `%APPDATA%\ZephyrInput\rime`；设置过 Rime 用户目录时沿用该目录。词库更新仅写用户目录，**不需要 UAC**。升级 Zephyr 程序本身仍由安装器处理。
- Android：沿用设置中的 Rime 用户目录，旧安装通常为 `/sdcard/rime-ai-debug`、`/sdcard/rime-ai`，新安装为 `/sdcard/ZephyrInput`。
- 下载状态、版本、许可及事务备份放在 `.zephyr-wanxiang/`；模型和字表使用带摘要的独立文件名，不覆盖正在使用的数据。新旧两代资源保留作恢复；更早的更新器自有资源在成功后清理，文件占用导致清理失败时保留到后续更新。
- 在切换前保存方案配置备份，只有新方案实际产生本地候选后才确认安装成功。失败时恢复原配置；如进程意外退出，下次点击更新会先恢复未完成的事务。
- 不删除旧学习词库、自定义短语、Policy、API Key 或回归测试语料。可以继续使用 `zephyr_wanxiang.custom.yaml` 定制万象方案。

## 来源与许可

万象数据及转写规则来自 **amzxyz 和贡献者**，采用 [CC BY 4.0](https://github.com/amzxyz/rime-wanxiang/blob/wanxiang/LICENSE)。语法模型来源和数据许可范围见 [rime-wanxiang-data](https://github.com/amzxyz/rime-wanxiang-data)。完整许可文本随 Zephyr 共享资源分发；在线更新时也写入用户数据目录。雾凇保留 GPL-3.0-only 许可，源码头和 `licenses/rime-ice` 中保留署名。

Zephyr 改动了方案、数据文件名和引用路径，保留原始字词内容。更新器由本项目自行实现，没有复制万象数据仓库中未授权再分发的 Python / Kotlin / Shell / PowerShell 工具。

## 开发与验证

- 共享实现：`shared/ai-core/src/main/kotlin/com/osfans/trime/rime/`。
- Windows 部署器：`windows/native/ZephyrDataDeploy.cpp`；`windows/scripts/build-data-deployer.ps1` 使用 Visual Studio C++ 工具构建，打包脚本自动调用。
- 默认单测用小型本地 HTTP / ZIP 固件验证续传、取消、摘要、路径检查、版本变化和恢复，不下载大模型。
- Windows 真实引擎测试：`WanxiangNativeTest` 与 `DualDictionaryNativeTest`，通过 `ZEPHYR_WANXIANG_FIXTURE` 指定独立测试目录后启用。
- Android 离线切换测试：`WanxiangAndroidTest#bundledTablesSwitchOfflineWithAndWithoutCachedGrammar`；剪贴板测试：`ClipboardTest`。
- Android 真实资源测试：`WanxiangAndroidTest#realWanxiangDeploymentGrammarAndSegmentedSelection`，需专用模拟器及 instrumentation 参数 `-e wanxiang 1`；可预置摘要命名的 `.part` 文件，应用仍会做完整校验。
- `.gram`、下载缓存和编译词库不提交 Git、不打入安装包。历史研究和生成语料保留。

## 2026-11-16 验证记录

- Windows 1.7.1 / Android 1.6.1 的安装包均通过内容检查：七份万象词表、五份雾凇词表、相应规则与许可已内置，没有 `.gram`。
- 共享核心 73 项通过（含 20 项下载、事务与双词库测试）；Windows 默认套件 45 项通过、5 项可选跳过，真实双词库引擎测试单独启用并通过，完成 GitHub 雾凇资源下载和新用户目录的离线部署。
- Android 模拟器 36 项已有测试及 5 项本次专项通过；真实模型映射、词库切换后开关恢复、拼音纠错、繁简与分段选词均覆盖。第一次重新编译雾凇需数分钟，此后使用已编译数据。
- 修复 Rime 同名内置方案的版本比较与秒级缓存问题；部署后检查编译配置确实引用选择的词表/模型。
- 本轮未更新电脑日常安装和 S26，未发送真实 LLM 请求，未推送 GitHub。
