# iOS CI — run 45540912605 (#17) — **failure**

- commit `53b5288d63d61547997dd3bc3e8232e88ab790d3` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45540912605

| job | conclusion | duration |
| --- | --- | --- |
| core-linux | success | 1m23s |
| rime-data | success | 0m51s |
| memory-release | success | 4m16s |
| e2e-debug | success | 11m47s |
| build-test | success | 17m52s |
| e2e | failure | 24m02s |
| ipa-device | success | 2m00s |
| e2e-hosts | failure | 19m45s |
| release | skipped | 0m00s |

**e2e** failed in step(s): End-to-end run (Release)

**e2e-hosts** failed in step(s): Two hosts and kills (Release)

#### build-test (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- app unit tests (OrangeCellTests, simulator): 22 passed, 0 failed, 0 skipped of 22
- OCCore `swift test` on macOS: 45 tests, 0 failures
- UI tests `ui-embedded`: 12 tests, 0 failures
- unit-test observations (OCINFO lines):
  - `appgroup.source` = `nominalNoProfile container=/Users/runner/Library/Developer/CoreSimulator/Devices/894724BC-BC82-40A8-ACC2-505AD4EEF5C1/data/Containers/Shared/AppGroup/F496F277-E7CF-417A-9473-7BFC568F9195`
  - `candidates.mingtian` = `明天|命题|明体|名|明|命`
  - `candidates.shijie` = `世界|时节|师姐|视界|食街|石阶`
  - `candidates.women` = `我们|我|握|沃|卧|窝`
  - `candidates.xiexie` = `谢谢|写写|歇歇|写些|斜斜|泄泻`
  - `candidates.zhongguo` = `中国|种过|重过|种果|中过|中果`
  - `comma.handled` = `true commit=， composing=false`
  - `data.builtWithLibrime` = `1.17.0 linked=1.17.0`
  - `f1.slowStart.inserted` = `你好 unhandled=0`
  - `learned.shijie.round1.picked` = `时节 order=时节|世界|师姐|视界`
  - `learned.shijie.round2.picked` = `世界 order=世界|时节|师姐|视界`
  - `learned.woyaochihuoguo.round1.picked` = `? order=火锅我要吃火锅|火锅|活过|火过`
  - `learned.woyaochihuoguo.round2.picked` = `? order=火锅我要吃火锅|火锅|活过|火过`
  - `learned.zhongguo.round1.picked` = `种过 order=种过|中国|重过|种果`
  - `learned.zhongguo.round2.picked` = `中国 order=中国|种过|重过|种果`
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
  - `r1.contended.startSeconds` = `0.33`
  - `r1.openUserdbFiles.hidden` = `0`
  - `r1.openUserdbFiles.visible` = `4`
  - `test.footprintMB` = `38.1`
  - `woyaochihuoguo.candidates` = `我要吃火锅|我要吃|我要|窝腰|我呀`

Memory with the shipped dictionary (phys_footprint in MB, XCTest process, baseline included):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.6 | 22.5 |
| 1-engine-and-session | 23.0 | 22.8 |
| 2-first-sentence-typed | 23.0 | 22.8 |
| 3-committed | 23.0 | 22.8 |
| 4-five-more-phrases | 23.0 | 22.8 |
| 5-stopped | 22.7 | 22.6 |

