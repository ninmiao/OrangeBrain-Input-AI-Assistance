# iOS CI — run 45578377253 (#21) — **failure**

- commit `78376cece2246c179863ee335191a593990a5731` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45578377253

| job | conclusion | duration |
| --- | --- | --- |
| rime-data | success | 1m50s |
| core-linux | success | 1m22s |
| e2e-debug | success | 15m03s |
| e2e-hosts | failure | 16m05s |
| build-test | failure | 13m14s |
| ipa-device | success | 2m23s |
| memory-release | success | 4m29s |
| e2e-ai | failure | 23m37s |
| e2e | failure | 17m54s |
| release | skipped | -1m59s |

**e2e-hosts** failed in step(s): Two hosts and kills (Release)

**build-test** failed in step(s): In-process keyboard UI tests (the real KeyboardView as a text view's input view)

**e2e-ai** failed in step(s): AI end-to-end run (Release)

**e2e** failed in step(s): End-to-end run (Release)

#### build-test (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- app unit tests (OrangeCellTests, simulator): 22 passed, 0 failed, 0 skipped of 22
- OCCore `swift test` on macOS: 112 tests, 0 failures
- UI tests `ui-embedded`: 12 tests, 2 failures
- unit-test observations (OCINFO lines):
  - `appgroup.source` = `nominalNoProfile container=/Users/runner/Library/Developer/CoreSimulator/Devices/E9EFD0AE-50A9-4358-8E9A-1D36A4DE4996/data/Containers/Shared/AppGroup/7CC33FE2-5F96-4797-826C-F166A06AF7BF`
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
  - `r1.contended.startSeconds` = `0.32`
  - `r1.openUserdbFiles.hidden` = `0`
  - `r1.openUserdbFiles.visible` = `4`
  - `test.footprintMB` = `36.8`
  - `woyaochihuoguo.candidates` = `我要吃火锅|我要吃|我要|窝腰|我呀`

Memory with the shipped dictionary (phys_footprint in MB, XCTest process, baseline included):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.7 | 22.7 |
| 1-engine-and-session | 23.3 | 23.0 |
| 2-first-sentence-typed | 23.3 | 23.0 |
| 3-committed | 23.3 | 23.0 |
| 4-five-more-phrases | 23.3 | 23.1 |
| 5-stopped | 22.8 | 22.9 |

- screenshots: `embedded-embedded-dark-1-zh-idle.png`, `embedded-embedded-dark-2-zh-candidates.png`, `embedded-embedded-dark-3-en.png`, `embedded-embedded-dark-4-123.png`, `embedded-embedded-dark-5-symbols.png`, `embedded-embedded-delete-hold.png`, `embedded-embedded-grid-light.png`, `embedded-embedded-landscape-1-zh-candidates.png`, `embedded-embedded-landscape-2-en.png`, `embedded-embedded-light-1-zh-idle.png`, `embedded-embedded-light-2-zh-candidates.png`, `embedded-embedded-light-3-en.png`, `embedded-embedded-light-4-123.png`, `embedded-embedded-light-5-symbols.png`, `embedded-embedded-nihao-light.png`, `embedded-embedded-number-row-light.png`, `embedded-embedded-numbers-light.png`, `embedded-embedded-sentence-light.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 6s |
| fetch-deps | ok | 8s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 0s |
| build-sim | ok | 40s |
| unit-tests | ok | 61s |
| build-ui-tests | ok | 20s |
| uitests-embedded | FAILED (65) | 451s |
| memory-debug-minimal | ok | 66s |
| memory-debug-all | ok | 64s |
| swift-test-macos | ok | 51s |


#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: 89 tests, 0 failures

| step | result | time |
| --- | --- | --- |
| apt | ok | 8s |
| native-core-test | ok | 13s |
| swift-test-linux | ok | 17s |


#### e2e (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-fullaccess-off`: 1 tests, 0 failures
- UI tests `ui-fullaccess`: 1 tests, 1 failures
- UI tests `ui-learn`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess-off`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess`: 1 tests, 0 failures
- UI tests `ui-typing`: 1 tests, 0 failures

### Simulator end-to-end (Release, full)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after typing (Release, pid 8717) | 47.0 MB |
| no letter fell through to plain text in 中 mode (until typing) | PASS (unhandledLetters=0) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | PASS  |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| keyboard start-up after it appeared (A, simulator) | engine ready 45.40908336639404 ms, first candidates 10269.23406124115 ms, user dictionary learning |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| keyboard process footprint after learned (Release, pid 8717) | 48.0 MB |
| no letter fell through to plain text in 中 mode (until learned) | PASS (unhandledLetters=0) |
| phase A: learn 拟好 without Full Access | PASS  |
| Settings UI: Allow Full Access | PASS  |
| keyboard process footprint after fullaccess (Release, pid 22801) | 46.0 MB |
| no letter fell through to plain text in 中 mode (until fullaccess) | PASS (unhandledLetters=0) |
| app deployment while the keyboard runs | PASS (0s) |
| deploy stamp changed | PASS (before: none, after: 2026-11-25T08:59:53Z-F45EB7C4) |
| phase B: with Full Access 拟好 is still first, the app deploys, the keyboard restarts, 拟好 is still first | **FAIL** (see ui-fullaccess logs and screenshots) |
| keyboard report (B) | fullAccess=true userDataShared=false rimeRunning=true deployStamp= staging=set snapshot=none |
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
| phase C: Full Access off again, 拟好 is still first | PASS  |
| phase C: Full Access off and the same private user dictionary folder | PASS (fullAccess=false) |
| memory budget: the highest keyboard footprint of 3 samples <= 55 MB | PASS (highest 48 MB; after typing 47.0 MB) |
| failed checks | 1 |

- keyboard process footprint (`footprint`, MB): typing **47.0**, learned **48.0**, fullaccess **46.0**
- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/09E8D9F3-C561-460D-A352-240D31F97404/data/Containers/Data/PluginKitPlugin/2B69683C-0702-46E3-B70C-58F4DF4EEC06/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 46.7 MB, start-up (after the keyboard appeared) engine ready 45.40908336639404 ms / first candidates 10269.23406124115 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (A2): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/09E8D9F3-C561-460D-A352-240D31F97404/data/Containers/Data/PluginKitPlugin/2B69683C-0702-46E3-B70C-58F4DF4EEC06/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 48 MB, start-up (after the keyboard appeared) engine ready 61.28191947937012 ms / first candidates 8925.681948661804 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (B): librime `1.17.0`, full access `True`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/09E8D9F3-C561-460D-A352-240D31F97404/data/Containers/Data/PluginKitPlugin/2B69683C-0702-46E3-B70C-58F4DF4EEC06/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 46 MB, start-up (after the keyboard appeared) engine ready 41.24093055725098 ms / first candidates 8171.977996826172 ms, user dictionary `learning`, user build `none`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (C): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/09E8D9F3-C561-460D-A352-240D31F97404/data/Containers/Data/PluginKitPlugin/2B69683C-0702-46E3-B70C-58F4DF4EEC06/Library/Application Support/rime-user`), deploy stamp `2026-11-25T08:59:53Z-F45EB7C4`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 47 MB, start-up (after the keyboard appeared) engine ready 44.32106018066406 ms / first candidates 8977.138042449951 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
  - biggest dirty categories after typing: dyld private memory 16 MB dirty, MALLOC_SMALL 13 MB dirty, __DATA 7265 KB dirty, __DATA_CONST 6171 KB dirty, page table 1638 KB dirty, CoreAnimation 1488 KB dirty
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `fullaccess-failure.png`, `fullaccess-off-system-learned-candidates.png`, `fullaccess-system-learn-3-after-deploy.png`, `fullaccess-system-learned-candidates.png`, `learn-system-learn-1-before.png`, `learn-system-learn-2-learned.png`, `settings-fullaccess-off-settings-01-launch.png`, `settings-fullaccess-off-settings-02-keyboard-page.png`, `settings-fullaccess-off-settings-03-keyboards-list.png`, `settings-fullaccess-off-settings-04-our-keyboard-page.png`, `settings-fullaccess-off-settings-05-full-access-off.png`, `settings-fullaccess-off-settings-06-full-access-done.png`, `settings-fullaccess-settings-01-launch.png`, `settings-fullaccess-settings-02-keyboard-page.png`, `settings-fullaccess-settings-03-keyboards-list.png`, `settings-fullaccess-settings-04-our-keyboard-page.png`, `settings-fullaccess-settings-05-full-access-alert.png`, `settings-fullaccess-settings-06-full-access-done.png`, `typing-system-1-keyboard.png`, `typing-system-2-nihao.png`, `typing-system-3-sentence.png`, `typing-system-4-committed.png`, `typing-system-5-english.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 6s |
| fetch-deps | ok | 8s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 0s |
| build-e2e | ok | 48s |
| e2e-run | FAILED (1) | 987s |


#### e2e-ai (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-ai-off`: 1 tests, 0 failures
- UI tests `ui-ai-secure`: 1 tests, 1 failures
- UI tests `ui-ai`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess-off`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess`: 1 tests, 0 failures

### Simulator end-to-end (Release, ai)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| ai: the mock service listens on 127.0.0.1:18765 (no real network, no real key) | PASS  |
| Settings UI: Allow Full Access | PASS  |
| ai: the app wrote the configuration and the loopback routes into the App Group | PASS (/Users/runner/Library/Developer/CoreSimulator/Devices/4A4EAE5B-C0E1-4A36-9885-C6B5557F79D6/data/Containers/Shared/AppGroup/581A3E86-B4B2-4298-8022-3F7DCFF0F1A8) |
| ai: the configuration file holds no key | PASS  |
| keyboard process footprint after ai (Release, pid 18553) | 48.0 MB |
| no letter fell through to plain text in 中 mode (until ai) | PASS (unhandledLetters=0) |
| ai: typo corrected and adopted, assistant then emoji key mid-stream (emoji wins), memory after the requests | PASS  |
| ai (ai): every request carried the stored key in its header | PASS  |
| ai (ai): the key is never inside a request body | PASS  |
| ai (ai): the shared core built bodies the service could read | PASS  |
| ai (ai): typing the pinyin of a typo sent an automatic request (correction + assistant) with that pinyin | PASS  |
| ai (ai): the assistant key and then the emoji key each sent a request, the emoji one last | PASS  |
| ai (ai): the assistant request was dropped by the keyboard when the emoji key took over (the service saw the connection close) | PASS  |
| ai (ai): at least one running request was cancelled by a newer one | PASS  |
| mock service stats | {"requests": 17, "unauthorized": 0, "aborted": 5, "complete": 12} |
| ai: nothing is sent from a password field | **FAIL** (see ui-ai-secure logs and screenshots) |
| ai (secure): every request carried the stored key in its header | PASS  |
| ai (secure): the key is never inside a request body | PASS  |
| ai (secure): the shared core built bodies the service could read | PASS  |
| ai (secure): nothing typed in the password field was sent | PASS  |
| Settings UI: Full Access off again | PASS  |
| ai: without Full Access the AI row shows its hint and the keys do nothing | PASS  |
| ai: no request reached the service without Full Access | PASS (before 17, after 17) |
| memory budget: the highest keyboard footprint of 1 samples <= 55 MB | PASS (highest 48 MB; after typing n/a MB) |
| failed checks | 1 |

- keyboard process footprint (`footprint`, MB): ai **48.0**
- screenshots: `ai-ai-0-idle.png`, `ai-ai-1-correction-streamed.png`, `ai-ai-2-adopted.png`, `ai-ai-3-assistant-streaming.png`, `ai-ai-4-emoji-wins.png`, `ai-ai-5-late-assistant-data-dropped.png`, `ai-ai-6-emoticon-adopted.png`, `ai-off-ai-nofullaccess-1-hint.png`, `ai-off-ai-nofullaccess-2-keys-pressed.png`, `ai-secure-ai-secure-0.png`, `ai-secure-ai-secure-1-typed.png`, `ai-secure-ai-secure-2-keys-pressed.png`, `ai-secure-system-keyboard-not-found.png`, `e2e-00-springboard.png`, `e2e-ai-policy.png`, `e2e-ai-settings.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `settings-fullaccess-off-settings-01-launch.png`, `settings-fullaccess-off-settings-02-keyboard-page.png`, `settings-fullaccess-off-settings-03-keyboards-list.png`, `settings-fullaccess-off-settings-04-our-keyboard-page.png`, `settings-fullaccess-off-settings-05-full-access-off.png`, `settings-fullaccess-off-settings-06-full-access-done.png`, `settings-fullaccess-settings-01-launch.png`, `settings-fullaccess-settings-02-keyboard-page.png`, `settings-fullaccess-settings-03-keyboards-list.png`, `settings-fullaccess-settings-04-our-keyboard-page.png`, `settings-fullaccess-settings-05-full-access-alert.png`, `settings-fullaccess-settings-06-full-access-done.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 35s |
| fetch-deps | ok | 9s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 85s |
| e2e-run | FAILED (1) | 1250s |


#### e2e-debug (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-typing`: 1 tests, 0 failures

### Simulator end-to-end (Debug, typing)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after typing (Debug, pid 11221) | 47.0 MB |
| no letter fell through to plain text in 中 mode (until typing) | PASS (unhandledLetters=0) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | PASS  |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| keyboard start-up after it appeared (A, simulator) | engine ready 151.84307098388672 ms, first candidates 14769.886016845703 ms, user dictionary learning |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| memory (Debug, information only) | after typing 47.0 MB, highest 47 MB |
| failed checks | 0 |

- keyboard process footprint (`footprint`, MB): typing **47.0**
- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/CCC3041C-D3DD-446F-AC5C-AF397918181C/data/Containers/Data/PluginKitPlugin/AC9890A4-8090-4EB8-909A-16A84A820C95/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 47.6 MB, start-up (after the keyboard appeared) engine ready 151.84307098388672 ms / first candidates 14769.886016845703 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
  - biggest dirty categories after typing: dyld private memory 15 MB dirty, MALLOC_SMALL 13 MB dirty, __DATA 7265 KB dirty, __DATA_CONST 6742 KB dirty, page table 1654 KB dirty, CoreAnimation 1504 KB dirty
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `typing-system-1-keyboard.png`, `typing-system-2-nihao.png`, `typing-system-3-sentence.png`, `typing-system-4-committed.png`, `typing-system-5-english.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 70s |
| fetch-deps | ok | 8s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 94s |
| e2e-run | ok | 681s |


#### e2e-hosts (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-hosts`: 1 tests, 1 failures
- UI tests `ui-kill`: 1 tests, 1 failures

### Simulator end-to-end (Release, hosts)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after host2 (Release, pid 9743) | 48.0 MB |
| no letter fell through to plain text in 中 mode (until host2) | PASS (unhandledLetters=0) |
| two host apps take turns typing and learning (one dictionary, both phrases) | **FAIL** (see ui-hosts logs and screenshots) |
| after the two hosts: the user dictionary folder exists with a CURRENT file | PASS (/Users/runner/Library/Developer/CoreSimulator/Devices/DC5CB768-E7C8-430E-9E04-F5EE449AC446/data/Containers/Data/PluginKitPlugin/DF0A171E-AAFF-4CBE-B9D2-23466668E5FF/Library/Application Support/rime-user) |
| after the two hosts: no *.userdb.old (librime did not repair or rename the dictionary) | PASS (0 found) |
| after the two hosts: user dictionary folders | 1 |
| keyboard report (two hosts) | userDictionaryMode=learning unhandledLetters=0 engineReadyMs=56.63800239562988 firstCandidatesMs=1174.862027168274 |
| two hosts: no letter fell through to plain text | PASS (unhandledLetters=0) |
| kill -9 right after a commit (no hide, no deployment): the last word and the earlier one are both learned | **FAIL** (see ui-kill logs and screenshots) |
| after the kill: the user dictionary folder exists with a CURRENT file | PASS (/Users/runner/Library/Developer/CoreSimulator/Devices/DC5CB768-E7C8-430E-9E04-F5EE449AC446/data/Containers/Data/PluginKitPlugin/DF0A171E-AAFF-4CBE-B9D2-23466668E5FF/Library/Application Support/rime-user) |
| after the kill: no *.userdb.old (librime did not repair or rename the dictionary) | PASS (0 found) |
| after the kill: user dictionary folders | 1 |
| memory budget: the highest keyboard footprint of 1 samples <= 55 MB | PASS (highest 48 MB; after typing n/a MB) |
| failed checks | 2 |

- keyboard process footprint (`footprint`, MB): host2 **48.0**
- keyboard report (H): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/DC5CB768-E7C8-430E-9E04-F5EE449AC446/data/Containers/Data/PluginKitPlugin/DF0A171E-AAFF-4CBE-B9D2-23466668E5FF/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 47.8 MB, start-up (after the keyboard appeared) engine ready 56.63800239562988 ms / first candidates 1174.862027168274 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (K): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/DC5CB768-E7C8-430E-9E04-F5EE449AC446/data/Containers/Data/PluginKitPlugin/DF0A171E-AAFF-4CBE-B9D2-23466668E5FF/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 49.5 MB, start-up (after the keyboard appeared) engine ready 71.38001918792725 ms / first candidates 9072.952032089233 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `hosts-failure.png`, `hosts-system-hosts-2-learned.png`, `kill-failure.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 7s |
| fetch-deps | ok | 11s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 2s |
| build-e2e | ok | 96s |
| e2e-run | FAILED (2) | 816s |


#### ipa-device
```
ipa: OrangeCell-iOS-0.2.21.ipa  32674874 bytes
sha256: 7f10f17283bfaf61cea71b94a41e55a3766955dc960429389981bbe2795c706a

== Info.plist (app)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell"
  "CFBundleShortVersionString" => "0.2.21"
  "CFBundleVersion" => "21"
  "DTPlatformName" => "iphoneos"
  "DTSDKName" => "iphoneos26.5"
  "MinimumOSVersion" => "17.0"
== Info.plist (keyboard)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell.keyboard"
  "CFBundleShortVersionString" => "0.2.21"
  "CFBundleVersion" => "21"
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
     4655  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/opencc/TWVariantsRev.ocd2
    14362  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/opencc/TSCharactersExt.ocd2
      676  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/opencc/s2t.json
      479  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/opencc/jp2t.json
    13843  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/opencc/CJK_Compatibility_Ideographs.ocd2
     1034  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/opencc/tw2sp.json
      370  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/default.custom.yaml
     2954  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/key_bindings.yaml
     1439  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/oc-data.json
     2107  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/punctuation.yaml
        0  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/build/
     8600  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang.schema.yaml
   275236  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
 58714452  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
   175732  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
     4757  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/build/default.yaml
    28356  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/symbols.yaml
     1227  11-25-2026 08:44   Payload/OrangeCell.app/rime-shared/default.yaml
  8600464  11-25-2026 08:44   Payload/OrangeCell.app/OrangeCell
    44536  11-25-2026 08:44   Payload/OrangeCell.app/Assets.car
    10592  11-25-2026 08:44   Payload/OrangeCell.app/AppIcon76x76@2x~ipad.png
     1320  11-25-2026 08:44   Payload/OrangeCell.app/Info.plist
        8  11-25-2026 08:44   Payload/OrangeCell.app/PkgInfo
---------                     -------
 77147978                     112 files
```

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 8s |
| fetch-deps | ok | 4s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| build-device | ok | 97s |
| make-ipa | ok | 8s |


#### memory-release (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

Release, simulator, phys_footprint in MB (the XCTest process itself is in the baseline):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.6 | 22.5 |
| 1-engine-and-session | 23.0 | 22.7 |
| 2-first-sentence-typed | 23.0 | 22.7 |
| 3-committed | 23.0 | 22.7 |
| 4-five-more-phrases | 23.0 | 22.8 |
| 5-stopped | 22.7 | 22.6 |

- minimal modules: engine + dictionary + first sentence cost **0.2 MB** over the baseline
- all modules: engine + dictionary + first sentence cost **0.4 MB** over the baseline
- mature user dictionary, `memory.mature.baseline` = `22.7 afterStart=22.7 afterLongInput=22.7 afterGrid=22.7 candidates=30`
- mature user dictionary, `memory.mature.commits` = `3025 userdbBytes=198082`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 8s |
| fetch-deps | ok | 9s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim-release | ok | 81s |
| memory-release-minimal | ok | 75s |
| memory-release-all | ok | 65s |


#### rime-data
- cache hit: true
- compiled with librime 1.17.0, 5 files, 56.4 MiB; dictionary wanxiang v18.1.13
  - 55.99 MiB build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
  - 0.26 MiB build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
  - 0.17 MiB build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
  - 0.01 MiB build/orangecell_wanxiang.schema.yaml
  - 0.00 MiB build/default.yaml
- bundle size:  58M	ios/.rime-data/rime-shared
