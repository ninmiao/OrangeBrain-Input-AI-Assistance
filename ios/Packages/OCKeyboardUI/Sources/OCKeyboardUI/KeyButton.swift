// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit

/// One key: a rounded rectangle with a title or an SF Symbol. Highlights while pressed
/// and reports touch-down (for the popup and haptics) and a completed tap.
final class KeyButton: UIControl {
    private(set) var spec: KeySpec
    var onTouchDown: ((KeyButton) -> Void)?
    var onTouchUp: ((KeyButton) -> Void)?
    var onTap: ((KeyButton) -> Void)?
    /// When the touch of the last completed tap happened (system uptime, the clock of UITouch).
    /// Double taps are measured with it: it does not drift when the main thread is busy.
    private(set) var lastTouchTimestamp: TimeInterval = ProcessInfo.processInfo.systemUptime

    private let label = UILabel()
    private let imageView = UIImageView()

    var fillColor: UIColor { baseColor }

    private var baseColor: UIColor {
        switch spec.style {
        case .normal: return KeyboardTheme.key
        case .modifier: return KeyboardTheme.modifier
        case .accent: return KeyboardTheme.accent
        }
    }

    private var pressedColor: UIColor {
        switch spec.style {
        case .normal: return KeyboardTheme.keyPressed
        case .modifier: return KeyboardTheme.modifierPressed
        case .accent: return KeyboardTheme.accent.withAlphaComponent(0.75)
        }
    }

    init(spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        layer.cornerRadius = KeyboardTheme.keyCornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        backgroundColor = baseColor

        // A one-point shadow underneath, as on the system keyboard. It is the layer's own shadow,
        // drawn behind the key face (a sublayer would be drawn over the face).
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 1
        layer.shadowColor = KeyboardTheme.keyShadow.cgColor

        isAccessibilityElement = true
        accessibilityTraits = [.keyboardKey, .button]
        accessibilityIdentifier = "oc.key." + spec.id
        configureContent()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func configureContent() {
        let tint: UIColor = spec.style == .accent ? KeyboardTheme.accentText : KeyboardTheme.text
        if label.superview == nil {
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            label.isUserInteractionEnabled = false
            imageView.contentMode = .center
            imageView.isUserInteractionEnabled = false
            addSubview(label)
            addSubview(imageView)
        }
        accessibilityIdentifier = "oc.key." + spec.id
        if spec.title.hasPrefix("sf:") {
            let name = String(spec.title.dropFirst(3))
            let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            imageView.image = UIImage(systemName: name, withConfiguration: configuration)
            imageView.tintColor = tint
            imageView.isHidden = false
            label.isHidden = true
            accessibilityLabel = Self.accessibilityName(for: name)
        } else {
            label.text = spec.title
            label.textColor = tint
            label.font = spec.style == .normal && spec.title.count == 1 ? KeyboardTheme.keyFont : KeyboardTheme.modifierFont
            if spec.id == "language" { label.font = UIFont.systemFont(ofSize: 18, weight: .medium) }
            label.isHidden = false
            imageView.isHidden = true
            accessibilityLabel = spec.title
        }
        backgroundColor = isHighlighted ? pressedColor : baseColor
        isEnabled = spec.enabled
        alpha = spec.enabled ? 1 : 0.4
    }

    /// Gives the key another title, symbol or colour without recreating it: shift, caps lock
    /// and the return key change often, and replacing thirty views on every capital letter
    /// is slow and can swallow a touch that is just arriving.
    func update(_ newSpec: KeySpec) {
        guard newSpec != spec else { return }
        spec = newSpec
        configureContent()
        setNeedsLayout()
    }

    private static func accessibilityName(for symbol: String) -> String {
        switch symbol {
        case "shift", "shift.fill": return "shift"
        case "capslock.fill": return "caps lock"
        case "delete.left": return "delete"
        case "globe": return "next keyboard"
        case "return.left": return "return"
        default: return symbol
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 2)
        imageView.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: KeyboardTheme.keyCornerRadius).cgPath
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? pressedColor : baseColor }
    }

    /// Re-applies dynamic colours after a light / dark change.
    func refreshColors() {
        backgroundColor = isHighlighted ? pressedColor : baseColor
        layer.shadowColor = KeyboardTheme.keyShadow.cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshColors()
    }

    // MARK: touches

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isHighlighted = true
        onTouchDown?(self)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let inside = bounds.insetBy(dx: -12, dy: -12).contains(touch.location(in: self))
        if inside != isHighlighted { isHighlighted = inside }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        let inside = isHighlighted
        isHighlighted = false
        onTouchUp?(self)
        lastTouchTimestamp = touch?.timestamp ?? ProcessInfo.processInfo.systemUptime
        if inside { onTap?(self) }
    }

    override func cancelTracking(with event: UIEvent?) {
        isHighlighted = false
        onTouchUp?(self)
    }

    /// For XCUITest: an accessibility activation taps the key.
    override func accessibilityActivate() -> Bool {
        guard spec.enabled else { return false }
        onTouchDown?(self)
        onTouchUp?(self)
        lastTouchTimestamp = ProcessInfo.processInfo.systemUptime
        onTap?(self)
        return true
    }
}
