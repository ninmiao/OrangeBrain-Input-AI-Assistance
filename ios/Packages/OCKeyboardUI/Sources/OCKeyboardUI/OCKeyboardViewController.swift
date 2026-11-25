// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import OCRime
import UIKit

/// Routes the extension's text document proxy to the controller. The proxy object is
/// looked up on every call because the system may swap it when the host's field changes.
private final class ProxyOutput: KeyboardTextOutput {
    private weak var owner: UIInputViewController?

    init(owner: UIInputViewController) { self.owner = owner }

    func insertText(_ text: String) { owner?.textDocumentProxy.insertText(text) }
    func deleteBackward() { owner?.textDocumentProxy.deleteBackward() }
    var returnKeyKind: ReturnKeyKind { ReturnKeyKind(owner?.textDocumentProxy.returnKeyType ?? .default) }
    var contextBefore: String? { owner?.textDocumentProxy.documentContextBeforeInput }
    var contextAfter: String? { owner?.textDocumentProxy.documentContextAfterInput }
    var selectedText: String? { owner?.textDocumentProxy.selectedText }
    var textTraits: TextTraits {
        guard let proxy = owner?.textDocumentProxy else { return TextTraits() }
        return TextTraits(proxy, hasText: proxy.hasText)
    }
    var documentIdentifier: UUID? { owner?.textDocumentProxy.documentIdentifier }
}

