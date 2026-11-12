# 开发环境与工具

仓库根目录包含 `android/`、`windows/`、`shared/ai-core/`，不需要嵌套仓库或子模块。Gradle wrapper 保留在根目录，Android 工程仍从根目录构建；Windows 是独立 Gradle 工程，使用 `gradlew.bat -p windows`，仅构建 Windows 时不要求 Android SDK。

## 共用工具

JDK 17（含 jpackage），Python 3.12+，Git，仓库中的 Gradle wrapper。设置 `JAVA_HOME` 并将 Python 放入 PATH。JDK / SDK / VS / Gradle 缓存都是本机工具，不上传到 Git。脚本也支持忽略目录 `.tools/jdk/<JDK>/`。无需全局安装 Kotlin 或 Gradle。

## Android

| 工具 | 版本 |
| --- | --- |
| SDK Platform / Build Tools | android-35 / 35.0.0 |
| NDK | 28.0.13004108 |
| CMake | 3.31.6 |
| JDK | 17 |
| Boost | 1.89.0，固定 SHA256 下载 |

设置 `ANDROID_HOME`；也可使用 `.tools/android-sdk/`。Android Studio 可选，command-line tools 足以构建。

```powershell
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;28.0.13004108" "cmake;3.31.6"
./script/build-android.ps1 -Variant demo -Abis 'arm64-v8a,x86_64'
./android/script/test-zephyr.ps1
# 模拟器 API 35 x86_64，Python cryptography 供本地 HTTPS 测试
python -m pip install cryptography
./android/script/test-android.ps1
```

APK 输出为 `android/app/build/outputs/apk/demo/`。原有 `script/` 测试工具已迁至 `android/script/`。脚本重建本机 JNI junction；不能提交 junction、预编译字典或用户数据。API 包名、存储兼容标识不因目录迁移改变。不要向日常手机运行会覆盖测试配置的模拟器回归脚本。

## Windows 11 x64

安装 Visual Studio 2022 Build Tools 的 C++ 桌面工具链、MSVC v143、ATL 和 Windows SDK 10.0.22621.0；不需要 MFC。安装 7-Zip；生成一键安装程序还需要 [Inno Setup 7](https://jrsoftware.org/isdl.php)，默认编译器为 `.tools/inno/ISCC.exe`，也可向 `build-installer.ps1` 传 `-Compiler`。此机器实测 MSVC 14.41.34120、JDK 17、Boost 1.89、librime 1.17.0。ARM64 不在此构建脚本范围。

```powershell
python windows/scripts/prepare-deps.py
./windows/scripts/build-native.ps1 -Architecture both
./gradlew.bat -p windows test installDist
./windows/scripts/package.ps1 -Destination ./.tools/release-image
./windows/scripts/build-installer.ps1 -Image ./.tools/release-image/ZephyrSettings
```

`prepare-deps.py` 校验官方 librime x64/x86 下载的 SHA256，准备 Boost 源码并编译两种位数的静态库。原生头文件、补丁与 Weasel 源码在 `windows/native/`，上游固定 commit 见 `UPSTREAM.json`。工具、压缩包及库在 `.tools/` 或忽略目录中。若 Boost 已准备好，可传 `--skip-boost`。

标准 VS 安装通过 vcvars 使用 ATL；此机额外的 `.tools/windows-atl` 是本机提取的微软开发依赖缓存，不属于项目源码，也不要求其他开发者复制。原生脚本使用可用的 VS 安装路径，不固定当前用户名。

`package.ps1` 从已提交的 OpenCC 源词表生成 Windows 文本词典，不依赖 Android 的历史构建产物。它运行 JVM 测试、打包自包含 Java 运行时、两个位数的 TSF DLL、x64 输入服务和词库。输出目录必须是新目录，避免覆盖正在运行的包。安装包不包含用户配置、API Key、测试证书或几十万条生成语料。`build-installer.ps1` 将 app-image 包装为单个 `dist/Zephyr-Input-Windows-1.5.1-Setup-x64.exe`；安装器源码位于 `windows/installer/`。EXE 尚未进行产品代码签名。

管理员 PowerShell 中可执行 `windows/scripts/test-installer.ps1 -Setup <Setup完整路径>`，它实际执行更新、重复覆盖、卸载和重装，检查注册项、程序文件及配置/凭据哈希。该脚本会暂时中断本机输入法，适合专用验证环境，不作为普通单元测试执行。最终恢复当前版本，原始报告保存在 `.tools/installer-validation.json`。

## 测试

```powershell
./gradlew.bat -p windows test
./gradlew.bat -p shared/ai-core test
python tests/corpus/generate.py
python -m unittest discover -s tests/corpus -p test_corpus.py
./windows/scripts/test-components.ps1
./windows/scripts/test-native.ps1 -Platform x64
./windows/scripts/test-native.ps1 -Platform x86
```

`test-native.ps1` 默认只检查 DLL/COM 接口；`-Registered -InstalledPath <安装目录>` 才检查真实 OS 管理的 profile 激活。不要将两者混写成一个“TSF 全部通过”。安装是管理员操作，构建及普通组件测试不要求管理员权限。

在输入服务和 Broker 已启动、云端 AI 已关闭时，执行 `test-components.ps1 -Ipc` 检查真实 librime、OpenCC、组合输入、上屏、焦点取消和本机管道。生成采样：`python tests/corpus/sample-native.py`；逐键回归：`test-components.ps1 -Corpus tests/corpus/generated/native-sample.tsv`。时延仅代表输入服务 IPC，不代表显示延迟。

真实 API 评估另行显式运行，见 Windows README。人工回归 44 条与自动生成 464,693 条分开报告；自动变体不是人工确认的唯一意图。质量验收必须查看逐条输出、协议失败、Top-1/Top-3 和同义答案，不能仅看请求成功数。


`windows/tests/tsf_ui_host.cpp` 是标准 Win32 Edit、RichEdit、密码框的交互测试宿主，使用真实注册的 TSF，仅在自己的进程激活 Profile。它不通过 SendInput 模拟输入、不修改系统默认输入法。使用 `./windows/scripts/build-test-host.ps1 -Platform x64` 构建（也支持 x86）。程序位于 `windows/build/ui-host-x64/tsf_ui_host.exe`，可供人工或经授权的电脑操作工具操作。真实逐键输入请使用键盘，不要用粘贴代替。
