# 在 iPhone 上安装 橘脑一颗 OrangeCell（Windows 11 + SideStore + 免费 Apple ID）

整个流程大约 30-45 分钟（电脑一次性设置约 15 分钟，手机设置约 10 分钟，安装和启用键盘约 10 分钟）。电脑只在第一步用到，之后全部在手机上完成。
标注「待核实」的内容，我没能从 SideStore 官方文档或仓库里确认。

## 1. 准备（约 5 分钟）

需要：
- 一部 iPhone，系统 iOS 15.0 或更高，并且设置了锁屏密码（官方要求设备必须有密码）。
- 一根能传数据的 USB 线。
- 一台 64 位 Windows 电脑（不支持 32 位 Windows，也不支持 ARM 版 Windows 10；Win11 通常没问题）。
- 一个 Apple ID。登录用的账号不必是手机上登录的那个，注意大小写和密码。
- 稳定的 Wi-Fi。官方明确说只有手机流量不行，安装和续签都需要 Wi-Fi。

关于是否用小号：官方安装页没有要求用小号。官方只在两处提到：安装失败时可以「换一个 Apple ID 试试，必要时免费新建一个专用于 SideStore 的账号」；报错 1102 时可以用专门的「一次性」账号。
所以主账号能用就先用主账号，出问题再换小号。这是官方的备用办法，不是强制要求。

免费账号的限制（官方 FAQ）：
- 同时最多装 3 个应用（SideStore 自己算 1 个）。装好橘脑一颗后，你还剩 1 个名额。
- 每 7 天最多新注册 10 个 App ID。App ID 不能手动删除。
- 应用有效期 7 天，到期前必须续签。
- 橘脑一颗包含「主 App + 键盘扩展」，可能各占一个 App ID，一次安装约占 2-3 个，超过 10 个会报错。「待核实」（官方没有明说扩展是否单独计数）。

## 2. 在电脑上一次性安装 SideStore（约 15 分钟）

官方现在的主流方式是 iloader，它取代了过去的 AltServer / SideServer，也不再需要手动做配对文件（iloader 会自动放好配对文件）。AltServer 方式现在被官方放进「Alternative/Outdated」页，不推荐新手使用。

1. 先在 iPhone 上安装 LocalDevVPN（App Store 搜索 LocalDevVPN），打开后点 Connect；如果提示「允许添加 VPN 配置」，点 Allow 并输入锁屏密码。
2. 在电脑上安装 iTunes。官方推荐直接从 Apple 官网下载 64 位版（https://www.apple.com/itunes/download/win64），也可用 Microsoft Store 版。两个都不行时才改用「Apple 设备」(Apple Devices) App。它的作用是提供 iPhone 的 USB 驱动。
3. 从 https://iloader.app 或 https://github.com/nab138/iloader/releases 下载 iloader 的 Windows 安装包（推荐 .msi），运行安装。只从这两处下载。
4. 用 USB 线连接 iPhone，手机上点「信任此电脑」并输入密码。
5. 打开 iloader，登录 Apple ID，选择你的 iPhone，点 Install SideStore (Stable)。
6. 手机会自动回到主屏幕并弹出通知，几秒后 SideStore 出现在主屏幕上。

配对文件说明：配对文件让 SideStore 能「自己连自己」去签名安装。用 iloader 安装时会自动放入。
如果以后提示配对文件失效（常见于升级或重置 iOS 之后，也会随机失效），到 iloader 里：点 Delete Stored Pairing，选中设备并在手机上点「信任」，再点 Manage Pairing File，在 SideStore 旁点 Place，看到绿色的 "Pairing file placed successfully!" 即可。
官方对 SideStore 版本的说明：截至 2026-11，GitHub 上最新发布是 0.7.0-alpha（2026-09-15，修复登录 503 错误）；0.6.4 及更早版本因 Apple 服务器变更无法登录。iloader 的「Stable」具体装哪个版本「待核实」，装完后若登录报错，先看第 8 节。

## 3. 手机上的设置（约 10 分钟）

官方按 iOS 版本分三种流程，下面是综合版：

1. 设置 → 通用 → VPN 与设备管理 → 「开发者 App」下点你的 Apple ID → 点「信任」并确认。
   - iOS 18 及以上：该按钮是「允许并重新启动」，之后输入锁屏密码确认。
2. iOS 16 及以上：设置 → 隐私与安全性 → 拉到最底部，打开「开发者模式」，手机会重启，重启后按提示确认开启。iOS 15 没有这一项。
3. 打开 LocalDevVPN，点 Connect（每次安装、更新、续签时它都必须是开启状态）。
4. 打开 SideStore，用 iloader 里同一个 Apple ID 登录。
5. 进入「我的 App」(My Apps)，点 SideStore 右边的「7 DAYS」计数器，手动续签一次，完成初始化。
6. 如果弹出「撤销/新建签名证书」，点 Yes 或 Refresh Now。
7. 官方 FAQ 提醒：登录后先续签 SideStore，再安装其他应用（因为 iloader 用的 App Group 和 SideStore 自己的不同，续签后才会统一）。

## 4. 添加源并安装橘脑一颗（约 5 分钟）

1. 确认 LocalDevVPN 已连接，手机连着 Wi-Fi。
2. 在 SideStore 里打开「Sources」（源）页，点右上角「+」，粘贴源地址：
   https://raw.githubusercontent.com/ninmiao/OrangeBrain-Input-AI-Assistance/ci-results/sidestore/source.json
   （Sources 页和「+」的具体位置，官方文档没有逐步截图，按界面为准「待核实」。）
3. 添加后进入这个源，找到 橘脑一颗，点 FREE / GET 安装。
4. 安装后 App Group 会变成 `group.io.github.ninmiao.orangecell.<TEAMID>`，这是正常的，应用已经处理好，不用理会。

