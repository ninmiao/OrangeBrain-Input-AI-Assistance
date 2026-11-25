# iOS CI — run 45536538670 (#15) — **failure**

- commit `a1a0081781473a9e87b14a551a01f12ae24dfd19` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45536538670

| job | conclusion | duration |
| --- | --- | --- |
| core-linux | success | 1m18s |
| rime-data | success | 0m45s |
| build-test | success | 17m35s |
| e2e-debug | success | 11m33s |
| memory-release | success | 6m14s |
| e2e | failure | 29m49s |
| ipa-device | success | 3m29s |
| release | skipped | 0m00s |

**e2e** failed in step(s): End-to-end run (Release)

#### build-test (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- app unit tests (OrangeCellTests, simulator): 17 passed, 0 failed, 0 skipped of 17
- OCCore `swift test` on macOS: 45 tests, 0 failures
- UI tests `ui-embedded`: 12 tests, 0 failures
- unit-test observations (OCINFO lines):
  - `appgroup.source` = `nominalNoProfile container=/Users/runner/Library/Developer/CoreSimulator/Devices/D493F43F-0690-41E8-94EF-090FDB06C918/data/Containers/Shared/AppGroup/50708714-BEC8-4314-8465-D89E716B0B43`
  - `comma.handled` = `true commit=， composing=false`
  - `data.builtWithLibrime` = `1.17.0 linked=1.17.0`
  - `f1.slowStart.inserted` = `你好 unhandled=0`
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
  - `test.footprintMB` = `36.9`
  - `woyaochihuoguo.candidates` = `我要吃火锅|我要吃|我要|窝腰|我呀`

Memory with the shipped dictionary (phys_footprint in MB, XCTest process, baseline included):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.6 | 22.6 |
| 1-engine-and-session | 23.1 | 22.8 |
| 2-first-sentence-typed | 23.1 | 22.8 |
| 3-committed | 23.1 | 22.8 |
| 4-five-more-phrases | 23.2 | 22.9 |
| 5-stopped | 22.8 | 22.6 |

- screenshots: `embedded-embedded-dark-1-zh-idle.png`, `embedded-embedded-dark-2-zh-candidates.png`, `embedded-embedded-dark-3-en.png`, `embedded-embedded-dark-4-123.png`, `embedded-embedded-dark-5-symbols.png`, `embedded-embedded-delete-hold.png`, `embedded-embedded-english-light.png`, `embedded-embedded-grid-light.png`, `embedded-embedded-landscape-1-zh-candidates.png`, `embedded-embedded-landscape-2-en.png`, `embedded-embedded-light-1-zh-idle.png`, `embedded-embedded-light-2-zh-candidates.png`, `embedded-embedded-light-3-en.png`, `embedded-embedded-light-4-123.png`, `embedded-embedded-light-5-symbols.png`, `embedded-embedded-nihao-light.png`, `embedded-embedded-number-row-light.png`, `embedded-embedded-numbers-light.png`, `embedded-embedded-sentence-light.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 13s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim | ok | 61s |
| unit-tests | ok | 73s |
| build-ui-tests | ok | 18s |
| uitests-embedded | ok | 633s |
| memory-debug-minimal | ok | 83s |
| memory-debug-all | ok | 65s |
| swift-test-macos | ok | 56s |


#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: 35 tests, 0 failures

| step | result | time |
| --- | --- | --- |
| apt | ok | 10s |
| native-core-test | ok | 11s |
| swift-test-linux | ok | 10s |


#### e2e (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-fullaccess-off`: 1 tests, 1 failures
- UI tests `ui-fullaccess`: 1 tests, 0 failures
- UI tests `ui-learn`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess-off`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess`: 1 tests, 0 failures
- UI tests `ui-typing`: 1 tests, 0 failures

