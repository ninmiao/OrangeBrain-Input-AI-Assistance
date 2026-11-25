# iOS CI — run 45583164951 (#22) — **failure**

- commit `719e6a65f7811048fac92f05a662d7e823be6954` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45583164951

| job | conclusion | duration |
| --- | --- | --- |
| core-linux | success | 1m23s |
| rime-data | success | 1m17s |
| e2e-hosts | success | 19m54s |
| build-test | failure | 19m56s |
| memory-release | success | 7m42s |
| ipa-device | success | 2m32s |
| e2e-ai | success | 19m52s |
| e2e | success | 30m50s |
| e2e-debug | success | 13m31s |
| release | skipped | 0m00s |

**build-test** failed in step(s): In-process keyboard UI tests (the real KeyboardView as a text view's input view)

#### build-test (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- app unit tests (OrangeCellTests, simulator): 22 passed, 0 failed, 0 skipped of 22
- OCCore `swift test` on macOS: 112 tests, 0 failures
- UI tests `ui-embedded`: 12 tests, 1 failures
- unit-test observations (OCINFO lines):
  - `appgroup.source` = `nominalNoProfile container=/Users/runner/Library/Developer/CoreSimulator/Devices/C7A5BF9D-383F-4D00-AD82-5832F114C49A/data/Containers/Shared/AppGroup/823CC1FF-F808-4CAB-8AC3-A829F5988EC7`
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
  - `oc_core.encode` = `["i": "nihao", "b": "previous"]`
  - `r1.contended.startSeconds` = `0.36`
  - `r1.openUserdbFiles.hidden` = `0`
  - `r1.openUserdbFiles.visible` = `4`
  - `test.footprintMB` = `36.9`
  - `woyaochihuoguo.candidates` = `我要吃火锅|我要吃|我要|窝腰|我呀`

Memory with the shipped dictionary (phys_footprint in MB, XCTest process, baseline included):

| stage | all | minimal |
| --- | --- | --- |
| 0-baseline | 22.6 | 22.5 |
| 1-engine-and-session | 23.2 | 22.8 |
| 2-first-sentence-typed | 23.2 | 22.8 |
| 3-committed | 23.2 | 22.8 |
| 4-five-more-phrases | 23.2 | 22.8 |
| 5-stopped | 22.8 | 22.6 |

- screenshots: `embedded-embedded-dark-1-zh-idle.png`, `embedded-embedded-dark-2-zh-candidates.png`, `embedded-embedded-dark-3-en.png`, `embedded-embedded-dark-4-123.png`, `embedded-embedded-dark-5-symbols.png`, `embedded-embedded-delete-hold.png`, `embedded-embedded-english-light.png`, `embedded-embedded-grid-light.png`, `embedded-embedded-landscape-1-zh-candidates.png`, `embedded-embedded-landscape-2-en.png`, `embedded-embedded-light-1-zh-idle.png`, `embedded-embedded-light-2-zh-candidates.png`, `embedded-embedded-light-3-en.png`, `embedded-embedded-light-4-123.png`, `embedded-embedded-light-5-symbols.png`, `embedded-embedded-nihao-light.png`, `embedded-embedded-number-row-light.png`, `embedded-embedded-numbers-light.png`, `embedded-embedded-sentence-light.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 12s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim | ok | 80s |
| unit-tests | ok | 114s |
| build-ui-tests | ok | 30s |
| uitests-embedded | FAILED (65) | 650s |
| memory-debug-minimal | ok | 89s |
| memory-debug-all | ok | 95s |
| swift-test-macos | ok | 65s |


#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: 89 tests, 0 failures

| step | result | time |
| --- | --- | --- |
| apt | ok | 9s |
| native-core-test | ok | 13s |
| swift-test-linux | ok | 17s |


#### e2e (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-fullaccess-off`: 1 tests, 0 failures
- UI tests `ui-fullaccess`: 1 tests, 0 failures
- UI tests `ui-learn`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess-off`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess`: 1 tests, 0 failures
- UI tests `ui-typing`: 1 tests, 0 failures

### Simulator end-to-end (Release, full)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after typing (Release, pid 12631) | 47.0 MB |
| no letter fell through to plain text in 中 mode (until typing) | PASS (unhandledLetters=0) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | PASS  |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| keyboard start-up after it appeared (A, simulator) | engine ready 78.8499116897583 ms, first candidates 9552.85096168518 ms, user dictionary learning |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| keyboard process footprint after learned (Release, pid 12631) | 49.0 MB |
| no letter fell through to plain text in 中 mode (until learned) | PASS (unhandledLetters=0) |
| phase A: learn 拟好 without Full Access | PASS  |
| Settings UI: Allow Full Access | PASS  |
| keyboard process footprint after fullaccess (Release, pid 28653) | 47.0 MB |
| no letter fell through to plain text in 中 mode (until fullaccess) | PASS (unhandledLetters=0) |
| app deployment while the keyboard runs | PASS (0s) |
| deploy stamp changed | PASS (before: none, after: 2026-11-25T09:36:37Z-5122E642) |
| kill keyboard process | killed pid 32250 |
| keyboard process footprint after restarted (Release, pid 33608) | 46.0 MB |
| no letter fell through to plain text in 中 mode (until restarted) | PASS (unhandledLetters=0) |
| phase B: with Full Access 拟好 is still first, the app deploys, the keyboard restarts, 拟好 is still first | PASS  |
| keyboard report (B) | fullAccess=true userDataShared=false rimeRunning=true deployStamp=2026-11-25T09:36:37Z-5122E642 staging=set snapshot=none |
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
| memory budget: the highest keyboard footprint of 4 samples <= 55 MB | PASS (highest 49 MB; after typing 47.0 MB) |
| failed checks | 0 |

- keyboard process footprint (`footprint`, MB): typing **47.0**, learned **49.0**, fullaccess **47.0**, restarted **46.0**
- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/08F4131A-52DD-444E-B76D-FB1D940176D8/data/Containers/Data/PluginKitPlugin/8814979C-EE76-4C86-B9B1-591AC518240F/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 47.5 MB, start-up (after the keyboard appeared) engine ready 78.8499116897583 ms / first candidates 9552.85096168518 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (A2): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/08F4131A-52DD-444E-B76D-FB1D940176D8/data/Containers/Data/PluginKitPlugin/8814979C-EE76-4C86-B9B1-591AC518240F/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 48.6 MB, start-up (after the keyboard appeared) engine ready 61.135053634643555 ms / first candidates 8904.742956161499 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (B): librime `1.17.0`, full access `True`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/08F4131A-52DD-444E-B76D-FB1D940176D8/data/Containers/Data/PluginKitPlugin/8814979C-EE76-4C86-B9B1-591AC518240F/Library/Application Support/rime-user`), deploy stamp `2026-11-25T09:36:37Z-5122E642`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 46 MB, start-up (after the keyboard appeared) engine ready 82.24403858184814 ms / first candidates 6595.820069313049 ms, user dictionary `learning`, user build `valid`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (C): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/08F4131A-52DD-444E-B76D-FB1D940176D8/data/Containers/Data/PluginKitPlugin/8814979C-EE76-4C86-B9B1-591AC518240F/Library/Application Support/rime-user`), deploy stamp `2026-11-25T09:36:37Z-5122E642`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 45.4 MB, start-up (after the keyboard appeared) engine ready 99.46191310882568 ms / first candidates 8662.9159450531 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
  - biggest dirty categories after typing: dyld private memory 16 MB dirty, MALLOC_SMALL 13 MB dirty, __DATA 7281 KB dirty, __DATA_CONST 6726 KB dirty, page table 1638 KB dirty, CoreAnimation 1504 KB dirty
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `fullaccess-off-system-learned-candidates.png`, `fullaccess-system-learn-3-after-deploy.png`, `fullaccess-system-learned-candidates.png`, `fullaccess-system-restart-1-keyboard.png`, `fullaccess-system-restart-2-candidates.png`, `learn-system-learn-1-before.png`, `learn-system-learn-2-learned.png`, `settings-fullaccess-off-settings-01-launch.png`, `settings-fullaccess-off-settings-02-keyboard-page.png`, `settings-fullaccess-off-settings-03-keyboards-list.png`, `settings-fullaccess-off-settings-04-our-keyboard-page.png`, `settings-fullaccess-off-settings-05-full-access-off.png`, `settings-fullaccess-off-settings-06-full-access-done.png`, `settings-fullaccess-settings-01-launch.png`, `settings-fullaccess-settings-02-keyboard-page.png`, `settings-fullaccess-settings-03-keyboards-list.png`, `settings-fullaccess-settings-04-our-keyboard-page.png`, `settings-fullaccess-settings-05-full-access-alert.png`, `settings-fullaccess-settings-06-full-access-done.png`, `typing-system-1-keyboard.png`, `typing-system-2-nihao.png`, `typing-system-3-sentence.png`, `typing-system-4-committed.png`, `typing-system-5-english.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 105s |
| fetch-deps | ok | 6s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 2s |
| build-e2e | ok | 115s |
| e2e-run | ok | 1561s |


#### e2e-ai (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-ai-off`: 1 tests, 0 failures
- UI tests `ui-ai-secure`: 1 tests, 0 failures
- UI tests `ui-ai`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess-off`: 1 tests, 0 failures
- UI tests `ui-settings-fullaccess`: 1 tests, 0 failures

### Simulator end-to-end (Release, ai)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| ai: the mock service listens on 127.0.0.1:18765 (no real network, no real key) | PASS  |
| Settings UI: Allow Full Access | PASS  |
| ai: the app wrote the configuration and the loopback routes into the App Group | PASS (/Users/runner/Library/Developer/CoreSimulator/Devices/6E202963-822D-4F76-A620-1A96503F3D12/data/Containers/Shared/AppGroup/E7E9F944-F1A4-4C1E-A20E-6A6A0DA98133) |
| ai: the configuration file holds no key | PASS  |
| keyboard process footprint after ai (Release, pid 14907) | 48.0 MB |
| no letter fell through to plain text in 中 mode (until ai) | PASS (unhandledLetters=0) |
| ai: typo corrected and adopted, assistant then emoji key mid-stream (emoji wins), memory after the requests | PASS  |
| ai (ai): every request carried the stored key in its header | PASS  |
| ai (ai): the key is never inside a request body | PASS  |
| ai (ai): the shared core built bodies the service could read | PASS  |
| ai (ai): typing the pinyin of a typo sent an automatic request (correction + assistant) with that pinyin | PASS  |
| ai (ai): the assistant key and then the emoji key each sent a request, the emoji one last | PASS  |
| ai (ai): the assistant request was dropped by the keyboard when the emoji key took over (the service saw the connection close) | PASS  |
| ai (ai): at least one running request was cancelled by a newer one | PASS  |
| mock service stats | {"requests": 17, "unauthorized": 0, "aborted": 4, "complete": 13} |
| keyboard process footprint after ai-secure (Release, pid 14907) | 48.0 MB |
| no letter fell through to plain text in 中 mode (until ai-secure) | PASS (unhandledLetters=0) |
| ai: nothing is sent from a password field | PASS  |
| ai (secure): every request carried the stored key in its header | PASS  |
| ai (secure): the key is never inside a request body | PASS  |
| ai (secure): the shared core built bodies the service could read | PASS  |
| ai (secure): nothing typed in the password field was sent | PASS  |
| Settings UI: Full Access off again | PASS  |
| ai: without Full Access the AI row shows its hint and the keys do nothing | PASS  |
| ai: no request reached the service without Full Access | PASS (before 17, after 17) |
| memory budget: the highest keyboard footprint of 2 samples <= 55 MB | PASS (highest 48 MB; after typing n/a MB) |
| failed checks | 0 |

- keyboard process footprint (`footprint`, MB): ai **48.0**, ai-secure **48.0**
- screenshots: `ai-ai-0-idle.png`, `ai-ai-1-correction-streamed.png`, `ai-ai-2-adopted.png`, `ai-ai-3-assistant-streaming.png`, `ai-ai-4-emoji-wins.png`, `ai-ai-5-late-assistant-data-dropped.png`, `ai-ai-6-emoticon-adopted.png`, `ai-off-ai-nofullaccess-1-hint.png`, `ai-off-ai-nofullaccess-2-keys-pressed.png`, `ai-secure-ai-secure-0.png`, `ai-secure-ai-secure-1-typed.png`, `ai-secure-ai-secure-2-keys-pressed.png`, `ai-secure-system-keyboard-not-found.png`, `e2e-00-springboard.png`, `e2e-ai-policy.png`, `e2e-ai-settings.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `settings-fullaccess-off-settings-01-launch.png`, `settings-fullaccess-off-settings-02-keyboard-page.png`, `settings-fullaccess-off-settings-03-keyboards-list.png`, `settings-fullaccess-off-settings-04-our-keyboard-page.png`, `settings-fullaccess-off-settings-05-full-access-off.png`, `settings-fullaccess-off-settings-06-full-access-done.png`, `settings-fullaccess-settings-01-launch.png`, `settings-fullaccess-settings-02-keyboard-page.png`, `settings-fullaccess-settings-03-keyboards-list.png`, `settings-fullaccess-settings-04-our-keyboard-page.png`, `settings-fullaccess-settings-05-full-access-alert.png`, `settings-fullaccess-settings-06-full-access-done.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 7s |
| fetch-deps | ok | 9s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 0s |
| build-e2e | ok | 58s |
| e2e-run | ok | 1062s |


#### e2e-debug (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-typing`: 1 tests, 0 failures