- screenshots: `embedded-embedded-dark-1-zh-idle.png`, `embedded-embedded-dark-2-zh-candidates.png`, `embedded-embedded-dark-3-en.png`, `embedded-embedded-dark-4-123.png`, `embedded-embedded-dark-5-symbols.png`, `embedded-embedded-delete-hold.png`, `embedded-embedded-english-light.png`, `embedded-embedded-grid-light.png`, `embedded-embedded-landscape-1-zh-candidates.png`, `embedded-embedded-landscape-2-en.png`, `embedded-embedded-light-1-zh-idle.png`, `embedded-embedded-light-2-zh-candidates.png`, `embedded-embedded-light-3-en.png`, `embedded-embedded-light-4-123.png`, `embedded-embedded-light-5-symbols.png`, `embedded-embedded-nihao-light.png`, `embedded-embedded-number-row-light.png`, `embedded-embedded-numbers-light.png`, `embedded-embedded-sentence-light.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 10s |
| fetch-deps | ok | 7s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim | ok | 68s |
| unit-tests | ok | 74s |
| build-ui-tests | ok | 21s |
| uitests-embedded | ok | 614s |
| memory-debug-minimal | ok | 88s |
| memory-debug-all | ok | 96s |
| swift-test-macos | ok | 54s |


#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: 35 tests, 0 failures

| step | result | time |
| --- | --- | --- |
| apt | ok | 12s |
| native-core-test | ok | 16s |
| swift-test-linux | ok | 17s |


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
| keyboard process footprint after typing (Release, pid 9919) | 48.0 MB |
| no letter fell through to plain text in 中 mode (until typing) | PASS (unhandledLetters=0) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | PASS  |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| keyboard start-up after it appeared (A, simulator) | engine ready 110.42702198028564 ms, first candidates 9405.04002571106 ms, user dictionary learning |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| keyboard process footprint after learned (Release, pid 9919) | 48.0 MB |
| no letter fell through to plain text in 中 mode (until learned) | PASS (unhandledLetters=0) |
| phase A: learn 拟好 without Full Access | PASS  |
| Settings UI: Allow Full Access | PASS  |
| keyboard process footprint after fullaccess (Release, pid 25353) | 47.0 MB |
| no letter fell through to plain text in 中 mode (until fullaccess) | PASS (unhandledLetters=0) |
| app deployment while the keyboard runs | PASS (0s) |
| deploy stamp changed | PASS (before: none, after: 2026-11-25T03:52:14Z-12F1E288) |
| kill keyboard process | killed pid 25353 |
| keyboard process footprint after restarted (Release, pid 29455) | 46.0 MB |
| no letter fell through to plain text in 中 mode (until restarted) | PASS (unhandledLetters=0) |
| phase B: with Full Access 拟好 is still first, the app deploys, the keyboard restarts, 拟好 is still first | PASS  |
| keyboard report (B) | fullAccess=true userDataShared=false rimeRunning=true deployStamp=2026-11-25T03:52:14Z-12F1E288 staging=set snapshot=none |
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
| memory budget: the highest keyboard footprint of 4 samples <= 55 MB | PASS (highest 48 MB; after typing 48.0 MB) |
| failed checks | 2 |

- keyboard process footprint (`footprint`, MB): typing **48.0**, learned **48.0**, fullaccess **47.0**, restarted **46.0**
- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/4D1959A6-9562-4C7C-A6D2-832486A8608B/data/Containers/Data/PluginKitPlugin/DFE633C0-44AE-48AC-B3F6-F185CB4BF872/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 47.5 MB, start-up (after the keyboard appeared) engine ready 110.42702198028564 ms / first candidates 9405.04002571106 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (A2): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/4D1959A6-9562-4C7C-A6D2-832486A8608B/data/Containers/Data/PluginKitPlugin/DFE633C0-44AE-48AC-B3F6-F185CB4BF872/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 48.4 MB, start-up (after the keyboard appeared) engine ready 52.0169734954834 ms / first candidates 9211.228966712952 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (B): librime `1.17.0`, full access `True`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/4D1959A6-9562-4C7C-A6D2-832486A8608B/data/Containers/Data/PluginKitPlugin/DFE633C0-44AE-48AC-B3F6-F185CB4BF872/Library/Application Support/rime-user`), deploy stamp `2026-11-25T03:52:14Z-12F1E288`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 46 MB, start-up (after the keyboard appeared) engine ready 78.31895351409912 ms / first candidates 7454.361915588379 ms, user dictionary `learning`, user build `valid`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (C): librime `1.17.0`, full access `True`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/4D1959A6-9562-4C7C-A6D2-832486A8608B/data/Containers/Data/PluginKitPlugin/DFE633C0-44AE-48AC-B3F6-F185CB4BF872/Library/Application Support/rime-user`), deploy stamp `2026-11-25T03:52:14Z-12F1E288`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 46 MB, start-up (after the keyboard appeared) engine ready 78.31895351409912 ms / first candidates 7454.361915588379 ms, user dictionary `learning`, user build `valid`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
  - biggest dirty categories after typing: dyld private memory 16 MB dirty, MALLOC_SMALL 13 MB dirty, __DATA 7185 KB dirty, __DATA_CONST 6710 KB dirty, page table 1638 KB dirty, CoreAnimation 1424 KB dirty
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `fullaccess-off-system-keyboard-not-found.png`, `fullaccess-system-learn-3-after-deploy.png`, `fullaccess-system-learned-candidates.png`, `fullaccess-system-restart-1-keyboard.png`, `fullaccess-system-restart-2-candidates.png`, `learn-system-learn-1-before.png`, `learn-system-learn-2-learned.png`, `settings-fullaccess-off-settings-01-launch.png`, `settings-fullaccess-off-settings-02-keyboard-page.png`, `settings-fullaccess-off-settings-03-keyboards-list.png`, `settings-fullaccess-off-settings-04-our-keyboard-page.png`, `settings-fullaccess-off-settings-05-full-access-off.png`, `settings-fullaccess-off-settings-06-full-access-done.png`, `settings-fullaccess-settings-01-launch.png`, `settings-fullaccess-settings-02-keyboard-page.png`, `settings-fullaccess-settings-03-keyboards-list.png`, `settings-fullaccess-settings-04-our-keyboard-page.png`, `settings-fullaccess-settings-05-full-access-alert.png`, `settings-fullaccess-settings-06-full-access-done.png`, `typing-system-1-keyboard.png`, `typing-system-2-nihao.png`, `typing-system-3-sentence.png`, `typing-system-4-committed.png`, `typing-system-5-english.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 8s |
| fetch-deps | ok | 9s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 0s |
| build-e2e | ok | 53s |
| e2e-run | FAILED (2) | 1333s |


