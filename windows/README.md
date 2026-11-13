# Zephyr Input for Windows

Windows 1.6.1，已在 Windows 11 x64 验证。C++ TSF 前端与输入服务基于 Weasel，离线使用 librime、雾凇词库和 OpenCC；Kotlin/JVM 复用共享 AI 核心。设置窗口使用 JDK Swing。安装包携带 Java 运行时，使用者不需要安装 Kotlin、JDK 或 Android 开发环境。

## 安装与运行

双击 `Zephyr-Input-Windows-1.6.1-Setup-x64.exe`，完成 Windows 管理员授权。安装程序自动定位 `%ProgramFiles%\Zephyr Input`，注册独立的 x64/x86 TSF 组件、开始菜单和登录启动项。运行新版 Setup 即可覆盖更新，保留当前用户的设置、Key 和词库。安装后注销再登录，从 Windows 输入法菜单选择 **Zephyr Input**。如未显示，在中文（简体，中国）的语言选项中添加 Zephyr Input。

开始菜单 **Zephyr Input** 打开设置；`ZephyrSettings.exe` 也可直接运行。`start_service.bat` 启动当前用户的 AI Broker 和本地输入服务。从 Windows“设置 → 应用 → 已安装的应用 → Zephyr Input”卸载，或运行安装目录的 `unins*.exe（具体编号以系统卸载入口为准）`。卸载程序注销输入法、清理程序文件、开始菜单和启动项；被其他应用占用的旧 TSF DLL 在重启时删除。用户数据默认保留在 `%APPDATA%\ZephyrInput`，便于重装恢复。

系统接入与桌面应用兼容性验收状态以项目 `docs/windows/VALIDATION.md` 为准；编译通过不代表所有文本框已验证。Windows ARM64、Windows 10、远程桌面尚不在已验证范围。

## 输入方式

选择 Rime 的前缀候选会确认该词组，组合区继续显示剩余拼音。继续选词后提交整句。AI 候选和原文候选提交整段文本。

**中文和英文均有组合区、原始输入提示和候选窗口。** 字母、空格和标点首先进入组合区，选择候选才提交；有候选时主键盘 1–5 选词，没有组合输入时数字直接输入；英文不是直接透传。默认保留空格作为词组边界。

| 按键 | 操作 |
| --- | --- |
| 单独轻按 Shift（默认） | 中 / EN 切换，保留当前组合输入；设置中可改为左/右 Shift、Ctrl+Space、Ctrl+Shift+Space 或关闭 |
| Ctrl+Shift+T | 简 / 繁切换 |
| ↑ / ↓ | 移动候选；跨页自动翻页 |
| 1…5，或点击候选 | 选择当前页对应候选 |
| 数字小键盘 | 输入数字；组合中追加原始数字 |
| Enter | 默认提交输入原文，可在设置中改成选词 |
| Tab | 上屏当前候选 |
| Ctrl+Enter | 原样上屏 |
| Esc | 取消组合输入 |
| ← / → / Home / End | 移动组合区光标 |
| Backspace / Delete | 编辑组合输入 |

中英和繁简快捷键均在 Input / 输入页面独立配置。单独轻按 Shift 指 500 ms 内释放，Shift+字母、Shift+方向键和长按不切换语言。Ctrl+Space 可能与系统或应用快捷键冲突，可改选其他组合。

启用“空格提交原文并加空格”后，Space 原样提交并加一个空格，此开关优先于分词；否则开启分词时保留空格，关闭分词时 Space 选词。切换到其他文本框会取消当前未上屏内容，防止旧请求写进另一个应用。密码、系统安全输入和禁用输入法的上下文不走云端。普通快捷键继续交给宿主应用。候选每页五项，AI 固定一项，不生成额外补全；AI 在前，其后是本地候选与原文，重复项合并。

中文提示词修复拼音为汉字、保留并修正英文；英文提示词修复英文、将中英文混输转换为英文。支持漏字母、重复、邻键、换位等常见错误，但候选质量依赖模型，实际失败样本保留在验证报告中。

## AI 设置

