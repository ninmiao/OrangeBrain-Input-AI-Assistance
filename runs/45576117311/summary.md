# iOS CI — run 45576117311 (#20) — **failure**

- commit `fb181ed6bfb9a885f1eee53dcc687e44aa417bf2` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45576117311

| job | conclusion | duration |
| --- | --- | --- |
| rime-data | success | 0m46s |
| core-linux | success | 1m23s |
| e2e-debug | failure | 1m35s |
| e2e | failure | 3m08s |
| build-test | failure | 9m57s |
| e2e-hosts | failure | 3m16s |
| e2e-ai | failure | 1m37s |
| memory-release | failure | 5m02s |
| ipa-device | failure | 2m03s |
| release | skipped | -1m59s |

**e2e-debug** failed in step(s): Build the app, the keyboard and the UI tests (Debug)

**e2e** failed in step(s): Build the app, the keyboard and the UI tests (Release)

**build-test** failed in step(s): Build for the simulator (Debug), Check that the unit-tests tests really ran, In-process keyboard UI tests (the real KeyboardView as a text view's input view), Memory with the shipped dictionary (Debug, minimal modules), Check that the memory-debug-minimal tests really ran, Memory with the shipped dictionary (Debug, all modules), Check that the memory-debug-all tests really ran

**e2e-hosts** failed in step(s): Build the app, the keyboard and the UI tests (Release)

**e2e-ai** failed in step(s): Build the app, the keyboard and the UI tests (Release)

**memory-release** failed in step(s): Build for the simulator (Release), Check that the memory-release-minimal tests really ran, Memory with the shipped dictionary (Release, all modules), Check that the memory-release-all tests really ran

**ipa-device** failed in step(s): Build for device (unsigned)

#### build-test (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- app unit tests (OrangeCellTests, simulator): no result
- OCCore `swift test` on macOS: 112 tests, 0 failures
- UI tests `ui-embedded`: no result

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 12s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim | FAILED (65) | 58s |
| uitests-embedded | FAILED (65) | 23s |
| memory-debug-minimal | FAILED (65) | 245s |
| memory-debug-all | FAILED (65) | 146s |
| swift-test-macos | ok | 70s |


#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: 89 tests, 0 failures

| step | result | time |
| --- | --- | --- |
| apt | ok | 10s |
| native-core-test | ok | 12s |
| swift-test-linux | ok | 17s |


#### e2e (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 41s |
| fetch-deps | ok | 12s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | FAILED (65) | 96s |


#### e2e-ai (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 9s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 0s |
| build-e2e | FAILED (65) | 59s |


#### e2e-debug (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 10s |
| fetch-deps | ok | 7s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | FAILED (65) | 55s |


#### e2e-hosts (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 84s |
| fetch-deps | ok | 8s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 2s |
| build-e2e | FAILED (65) | 78s |


#### ipa-device

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 12s |
| fetch-deps | ok | 4s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| build-device | FAILED (65) | 80s |


#### memory-release (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 62s |
| fetch-deps | ok | 8s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim-release | FAILED (65) | 47s |
| memory-release-all | FAILED (65) | 162s |


#### rime-data
- cache hit: true
- compiled with librime 1.17.0, 5 files, 56.4 MiB; dictionary wanxiang v18.1.13
  - 55.99 MiB build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
  - 0.26 MiB build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
  - 0.17 MiB build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
  - 0.01 MiB build/orangecell_wanxiang.schema.yaml
  - 0.00 MiB build/default.yaml
- bundle size:  58M	ios/.rime-data/rime-shared
