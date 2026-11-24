// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit

/// One key: a rounded rectangle with a title or an SF Symbol. Highlights while pressed
/// and reports touch-down (for the popup and haptics) and a completed tap.
final class KeyButton: UIControl {
    let spec: KeySpec
    var onTouchDown: ((KeyButton) -> Void)?
    var onTouchUp: ((KeyButton) -> Void)?
    var onTap: ((KeyButton) -> Void)?

    private let label = UILabel()
    private let imageView = UIImageView()
    private let shadowLayer = CALayer()

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

        // A one-point shadow underneath, as on the system keyboard.
        shadowLayer.backgroundColor = KeyboardTheme.keyShadow.cgColor
        shadowLayer.cornerRadius = KeyboardTheme.keyCornerRadius
        layer.insertSublayer(shadowLayer, at: 0)

        isAccessibilityElement = true
        accessibilityTraits = [.keyboardKey, .button]
        accessibilityIdentifier = "oc.key." + spec.id
        configureContent()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func configureContent() {
        let tint: UIColor = spec.style == .accent ? KeyboardTheme.accentText : KeyboardTheme.text
        if spec.title.hasPrefix("sf:") {
            let name = String(spec.title.dropFirst(3))
            let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            imageView.image = UIImage(systemName: name, withConfiguration: configuration)
            imageView.tintColor = tint
            imageView.contentMode = .center
            addSubview(imageView)
            accessibilityLabel = Self.accessibilityName(for: name)
        } else {
            label.text = spec.title
            label.textColor = tint
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            label.font = spec.style == .normal && spec.title.count == 1 ? KeyboardTheme.keyFont : KeyboardTheme.modifierFont
            if spec.id == "language" { label.font = UIFont.systemFont(ofSize: 18, weight: .medium) }
            addSubview(label)
            accessibilityLabel = spec.title
        }
        label.isUserInteractionEnabled = false
        imageView.isUserInteractionEnabled = false
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = CGRect(x: 0, y: 1, width: bounds.width, height: bounds.height)
        CATransaction.commit()
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? pressedColor : baseColor }
    }

    /// Re-applies dynamic colours after a light / dark change.
    func refreshColors() {
        backgroundColor = isHighlighted ? pressedColor : baseColor
        shadowLayer.backgroundColor = KeyboardTheme.keyShadow.cgColor
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
        if inside { onTap?(self) }
    }

    override func cancelTracking(with event: UIEvent?) {
        isHighlighted = false
        onTouchUp?(self)
    }

    /// For XCUITest: an accessibility activation taps the key.
    override func accessibilityActivate() -> Bool {
        onTouchDown?(self)
        onTouchUp?(self)
        onTap?(self)
        return true
    }
}