### Simulator end-to-end (Release, full)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after typing (Release, pid 11105) | 54.0 MB |
| no letter fell through to plain text in 中 mode (until typing) | PASS (unhandledLetters=0) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | PASS  |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| keyboard process footprint after learned (Release, pid 11105) | 56.0 MB |
| no letter fell through to plain text in 中 mode (until learned) | PASS (unhandledLetters=0) |
| phase A: learn 拟好 without Full Access | PASS  |
| Settings UI: Allow Full Access | PASS  |
| keyboard process footprint after fullaccess (Release, pid 25969) | 49.0 MB |
| no letter fell through to plain text in 中 mode (until fullaccess) | PASS (unhandledLetters=0) |
| app deployment while the keyboard runs | PASS (0s) |
| deploy stamp changed | PASS (before: none, after: 2026-11-25T03:18:43Z-C1FD2C0F) |
| kill keyboard process | killed pid 25969 |
| keyboard process footprint after restarted (Release, pid 29590) | 51.0 MB |
| no letter fell through to plain text in 中 mode (until restarted) | PASS (unhandledLetters=0) |
| phase B: with Full Access 拟好 is still first, the app deploys, the keyboard restarts, 拟好 is still first | PASS  |
| keyboard report (B) | fullAccess=true userDataShared=false rimeRunning=true deployStamp=2026-11-25T03:18:43Z-C1FD2C0F staging=set snapshot=none |
| phase B: the keyboard runs with Full Access | PASS  |
| phase B: the live user dictionary is the same private folder as without Full Access | PASS (userDataShared=false) |
| phase B: with Full Access the keyboard reads the app deployments from the App Group | PASS  |
| phase B: oc_core round trip inside the extension | PASS  |
| phase B: librime modules registered (lua, octagram, predict, qjs) | PASS  |
| phase B: Rime data stamp readable and built by the linked librime | PASS  |
| phase B: the extension sees the app probe file (App Group shared) | PASS  |
| phase B: encrypted-file key store readable across processes | PASS  |
| phase B: the user dictionary files are in the keyboard private folder | PASS  |
| snapshot export in the App Group (information) | 0 file(s) |
| Settings UI: Full Access off again | PASS  |
| phase C: Full Access off again, 拟好 is still first | **FAIL** (see ui-fullaccess-off logs and screenshots) |
| phase C: Full Access off and the same private user dictionary folder | **FAIL** (fullAccess=true) |
| memory budget: keyboard footprint after typing <= 55 MB | PASS (measured 54.0 MB, highest of all measurements 56 MB) |
| failed checks | 2 |

- keyboard process footprint (`footprint`, MB): typing **54.0**, learned **56.0**, fullaccess **49.0**, restarted **51.0**
- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/42970DA0-0FD0-4FEC-B1A9-39B434013445/data/Containers/Data/PluginKitPlugin/418C3733-9653-4A94-923C-F0DB73801E9C/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 54.5 MB
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (B): librime `1.17.0`, full access `True`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/42970DA0-0FD0-4FEC-B1A9-39B434013445/data/Containers/Data/PluginKitPlugin/418C3733-9653-4A94-923C-F0DB73801E9C/Library/Application Support/rime-user`), deploy stamp `2026-11-25T03:18:43Z-C1FD2C0F`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 51.5 MB
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
  - biggest dirty categories after typing: MALLOC_SMALL 17 MB dirty, dyld private memory 16 MB dirty, __DATA 7201 KB dirty, __DATA_CONST 6694 KB dirty, CoreAnimation 4960 KB dirty, page table 1654 KB dirty
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `fullaccess-system-learn-3-after-deploy.png`, `fullaccess-system-learned-candidates.png`, `fullaccess-system-restart-1-keyboard.png`, `fullaccess-system-restart-2-candidates.png`, `learn-system-learn-1-before.png`, `learn-system-learn-2-learned.png`, `settings-fullaccess-off-settings-01-launch.png`, `settings-fullaccess-off-settings-02-keyboard-page.png`, `settings-fullaccess-off-settings-03-keyboards-list.png`, `settings-fullaccess-off-settings-04-our-keyboard-page.png`, `settings-fullaccess-off-settings-05-full-access-off.png`, `settings-fullaccess-off-settings-06-full-access-done.png`, `settings-fullaccess-settings-01-launch.png`, `settings-fullaccess-settings-02-keyboard-page.png`, `settings-fullaccess-settings-03-keyboards-list.png`, `settings-fullaccess-settings-04-our-keyboard-page.png`, `settings-fullaccess-settings-05-full-access-alert.png`, `settings-fullaccess-settings-06-full-access-done.png`, `typing-system-1-keyboard.png`, `typing-system-2-nihao.png`, `typing-system-3-sentence.png`, `typing-system-4-committed.png`, `typing-system-5-english.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 77s |
| e2e-run | FAILED (2) | 1632s |