#### e2e-debug (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-typing`: 1 tests, 0 failures

### Simulator end-to-end (Debug, typing)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after typing (Debug, pid 9714) | 47.0 MB |
| no letter fell through to plain text in 中 mode (until typing) | PASS (unhandledLetters=0) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | PASS  |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| keyboard start-up after it appeared (A, simulator) | engine ready 63.519954681396484 ms, first candidates 15678.496956825256 ms, user dictionary learning |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| memory (Debug, information only) | after typing 47.0 MB, highest 47 MB |
| failed checks | 0 |

- keyboard process footprint (`footprint`, MB): typing **47.0**
- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/374C3F0B-A401-4179-AB53-2043DAA272AB/data/Containers/Data/PluginKitPlugin/25C4BF39-42C2-43DA-A243-698748E57F1E/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 47.1 MB, start-up (after the keyboard appeared) engine ready 63.519954681396484 ms / first candidates 15678.496956825256 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
  - biggest dirty categories after typing: dyld private memory 16 MB dirty, MALLOC_SMALL 13 MB dirty, __DATA 7153 KB dirty, __DATA_CONST 6710 KB dirty, page table 1638 KB dirty, CoreAnimation 1424 KB dirty
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `typing-system-1-keyboard.png`, `typing-system-2-nihao.png`, `typing-system-3-sentence.png`, `typing-system-4-committed.png`, `typing-system-5-english.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 9s |
| fetch-deps | ok | 5s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 68s |
| e2e-run | ok | 588s |


#### e2e-hosts (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-hosts`: 1 tests, 1 failures
- UI tests `ui-kill`: 1 tests, 1 failures

### Simulator end-to-end (Release, hosts)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| two host apps take turns typing and learning (one dictionary, both phrases) | **FAIL** (see ui-hosts logs and screenshots) |
| after the two hosts: the user dictionary folder exists with a CURRENT file | PASS (/Users/runner/Library/Developer/CoreSimulator/Devices/F92199FE-EE0C-41CB-BEE5-A31EE01E4E9E/data/Containers/Data/PluginKitPlugin/16242CB5-7456-42B8-9556-4A9B70F00E36/Library/Application Support/rime-user) |
| after the two hosts: no *.userdb.old (librime did not repair or rename the dictionary) | PASS (0 found) |
| after the two hosts: user dictionary folders | 1 |
| keyboard report (two hosts) | userDictionaryMode=learning unhandledLetters=0 engineReadyMs=29.057979583740234 firstCandidatesMs=9224.658966064453 |
| two hosts: no letter fell through to plain text | PASS (unhandledLetters=0) |
| kill -9 right after a commit (no hide, no deployment): the last word and the earlier one are both learned | **FAIL** (see ui-kill logs and screenshots) |
| after the kill: the user dictionary folder exists with a CURRENT file | PASS (/Users/runner/Library/Developer/CoreSimulator/Devices/F92199FE-EE0C-41CB-BEE5-A31EE01E4E9E/data/Containers/Data/PluginKitPlugin/16242CB5-7456-42B8-9556-4A9B70F00E36/Library/Application Support/rime-user) |
| after the kill: no *.userdb.old (librime did not repair or rename the dictionary) | PASS (0 found) |
| after the kill: user dictionary folders | 1 |
| memory budget: the highest keyboard footprint of 0 samples <= 55 MB | **FAIL** (highest 0 MB; after typing n/a MB) |
| failed checks | 3 |

