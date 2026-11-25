# iOS CI — run 45478953299 (#14) — **success**

- commit `1c69509b7b022fa8ca6f5388332258ee6151abe4` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45478953299

| job | conclusion | duration |
| --- | --- | --- |
| core-linux | success | 1m25s |
| rime-data | success | 0m32s |
| ipa-device | success | 2m37s |
| e2e-debug | success | 14m57s |
| e2e | success | 19m01s |
| memory-release | success | 5m20s |
| build-test | success | 17m31s |
| release | success | 0m15s |

#### build-test (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- app unit tests (OrangeCellTests, simulator): 15 passed, 0 failed, 0 skipped of 15
- OCCore `swift test` on macOS: 40 tests, 0 failures
- UI tests `ui-embedded`: 10 tests, 0 failures
- unit-test observations (OCINFO lines):
  - `appgroup.source` = `nominalNoProfile container=/Users/runner/Library/Developer/CoreSimulator/Devices/51AAF04C-A3DD-4316-A875-66416504062B/data/Containers/Shared/AppGroup/CC06835F-60E4-4972-921B-2AFE35F2AC9A`
  - `comma.handled` = `true commit=， composing=false`
  - `data.builtWithLibrime` = `1.17.0 linked=1.17.0`
  - `learning.after` = `拟好|你好|你号|你|泥`
  - `learning.before` = `你好|你号|拟好|你|泥 learn=拟好`
  - `learning.orderAfterEachRound` = `拟好,你好,你号 | 拟好,你好,你号 | 拟好,你好,你号 | 拟好,你好,你号 | 拟好,你好,你号 | 拟好,你好,你号`
  - `learning.roundsToTop` = `1`
  - `learning.tapIndices` = `2,0,0,0,0,0`
  - `librime.missingRequired` = ``
  - `librime.modules.afterStart` = `default,core,dict,gears,levers,deployer,lua,octagram,grammar,predict,qjs`
  - `librime.modules.beforeStart` = `default,core,dict,gears,levers,deployer,lua,octagram,grammar,predict,qjs`
  - `librime.started` = `true`
  - `librime.version` = `1.17.0`
  - `lua.candidates` = `LUA-OK composing=true`
  - `lua.deployed` = `true`
  - `nihao.candidates` = `你好|你号|拟好|你|泥|拟|腻|逆`
  - `nihao.preedit` = `ni hao`
  - `oc_core.encode` = `["b": "previous", "i": "nihao"]`
  - `test.footprintMB` = `36.5`
  - `woyaochihuoguo.candidates` = `我要吃火锅|我要吃|我要|窝腰|我呀`

Memory with the shipped dictionary (phys_footprint in MB, XCTest process, baseline included):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.6 | 22.5 |
| 1-engine-and-session | 23.1 | 22.8 |
| 2-first-sentence-typed | 23.1 | 22.8 |
| 3-committed | 23.1 | 22.8 |
| 4-five-more-phrases | 23.2 | 22.8 |
| 5-stopped | 22.8 | 22.6 |