#### e2e-debug (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-typing`: 1 tests, 0 failures

### Simulator end-to-end (Debug, typing)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after typing (Debug, pid 8803) | 55.0 MB |
| no letter fell through to plain text in 中 mode (until typing) | PASS (unhandledLetters=0) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | PASS  |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| memory (Debug, information only) | after typing 55.0 MB, highest 55 MB |
| failed checks | 0 |

- keyboard process footprint (`footprint`, MB): typing **55.0**
- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/10F0E981-53F3-4890-9FAA-B767E653B906/data/Containers/Data/PluginKitPlugin/F93048F3-D2BC-47A5-AE58-E7CBE3F81298/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 54.6 MB
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
  - biggest dirty categories after typing: MALLOC_SMALL 17 MB dirty, dyld private memory 16 MB dirty, __DATA 7201 KB dirty, __DATA_CONST 6614 KB dirty, CoreAnimation 5536 KB dirty, page table 1654 KB dirty
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `typing-system-1-keyboard.png`, `typing-system-2-nihao.png`, `typing-system-3-sentence.png`, `typing-system-4-committed.png`, `typing-system-5-english.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 9s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 57s |
| e2e-run | ok | 577s |


#### ipa-device
```
ipa: OrangeCell-iOS-0.2.15.ipa  32045163 bytes
sha256: 319887dfa852cfe29b03e359ad00f20a30ee9389e5d9aa6e65d856cdbcfcdab5

== Info.plist (app)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell"
  "CFBundleShortVersionString" => "0.2.15"
  "CFBundleVersion" => "15"
  "DTPlatformName" => "iphoneos"
  "DTSDKName" => "iphoneos26.5"
  "MinimumOSVersion" => "17.0"
== Info.plist (keyboard)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell.keyboard"
  "CFBundleShortVersionString" => "0.2.15"
  "CFBundleVersion" => "15"
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
     4655  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/opencc/TWVariantsRev.ocd2
    14362  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/opencc/TSCharactersExt.ocd2
      676  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/opencc/s2t.json
      479  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/opencc/jp2t.json
    13843  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/opencc/CJK_Compatibility_Ideographs.ocd2
     1034  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/opencc/tw2sp.json
      370  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/default.custom.yaml
     2954  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/key_bindings.yaml
      996  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/oc-data.json
     2107  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/punctuation.yaml
        0  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/build/
     8600  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang.schema.yaml
   275236  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
 58714452  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
   175732  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
     4757  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/build/default.yaml
    28356  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/symbols.yaml
     1227  11-25-2026 03:01   Payload/OrangeCell.app/rime-shared/default.yaml
  7202416  11-25-2026 03:01   Payload/OrangeCell.app/OrangeCell
    44536  11-25-2026 03:01   Payload/OrangeCell.app/Assets.car
    10592  11-25-2026 03:01   Payload/OrangeCell.app/AppIcon76x76@2x~ipad.png
     1151  11-25-2026 03:01   Payload/OrangeCell.app/Info.plist
        8  11-25-2026 03:01   Payload/OrangeCell.app/PkgInfo
---------                     -------
 74996669                     111 files
```

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 88s |
| fetch-deps | ok | 5s |
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
| 1-engine-and-session | 23.1 | 22.8 |
| 2-first-sentence-typed | 23.1 | 22.8 |
| 3-committed | 23.1 | 22.8 |
| 4-five-more-phrases | 23.2 | 22.9 |
| 5-stopped | 22.7 | 22.7 |

- minimal modules: engine + dictionary + first sentence cost **0.3 MB** over the baseline
- all modules: engine + dictionary + first sentence cost **0.6 MB** over the baseline

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 87s |
| fetch-deps | ok | 9s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim-release | ok | 73s |
| memory-release-minimal | ok | 109s |
| memory-release-all | ok | 62s |


#### rime-data
- cache hit: true
- compiled with librime 1.17.0, 5 files, 56.4 MiB; dictionary wanxiang v18.1.13
  - 55.99 MiB build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
  - 0.26 MiB build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
  - 0.17 MiB build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
  - 0.01 MiB build/orangecell_wanxiang.schema.yaml
  - 0.00 MiB build/default.yaml
- bundle size:  58M	ios/.rime-data/rime-shared
