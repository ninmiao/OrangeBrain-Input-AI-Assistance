// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import OCRime
import UIKit

/// M0 keyboard: proves that the extension loads, that librime and the shared
/// native core are linked in, and that text can be inserted. Real typing comes
/// with milestone M1.
final class KeyboardViewController: UIInputViewController {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let content = UIStackView()
    private var heightConstraint: NSLayoutConstraint?
    private var engine: RimeEngine?
    private var checksStarted = false
    private let rimeQueue = DispatchQueue(label: "io.github.ninmiao.orangecell.keyboard.rime", qos: .userInitiated)

    // MARK: lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        titleLabel.text = bannerText(rimeVersion: RimeEngine.version())
        detailLabel.text = "正在检查 librime 模块…"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if heightConstraint == nil {
            let constraint = view.heightAnchor.constraint(equalToConstant: 260)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        runChecksOnce()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        detailLabel.text = (detailLabel.text ?? "") + "\n内存警告"
    }

    deinit {
        engine?.finalize()
    }

    // MARK: checks

    private func bannerText(rimeVersion: String?) -> String {
        let core = NativeCore.selfTest() ? "oc_core OK" : "oc_core FAIL"
        return "橘脑一颗 · librime \(rimeVersion ?? "?") · \(core)"
    }

    private func runChecksOnce() {
        guard !checksStarted else { return }
        checksStarted = true
        let fullAccess = hasFullAccess
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = caches.appendingPathComponent("rime-m0-keyboard", isDirectory: true)

        rimeQueue.async { [weak self] in
            // Keep Rime running so the memory number below includes it.
            let probe = RimeProbe.run(workingDirectory: directory, keepRunning: true)
            let report = DiagnosticsCollector.collect(
                role: "keyboard",
                peerRole: "app",
                fullAccess: fullAccess,
                writesKeySample: false,
                rimeVersion: probe.result.version,
                rimeModules: probe.result.modules
            )
            DiagnosticsCollector.save(report)
            DispatchQueue.main.async {
                guard let self else { return }
                self.engine = probe.engine
                self.titleLabel.text = self.bannerText(rimeVersion: probe.result.version)
                self.detailLabel.text = self.detailText(report: report, probe: probe.result)
            }
        }
    }

    private func detailText(report: DiagnosticsReport, probe: RimeProbeResult) -> String {
        var lines: [String] = []
        lines.append("模块: " + (probe.modules.isEmpty ? "无" : probe.modules.joined(separator: " ")))
        if !probe.missingRequired.isEmpty { lines.append("缺少: " + probe.missingRequired.joined(separator: " ")) }
        lines.append("Rime 启动: " + (probe.started ? "成功" : "失败 \(probe.error ?? "")"))
        lines.append("App Group: " + (report.groupResolved ?? "无") + (report.containerPath == nil ? "（不可用）" : ""))
        lines.append("完全访问: " + (hasFullAccess ? "是" : "否")
            + " · 内存 " + (report.footprintMB.map { String(format: "%.1f MB", $0) } ?? "?"))
        return lines.joined(separator: "\n")
    }

    // MARK: interface

    private func buildInterface() {
        view.backgroundColor = .clear

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.accessibilityIdentifier = "oc.m0.title"

        detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textAlignment = .left
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 5
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.contentMode = .topLeft
        detailLabel.accessibilityIdentifier = "oc.m0.detail"

        let textRow = row([
            textKey("你", id: "oc.key.ni"),
            textKey("好", id: "oc.key.hao"),
            textKey("，", id: "oc.key.comma"),
            textKey("。", id: "oc.key.period"),
            textKey("？", id: "oc.key.question"),
        ])
        let controlRow = row([
            globeKey(),
            textKey("空格", insert: " ", id: "oc.key.space", weight: 3),
            actionKey("⌫", id: "oc.key.delete") { [weak self] in self?.textDocumentProxy.deleteBackward() },
            textKey("↩︎", insert: "\n", id: "oc.key.return"),
        ])

        content.axis = .vertical
        content.spacing = 8
        content.distribution = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        let arranged: [UIView] = [titleLabel, detailLabel, textRow, controlRow]
        arranged.forEach { content.addArrangedSubview($0) }
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -6),
            // Fixed heights keep the keys where the UI test taps them (it cannot see
            // inside the keyboard extension and taps by coordinates).
            titleLabel.heightAnchor.constraint(equalToConstant: 20),
            detailLabel.heightAnchor.constraint(equalToConstant: 70),
            textRow.heightAnchor.constraint(equalToConstant: 46),
            controlRow.heightAnchor.constraint(equalToConstant: 46),
        ])
    }

    private func row(_ keys: [UIButton]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: keys)
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fillProportionally
        keys.forEach { $0.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        return stack
    }

    private func baseKey(_ title: String, id: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 20)
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = .systemBackground
        button.layer.cornerRadius = 7
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.25
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.accessibilityIdentifier = id
        button.accessibilityLabel = title
        return button
    }

    private func textKey(_ title: String, insert text: String? = nil, id: String, weight: CGFloat = 1) -> UIButton {
        let key = baseKey(title, id: id)
        let output = text ?? title
        key.addAction(UIAction { [weak self] _ in self?.textDocumentProxy.insertText(output) }, for: .touchUpInside)
        if weight > 1 {
            key.widthAnchor.constraint(greaterThanOrEqualToConstant: 40 * weight).isActive = true
        }
        return key
    }

    private func actionKey(_ title: String, id: String, action: @escaping () -> Void) -> UIButton {
        let key = baseKey(title, id: id)
        key.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return key
    }

    /// The system requires an input-mode switch key; long press shows the list.
    private func globeKey() -> UIButton {
        let key = baseKey("🌐", id: "oc.key.globe")
        key.accessibilityLabel = "下一个键盘"
        key.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        return key
    }
}
