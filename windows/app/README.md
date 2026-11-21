# Native Windows client

Windows 1.9.1 uses C++17 throughout. `OrangeCellSettings.exe` is a Win32 common-controls UI; `OrangeCellBroker.exe` runs the AI named-pipe service. The existing Weasel TSF, Rime server, and data deployer remain native C++.

- `configuration.cpp`: existing JSON settings, policy selection/copy/deletion, DPAPI credentials bound to an HTTPS origin.
- `network.cpp`: asynchronous WinHTTP, bounded responses, cancellation, a total deadline, and no automatic redirects for API calls.
- `service.cpp`: Z1/Z2 pipe compatibility, long contextual benchmarks, direct calls to the shared C++ AI protocol, and bounded truncation retry.
- `dictionary.cpp`: official GitHub release metadata, resumable downloads, SHA-256, ZIP CRC validation, versioned dictionaries, deployment, and transaction recovery.
- `ui.cpp`: standard controls, five compact tabs, explicit Save with draft edits and visual feedback, checkbox policy benchmarks, and scrolling for small windows. No embedded browser or external UI framework.

The applications statically link the C++ runtime and shared AI core. Their imports are Windows system DLLs. No Kotlin, JNI, Java runtime, JAR, Qt, or WebView is packaged. Android continues to use its own Kotlin adapters and JNI bridge.

Build from the repository root:

```powershell
./windows/scripts/build-app.ps1
python windows/tests/test-native-app.py
./windows/scripts/package.ps1 -Destination .tools/native-release
./windows/scripts/build-installer.ps1 -Image .tools/native-release/OrangeCellSettings
```

Requires Visual Studio 2022 C++ Build Tools and CMake 3.18+; the complete Rime build also uses ATL/Boost and the preparation scripts documented in `docs/DEVELOPMENT.md`. Windows builds do not require JDK, Kotlin, Gradle, or an Android SDK.

The optional `orangecell_dictionary_test` takes an app image and a fresh, isolated user directory. A fourth argument can point at an existing test fixture containing a downloaded grammar model; it creates a hard link for that immutable test model. `orangecell_network_probe` reads public GitHub metadata without API credentials. Neither runs automatically as a paid model test.

Target: Windows 10/11 x64, with x86 TSF retained for 32-bit applications. Current-machine testing was on Windows 11; this is not a claim that every Windows release or application has been tested.
