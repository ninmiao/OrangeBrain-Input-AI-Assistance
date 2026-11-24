// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import OCKeyboardUI
import OCRime
import SwiftUI
import UIKit

/// Simulator-only test host. Two modes, chosen by launch argument:
///
/// * default: one text field that grabs focus at launch, so the system shows whatever
///   keyboard is selected (ideally the real OrangeCell extension) without a tap;
/// * `-OCEmbeddedKeyboard`: a text view whose `inputView` is the very same KeyboardView
///   the extension uses, driven in-process. XCUITest can then tap the keys by their
///   accessibility identifiers (no coordinates, no system keyboard involved).
///   `-OCAppearance light|dark` forces the appearance for the screenshots.
@main
struct OCTestHostApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-OCEmbeddedKeyboard") {
                EmbeddedHost().ignoresSafeArea(.keyboard)
            } else {
                SystemKeyboardHost()
            }
        }
    }
}

struct SystemKeyboardHost: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OCTestHost")
                .font(.headline)
            TextField("type here", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("oc.testhost.field")
            Text("typed: \(text)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("oc.testhost.mirror")
            Spacer()
        }
        .padding()
        .task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            focused = true
        }
    }
}

struct EmbeddedHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> EmbeddedHostViewController { EmbeddedHostViewController() }
    func updateUIViewController(_ controller: EmbeddedHostViewController, context: Context) {}
}

final class EmbeddedHostViewController: UIViewController, UITextViewDelegate {
    private let textView = UITextView()
    private let mirror = UILabel()
    private var keyboardController: KeyboardController!
    private var inputContainer: UIInputView!
    private var keyboardHeight: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-OCAppearance"), arguments.indices.contains(index + 1) {
            overrideUserInterfaceStyle = arguments[index + 1] == "dark" ? .dark : .light
        }
        view.backgroundColor = .systemBackground

        textView.font = .systemFont(ofSize: 22)
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.accessibilityIdentifier = "oc.testhost.field"
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false

        mirror.font = .systemFont(ofSize: 12)
        mirror.textColor = .secondaryLabel
        mirror.text = "typed: "
        mirror.accessibilityIdentifier = "oc.testhost.mirror"
        mirror.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(textView)
        view.addSubview(mirror)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(equalToConstant: 110),
            mirror.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            mirror.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
        ])

        let service = makeService()
        keyboardController = KeyboardController(
            service: service,
            output: KeyInputTextOutput(textView),
            notice: service == nil ? "测试宿主没有找到词库" : nil
        )
        let keyboard = KeyboardView(controller: keyboardController)
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        let container = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: KeyboardView.preferredHeight(landscape: false)),
                                    inputViewStyle: .keyboard)
        container.allowsSelfSizing = true
        container.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        container.addSubview(keyboard)
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: container.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        keyboardHeight = container.heightAnchor.constraint(equalToConstant: KeyboardView.preferredHeight(landscape: false))
        keyboardHeight.isActive = true
        inputContainer = container
        textView.inputView = container
        keyboardController.prepare()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    /// The extension sizes itself like this (OCKeyboardViewController.currentHeight).
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboardHeight?.constant = KeyboardView.preferredHeight(landscape: traitCollection.verticalSizeClass == .compact)
    }

    func textViewDidChange(_ textView: UITextView) {
        mirror.text = "typed: " + textView.text
    }

    /// Data from the bundle, or from OC_RIME_SHARED (the UI tests point it at the CI build).
    /// A fresh user dictionary per launch unless `-OCUserDir <path>` is given.
    private func makeService() -> RimeService? {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        let shared = environment["OC_RIME_SHARED"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? RimeDataLocator.sharedDataDirectory()
        guard let shared else { return nil }
        var user = FileManager.default.temporaryDirectory.appendingPathComponent("oc-host-\(UUID().uuidString)")
        if let index = arguments.firstIndex(of: "-OCUserDir"), arguments.indices.contains(index + 1) {
            user = URL(fileURLWithPath: arguments[index + 1])
        }
        return RimeService(configuration: RimeServiceConfiguration(
            sharedDataDirectory: shared.path, userDataDirectory: user.path
        ))
    }
}
