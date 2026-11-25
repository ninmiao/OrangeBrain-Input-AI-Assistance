// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import OCCore

/// Simulator-only set-up for the CI end-to-end run: no real service and no real key exist there. Asked for with
///
///     -OCSeedAi http://127.0.0.1:PORT [-OCSeedAiMode none|correction|assistant] [-OCSeedAiPolicy openrouter|openai|gemini]
///
/// it selects a policy, agrees to cloud AI, stores a made-up key for it and writes the loopback routes that send
/// the three logical endpoints to the mock server on this machine. Nothing in this file is compiled for a
/// device, so an installed app has no way to redirect a request.
enum AiSeed {
    static func applyIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if targetEnvironment(simulator)
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard let base = value("-OCSeedAi"), let url = URL(string: base), url.host == "127.0.0.1" else { return }
        let context = AppGroupContext.detect()
        guard let store = AiStore(context: context) else { return }
        let policy = value("-OCSeedAiPolicy") ?? "openrouter"
        let mode: AiMode
        switch value("-OCSeedAiMode") ?? "assistant" {
        case "none": mode = .none
        case "correction": mode = .correction
        default: mode = .assistant
        }
        try? store.selectPolicy(policy)
        let endpoint = store.config.endpoint
        _ = try? store.update { config in
            config = mode.applying(to: config)
            config.consent = true
            config.debounceMs = 100
        }
        CredentialVault.chooseBackend("encrypted-file", in: context)
        try? CredentialVault(context: context).save(policyID: policy, endpoint: endpoint, secret: "sk-mock-orangecell-test")
        let routes = [
            ApiRouting.openAI: base + "/openai/v1/responses",
            ApiRouting.openRouter: base + "/openrouter/api/v1/chat/completions",
            ApiRouting.gemini: base + "/gemini/v1beta/interactions",
        ]
        if let directory = context.sharedDirectory("config"), let data = try? JSONEncoder().encode(routes) {
            try? data.write(to: directory.appendingPathComponent(AiLoopbackRoutes.fileName), options: [.atomic])
        }
        #endif
    }
}