/// The keyboard extension's view controller. The extension target only subclasses it
/// (`NSExtensionPrincipalClass` has to live in the extension's own module).
///
/// Lifecycle (docs/IOS_PLAN.md section 4.4):
/// * the compiled data is read from the host app's bundle; nothing is ever deployed here;
/// * the user dictionary lives in the App Group with Full Access, otherwise in the
///   extension's private folder (learning then stays private);
/// * when the app writes a new deploy stamp the engine restarts at the next appearance;
/// * when the keyboard goes away the engine is stopped after a short grace period, which
///   closes the user dictionary and frees its memory.
open class OCKeyboardViewController: UIInputViewController {
    private var controller: KeyboardController!
    private var keyboardView: KeyboardView!
    private var proxyOutput: ProxyOutput!
    private var ai: AiKeyboardController?
    private lazy var groupContext = AppGroupContext.detect()
    private var documentID: UUID?
    private var fieldTraits: TextTraits?
    private var heightConstraint: NSLayoutConstraint?
    private var currentConfiguration: RimeServiceConfiguration?
    private var lastStamp: String?
    private var diagnosticsWorkItem: DispatchWorkItem?
    private var lastMigration: String?
    private var lastUserBuild: String?
    private var backgroundObserver: NSObjectProtocol?

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        // The engine front door is closed with the controller (its session, its lease): an old keyboard
        // can never keep the user dictionary open or finalise what a new one uses.
        controller?.deactivate()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        proxyOutput = ProxyOutput(owner: self)
        controller = KeyboardController(service: nil, output: proxyOutput)
        controller.onActivity = { [weak self] in self?.scheduleDiagnostics() }
        // The AI row (Android AiKeyboardController): configuration and key from the App Group, read-only.
        let ai = AiKeyboardController(
            keyboard: controller, output: { [weak self] in self?.proxyOutput },
            hasFullAccess: { [weak self] in self?.hasFullAccess ?? false },
            groupContext: { [weak self] in self?.groupContext ?? AppGroupContext.detect() })
        controller.aiHandler = ai.handler
        controller.aiEvents = ai.events
        self.ai = ai
        keyboardView = KeyboardView(controller: controller)
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.globeTarget = self   // weak in the view: the controller owns the view, not the other way round
        keyboardView.globeAction = #selector(handleInputModeList(from:with:))
        // The host app went to the background (the app switcher, another app): the user dictionary must not
        // stay open in a process that is about to be suspended.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSExtensionHostDidEnterBackground, object: nil, queue: .main
        ) { [weak self] _ in self?.keyboardWentAway() }
        view.addSubview(keyboardView)
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if heightConstraint == nil {
            let constraint = view.heightAnchor.constraint(equalToConstant: currentHeight())
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
        configureEngine()
        // Settings the app writes into the App Group (Full Access); without them the defaults apply.
        keyboardView.numberRowEnabled = hasFullAccess ? KeyboardSettings.load(in: AppGroupContext.detect()).numberRow : true
        keyboardView.hapticsEnabled = hasFullAccess
        keyboardView.returnKind = ReturnKeyKind(textDocumentProxy.returnKeyType ?? .default)
        // Whatever field is focused now: its traits decide the panel, the language, the capitals and the AI row.
        documentID = textDocumentProxy.documentIdentifier
        fieldTraits = nil
        fieldChanged(newField: true)
    }

    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        heightConstraint?.constant = currentHeight()
        keyboardView.showsGlobeKey = needsInputModeSwitchKey
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleDiagnostics()
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        keyboardWentAway()
    }

    /// Hidden or in the background: drop what is being composed and close the session, which flushes and
    /// closes the user dictionary (another keyboard process may want it next).
    private func keyboardWentAway() {
        keyboardView?.stopDeleteRepeat()
        // Android commits the typed letters as composing text when the keyboard goes away; here the composition
        // lives in the keyboard, never in the host text, so it is discarded (docs/IOS_PLAN.md section 15).
        ai?.finish()
        controller?.deactivate()
    }

    open override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        controller.handleMemoryWarning()
    }

    open override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        keyboardView?.returnKind = ReturnKeyKind(textDocumentProxy.returnKeyType ?? .default)
        fieldChanged(newField: false)
    }

    /// The caret moved or the selection changed: a composition that was typed elsewhere is dropped.
    open override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        fieldChanged(newField: false)
    }

    /// The host changed something (a new field, a moved caret, other traits): the keyboard reads the field again.
    private func fieldChanged(newField: Bool) {
        guard let controller else { return }
        let proxy = textDocumentProxy
        let before = proxy.documentContextBeforeInput
        let after = proxy.documentContextAfterInput
        let traits = TextTraits(proxy, hasText: proxy.hasText)
        let identifier = proxy.documentIdentifier
        if newField || identifier != documentID || fieldTraits == nil {
            documentID = identifier
            fieldTraits = traits
            controller.setTraits(traits, contextBefore: before, contextAfter: after)
            keyboardView?.setNeedsLayout()
            ai?.start(traits: traits)
            return
        }
        controller.hostContextChanged(traits: traits, contextBefore: before, contextAfter: after)
        // Whether the field is private is what the AI row cares about; an empty field filling up is not a new field.
        let privacyChanged = traits.isPrivate != fieldTraits?.isPrivate
        fieldTraits = traits
        if privacyChanged {
            ai?.start(traits: traits)
        } else {
            ai?.hostContextChanged()
        }
    }

    private func currentHeight() -> CGFloat {
        KeyboardView.preferredHeight(landscape: traitCollection.verticalSizeClass == .compact, numberRow: keyboardView?.numberRowEnabled ?? true)
    }

    // MARK: engine

    /// Finds the data and the user directory and (re)creates the Rime front door when needed.
    private func configureEngine() {
        let context = AppGroupContext.detect()
        guard let shared = RimeDataLocator.sharedDataDirectory(),
              let directories = RimeDataLocator.keyboardDirectories(context: context, hasFullAccess: hasFullAccess)
        else {
            controller.setService(nil)
            currentConfiguration = nil
            return
        }
        // The live user dictionary is private to the keyboard whatever Full Access says. A dictionary an M1
        // build left in the App Group is moved here once; with Full Access the app deployments (staging)
        // are read from the group and the dictionary is exported there as text when the engine is idle.
        if let legacy = directories.legacyUser {
            let result = UserDictionaryMigration.migrate(from: legacy, to: directories.user)
            if result != .notNeeded { lastMigration = result.summary }
        }
        RimeInstallation.prepare(userDirectory: directories.user, syncDirectory: directories.syncExport)
        // The app deployment is used only when it matches the data bundled with this version of the app.
        var staging: URL?
        if let candidate = directories.staging {
            let validity = RimeBuildStamp.validate(stagingDirectory: candidate, sharedDirectory: shared)
            lastUserBuild = validity.summary
            if validity == .valid { staging = candidate }
        } else {
            lastUserBuild = nil
        }
        let configuration = RimeServiceConfiguration(
            sharedDataDirectory: shared.path, userDataDirectory: directories.user.path,
            stagingDirectory: staging?.path, exportSnapshotOnIdle: directories.syncExport != nil)
        let stamp = DeployStamp.read(in: context)
        if configuration != currentConfiguration {
            controller.setService(RimeService(configuration: configuration))
            currentConfiguration = configuration
            lastStamp = stamp
        } else if stamp != lastStamp {
            // The app deployed something: a new session reads it (prepare below opens it).
            controller.rimeService?.deactivate()
            controller.resetComposition()
            lastStamp = stamp
        }
        controller.prepare()
    }

    // MARK: diagnostics (for the CI run and the app's diagnostics page)

    private func scheduleDiagnostics() {
        diagnosticsWorkItem?.cancel()
        let fullAccess = hasFullAccess
        let migration = lastMigration
        let userBuild = lastUserBuild
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let service = self.controller.rimeService
            let unhandled = self.controller.unhandledLetters
            let timings = self.controller.timings
            DispatchQueue.global(qos: .utility).async {
                // Asked on this queue: the engine's own queue may be busy and must not stall typing.
                let running = service?.isRunning
                let mode = service?.userDictionaryMode.rawValue
                let report = DiagnosticsCollector.collect(
                    role: "keyboard",
                    peerRole: "app",
                    fullAccess: fullAccess,
                    writesKeySample: false,
                    rimeVersion: RimeEngine.version(),
                    rimeModules: RimeEngine.registeredModules(),
                    rimeRunning: running,
                    unhandledLetters: unhandled,
                    userDictionaryMigration: migration,
                    engineReadyMs: timings.engineReadyMs,
                    firstCandidatesMs: timings.firstCandidatesMs,
                    userDictionaryMode: mode,
                    userBuild: userBuild
                )
                DiagnosticsCollector.save(report)
            }
        }
        diagnosticsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }
}