- screenshots: `embedded-embedded-dark-1-zh-idle.png`, `embedded-embedded-dark-2-zh-candidates.png`, `embedded-embedded-dark-3-en.png`, `embedded-embedded-dark-4-123.png`, `embedded-embedded-dark-5-symbols.png`, `embedded-embedded-delete-hold.png`, `embedded-embedded-english-light.png`, `embedded-embedded-landscape-1-zh-candidates.png`, `embedded-embedded-landscape-2-en.png`, `embedded-embedded-light-1-zh-idle.png`, `embedded-embedded-light-2-zh-candidates.png`, `embedded-embedded-light-3-en.png`, `embedded-embedded-light-4-123.png`, `embedded-embedded-light-5-symbols.png`, `embedded-embedded-nihao-light.png`, `embedded-embedded-numbers-light.png`, `embedded-embedded-sentence-light.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 65s |
| fetch-deps | ok | 8s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim | ok | 64s |
| unit-tests | ok | 69s |
| build-ui-tests | ok | 22s |
| uitests-embedded | ok | 567s |
| memory-debug-minimal | ok | 76s |
| memory-debug-all | ok | 75s |
| swift-test-macos | ok | 58s |


#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: 30 tests, 0 failures

| step | result | time |
| --- | --- | --- |
| apt | ok | 10s |
| native-core-test | ok | 11s |
| swift-test-linux | ok | 10s |


#### e2e (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-learn`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess`: 1 tests, 0 failures
- UI tests `ui-typing`: 1 tests, 0 failures

### Simulator end-to-end (Release, full)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after typing (Release, pid 8643) | 46.0 MB |
| no letter fell through to plain text in 中 mode (until typing) | PASS (unhandledLetters=0) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | PASS  |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| Settings UI: Allow Full Access | PASS  |
| keyboard process footprint after learned (Release, pid 16799) | 45.0 MB |
| no letter fell through to plain text in 中 mode (until learned) | PASS (unhandledLetters=0) |
| app deployment while the keyboard runs | PASS (0s) |
| deploy stamp changed | PASS (before: none, after: 2026-11-24T20:33:08Z-3D914789) |
| kill keyboard process | killed pid 16799 |
| keyboard process footprint after restarted (Release, pid 20861) | 44.0 MB |
| no letter fell through to plain text in 中 mode (until restarted) | PASS (unhandledLetters=0) |
| phase B: learn 拟好, app deploys, keyboard restarts, 拟好 is still first | PASS  |
| keyboard report (B) | fullAccess=true userDataShared=true rimeRunning=true deployStamp=2026-11-24T20:33:08Z-3D914789 |
| phase B: with Full Access the user dictionary is in the App Group | PASS (userDataShared=true) |
| phase B: oc_core round trip inside the extension | PASS  |
| phase B: librime modules registered (lua, octagram, predict, qjs) | PASS  |
| phase B: Rime data stamp readable and built by the linked librime | PASS  |
| phase B: the extension sees the app probe file (App Group shared) | PASS  |
| phase B: encrypted-file key store readable across processes | PASS  |
| phase B: user dictionary files present in the App Group | PASS  |
| memory budget: keyboard footprint after typing <= 55 MB | PASS (measured 46.0 MB, highest of all measurements 46 MB) |
| failed checks | 0 |

- keyboard process footprint (`footprint`, MB): typing **46.0**, learned **45.0**, restarted **44.0**
- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/DF361A28-4CE1-4C7E-94C7-9F6F65807926/data/Containers/Data/PluginKitPlugin/04FE94DB-2896-4C31-B6FA-2D54B41C96E9/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 45.7 MB
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (B): librime `1.17.0`, full access `True`, engine running `True`, user dictionary shared `True` (`/Users/runner/Library/Developer/CoreSimulator/Devices/DF361A28-4CE1-4C7E-94C7-9F6F65807926/data/Containers/Shared/AppGroup/C53A460D-97A7-454E-9EDD-4FBD8E495E8E/rime-user`), deploy stamp `2026-11-24T20:33:08Z-3D914789`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 44.3 MB
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
  - biggest dirty categories after typing: dyld private memory 16 MB dirty, MALLOC_SMALL 12 MB dirty, __DATA 7169 KB dirty, __DATA_CONST 6123 KB dirty, page table 1638 KB dirty, CoreAnimation 1376 KB dirty
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `learn-system-learn-1-before.png`, `learn-system-learn-2-learned.png`, `learn-system-learn-3-after-deploy.png`, `learn-system-restart-1-keyboard.png`, `learn-system-restart-2-candidates.png`, `settings-fullaccess-settings-01-launch.png`, `settings-fullaccess-settings-02-keyboard-page.png`, `settings-fullaccess-settings-03-keyboards-list.png`, `settings-fullaccess-settings-04-our-keyboard-page.png`, `settings-fullaccess-settings-05-full-access-alert.png`, `settings-fullaccess-settings-06-full-access-done.png`, `typing-system-1-keyboard.png`, `typing-system-2-nihao.png`, `typing-system-3-sentence.png`, `typing-system-4-committed.png`, `typing-system-5-english.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 12s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 70s |
| e2e-run | ok | 1003s |


#### e2e-debug (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-typing`: 1 tests, 0 failures

### Simulator end-to-end (Debug, typing)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after typing (Debug, pid 12628) | 46.0 MB |
| no letter fell through to plain text in 中 mode (until typing) | PASS (unhandledLetters=0) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | PASS  |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| memory (Debug, information only) | after typing 46.0 MB, highest 46 MB |
| failed checks | 0 |

- keyboard process footprint (`footprint`, MB): typing **46.0**
- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/F68F1541-42F2-42C6-BFA0-D1E314A10762/data/Containers/Data/PluginKitPlugin/6C5DD2BE-30EC-4852-A756-8711292E23B4/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 45.6 MB
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
  - biggest dirty categories after typing: dyld private memory 16 MB dirty, MALLOC_SMALL 12 MB dirty, __DATA 7185 KB dirty, __DATA_CONST 6171 KB dirty, page table 1654 KB dirty, CoreAnimation 1376 KB dirty
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `typing-system-1-keyboard.png`, `typing-system-2-nihao.png`, `typing-system-3-sentence.png`, `typing-system-4-committed.png`, `typing-system-5-english.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 34s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 0s |
| build-e2e | ok | 72s |
| e2e-run | ok | 729s |


#### ipa-device
```
ipa: OrangeCell-iOS-0.2.14.ipa  31983170 bytes
sha256: ac52192938a0736ad12d8f63df3bf98eb7695c66748307f2e423041fcc99465a

== Info.plist (app)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell"
  "CFBundleShortVersionString" => "0.2.14"
  "CFBundleVersion" => "14"
  "DTPlatformName" => "iphoneos"
  "DTSDKName" => "iphoneos26.5"
  "MinimumOSVersion" => "17.0"
