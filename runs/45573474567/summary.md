# iOS CI — run 45573474567 (#19) — **failure**

- commit `d3c8a777224949da57b889cecccf4ad5dbae3912` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45573474567

| job | conclusion | duration |
| --- | --- | --- |
| rime-data | success | 0m54s |
| core-linux | failure | 1m13s |
| e2e | failure | 2m31s |
| e2e-hosts | failure | 1m52s |
| ipa-device | failure | 2m23s |
| e2e-ai | failure | 1m34s |
| e2e-debug | failure | 2m16s |
| build-test | failure | 15m07s |
| memory-release | failure | 7m47s |
| release | skipped | -1m59s |

**core-linux** failed in step(s): OCCore swift test, Check that the OCCore tests really ran (Linux)

**e2e** failed in step(s): Build the app, the keyboard and the UI tests (Release)

**e2e-hosts** failed in step(s): Build the app, the keyboard and the UI tests (Release)

**ipa-device** failed in step(s): Build for device (unsigned)

**e2e-ai** failed in step(s): Build the app, the keyboard and the UI tests (Release)

**e2e-debug** failed in step(s): Build the app, the keyboard and the UI tests (Debug)

**build-test** failed in step(s): Build for the simulator (Debug), Check that the unit-tests tests really ran, In-process keyboard UI tests (the real KeyboardView as a text view's input view), Memory with the shipped dictionary (Debug, minimal modules), Check that the memory-debug-minimal tests really ran, Memory with the shipped dictionary (Debug, all modules), Check that the memory-debug-all tests really ran, OCCore swift test (macOS, with the mock AI server on 127.0.0.1)

**memory-release** failed in step(s): Build for the simulator (Release), Check that the memory-release-minimal tests really ran, Memory with the shipped dictionary (Release, all modules), Check that the memory-release-all tests really ran

#### build-test (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- app unit tests (OrangeCellTests, simulator): no result
- OCCore `swift test` on macOS: 112 tests, 1 failures
- UI tests `ui-embedded`: no result

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 45s |
| fetch-deps | ok | 14s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 2s |
| build-sim | FAILED (65) | 67s |
| uitests-embedded | FAILED (65) | 30s |
| memory-debug-minimal | FAILED (65) | 383s |
| memory-debug-all | FAILED (65) | 222s |
| swift-test-macos | FAILED (1) | 99s |


#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: no result

| step | result | time |
| --- | --- | --- |
| apt | ok | 8s |
| native-core-test | ok | 13s |
| swift-test-linux | FAILED (1) | 9s |


#### e2e (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 39s |
| fetch-deps | ok | 10s |
| xcodegen-install | ok | 0s |
| xcodegen | ok | 1s |
| simulator-create | ok | 1s |
| build-e2e | FAILED (65) | 68s |


#### e2e-ai (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 10s |
| fetch-deps | ok | 9s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | FAILED (65) | 50s |


#### e2e-debug (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 30s |
| fetch-deps | ok | 9s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | FAILED (65) | 65s |


#### e2e-hosts (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 8s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-e2e | FAILED (65) | 61s |


#### ipa-device

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 50s |
| fetch-deps | ok | 4s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| build-device | FAILED (65) | 59s |


#### memory-release (macos-26)
- toolchain: Xcode 26.6; Build version 17F113; swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)

| step | result | time |
| --- | --- | --- |
| toolchain | ok | 11s |
| fetch-deps | ok | 8s |
| xcodegen-install | ok | 1s |
| xcodegen | ok | 0s |
| simulator-create | ok | 1s |
| build-sim-release | FAILED (65) | 59s |
| memory-release-all | FAILED (65) | 360s |


#### rime-data
- cache hit: true
- compiled with librime 1.17.0, 5 files, 56.4 MiB; dictionary wanxiang v18.1.13
  - 55.99 MiB build/orangecell_wanxiang_d_2a94c48aa51e.table.bin
  - 0.26 MiB build/orangecell_wanxiang_d_2a94c48aa51e.reverse.bin
  - 0.17 MiB build/orangecell_wanxiang_d_2a94c48aa51e.prism.bin
  - 0.01 MiB build/orangecell_wanxiang.schema.yaml
  - 0.00 MiB build/default.yaml
- bundle size:  58M	ios/.rime-data/rime-shared
