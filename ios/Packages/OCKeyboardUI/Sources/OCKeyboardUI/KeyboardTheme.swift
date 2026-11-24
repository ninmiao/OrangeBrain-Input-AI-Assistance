// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit

/// Colours follow the Android keyboard's "iOS Light" scheme (rime_ai_ios.yaml:
/// background d1d3d9, keys ffffff, modifier keys abb0ba, text 151515) plus the
/// project's orange accent; the dark variant follows the system keyboard's dark scheme.
enum KeyboardTheme {
    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    static let background = dynamic(light: 0xD1D3D9, dark: 0x2B2B2D)
    static let key = dynamic(light: 0xFFFFFF, dark: 0x6A6A6C)
    static let keyPressed = dynamic(light: 0xB8BDC7, dark: 0x8E8E90)
    static let modifier = dynamic(light: 0xABB0BA, dark: 0x454547)
    static let modifierPressed = dynamic(light: 0xFFFFFF, dark: 0x6A6A6C)
    static let text = dynamic(light: 0x151515, dark: 0xFFFFFF)
    static let secondaryText = dynamic(light: 0x66717B, dark: 0xAEAEB2)
    static let keyShadow = dynamic(light: 0xA6A9AF, dark: 0x000000)
    static let separator = dynamic(light: 0xC1C7CA, dark: 0x3A3A3C)
    static let candidateHighlight = dynamic(light: 0xFFFFFF, dark: 0x6A6A6C)
    static let accent = dynamic(light: 0xF28C28, dark: 0xF59A3D)
    static let accentText = UIColor.white

    static let keyCornerRadius: CGFloat = 6
    static let keyFont = UIFont.systemFont(ofSize: 24, weight: .regular)
    static let modifierFont = UIFont.systemFont(ofSize: 16, weight: .regular)
    static let candidateFont = UIFont.systemFont(ofSize: 20, weight: .regular)
    static let commentFont = UIFont.systemFont(ofSize: 12, weight: .regular)
    static let compositionFont = UIFont.systemFont(ofSize: 13, weight: .regular)
}
