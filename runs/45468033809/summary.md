# iOS CI — run 45468033809 (#11) — **failure**

- commit `ab797fbf2b9583f47b2b504047dd41190c3383d2` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45468033809

| job | conclusion | duration |
| --- | --- | --- |
| rime-data | success | 0m38s |
| core-linux | success | 1m22s |
| e2e-debug | failure | 10m55s |
| build-test | success | 16m50s |
| ipa-device | success | 2m16s |
| memory-release | success | 3m22s |
| e2e | failure | 19m06s |
| release | skipped | 0m00s |

**e2e-debug** failed in step(s): Typing run (Debug)

**e2e** failed in step(s): End-to-end run (Release)

#### build-test (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- app unit tests (OrangeCellTests, simulator): 15 passed, 0 failed, 0 skipped of 15
- OCCore `swift test` on macOS: 40 tests, 0 failures
- UI tests `ui-embedded`: 10 tests, 0 failures
- unit-test observations (OCINFO lines):
  - `appgroup.source` = `nominalNoProfile container=/Users/runner/Library/Developer/CoreSimulator/Devices/FDDED8BD-B8B7-4403-9219-B71B33BF27F3/data/Containers/Shared/AppGroup/9C7715B2-A967-4764-96E9-C7421E68D91A`
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
  - `oc_core.encode` = `["i": "nihao", "b": "previous"]`
  - `test.footprintMB` = `36.6`
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
| toolchain | ok | 48s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim | ok | 56s |
| unit-tests | ok | 53s |
| build-ui-tests | ok | 18s |
| uitests-embedded | ok | 588s |
| memory-debug-minimal | ok | 81s |
| memory-debug-all | ok | 68s |
| swift-test-macos | ok | 52s |


#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: 30 tests, 0 failures

| step | result | time |
| --- | --- | --- |
| apt | ok | 11s |
| native-core-test | ok | 16s |
| swift-test-linux | ok | 15s |


#### e2e (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-learn`: 1 tests, 1 failures
- UI tests `ui-settings-fullaccess`: 1 tests, 0 failures
- UI tests `ui-typing`: 1 tests, 1 failures

### Simulator end-to-end (Release, full)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | **FAIL** (see ui-typing logs and screenshots) |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| Settings UI: Allow Full Access | PASS  |
| phase B: learn 拟好, app deploys, keyboard restarts, 拟好 is still first | **FAIL** (see ui-learn logs and screenshots) |
| keyboard report (B) | fullAccess=true userDataShared=true rimeRunning=true deployStamp= |
| phase B: with Full Access the user dictionary is in the App Group | PASS (userDataShared=true) |
| phase B: oc_core round trip inside the extension | PASS  |
| phase B: librime modules registered (lua, octagram, predict, qjs) | PASS  |
| phase B: Rime data stamp readable and built by the linked librime | PASS  |
| phase B: the extension sees the app probe file (App Group shared) | PASS  |
| phase B: encrypted-file key store readable across processes | PASS  |
| phase B: user dictionary files present in the App Group | PASS  |
| memory budget: keyboard footprint after typing <= 55 MB | **FAIL** (measured n/a MB, highest of all measurements 0 MB) |
| failed checks | 3 |

- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/2BCF8C5A-4964-470D-8C98-9F5E58ECC92E/data/Containers/Data/PluginKitPlugin/13135696-18A4-4D07-A447-5C1705C91944/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 39.9 MB
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (B): librime `1.17.0`, full access `True`, engine running `True`, user dictionary shared `True` (`/Users/runner/Library/Developer/CoreSimulator/Devices/2BCF8C5A-4964-470D-8C98-9F5E58ECC92E/data/Containers/Shared/AppGroup/0F12F9FC-00C6-4AF7-9B36-B096A1A49F0C/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 41.2 MB
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `settings-fullaccess-settings-01-launch.png`, `settings-fullaccess-settings-02-keyboard-page.png`, `settings-fullaccess-settings-03-keyboards-list.png`, `settings-fullaccess-settings-04-our-keyboard-page.png`, `settings-fullaccess-settings-05-full-access-alert.png`, `settings-fullaccess-settings-06-full-access-done.png`, `typing-system-1-keyboard.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 8s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 76s |
| e2e-run | FAILED (3) | 996s |


#### e2e-debug (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-typing`: 1 tests, 1 failures

### Simulator end-to-end (Debug, typing)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | **FAIL** (see ui-typing logs and screenshots) |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| memory (Debug, information only) | after typing n/a MB, highest 0 MB |
| failed checks | 1 |

- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/10ACEDB2-246D-45E6-8F86-C08226E01D98/data/Containers/Data/PluginKitPlugin/9454EED9-5E73-48EA-B3B1-0C6FBDA9FB29/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 40.1 MB
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `typing-system-1-keyboard.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 14s |
| fetch-deps | ok | 11s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 57s |
| e2e-run | FAILED (1) | 524s |


#### ipa-device
```
ipa: OrangeCell-iOS-0.2.11.ipa  31982064 bytes
sha256: 6eeb6f68a8c6b6054d0d1a4d22688430c3b4fa45d735a27a56ee9bd4d394a600

== Info.plist (app)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell"
  "CFBundleShortVersionString" => "0.2.11"
  "CFBundleVersion" => "11"
  "DTPlatformName" => "iphoneos"
  "DTSDKName" => "iphoneos26.5"
  "MinimumOSVersion" => "17.0"
== Info.plist (keyboard)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell.keyboard"
  "CFBundleShortVersionString" => "0.2.11"
  "CFBundleVersion" => "11"
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
     4655  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/opencc/TWVariantsRev.ocd2
    14362  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/opencc/TSCharactersExt.ocd2
      676  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/opencc/s2t.json
      479  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/opencc/jp2t.json
    13843  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/opencc/CJK_Compatibility_Ideographs.ocd2
     1034  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/opencc/tw2sp.json
      370  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/default.custom.yaml
     2954  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/key_bindings.yaml
      996  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/oc-data.json
     2107  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/punctuation.yaml
        0  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/build/
     8600  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang.schema.yaml
   275236  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
 58714452  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
   175732  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
     4757  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/build/default.yaml
    28356  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/symbols.yaml
     1227  11-24-2026 19:16   Payload/OrangeCell.app/rime-shared/default.yaml
  7108416  11-24-2026 19:16   Payload/OrangeCell.app/OrangeCell
    64360  11-24-2026 19:16   Payload/OrangeCell.app/Assets.car
    15754  11-24-2026 19:16   Payload/OrangeCell.app/AppIcon76x76@2x~ipad.png
     1151  11-24-2026 19:16   Payload/OrangeCell.app/Info.plist
        8  11-24-2026 19:16   Payload/OrangeCell.app/PkgInfo
---------                     -------
 74772964                     111 files
```

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 10s |
| fetch-deps | ok | 4s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| build-device | ok | 76s |
| make-ipa | ok | 11s |


#### memory-release (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

Release, simulator, phys_footprint in MB (the XCTest process itself is in the baseline):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.5 | 22.5 |
| 1-engine-and-session | 22.9 | 22.7 |
| 2-first-sentence-typed | 22.9 | 22.8 |
| 3-committed | 22.9 | 22.8 |
| 4-five-more-phrases | 23.0 | 22.8 |
| 5-stopped | 22.6 | 22.6 |

- minimal modules: engine + dictionary + first sentence cost **0.3 MB** over the baseline
- all modules: engine + dictionary + first sentence cost **0.4 MB** over the baseline

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 9s |
| fetch-deps | ok | 9s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 1s |
| simulator-create | ok | 1s |
| build-sim-release | ok | 55s |
| memory-release-minimal | ok | 54s |
| memory-release-all | ok | 45s |


#### rime-data
- cache hit: true
- compiled with librime 1.17.0, 5 files, 56.4 MiB; dictionary wanxiang v18.1.13
  - 55.99 MiB build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
  - 0.26 MiB build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
  - 0.17 MiB build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
  - 0.01 MiB build/orangecell_wanxiang.schema.yaml
  - 0.00 MiB build/default.yaml
- bundle size:  58M	ios/.rime-data/rime-shared
