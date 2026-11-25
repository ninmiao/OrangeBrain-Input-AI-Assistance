# iOS CI — run 45462511603 (#9) — **cancelled**

- commit `dacb69efd456d10fc81b95781d9921ec8f2cc194` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45462511603

| job | conclusion | duration |
| --- | --- | --- |
| rime-data | success | 0m49s |
| core-linux | success | 1m29s |
| build-test | cancelled | 9m42s |
| memory-release | success | 4m36s |
| ipa-device | success | 1m44s |
| release | cancelled | -1m59s |

#### build-test (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- app unit tests (OrangeCellTests, simulator): 14 passed, 0 failed, 0 skipped of 14
- OCCore `swift test` on macOS: no result
- UI tests `ui-embedded`: no result
- unit-test observations (OCINFO lines):
  - `appgroup.source` = `nominalNoProfile container=/Users/runner/Library/Developer/CoreSimulator/Devices/F26AACF4-C387-4B58-8EF0-627291B2D8F1/data/Containers/Shared/AppGroup/4565DB44-E92C-44ED-8EBD-5B510EC7A327`
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
  - `oc_core.encode` = `["b": "previous", "i": "nihao"]`
  - `test.footprintMB` = `36.4`
  - `woyaochihuoguo.candidates` = `我要吃火锅|我要吃|我要|窝腰|我呀`
- keyboard extension self-report: NOT FOUND (the extension never wrote one)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 56s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim | ok | 79s |
| unit-tests | ok | 91s |
| build-ui-tests | ok | 16s |


#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: 30 tests, 0 failures

| step | result | time |
| --- | --- | --- |
| apt | ok | 13s |
| native-core-test | ok | 18s |
| swift-test-linux | ok | 17s |


#### ipa-device
```
ipa: OrangeCell-iOS-0.2.9.ipa  31982229 bytes
sha256: 897275fe6340b01b2f541b0c78f7c6f6825b1643c446091ef49a2d85461e599a

== Info.plist (app)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell"
  "CFBundleShortVersionString" => "0.2.9"
  "CFBundleVersion" => "9"
  "DTPlatformName" => "iphoneos"
  "DTSDKName" => "iphoneos26.5"
  "MinimumOSVersion" => "17.0"
== Info.plist (keyboard)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell.keyboard"
  "CFBundleShortVersionString" => "0.2.9"
  "CFBundleVersion" => "9"
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
     4655  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/opencc/TWVariantsRev.ocd2
    14362  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/opencc/TSCharactersExt.ocd2
      676  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/opencc/s2t.json
      479  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/opencc/jp2t.json
    13843  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/opencc/CJK_Compatibility_Ideographs.ocd2
     1034  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/opencc/tw2sp.json
      370  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/default.custom.yaml
     2954  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/key_bindings.yaml
      996  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/oc-data.json
     2107  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/punctuation.yaml
        0  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/build/
     8600  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang.schema.yaml
   275236  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
 58714452  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
   175732  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
     4757  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/build/default.yaml
    28356  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/symbols.yaml
     1227  11-24-2026 18:45   Payload/OrangeCell.app/rime-shared/default.yaml
  7107616  11-24-2026 18:45   Payload/OrangeCell.app/OrangeCell
    64360  11-24-2026 18:45   Payload/OrangeCell.app/Assets.car
    15754  11-24-2026 18:45   Payload/OrangeCell.app/AppIcon76x76@2x~ipad.png
     1149  11-24-2026 18:45   Payload/OrangeCell.app/Info.plist
        8  11-24-2026 18:45   Payload/OrangeCell.app/PkgInfo
---------                     -------
 74771456                     111 files
```

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 8s |
| fetch-deps | ok | 5s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| build-device | ok | 56s |
| make-ipa | ok | 8s |


#### memory-release (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

Release, simulator, phys_footprint in MB (the XCTest process itself is in the baseline):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.6 | 22.5 |
| 1-engine-and-session | 23.1 | 22.7 |
| 2-first-sentence-typed | 23.1 | 22.7 |
| 3-committed | 23.1 | 22.7 |
| 4-five-more-phrases | 23.1 | 22.7 |
| 5-stopped | 22.6 | 22.6 |

- minimal modules: engine + dictionary + first sentence cost **0.2 MB** over the baseline
- all modules: engine + dictionary + first sentence cost **0.5 MB** over the baseline

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 13s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 1s |
| simulator-create | ok | 1s |
| build-sim-release | ok | 67s |
| memory-release-minimal | ok | 91s |
| memory-release-all | ok | 66s |


#### rime-data
- cache hit: 
- compiled with librime 1.17.0, 5 files, 56.4 MiB; dictionary wanxiang v18.1.13
  - 55.99 MiB build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
  - 0.26 MiB build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
  - 0.17 MiB build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
  - 0.01 MiB build/orangecell_wanxiang.schema.yaml
  - 0.00 MiB build/default.yaml
- bundle size:  26M	ios/.rime-data/rime-shared
