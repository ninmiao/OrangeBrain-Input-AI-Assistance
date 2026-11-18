# Zephyr Input for Windows

Windows 客户端完全使用 C++。标准 Win32 设置窗口、WinHTTP 网络层、DPAPI 凭据存储和基于 Weasel 的 TSF 输入服务，共用 C++17 AI 核心。安装包不包含 JVM、Kotlin、JAR、Qt 或 WebView，不需要安装 Java、.NET 桌面运行时或 VC++ Redistributable。目标为 Windows 10/11 x64，包含供 32 位应用使用的 TSF DLL；本轮在当前 Windows 11 机器验证。

## 安装与运行

双击 `Zephyr-Input-Windows-1.12.3-Setup-x64.exe`，完成 Windows 管理员授权。安装程序自动定位 `%ProgramFiles%\Zephyr Input`，注册独立的 x64/x86 TSF 组件、开始菜单和登录启动项。运行新版 Setup 即可覆盖更新，保留当前用户的设置、Key 和词库。安装后注销再登录，从 Windows 输入法菜单选择 **Zephyr Input**。如未显示，在中文（简体，中国）的语言选项中添加 Zephyr Input。

开始菜单 **Zephyr Input** 打开设置；`ZephyrSettings.exe` 也可直接运行。`start_service.bat` 启动当前用户的 AI Broker 和本地输入服务。从 Windows“设置 → 应用 → 已安装的应用 → Zephyr Input”卸载，或运行安装目录的 `unins*.exe（具体编号以系统卸载入口为准）`。卸载程序注销输入法、清理程序文件、开始菜单和启动项；被其他应用占用的旧 TSF DLL 在重启时删除。用户数据默认保留在 `%APPDATA%\ZephyrInput`，便于重装恢复。

系统接入与桌面应用兼容性验收状态以项目 `docs/windows/VALIDATION.md` 为准；编译通过不代表所有文本框已验证。Windows ARM64、Windows 10、远程桌面尚不在已验证范围。

## 输入方式

选择 Rime 的前缀候选会确认该词组，组合区继续显示剩余拼音。继续选词后提交整句。AI 候选和原文候选提交整段文本。

**中文和英文均有组合区、原始输入提示和候选窗口。** 字母、空格和标点首先进入组合区，选择候选才提交；有候选时主键盘 1–5 选词，没有组合输入时数字直接输入；英文不是直接透传。默认保留空格作为词组边界。

| 按键 | 操作 |
| --- | --- |
| 单独轻按 Shift（默认） | 中 / EN 切换，保留当前组合输入；设置中可改为左/右 Shift、Ctrl+Space、Ctrl+Shift+Space 或关闭 |
| Ctrl+Shift+T | 简 / 繁切换 |
| F8（默认） | 组字时取消旧 AI 请求并召唤助手。可改为 F9、F10、Ctrl+Shift+F8 或禁用 |
| ↑ / ↓ | 移动候选；跨页自动翻页 |
| 1…5，或点击候选 | 选择当前页对应候选 |
| 数字小键盘 | 输入数字；组合中追加原始数字 |
| Enter | 默认提交输入原文，可在设置中改成选词 |
| Tab | 上屏当前候选 |
| Ctrl+Enter | 原样上屏 |
| Esc | 取消组合输入 |
| ← / → / Home / End | 移动组合区光标 |
| Backspace / Delete | 编辑组合输入 |

中英和繁简快捷键均在 Input / 输入页面独立配置，点击保存后生效。单独轻按 Shift 指 500 ms 内释放，Shift+字母、Shift+方向键和长按不切换语言。Ctrl+Space 可能与系统或应用快捷键冲突，可改选其他组合。

启用“空格提交原文并加空格”后，Space 原样提交并加一个空格，此开关优先于分词。分词开启时保留空格，关闭时用 Space 选词。切换文本框会取消未上屏的内容和旧请求。密码、系统安全输入和禁用输入法的上下文不走云端。候选每页五项，AI 候选排在本地候选和原文前面。

中文提示词修复拼音为汉字、保留并修正英文；英文提示词修复英文、将中英文混输转换为英文。支持漏字母、重复、邻键、换位等常见错误，但候选质量依赖模型，实际失败样本保留在验证报告中。

## AI 设置

在 **方案 / Policy** 设置接口、Key、模型和参数，然后点击 **保存并生效**。可编辑中英文附加提示词，也可复制方案及其加密凭据。项目首页列出了三个内置方案的初始参数。

**更新模型列表**会同步刷新思考选项。OpenRouter 读取服务端档位，OpenAI 和 Gemini 按已核实的型号显示，Gemini 明确标记不支持思考时隐藏档位。已有档位仍适用就保留，否则改用服务端默认。OpenRouter 可另行刷新并选择供应商。

**输入 / Input** 页可设置自动纠错、自动助手及手动快捷键。自动纠错只返回一个候选。自动助手用一次流式请求先显示纠错，再显示助手。两个自动模式都关闭时，可以在组字中按 **F8** 手动请求。前后文默认前 50 字、后 0 字，输出 token 软预算默认 256，均可调整。

每次一键测速从现有 Policy 勾选 1–5 项并点击运行，逐项追加全部成功或失败结果。使用各自的模型、Key 和参数，发送含前后文的长输入样例。它会发送实际请求并产生 API 用量。网络请求在独立后台进程执行，失败保留本地候选；默认读取前 50 / 后 0 字，可关闭上下文。

配置位于 `%APPDATA%\ZephyrInput\settings.json`，凭据经当前 Windows 用户的 DPAPI 加密，分别绑定 Policy 和 HTTPS 来源；接口域名或端口改变后必须重新保存对应 Key。Key 留空表示保留。用户词库位于 `%APPDATA%\ZephyrInput\rime`。源代码、安装包和测试报告不包含真实 Key。

## 开发与验证

从项目根目录运行，详见 `docs/DEVELOPMENT.md`：

```powershell
python windows/scripts/prepare-deps.py
./windows/scripts/build-native.ps1
./windows/scripts/build-app.ps1
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
# 原生程序；最后一个参数选择已保存的 Policy。
./ZephyrSettings.exe --evaluate <gold.jsonl的完整路径> <report.json的完整路径> 60 openai
./ZephyrSettings.exe --evaluate <gold.jsonl的完整路径> <report.json的完整路径> 60 openrouter
```

保留上游许可证及来源，见 `THIRD-PARTY.md`、`native/UPSTREAM.json`。

覆盖升级会关闭 Zephyr 自身设置与后台进程，请先保存编辑。TSF DLL 按内容版本命名，其他应用持有的旧 DLL 保留到卸载清理；新启动应用加载新版本。