AI 默认关闭。在设置中启用并保存。内置三个独立 Policy：OpenAI `gpt-6.1-terra`（低思考、Fast 快速模式）、OpenRouter `deepseek/deepseek-v4-flash-0731`（`wafer/us`），OpenRouter 保持无思考、普通速度；Gemini `gemini-4-hydrogen` 使用 low、普通速度。模型支持下拉选择或直接输入 ID，点击“Update models / 更新模型列表”使用当前 Policy 的接口和 Key 获取可用模型；刷新不会更改当前模型，保存 Policy 后记住列表。OpenRouter 同步接口返回的思考参数；列表按接口隔离，刷新失败保留已有内容。每个 Policy 可编辑接口、模型、路由、按模型适配的思考档位、速度和中英文附加提示词，并测试当前 Policy 延迟。测速有独立结果区，显示被测 Policy、模型、思考、速度、耗时、候选与 token；切换 Policy 后结果保留在原项，HTTP 错误显示状态码。未知模型默认省略思考参数。OpenRouter 模型自动拉取可用供应商，支持下拉选择、刷新和手填路由 ID；列表显示名称及真实路由 tag（例如 `wafer/us`），Policy 列表同步显示所选供应商。OpenAI 和 Gemini 不使用供应商参数。OpenRouter Preset 开关默认关闭，发送完整本地提示词；打开后可设置简体、繁体、英文三个引用，默认是 `@preset/zephyr-zh-hans`、`@preset/zephyr-zh-hant`、`@preset/zephyr-en`。保存 Policy 后生效。Key 无可用 Preset 时，候选窗和测试结果提示关闭此功能。双端都只请求一个纯文本候选，无前后文和表达风格设置。复制 Policy 会复制其参数及已保存的加密凭据。

每次一键测速最多五组，支持 OpenAI、OpenRouter 和 Gemini，每个已保存 Key 的 API 至少一组；它发送实际请求并可能产生费用。网络请求在独立进程执行，失败时保留本地候选和原文。只发送当前组合内容，不读取周边文档或剪贴板。

配置位于 `%APPDATA%\ZephyrInput\settings.json`，凭据经当前 Windows 用户的 DPAPI 加密，分别绑定 Policy 和 HTTPS 来源；接口域名或端口改变后必须重新保存对应 Key。Key 留空表示保留。用户词库位于 `%APPDATA%\ZephyrInput\rime`。源代码、安装包和测试报告不包含真实 Key。

## 开发与验证

从项目根目录运行，详见 `docs/DEVELOPMENT.md`：

```powershell
python windows/scripts/prepare-deps.py
./windows/scripts/build-native.ps1
./gradlew.bat -p windows test installDist
./windows/scripts/package.ps1 -Destination ./.tools/release-image
./windows/scripts/build-installer.ps1 -Image ./.tools/release-image/ZephyrSettings
python tests/corpus/generate.py
python -m unittest discover -s tests/corpus -p test_corpus.py
./windows/scripts/test-components.ps1
./windows/scripts/test-native.ps1 -Platform x64
./windows/scripts/test-native.ps1 -Platform x86
```

运行中的本地服务与 Broker 关闭云端 AI 后，可执行 `test-components.ps1 -Ipc` 及 `-Corpus tests/corpus/generated/native-sample.tsv`。系统安装后使用 `test-native.ps1 -Registered -InstalledPath 'C:\Program Files\Zephyr Input'` 单独验证 OS 管理的 TSF 激活；它仅影响测试进程。

真实 API 回归显式执行，默认不会把大语料发到云端：

```powershell
# 安装包携带运行时；最后一个参数选择已保存的 Policy。
./ZephyrSettings.exe --evaluate <gold.jsonl的完整路径> <report.json的完整路径> 60 openai
./ZephyrSettings.exe --evaluate <gold.jsonl的完整路径> <report.json的完整路径> 60 openrouter
```

保留上游许可证及来源，见 `THIRD-PARTY.md`、`native/UPSTREAM.json`。

覆盖升级会关闭 Zephyr 自身设置与后台进程，请先保存编辑。TSF DLL 按内容版本命名，其他应用持有的旧 DLL 保留到卸载清理；新启动应用加载新版本。