如果源加载失败或装不上：
1. 在手机 Safari 打开 https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/releases/tag/ios-nightly ，下载 .ipa 文件到「文件」App。
2. 打开 SideStore，在「我的 App」页点左上角或右上角的「+」（位置按界面为准「待核实」），选择刚下载的 .ipa，SideStore 会重新签名并安装。
3. 也可以在电脑上用 iloader 的 Import IPA 功能装（iloader 官方 README 列出了此功能），但手机端用「+」更简单。

## 5. 启用键盘（约 2 分钟）

1. 设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 选 橘脑一颗。
2. 回到键盘列表，点 橘脑一颗，打开「允许完全访问」。
3. 打开任意输入框（比如「备忘录」），长按或点按地球键切换到 橘脑一颗。

## 6. 回传诊断信息

1. 打开 橘脑一颗 → 诊断 → 点「复制诊断信息」，把内容粘贴发回来。
2. 再发两张截图：诊断页面的截图，以及在「备忘录」里用 橘脑一颗 键盘输入「你好」的截图。

## 7. 7 天续签

- 应用有效期 7 天。「我的 App」里每个应用旁的数字就是剩余天数，点它可以手动续签。
- 自动续签：官方 FAQ 说 SideStore 会在后台定期续签你的应用，以免过期。但官方文档没有写具体触发条件和设置项，是否需要保持 LocalDevVPN 开着、需不需要 Wi-Fi，以官方的说法是「安装、更新、续签时 VPN 必须开着」。建议：LocalDevVPN 保持连接，开启 SideStore 的后台 App 刷新，每隔几天手动看一次剩余天数。自动续签的实际可靠性「待核实」。
- 0.6.4 更新说明里提到可以开启「蜂窝网络续签」，需要配合快捷指令；这不是默认功能，本指南不依赖它「待核实」。
- 过期后会怎样：应用和键盘扩展会失效，键盘无法加载，主 App 也打不开。你的数据不会丢（官方 FAQ 的说法是重新签名安装同一个应用，数据保留，但对本应用的数据保留以实测为准）。打开 SideStore，连上 LocalDevVPN 和 Wi-Fi，在「我的 App」里续签 橘脑一颗 即可恢复。
- 如果「我的 App」里应用消失了：不要卸载，在 SideStore 里重新安装同一个应用，并先续签 SideStore 看它们是否回来（官方建议）。

## 8. 常见问题

- 提示 "Could not find AltServer"：这是旧的 AltStore / AltServer 方式的报错。现行官方流程不再使用 AltServer，也不会遇到它。如果你看到它，说明用的是过时教程，请按本指南第 2 节用 iloader 重装。官方文档里没有这个报错条目「待核实」。
- 提示没有 Wi-Fi/VPN（错误 1414），或 AFC 连接失败（minimuxer 错误 27）：确认 LocalDevVPN 和 Wi-Fi 都连着，重启 SideStore 和 LocalDevVPN，关闭 DNS 屏蔽类应用，必要时换回 LocalDevVPN（官方已弃用 WireGuard；StosVPN 在官方文档里已被 LocalDevVPN 取代）。仍不行，就用 iloader 重新放置配对文件。iOS 26.4 及以上若仍报错 27，官方建议更新到 SideStore nightly。
- 配对文件失效（错误 1006 或升级 iOS 之后）：按第 2 节的配对文件步骤重做。官方对 1006 还提示：到 SideStore 设置里点 Reset Pairing File，再用 iloader 的 Delete Stored Pairing、Manage Pairing File → Place；仍不行就重启手机。
- App ID 超限（错误 1009 / 3013，每 7 天只能注册 10 个）：无法手动删除。到「我的 App」查看 App ID 何时过期，等过期后再装；不要反复卸载重装。
- 超过 3 个应用：先删掉一个不用的。
- 登录卡住或报错：多半是 Anisette 服务器临时故障。SideStore 设置里换一个 Anisette 服务器。收不到验证码时，在手机设置里点你的名字 → 登录与安全，临时关掉 Wi-Fi 和蜂窝数据，再点「获取验证码」。
- 反复用不可靠的第三方 Anisette 服务器可能导致 Apple ID 被锁，官方建议只用官方服务器。
- 错误 1102（Apple ID 不能用于开发）：到 developer.apple.com 同意 Apple 的条款；还不行就新建一个专用小号。
- 安装时进度卡在最后：回到主屏幕等一会儿，官方说这是已知现象。
- 点开应用报「未受信任的开发者」或错误 1011：回第 3 节第 1 步重新信任 Apple ID。
- SideStore 本身打不开：用 iloader 重新安装 SideStore。
- iloader 本身的问题，官方让去 idevice Discord 求助，SideStore 官方群不处理。

## 参考来源（官方）

- https://docs.sidestore.io/docs/installation/prerequisites
- https://docs.sidestore.io/docs/installation/install
- https://docs.sidestore.io/docs/advanced/pairing-file
- https://docs.sidestore.io/docs/advanced/alternative （AltServer / WireGuard / idevice_pair，已降级为旧方法）
- https://docs.sidestore.io/docs/faq
- https://docs.sidestore.io/docs/troubleshooting/common-issues
- https://docs.sidestore.io/docs/troubleshooting/troubleshooting
- https://docs.sidestore.io/docs/troubleshooting/error-codes
- https://docs.sidestore.io/docs/release-notes
- https://github.com/SideStore/SideStore/releases （0.6.4、0.7.0-alpha 发布说明）
- https://github.com/nab138/iloader （iloader 官方仓库，v2.4.2，2026-11-20）
- https://iloader.app
