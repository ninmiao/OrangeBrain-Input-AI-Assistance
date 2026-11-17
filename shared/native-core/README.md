# Zephyr native AI core

C++17 owns input/context encoding, prompt composition, provider payloads, reasoning/model capability rules, parameter validation, model/provider-list parsing, candidate parsing and token-budget decisions and incremental SSE decoding. Android loads `libzephyr_core.so`; Windows statically links `core.cpp` into its native settings and broker executables; it has no JNI or JVM dependency.

`shared/ai-core` supplies Android JVM adapters and common resources. Android retains Kotlin UI and platform integration. Windows 1.9.0 uses native Win32 controls, asynchronous WinHTTP, DPAPI, and a C++ dictionary updater. Windows source and builds no longer use Kotlin, Gradle, JDK, or a bundled JVM. iOS is not implemented.

## Wire contract

Input: `{"i":"nihao","b":"previous","a":"next"}`. `b` and `a` are omitted when empty. Context defaults to enabled, 50 code points before and 0 after; it excludes the current composition. The correction slot transforms `i`; the assistant slot infers intent using the available context. There is no history chain or Preset reference.

Output: `["correction","assistant"]` by default, or `["correction"]` with the assistant disabled. The `assistantEnabled` flag selects the prompt and preserves duplicate texts so role indices remain stable. Clients label the first item as correction and subsequent items as assistant. Up to 8 strings are accepted, with a 32 KiB output text limit and 2,000 code points per string. Assistant mode accepts one complete Markdown JSON fence around the entire array; prose before or after it is rejected. The client rejects objects, malformed JSON and recognizable thought markers. JSON nesting is bounded at the native boundary. A valid array cannot prove that a model followed the semantic instruction; it does prevent free-form reasoning from being treated as the response protocol.

## Soft token budget and truncation

L defaults to 256 output tokens. The first request reserves `max(L, 4 × input code points + 32)` tokens. This conservative estimate is not an exact tokenizer and cannot guarantee arbitrary model output fits. A model-specific max token parameter, if configured, supplies L. Thinking models may spend this budget on reasoning too.

OpenAI Responses, OpenRouter Chat Completions and Gemini Interactions use one streaming request. Only fully closed JSON strings become candidates. The correction appears as soon as complete; the assistant fills the second, reserved slot. Reasoning events never enter candidate text. Both clients cancel obsolete requests and reject late updates.

The shared `stream` operation accepts raw chunks as hex plus bounded parser state. It handles split UTF-8, SSE events, JSON escapes and role order. Stream bytes are bounded to 1 MiB; visible text retains the 32 KiB limit. Compatible gateways returning ordinary JSON are parsed once at EOF, without sending another request.

On truncation, timeout or a broken stream, an already complete correction remains usable. Incomplete strings are never displayed or repaired by adding a quote. There is no automatic truncation retry. If no complete candidate arrives, the client keeps local candidates and reports failure. Streaming advances display; it does not remove model thinking time or guarantee a faster server response.

## Build and tests

Windows: `powershell -File windows/scripts/build-app.ps1`; CMake compiles and tests the core without JNI or JDK. `script/build-core.ps1` remains available for Android JVM bridge tests. Android's existing CMake build includes this directory for each selected ABI; the APK excludes the Windows DLL.

`tests/corpus/truncated-output.jsonl` has 24 cases, including 18 explicitly truncated outputs. Native tests, JVM bridge tests and Android instrumentation exercise these cases. The large generated correction corpus remains in `tests/corpus/generated/` and is not removed or submitted to APIs.

`third_party/nlohmann/json.hpp` is version 3.12.0 under MIT; see `third_party/nlohmann/LICENSE.MIT`. Zephyr source is GPL-3.0-or-later.
