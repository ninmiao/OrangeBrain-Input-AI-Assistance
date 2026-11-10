# Zephyr Input 品牌迁移

2026-11-07。主名称 Zephyr Input，中文名 微风输入法 · Zephyr。版本 1.0.0，versionCode 20261115，覆盖先前 ai.10。

Gradle 项目名、桌面项目目录、应用/输入法列表名称、设置标题、启用向导、关于页、默认主题显示名称、导出 JSON 名称、安装包文件名和主文档更新。

为兼容升级保留 applicationId com.osfans.trime.ai.demo、代码命名空间 com.osfans.trime、Android Keystore 别名、已有数据路径及提示词/方案的内部 ID。新安装默认使用 /sdcard/ZephyrInput；旧安装不移动用户词库。未建立新的用户资料或复制 Key。上游源码许可证、署名、仓库来源和历史记录如实保留。

## 验证
- 在新目录完成 ARM64 与 x86_64 构建；22 项核心测试通过。
- APK 签名校验通过，各语言 application-label 均为 Zephyr Input。
- 模拟器覆盖安装成功，首页品牌与中文副标题确认。
- S26 按用户新指示卸载旧版后全新安装成功，版本 1.0.0；首页与默认 gpt-6-luna 已确认。
- 未发送云端 API 请求。

- 手机默认 Policy 已在用户完成系统身份验证后保存临时 Key（仅设备加密存储）；gpt-6-luna / none / default，AI 已开启。
