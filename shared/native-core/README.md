# Zephyr native AI core

C++17 owns input/context encoding, prompt composition, provider payloads, reasoning/model capability rules, parameter validation, model/provider-list parsing, candidate parsing and token/retry-budget decisions. Android loads `libzephyr_core.so`; Windows statically links `core.cpp` into its native settings and broker executables; it has no JNI or JVM dependency.

`shared/ai-core` supplies Android JVM adapters and common resources. Android retains Kotlin UI and platform integration. Windows 1.9.0 uses native Win32 controls, asynchronous WinHTTP, DPAPI, and a C++ dictionary updater. Windows source and builds no longer use Kotlin, Gradle, JDK, or a bundled JVM. iOS is not implemented.

## Wire contract

Input: `{"i":"nihao","b":"previous","a":"next"}`. `b` and `a` are omitted when empty. Context defaults to enabled, 50 code points before and 0 after; it excludes the current composition. Only `i` is transformed. There is no history chain or Preset reference.

Output: `["你好"]`, or ordered future multi-candidate output such as `["你好","您好"]`. Default prompts ask for one candidate. Up to 8 distinct strings are accepted, with a 32 KiB output text limit and 2,000 code points per string. The client rejects prose, code fences, objects, malformed JSON and recognizable thought markers. JSON nesting is bounded at the native boundary. A valid array cannot prove that a model followed the semantic instruction; it does prevent free-form reasoning from being treated as the response protocol.

## Soft token budget and truncation

L defaults to 256 output tokens. The first request reserves `max(L, 4 × input code points + 32)` tokens. This conservative estimate is not an exact tokenizer and cannot guarantee arbitrary model output fits. A model-specific max token parameter, if configured, supplies L. Thinking models may spend this budget on reasoning too.

If the provider explicitly reports length/incomplete, the parser retains only fully closed JSON strings in an otherwise valid array prefix. It never invents a missing quote, escape, emoji or sentence. With no complete candidate, one retry can raise the budget to `min(65536, max(2L, 8 × input code points + 256))`, using only the original deadline's remaining time. Malformed output and provider errors do not trigger this retry. Recovery cannot guarantee success during network or provider failures.

## Build and tests

Windows: `powershell -File windows/scripts/build-app.ps1`; CMake compiles and tests the core without JNI or JDK. `script/build-core.ps1` remains available for Android JVM bridge tests. Android's existing CMake build includes this directory for each selected ABI; the APK excludes the Windows DLL.

`tests/corpus/truncated-output.jsonl` has 24 cases, including 18 explicitly truncated outputs. Native tests, JVM bridge tests and Android instrumentation exercise these cases. The large generated correction corpus remains in `tests/corpus/generated/` and is not removed or submitted to APIs.

`third_party/nlohmann/json.hpp` is version 3.12.0 under MIT; see `third_party/nlohmann/LICENSE.MIT`. Zephyr source is GPL-3.0-or-later.
