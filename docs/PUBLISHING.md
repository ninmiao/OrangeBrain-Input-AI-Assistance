# 发布 Zephyr Input

项目保留 GPL-3.0-or-later 许可证、AUTHORS 和第三方源码/许可证。新仓库以本目录作为仓库根目录；不需要恢复旧 Git 历史或子模块。

## 首次提交

- 提交源码、Gradle wrapper、词库、构建脚本、文档和第三方依赖源码。
- `.tools/` 是本机 SDK/JDK/模拟器及缓存，不提交；它不属于源码。
- `dist/` 中 APK 留作 GitHub Release 附件，不提交进 Git 历史。
- 已添加发布用 `.gitignore`，自动排除开发工具、下载的 Boost、构建产物和密钥。开发环境及安装方法见 [DEVELOPMENT.md](DEVELOPMENT.md)。
- 原上游 GitHub 工作流、捐赠配置及其归档已删除。新仓库可自行配置 Actions。
- 新仓库仍须保留上游版权及许可证；旧名称在包名、兼容配置及第三方源码中出现是有意保留。

## 构建

需要 JDK 17、Android SDK（platforms;android-35、build-tools;35.0.0、NDK 28.0.13004108、CMake 3.31.6）、Git 和 Python 3。通过 JAVA_HOME / ANDROID_HOME 配置环境；本机脚本也支持 `.tools/jdk/` 和 `.tools/android-sdk/`。

Windows PowerShell：

```powershell
./script/build-zephyr.ps1 -Variant demo -Abis 'arm64-v8a,x86_64'
```

脚本会重新建立原生插件目录链接。Boost 由 CMake 按固定版本和 SHA256 下载；依赖下载需要网络。不要把本机绝对路径的 Windows junction 当作源码提交。

模拟器测试需要 Python cryptography；`script/test-android.ps1` 会在本地重新生成测试证书并构建测试包。测试私钥不会随源码发布。

清理不改变手机上的应用、词库或加密凭据；清理后的首次本地构建会重新生成缓存。当前发布 APK 为 1.3.0，构建和测试结果见 `docs/ai/zephyr-1.3.0.md`。
