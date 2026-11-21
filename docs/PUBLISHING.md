# 发布 OrangeCell

以项目根目录建库。`.gitignore` 使用根目录允许清单，并进一步排除缓存、编译输出、本机凭据、旧截图和历史测试输出。

## 源码范围

- `android/`、`windows/`、`shared/`：客户端、共享 AI 核心、必需原生依赖源码、词库和资源。
- `script/`、`tests/`：构建入口、测试程序、语料生成器与人工参考集。
- `gradle/` 和根目录构建配置：包含必须提交的 Gradle wrapper JAR。
- `docs/DEVELOPMENT.md`：Android/Windows 开发环境和工具安装说明。
- 当前版本验证说明、测试使用的模型配置示例和参考数据。
- README、PRIVACY、LICENSE、AUTHORS 以及第三方组件原有许可证。

SDK、JDK、模拟器、VS/Boost 缓存、生成语料、截图、测试日志、编译输出、私钥和用户凭据不进入源码仓库。按项目发布要求，`dist/` 例外跟踪当前 Android ARM64 Demo APK、Windows x64 安装器和 `SHA256SUMS`。最新版本和下载链接见 [README](../README.md)。升级时必须同步更新 `.gitignore` 的精确允许清单；其他 APK/ZIP/EXE 仍被忽略。

本项目仍有约五千个源码/资源文件，主要来自 Weasel、librime、OpenCC 等原生依赖及词库；它们不是开发工具缓存，不应仅为降低文件数而移除。源码体积较大的部分是必要词库。万象与雾凇原始字词表、全拼规则、署名和许可证应一同提交；`.gram` 模型、下载缓存和编译词库保留在本地忽略目录。

## 发布前检查

运行 `python script/check-publish.py` 检查当前文件清单、必需构建文件、被误跟踪的忽略文件、凭据特征和 GitHub 单文件大小限制。检查不会显示密钥内容，不会提交或上传。

`.gitignore` 不会自动取消已经跟踪的文件。如果检查提示被忽略但仍被跟踪的文件，先用 `git rm --cached -- <路径>` 取消跟踪，保留本地文件，再重新检查。不要用 `git clean -xfd`：它会删除本机工具和发布包。

## 构建与发布附件

两端均内置万象、雾凇词表，可从官方 GitHub 更新。约 407 MB 的万象语法模型单独下载。两端共用 C++ AI 核心，使用流式 JSON 候选数组、默认前 50 / 后 0 字上下文和 token 软预算。Windows 手动保存，Android 设置自动生效，一键测速选择已有 Policy。

在 GitHub Actions 手动运行 OrangeCell cloud builds，两端通过后下载同一个 `dist` 附件并核对校验值。发布到仓库之前，用本地既有 Demo 证书给云端 APK 重签，并重新生成 `SHA256SUMS`，保证已有 Demo 用户可覆盖安装。环境与命令见 [DEVELOPMENT.md](DEVELOPMENT.md)。Windows 先使用 `windows/scripts/package.ps1` 生成 app-image，再使用 `build-installer.ps1` 生成包含原生程序和词表的 Setup EXE（不含 JVM/Kotlin），只发布这个安装器；Android 发布 ARM64 demo APK。各版本的构建和验证结果见 [更新日志](../UPDATE_LOG.md)。

新库仍需保留项目及第三方源码许可证、版权和来源信息。不将手机或 Windows 用户数据放入项目；不将本地加密凭据作为“安全文件”发布。

最新颜表情功能与验证见 [更新说明](ai/kaomoji-1.3.6-1.4.5.md)。

Android Policy 复制功能见 [1.3.7 更新说明](ai/policy-copy-1.3.7.md)。

Windows Policy 复制见 [1.4.6 更新说明](windows/policy-copy-1.4.6.md)。

生成语料保存在 `tests/corpus/generated/`，构建清理保留。人工重点回归集当前为 60 条，中英文各 30 条。更新历史见根目录 `UPDATE_LOG.md`。
