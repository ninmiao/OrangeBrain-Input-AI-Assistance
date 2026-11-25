// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit

/// The AI row: status dot, the AI candidates (纠错 / 助手 or emoticons) and the two trigger keys
/// (emoji, assistant). Same arrangement as the second row of the Android keyboard.
final class AiBarView: UIView {
    var onItem: ((Int) -> Void)?
    var onAssistant: (() -> Void)?
    var onEmoji: (() -> Void)?
    var onCancel: (() -> Void)?

    private let dot = UILabel()
    private let scroll = UIScrollView()
    private let content = UIView()
    private let hintLabel = UILabel()
    private let assistantButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    private var itemButtons: [UIButton] = []
    private var placeholderLabel: UILabel?
    private(set) var state = AiBarState.disabled
    private let keyWidth: CGFloat = 38

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "oc.ai.bar"

        dot.text = "●"
        dot.font = UIFont.systemFont(ofSize: 9)
        dot.textAlignment = .center
        dot.accessibilityIdentifier = "oc.ai.dot"
        dot.isAccessibilityElement = true
        addSubview(dot)

        scroll.showsHorizontalScrollIndicator = false
        scroll.accessibilityIdentifier = "oc.ai.items"
        scroll.addSubview(content)
        addSubview(scroll)

        hintLabel.font = UIFont.systemFont(ofSize: 13)
        hintLabel.textColor = KeyboardTheme.secondaryText
        hintLabel.accessibilityIdentifier = "oc.ai.hint"
        addSubview(hintLabel)

        configure(emojiButton, symbol: "face.smiling", id: "oc.ai.emoji", label: "AI 表情")
        configure(assistantButton, symbol: "sparkles", id: "oc.ai.assistant", label: "AI 助手")
        emojiButton.addTarget(self, action: #selector(emojiTapped), for: .touchUpInside)
        assistantButton.addTarget(self, action: #selector(assistantTapped), for: .touchUpInside)
        for button in [emojiButton, assistantButton] {
            button.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
            addSubview(button)
        }
        apply(.disabled)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func configure(_ button: UIButton, symbol: String, id: String, label: String) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        button.setImage(UIImage(systemName: symbol, withConfiguration: configuration), for: .normal)
        button.accessibilityIdentifier = id
        button.accessibilityLabel = label
        button.tintColor = KeyboardTheme.secondaryText
    }

    @objc private func emojiTapped() { onEmoji?() }
    @objc private func assistantTapped() { onAssistant?() }
    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { onCancel?() }
    }
    @objc private func itemTapped(_ sender: UIButton) { onItem?(sender.tag) }

    // MARK: state

    private func dotColor(_ phase: AiBarState.Phase) -> UIColor {
        switch phase {
        case .failed: return UIColor(red: 0.70, green: 0.15, blue: 0.12, alpha: 1)
        case .waiting, .streaming: return UIColor(red: 0.60, green: 0.40, blue: 0, alpha: 1)
        case .done: return UIColor(red: 0.15, green: 0.45, blue: 0.28, alpha: 1)
        case .idle: return UIColor(red: 0.38, green: 0.41, blue: 0.45, alpha: 1)
        }
    }

    private func tint(for phase: AiBarState.Phase, active: Bool, enabled: Bool) -> UIColor {
        guard enabled else { return KeyboardTheme.secondaryText.withAlphaComponent(0.4) }
        guard active else { return KeyboardTheme.secondaryText }
        switch phase {
        case .failed: return UIColor(red: 0.70, green: 0.15, blue: 0.12, alpha: 1)
        case .waiting, .streaming: return UIColor(red: 0.86, green: 0.5, blue: 0.1, alpha: 1)
        case .done: return UIColor(red: 0.15, green: 0.45, blue: 0.28, alpha: 1)
        case .idle: return KeyboardTheme.secondaryText
        }
    }

    func apply(_ newState: AiBarState) {
        let itemsChanged = newState.items != state.items || newState.placeholder != state.placeholder
        state = newState
        dot.textColor = dotColor(newState.phase)
        dot.accessibilityLabel = "AI 状态：" + newState.indicator
        hintLabel.text = newState.hint
        hintLabel.isHidden = newState.hint == nil
        scroll.isHidden = newState.hint != nil
        for (button, active) in [(emojiButton, newState.emojiShown), (assistantButton, !newState.emojiShown)] {
            button.tintColor = tint(for: newState.phase, active: active, enabled: newState.enabled)
            button.alpha = newState.enabled ? 1 : 0.6
            let running = active && (newState.phase == .waiting || newState.phase == .streaming)
            if running { startPulse(button) } else { stopPulse(button) }
        }
        emojiButton.accessibilityValue = newState.emojiShown ? newState.indicator : nil
        assistantButton.accessibilityValue = newState.emojiShown ? nil : newState.indicator
        if itemsChanged { rebuildItems() }
        setNeedsLayout()
    }

    private func startPulse(_ button: UIButton) {
        guard button.layer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.35
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        button.layer.add(pulse, forKey: "pulse")
    }

    private func stopPulse(_ button: UIButton) {
        button.layer.removeAnimation(forKey: "pulse")
    }

    private func rebuildItems() {
        itemButtons.forEach { $0.removeFromSuperview() }
        itemButtons = []
        placeholderLabel?.removeFromSuperview()
        placeholderLabel = nil
        for (index, item) in state.items.enumerated() {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = KeyboardTheme.text
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
            var title = AttributedString(item.label)
            title.font = item.isEmoji ? UIFont.systemFont(ofSize: 16) : UIFont.systemFont(ofSize: 15)
            configuration.attributedTitle = title
            button.configuration = configuration
            button.tag = index
            button.accessibilityIdentifier = "oc.ai.item.\(index)"
            button.accessibilityLabel = (item.isEmoji ? "AI 表情：" : item.role.isEmpty ? "AI 候选：" : "AI \(item.role)：") + item.text
            button.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            content.addSubview(button)
            itemButtons.append(button)
        }
        if let placeholder = state.placeholder {
            let label = UILabel()
            label.text = placeholder
            label.font = UIFont.systemFont(ofSize: 15)
            label.textColor = KeyboardTheme.secondaryText
            label.accessibilityIdentifier = "oc.ai.placeholder"
            content.addSubview(label)
            placeholderLabel = label
        }
        scroll.setContentOffset(.zero, animated: false)
    }

    // MARK: layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height
        dot.frame = CGRect(x: 6, y: 0, width: 16, height: height)
        let trailing = 2 * keyWidth + 4
        emojiButton.frame = CGRect(x: bounds.width - 2 * keyWidth - 2, y: 0, width: keyWidth, height: height)
        assistantButton.frame = CGRect(x: bounds.width - keyWidth - 2, y: 0, width: keyWidth, height: height)
        let area = CGRect(x: 24, y: 0, width: max(0, bounds.width - 24 - trailing), height: height)
        scroll.frame = area
        hintLabel.frame = area
        var x: CGFloat = 0
        for button in itemButtons {
            let width = ceil(button.sizeThatFits(CGSize(width: 10_000, height: height)).width)
            button.frame = CGRect(x: x, y: 0, width: width, height: height)
            x += width
        }
        if let label = placeholderLabel {
            let width = ceil(label.sizeThatFits(CGSize(width: 10_000, height: height)).width) + 16
            label.frame = CGRect(x: x + 8, y: 0, width: width, height: height)
            x += width + 8
        }
        content.frame = CGRect(x: 0, y: 0, width: x, height: height)
        scroll.contentSize = CGSize(width: x, height: height)
    }
}
