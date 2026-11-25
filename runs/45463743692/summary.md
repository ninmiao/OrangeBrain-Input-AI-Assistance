# iOS CI — run 45463743692 (#10) — **failure**

- commit `a514dfa9009446dceb19d0aba07955c0d7c8628b` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45463743692

| job | conclusion | duration |
| --- | --- | --- |
| rime-data | success | 2m04s |
| core-linux | success | 1m17s |
| build-test | failure | 16m17s |
| e2e-debug | failure | 1m30s |
| ipa-device | success | 3m11s |
| e2e | failure | 3m26s |
| memory-release | success | 4m06s |
| release | skipped | 0m00s |

**build-test** failed in step(s): In-process keyboard UI tests (the real KeyboardView as a text view's input view), OCCore swift test (macOS)

**e2e-debug** failed in step(s): Typing run (Debug)

**e2e** failed in step(s): End-to-end run (Release)

#### build-test (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- app unit tests (OrangeCellTests, simulator): 14 passed, 0 failed, 0 skipped of 14
- OCCore `swift test` on macOS: 40 tests, 1 failures
- UI tests `ui-embedded`: 9 tests, 1 failures
- unit-test observations (OCINFO lines):
  - `appgroup.source` = `nominalNoProfile container=/Users/runner/Library/Developer/CoreSimulator/Devices/D5562468-1806-45B6-A21B-C897205B3886/data/Containers/Shared/AppGroup/4A4A574F-CD4C-4D4D-8192-2E26F54AFACC`
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
  - `nihao.candidates` = `你好|你号|拟好|你|泥|拟|腻|逆`
  - `nihao.preedit` = `ni hao`
  - `oc_core.encode` = `["i": "nihao", "b": "previous"]`
  - `test.footprintMB` = `36.4`
  - `woyaochihuoguo.candidates` = `我要吃火锅|我要吃|我要|窝腰|我呀`

Memory with the shipped dictionary (phys_footprint in MB, XCTest process, baseline included):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.4 | 22.4 |
| 1-engine-and-session | 23.0 | 22.7 |
| 2-first-sentence-typed | 23.0 | 22.7 |
| 3-committed | 23.0 | 22.7 |
| 4-five-more-phrases | 23.0 | 22.7 |
| 5-stopped | 22.6 | 22.5 |

- screenshots: `embedded-embedded-dark-1-zh-idle.png`, `embedded-embedded-dark-2-zh-candidates.png`, `embedded-embedded-dark-3-en.png`, `embedded-embedded-dark-4-123.png`, `embedded-embedded-dark-5-symbols.png`, `embedded-embedded-delete-hold.png`, `embedded-embedded-english-light.png`, `embedded-embedded-light-1-zh-idle.png`, `embedded-embedded-light-2-zh-candidates.png`, `embedded-embedded-light-3-en.png`, `embedded-embedded-light-4-123.png`, `embedded-embedded-light-5-symbols.png`, `embedded-embedded-numbers-light.png`, `embedded-embedded-sentence-light.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 9s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 2s |
| build-sim | ok | 60s |
| unit-tests | ok | 70s |
| build-ui-tests | ok | 20s |
| uitests-embedded | FAILED (65) | 575s |
| memory-debug-minimal | ok | 72s |
| memory-debug-all | ok | 77s |
| swift-test-macos | FAILED (1) | 52s |


#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: 30 tests, 0 failures

| step | result | time |
| --- | --- | --- |
| apt | ok | 8s |
| native-core-test | ok | 12s |
| swift-test-linux | ok | 10s |


#### e2e (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

### Simulator end-to-end (Release, full)

| step | result |
| --- | --- |
| products | missing OrangeCell.app or OCTestHost.app in /Users/runner/work/OrangeBrain-Input-AI-Assistance/OrangeBrain-Input-AI-Assistance/build/dd/Build/Products/Release-iphonesimulator |


| step | result | time |
| --- | --- | --- |
| toolchain | ok | 112s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 1s |
| simulator-create | ok | 1s |
| build-e2e | ok | 54s |
| e2e-run | FAILED (2) | 0s |


#### e2e-debug (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

### Simulator end-to-end (Debug, typing)

| step | result |
| --- | --- |
| products | missing OrangeCell.app or OCTestHost.app in /Users/runner/work/OrangeBrain-Input-AI-Assistance/OrangeBrain-Input-AI-Assistance/build/dd/Build/Products/Debug-iphonesimulator |


| step | result | time |
| --- | --- | --- |
| toolchain | ok | 12s |
| fetch-deps | ok | 9s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 42s |
| e2e-run | FAILED (2) | 0s |


#### ipa-device
```
ipa: OrangeCell-iOS-0.2.10.ipa  31981983 bytes
sha256: 767dd0e5eefdea2b48f04af54c1ca993375e98fd737089e20b5e90b74f7495eb

== Info.plist (app)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell"
  "CFBundleShortVersionString" => "0.2.10"
  "CFBundleVersion" => "10"
  "DTPlatformName" => "iphoneos"
  "DTSDKName" => "iphoneos26.5"
  "MinimumOSVersion" => "17.0"
== Info.plist (keyboard)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell.keyboard"
  "CFBundleShortVersionString" => "0.2.10"
  "CFBundleVersion" => "10"
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
     4655  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/opencc/TWVariantsRev.ocd2
    14362  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/opencc/TSCharactersExt.ocd2
      676  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/opencc/s2t.json
      479  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/opencc/jp2t.json
    13843  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/opencc/CJK_Compatibility_Ideographs.ocd2
     1034  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/opencc/tw2sp.json
      370  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/default.custom.yaml
     2954  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/key_bindings.yaml
      996  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/oc-data.json
     2107  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/punctuation.yaml
        0  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/build/
     8600  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang.schema.yaml
   275236  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
 58714452  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
   175732  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
     4757  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/build/default.yaml
    28356  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/symbols.yaml
     1227  11-24-2026 18:59   Payload/OrangeCell.app/rime-shared/default.yaml
  7108336  11-24-2026 18:59   Payload/OrangeCell.app/OrangeCell
    64360  11-24-2026 18:59   Payload/OrangeCell.app/Assets.car
    15754  11-24-2026 18:59   Payload/OrangeCell.app/AppIcon76x76@2x~ipad.png
     1151  11-24-2026 18:59   Payload/OrangeCell.app/Info.plist
        8  11-24-2026 18:59   Payload/OrangeCell.app/PkgInfo
---------                     -------
 74772804                     111 files
```

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 64s |
| fetch-deps | ok | 4s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| build-device | ok | 79s |
| make-ipa | ok | 12s |


#### memory-release (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

Release, simulator, phys_footprint in MB (the XCTest process itself is in the baseline):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.4 | 22.5 |
| 1-engine-and-session | 23.0 | 22.8 |
| 2-first-sentence-typed | 23.0 | 22.8 |
| 3-committed | 23.0 | 22.8 |
| 4-five-more-phrases | 23.0 | 22.8 |
| 5-stopped | 22.6 | 22.6 |

- minimal modules: engine + dictionary + first sentence cost **0.3 MB** over the baseline
- all modules: engine + dictionary + first sentence cost **0.6 MB** over the baseline

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 10s |
| fetch-deps | ok | 12s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 2s |
| build-sim-release | ok | 69s |
| memory-release-minimal | ok | 73s |
| memory-release-all | ok | 53s |


#### rime-data
- cache hit: true
- compiled with librime 1.17.0, 5 files, 56.4 MiB; dictionary wanxiang v18.1.13
  - 55.99 MiB build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
  - 0.26 MiB build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
  - 0.17 MiB build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
  - 0.01 MiB build/orangecell_wanxiang.schema.yaml
  - 0.00 MiB build/default.yaml
- bundle size:  58M	ios/.rime-data/rime-shared