- keyboard report (H): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/F92199FE-EE0C-41CB-BEE5-A31EE01E4E9E/data/Containers/Data/PluginKitPlugin/16242CB5-7456-42B8-9556-4A9B70F00E36/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 49 MB, start-up (after the keyboard appeared) engine ready 29.057979583740234 ms / first candidates 9224.658966064453 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (K): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/F92199FE-EE0C-41CB-BEE5-A31EE01E4E9E/data/Containers/Data/PluginKitPlugin/16242CB5-7456-42B8-9556-4A9B70F00E36/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 50.4 MB, start-up (after the keyboard appeared) engine ready 123.57604503631592 ms / first candidates 11073.986053466797 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `hosts-failure.png`, `kill-failure.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 11s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 90s |
| e2e-run | FAILED (3) | 1020s |


#### ipa-device
```
ipa: OrangeCell-iOS-0.2.17.ipa  32091198 bytes
sha256: de8778ee71d1bc494f936d76346ab9b32c2e021647c92e3471798129335e3b99

== Info.plist (app)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell"
  "CFBundleShortVersionString" => "0.2.17"
  "CFBundleVersion" => "17"
  "DTPlatformName" => "iphoneos"
  "DTSDKName" => "iphoneos26.5"
  "MinimumOSVersion" => "17.0"
== Info.plist (keyboard)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell.keyboard"
  "CFBundleShortVersionString" => "0.2.17"
  "CFBundleVersion" => "17"
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
     4655  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/opencc/TWVariantsRev.ocd2
    14362  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/opencc/TSCharactersExt.ocd2
      676  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/opencc/s2t.json
      479  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/opencc/jp2t.json
    13843  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/opencc/CJK_Compatibility_Ideographs.ocd2
     1034  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/opencc/tw2sp.json
      370  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/default.custom.yaml
     2954  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/key_bindings.yaml
     1439  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/oc-data.json
     2107  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/punctuation.yaml
        0  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/build/
     8600  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang.schema.yaml
   275236  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
 58714452  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
   175732  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
     4757  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/build/default.yaml
    28356  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/symbols.yaml
     1227  11-25-2026 03:41   Payload/OrangeCell.app/rime-shared/default.yaml
  7297136  11-25-2026 03:41   Payload/OrangeCell.app/OrangeCell
    44536  11-25-2026 03:41   Payload/OrangeCell.app/Assets.car
    10592  11-25-2026 03:41   Payload/OrangeCell.app/AppIcon76x76@2x~ipad.png
     1151  11-25-2026 03:41   Payload/OrangeCell.app/Info.plist
        8  11-25-2026 03:41   Payload/OrangeCell.app/PkgInfo
---------                     -------
 75117664                     112 files
```

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 6s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 1s |
| build-device | ok | 71s |
| make-ipa | ok | 8s |


#### memory-release (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

Release, simulator, phys_footprint in MB (the XCTest process itself is in the baseline):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.4 | 22.3 |
| 1-engine-and-session | 23.0 | 22.6 |
| 2-first-sentence-typed | 23.0 | 22.6 |
| 3-committed | 23.0 | 22.6 |
| 4-five-more-phrases | 23.0 | 22.7 |
| 5-stopped | 22.6 | 22.6 |

- minimal modules: engine + dictionary + first sentence cost **0.3 MB** over the baseline
- all modules: engine + dictionary + first sentence cost **0.6 MB** over the baseline
- mature user dictionary, `memory.mature.baseline` = `22.6 afterStart=22.6 afterLongInput=22.6 afterGrid=22.6 candidates=30`
- mature user dictionary, `memory.mature.commits` = `3025 userdbBytes=198082`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 42s |
| fetch-deps | ok | 6s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim-release | ok | 52s |
| memory-release-minimal | ok | 65s |
| memory-release-all | ok | 52s |


#### rime-data
- cache hit: 
- compiled with librime 1.17.0, 5 files, 56.4 MiB; dictionary wanxiang v18.1.13
  - 55.99 MiB build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
  - 0.26 MiB build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
  - 0.17 MiB build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
  - 0.01 MiB build/orangecell_wanxiang.schema.yaml
  - 0.00 MiB build/default.yaml
- bundle size:  26M	ios/.rime-data/rime-shared