== Info.plist (keyboard)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell.keyboard"
  "CFBundleShortVersionString" => "0.2.14"
  "CFBundleVersion" => "14"
  "MinimumOSVersion" => "17.0"
      "IsASCIICapable" => true
      "PrimaryLanguage" => "zh-Hans"
      "RequestsOpenAccess" => true
    "NSExtensionPointIdentifier" => "com.apple.keyboard-service"
    "NSExtensionPrincipalClass" => "OrangeCellKeyboard.KeyboardViewController"
== architectures
Non-fat file: /Users/runner/work/OrangeBrain-Input-AI-Assistance/OrangeBrain-Input-AI-Assistance/build/dd-device/Build/Products/Release-iphoneos/OrangeCell.app/OrangeCell is architecture: arm64
Non-fat file: /Users/runner/work/OrangeBrain-Input-AI-Assistance/OrangeBrain-Input-AI-Assistance/build/dd-device/Build/Products/Release-iphoneos/OrangeCell.app/PlugIns/OrangeCellKeyboard.appex/OrangeCellKeyboard is architecture: arm64
== platform
/Users/runner/work/OrangeBrain-Input-AI-Assistance/OrangeBrain-Input-AI-Assistance/build/dd-device/Build/Products/Release-iphoneos/OrangeCell.app/OrangeCell:
Load command 11
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform IOS
    minos 17.0
      sdk 26.5
   ntools 1
== entitlements (app)
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.application-groups</key><array><string>group.io.github.ninmiao.orangecell</string></array></dict></plist>
== entitlements (keyboard)
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.application-groups</key><array><string>group.io.github.ninmiao.orangecell</string></array></dict></plist>
== signature
Identifier=io.github.ninmiao.orangecell
Format=app bundle with Mach-O thin (arm64)
Signature=adhoc
TeamIdentifier=not set
== librime linked in (symbol present)
1
== payload
     4655  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/opencc/TWVariantsRev.ocd2
    14362  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/opencc/TSCharactersExt.ocd2
      676  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/opencc/s2t.json
      479  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/opencc/jp2t.json
    13843  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/opencc/CJK_Compatibility_Ideographs.ocd2
     1034  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/opencc/tw2sp.json
      370  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/default.custom.yaml
     2954  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/key_bindings.yaml
      996  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/oc-data.json
     2107  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/punctuation.yaml
        0  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/build/
     8600  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang.schema.yaml
   275236  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
 58714452  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
   175732  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
     4757  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/build/default.yaml
    28356  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/symbols.yaml
     1227  11-24-2026 20:18   Payload/OrangeCell.app/rime-shared/default.yaml
  7109168  11-24-2026 20:18   Payload/OrangeCell.app/OrangeCell
    64360  11-24-2026 20:18   Payload/OrangeCell.app/Assets.car
    15754  11-24-2026 20:18   Payload/OrangeCell.app/AppIcon76x76@2x~ipad.png
     1151  11-24-2026 20:18   Payload/OrangeCell.app/Info.plist
        8  11-24-2026 20:18   Payload/OrangeCell.app/PkgInfo
---------                     -------
 74775556                     111 files
```

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 6s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| build-device | ok | 84s |
| make-ipa | ok | 10s |


#### memory-release (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

Release, simulator, phys_footprint in MB (the XCTest process itself is in the baseline):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.5 | 22.5 |
| 1-engine-and-session | 23.0 | 22.8 |
| 2-first-sentence-typed | 23.1 | 22.8 |
| 3-committed | 23.1 | 22.8 |
| 4-five-more-phrases | 23.1 | 22.8 |
| 5-stopped | 22.6 | 22.6 |

- minimal modules: engine + dictionary + first sentence cost **0.3 MB** over the baseline
- all modules: engine + dictionary + first sentence cost **0.6 MB** over the baseline

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 13s |
| fetch-deps | ok | 9s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 2s |
| build-sim-release | ok | 93s |
| memory-release-minimal | ok | 92s |
| memory-release-all | ok | 62s |


#### release
- release: https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/releases/tag/ios-nightly
- SideStore source: https://raw.githubusercontent.com/ninmiao/OrangeBrain-Input-AI-Assistance/ci-results/sidestore/source.json
- total 31240
- -rw-r--r-- 1 runner runner 31983170 Nov 24 20:35 OrangeCell-iOS-0.2.14.ipa
- -rw-r--r-- 1 runner runner       46 Nov 24 20:35 entitlements.json

#### rime-data
- cache hit: true
- compiled with librime 1.17.0, 5 files, 56.4 MiB; dictionary wanxiang v18.1.13
  - 55.99 MiB build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
  - 0.26 MiB build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
  - 0.17 MiB build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
  - 0.01 MiB build/orangecell_wanxiang.schema.yaml
  - 0.00 MiB build/default.yaml
- bundle size:  58M	ios/.rime-data/rime-shared
