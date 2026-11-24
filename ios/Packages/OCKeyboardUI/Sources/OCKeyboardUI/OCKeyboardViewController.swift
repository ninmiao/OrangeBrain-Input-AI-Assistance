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
    private var heightConstraint: NSLayoutConstraint?
    private var currentConfiguration: RimeServiceConfiguration?
    private var lastStamp: String?
    private var stopWorkItem: DispatchWorkItem?
    private var diagnosticsWorkItem: DispatchWorkItem?

    /// How long the engine stays up after the keyboard disappeared.
    private let idleStopDelay: TimeInterval = 8

    open override func viewDidLoad() {
        super.viewDidLoad()
        controller = KeyboardController(service: nil, output: ProxyOutput(owner: self))
        controller.onActivity = { [weak self] in self?.scheduleDiagnostics() }
        keyboardView = KeyboardView(controller: controller)
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.globeTarget = self
        keyboardView.globeAction = #selector(handleInputModeList(from:with:))
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
        stopWorkItem?.cancel()
        stopWorkItem = nil
        if heightConstraint == nil {
            let constraint = view.heightAnchor.constraint(equalToConstant: currentHeight())
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
        configureEngine()
        keyboardView.hapticsEnabled = hasFullAccess
        keyboardView.returnKind = ReturnKeyKind(textDocumentProxy.returnKeyType ?? .default)
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
        controller.clearComposition()
        let item = DispatchWorkItem { [weak self] in self?.controller.rimeService?.stop() }
        stopWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + idleStopDelay, execute: item)
    }

    open override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        controller.rimeService?.handleMemoryWarning()
    }

    open override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        keyboardView?.returnKind = ReturnKeyKind(textDocumentProxy.returnKeyType ?? .default)
    }

    private func currentHeight() -> CGFloat {
        KeyboardView.preferredHeight(landscape: traitCollection.verticalSizeClass == .compact)
    }

    // MARK: engine

    /// Finds the data and the user directory and (re)creates the Rime front door when needed.
    private func configureEngine() {
        let context = AppGroupContext.detect()
        guard let shared = RimeDataLocator.sharedDataDirectory(),
              let user = RimeDataLocator.userDataDirectory(context: context, hasFullAccess: hasFullAccess)
        else {
            controller.setService(nil)
            currentConfiguration = nil
            return
        }
        let configuration = RimeServiceConfiguration(sharedDataDirectory: shared.path, userDataDirectory: user.url.path)
        let stamp = DeployStamp.read(in: context)
        if configuration != currentConfiguration {
            controller.setService(RimeService(configuration: configuration))
            currentConfiguration = configuration
            lastStamp = stamp
        } else if stamp != lastStamp {
            // The app deployed something: drop the engine, it restarts with the next key.
            controller.rimeService?.stopSync()
            controller.resetComposition()
            lastStamp = stamp
        }
        controller.prepare()
    }

    // MARK: diagnostics (for the CI run and the app's diagnostics page)

    private func scheduleDiagnostics() {
        diagnosticsWorkItem?.cancel()
        let fullAccess = hasFullAccess
        let item = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            DispatchQueue.global(qos: .utility).async {
                let report = DiagnosticsCollector.collect(
                    role: "keyboard",
                    peerRole: "app",
                    fullAccess: fullAccess,
                    writesKeySample: false,
                    rimeVersion: RimeEngine.version(),
                    rimeModules: RimeEngine.registeredModules()
                )
                DiagnosticsCollector.save(report)
            }
        }
        diagnosticsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }
}