### Simulator end-to-end (Debug, typing)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after typing (Debug, pid 9229) | 47.0 MB |
| no letter fell through to plain text in 中 mode (until typing) | PASS (unhandledLetters=0) |
| phase A: typing through the real keyboard extension (nihao, sentence, backspace, 中/EN) | PASS  |
| keyboard report (A) | fullAccess=false userDataShared=false rimeRunning=true dictionary=wanxiang v18.1.13 |
| keyboard start-up after it appeared (A, simulator) | engine ready 236.05608940124512 ms, first candidates 10127.532005310059 ms, user dictionary learning |
| phase A: engine running inside the extension | PASS  |
| phase A: without Full Access the user dictionary is private | PASS (userDataShared=false) |
| memory (Debug, information only) | after typing 47.0 MB, highest 47 MB |
| failed checks | 0 |

- keyboard process footprint (`footprint`, MB): typing **47.0**
- keyboard report (A): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/03E63172-8935-4363-A330-544F1F015D3B/data/Containers/Data/PluginKitPlugin/7E3ED900-C3DA-4833-B0D0-D0118D59C303/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 47.5 MB, start-up (after the keyboard appeared) engine ready 236.05608940124512 ms / first candidates 10127.532005310059 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
  - biggest dirty categories after typing: dyld private memory 16 MB dirty, MALLOC_SMALL 13 MB dirty, __DATA 7249 KB dirty, __DATA_CONST 6694 KB dirty, page table 1654 KB dirty, CoreAnimation 1504 KB dirty
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `typing-system-1-keyboard.png`, `typing-system-2-nihao.png`, `typing-system-3-sentence.png`, `typing-system-4-committed.png`, `typing-system-5-english.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 12s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | ok | 91s |
| e2e-run | ok | 644s |


#### e2e-hosts (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- UI tests `ui-hosts`: 1 tests, 0 failures
- UI tests `ui-kill`: 1 tests, 0 failures

### Simulator end-to-end (Release, hosts)

| step | result |
| --- | --- |
| install | ok (app with keyboard extension, test host) |
| keyboard process footprint after host2 (Release, pid 13341) | 49.0 MB |
| no letter fell through to plain text in 中 mode (until host2) | PASS (unhandledLetters=0) |
| keyboard process footprint after hosts-done (Release, pid 17985) | 48.0 MB |
| no letter fell through to plain text in 中 mode (until hosts-done) | PASS (unhandledLetters=0) |
| two host apps take turns typing and learning (one dictionary, both phrases) | PASS  |
| after the two hosts: the user dictionary folder exists with a CURRENT file | PASS (/Users/runner/Library/Developer/CoreSimulator/Devices/C5C05989-4E86-4560-9790-14EE9B36CB24/data/Containers/Data/PluginKitPlugin/F2B666E7-6F70-4EC6-AF48-D2ACB79002A4/Library/Application Support/rime-user) |
| after the two hosts: no *.userdb.old (librime did not repair or rename the dictionary) | PASS (0 found) |
| after the two hosts: user dictionary folders | 1 |
| keyboard report (two hosts) | userDictionaryMode=learning unhandledLetters=0 engineReadyMs=248.87502193450928 firstCandidatesMs=2827.517032623291 |
| two hosts: no letter fell through to plain text | PASS (unhandledLetters=0) |
| kill keyboard process | killed pid 17985 |
| kill -9 right after a commit (no hide, no deployment): the last word and the earlier one are both learned | PASS  |
| after the kill: the user dictionary folder exists with a CURRENT file | PASS (/Users/runner/Library/Developer/CoreSimulator/Devices/C5C05989-4E86-4560-9790-14EE9B36CB24/data/Containers/Data/PluginKitPlugin/F2B666E7-6F70-4EC6-AF48-D2ACB79002A4/Library/Application Support/rime-user) |
| after the kill: no *.userdb.old (librime did not repair or rename the dictionary) | PASS (0 found) |
| after the kill: user dictionary folders | 1 |
| memory budget: the highest keyboard footprint of 2 samples <= 55 MB | PASS (highest 49 MB; after typing n/a MB) |
| failed checks | 0 |

- keyboard process footprint (`footprint`, MB): host2 **49.0**, hosts-done **48.0**
- keyboard report (H): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/C5C05989-4E86-4560-9790-14EE9B36CB24/data/Containers/Data/PluginKitPlugin/F2B666E7-6F70-4EC6-AF48-D2ACB79002A4/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 47.8 MB, start-up (after the keyboard appeared) engine ready 248.87502193450928 ms / first candidates 2827.517032623291 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- keyboard report (K): librime `1.17.0`, full access `False`, engine running `True`, user dictionary shared `False` (`/Users/runner/Library/Developer/CoreSimulator/Devices/C5C05989-4E86-4560-9790-14EE9B36CB24/data/Containers/Data/PluginKitPlugin/F2B666E7-6F70-4EC6-AF48-D2ACB79002A4/Library/Application Support/rime-user`), deploy stamp `None`, data `wanxiang v18.1.13` / schema `orangecell_wanxiang`, in-process phys_footprint 46.7 MB, start-up (after the keyboard appeared) engine ready 52.204012870788574 ms / first candidates 7481.536030769348 ms, user dictionary `learning`, user build `None`, letters through to plain text 0
  - key storage `keychain-default`: cross-process read `False` sample not found
  - key storage `encrypted-file`: cross-process read `True` 
- screenshots: `e2e-00-springboard.png`, `e2e-app-diagnostics.png`, `e2e-app-home.png`, `e2e-app-licenses.png`, `hosts-system-hosts-1-back.png`, `hosts-system-hosts-2-learned.png`, `kill-system-kill-1-last-word.png`, `kill-system-kill-2-earlier-word.png`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 66s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 2s |
| build-e2e | ok | 95s |
| e2e-run | ok | 962s |


#### ipa-device
```
ipa: OrangeCell-iOS-0.2.22.ipa  32674870 bytes
sha256: 67b85ad1122627e44d57f858bba5775e9305fc410a7d644476b14c7998912917

