# iOS CI — run 45540491619 (#16) — **failure**

- commit `7a95d06ed3bbef8a2dc33e3567b3eff8a482e389` on `ios` (push)
- https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance/actions/runs/45540491619

| job | conclusion | duration |
| --- | --- | --- |
| core-linux | success | 1m16s |
| rime-data | failure | 0m28s |
| e2e-hosts | skipped | 0m00s |
| memory-release | skipped | 0m00s |
| e2e | skipped | 0m00s |
| ipa-device | skipped | 0m00s |
| build-test | skipped | 0m00s |
| e2e-debug | skipped | 0m00s |
| release | skipped | 0m00s |

**rime-data** failed in step(s): Run ./.github/actions/ios-mac-setup

#### core-linux
- native-core C++ test (CMake, with the C API cases): 780 cases passed
- OCCore `swift test` on Linux: 35 tests, 0 failures

| step | result | time |
| --- | --- | --- |
| apt | ok | 8s |
| native-core-test | ok | 12s |
| swift-test-linux | ok | 11s |


#### rime-data
- cache hit: 
