// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import OCCore

/// The AI part of the keyboard extension: reads the configuration the app wrote (read-only, reloaded when the
/// app changes it), finds the key, builds the transport and connects `AiController` (the rules) to the keyboard
/// (the document, the Rime composition, the AI row). Without Full Access nothing here touches the App Group or
/// the network: the AI row says so in one line.
@MainActor
public final class AiKeyboardController {
    /// Taps on the AI row and events from the keyboard reach the controller through these two objects, which
    /// are plain classes: the keyboard controller is not main-actor isolated and calls them synchronously (it
    /// only ever runs on the main thread).
    private final class Relay: AiBarHandler, KeyboardAiEvents {
        weak var owner: AiKeyboardController?

        func aiItemTapped(_ index: Int) { run { $0.ai.itemTapped(index) } }
        func aiAssistantTapped() { run { $0.reloadConfigIfChanged(); $0.ai.requestAssistant() } }
        func aiEmojiTapped() { run { $0.reloadConfigIfChanged(); $0.ai.requestEmoji() } }
        func aiCancelTapped() { run { $0.ai.cancelRequest() } }
        func aiAdoptTapped(_ index: Int) { run { $0.ai.adopt(index) } }
        func aiDismissExpanded() { run { $0.ai.dismissExpanded() } }
        func keyboardUserInput() { run { $0.ai.userInput() } }
        func keyboardCommitted(_ text: String) { run { $0.ai.textCommitted(text) } }
        func keyboardCompositionChanged() { run { $0.ai.compositionChanged() } }

        private func run(_ body: @MainActor (AiKeyboardController) -> Void) {
            MainActor.assumeIsolated {
                if let owner { body(owner) }
            }
        }
    }

    /// The document and the composition as the AI logic sees them.
    private final class Bridge: AiEditor {
        unowned let owner: AiKeyboardController

        init(owner: AiKeyboardController) { self.owner = owner }

        var isChinese: Bool { owner.keyboard.isChineseMode }
        var composition: AiComposition? { owner.keyboard.aiComposition }
        var contextBefore: String { owner.output()?.contextBefore ?? "" }
        var contextAfter: String { owner.output()?.contextAfter ?? "" }
        var selectedText: String? { owner.output()?.selectedText }
        var hasFullAccess: Bool { owner.hasFullAccess() }
        func clearComposition() { owner.keyboard.clearComposition() }
        func insert(_ text: String) { owner.keyboard.insertForAi(text) }
        func deleteBackward(_ count: Int) { owner.keyboard.deleteForAi(count) }
    }

    private let keyboard: KeyboardController
    private let output: () -> KeyboardTextOutput?
    private let hasFullAccess: () -> Bool
    private let groupContext: () -> AppGroupContext
    private let relay = Relay()
    private var bridge: Bridge!
    private var ai: AiController!

    private var config = AiConfig()
    private var configStamp: String?
    private var configLoaded = false
    private var vault: CredentialVault?
    private(set) var client = AiChatClient()
    private var lastStampCheck: TimeInterval = -.infinity
    private var started = false

    public var handler: AiBarHandler { relay }
    public var events: KeyboardAiEvents { relay }

    public init(keyboard: KeyboardController, output: @escaping () -> KeyboardTextOutput?, hasFullAccess: @escaping () -> Bool,
                groupContext: @escaping () -> AppGroupContext) {
        self.keyboard = keyboard
        self.output = output
        self.hasFullAccess = hasFullAccess
        self.groupContext = groupContext
        relay.owner = self
        bridge = Bridge(owner: self)
        ai = AiController(
            editor: bridge,
            config: { [unowned self] in self.config },
            credential: { [unowned self] c in self.key(for: c) },
            parameters: { c in AiStore.parameters(for: c) },
            send: { [weak self] call, onPartial in
                guard let client = await self?.client else { throw AiError.invalidConfiguration }
                return try await client.send(call, onPartial: onPartial)
            },
            notice: { _ in },
            render: { [weak keyboard] state in keyboard?.setAi(state) })
    }

    // MARK: lifecycle

    /// The keyboard appeared or the host moved to another field.
    public func start(traits: TextTraits) {
        reloadConfigIfChanged(force: true)
        started = true
        ai.start(sensitive: traits.isPrivate)
    }

    public func finish() {
        guard started else { return }
        started = false
        ai.finish()
    }

    /// The host reported a change in the document (`textDidChange`).
    public func hostContextChanged() {
        reloadConfigIfChanged()
        ai.contextChanged()
    }

    // MARK: configuration (read-only)

    /// Reads `config/ai-config.json` again when the app changed it (`state/config-stamp`). At most twice a
    /// second unless forced.
    func reloadConfigIfChanged(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if !force && now - lastStampCheck < 0.5 { return }
        lastStampCheck = now
        guard hasFullAccess() else {
            // No App Group, no configuration, no key: the AI row says why.
            if configLoaded || configStamp != nil { config = AiConfig(); configStamp = nil; configLoaded = false; ai?.configChanged() }
            return
        }
        let context = groupContext()
        let stamp = AiConfigFile.readStamp(in: context)
        guard force || !configLoaded || stamp != configStamp else { return }
        let changed = stamp != configStamp || !configLoaded
        configStamp = stamp
        let loaded = AiConfigFile.read(in: context) ?? AiConfig()
        let different = loaded != config
        config = loaded
        configLoaded = true
        vault = nil
        client = AiChatClient(routes: AiLoopbackRoutes.load(in: context))
        if changed && different { ai?.configChanged() }
    }

    /// The key of the selected policy, from the backend the app chose.
    private func key(for c: AiConfig) -> String? {
        if vault == nil { vault = CredentialVault(context: groupContext()) }
        return vault?.read(policyID: c.selectedPolicyId, endpoint: c.endpoint)
    }
}