== Info.plist (app)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell"
  "CFBundleShortVersionString" => "0.2.22"
  "CFBundleVersion" => "22"
  "DTPlatformName" => "iphoneos"
  "DTSDKName" => "iphoneos26.5"
  "MinimumOSVersion" => "17.0"
== Info.plist (keyboard)
  "CFBundleDisplayName" => "橘脑一颗"
  "CFBundleIdentifier" => "io.github.ninmiao.orangecell.keyboard"
  "CFBundleShortVersionString" => "0.2.22"
  "CFBundleVersion" => "22"
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
     4655  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/opencc/TWVariantsRev.ocd2
    14362  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/opencc/TSCharactersExt.ocd2
      676  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/opencc/s2t.json
      479  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/opencc/jp2t.json
    13843  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/opencc/CJK_Compatibility_Ideographs.ocd2
     1034  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/opencc/tw2sp.json
      370  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/default.custom.yaml
     2954  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/key_bindings.yaml
     1439  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/oc-data.json
     2107  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/punctuation.yaml
        0  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/build/
     8600  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang.schema.yaml
   275236  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
 58714452  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
   175732  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
     4757  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/build/default.yaml
    28356  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/symbols.yaml
     1227  11-25-2026 09:15   Payload/OrangeCell.app/rime-shared/default.yaml
  8600464  11-25-2026 09:15   Payload/OrangeCell.app/OrangeCell
    44536  11-25-2026 09:15   Payload/OrangeCell.app/Assets.car
    10592  11-25-2026 09:15   Payload/OrangeCell.app/AppIcon76x76@2x~ipad.png
     1320  11-25-2026 09:15   Payload/OrangeCell.app/Info.plist
        8  11-25-2026 09:15   Payload/OrangeCell.app/PkgInfo
---------                     -------
 77147978                     112 files
```

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 12s |
| fetch-deps | ok | 6s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| build-device | ok | 89s |
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
| 4-five-more-phrases | 23.1 | 22.9 |
| 5-stopped | 22.7 | 22.7 |

- minimal modules: engine + dictionary + first sentence cost **0.3 MB** over the baseline
- all modules: engine + dictionary + first sentence cost **0.6 MB** over the baseline
- mature user dictionary, `memory.mature.baseline` = `22.7 afterStart=22.7 afterLongInput=22.7 afterGrid=22.7 candidates=30`
- mature user dictionary, `memory.mature.commits` = `3025 userdbBytes=198082`

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 96s |
| fetch-deps | ok | 8s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim-release | ok | 96s |
| memory-release-minimal | ok | 138s |
| memory-release-all | ok | 87s |


#### rime-data
- cache hit: true
- compiled with librime 1.17.0, 5 files, 56.4 MiB; dictionary wanxiang v18.1.13
  - 55.99 MiB build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
  - 0.26 MiB build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
  - 0.17 MiB build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
  - 0.01 MiB build/orangecell_wanxiang.schema.yaml
  - 0.00 MiB build/default.yaml
- bundle size:  58M	ios/.rime-data/rime-shared
