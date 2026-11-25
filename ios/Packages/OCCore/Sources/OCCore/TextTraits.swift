// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What the host field tells a keyboard about itself (`UITextInputTraits`), reduced to what we act on. The
/// UIKit side builds it (OCKeyboardUI `TextTraits(_ traits:)`); the rules live here so they run in unit tests
/// on every platform.
public struct TextTraits: Equatable, Sendable {
    public enum Layout: Equatable, Sendable {
        case text, numbersAndPunctuation, numberPad, phonePad, decimalPad, email, url
    }

    public enum Capitalization: Equatable, Sendable {
        case none, words, sentences, allCharacters
    }

    public var layout: Layout = .text
    public var capitalization: Capitalization = .sentences
    public var isSecure = false
    /// A content type AI must never see: password, one-time code, card data.
    public var hasSensitiveContentType = false
    public var enablesReturnKeyAutomatically = false
    /// Whether the field has text (the return key can be disabled while it has none).
    public var hasText = true

    public init(layout: Layout = .text, capitalization: Capitalization = .sentences, isSecure: Bool = false,
                hasSensitiveContentType: Bool = false, enablesReturnKeyAutomatically: Bool = false, hasText: Bool = true) {
        self.layout = layout
        self.capitalization = capitalization
        self.isSecure = isSecure
        self.hasSensitiveContentType = hasSensitiveContentType
        self.enablesReturnKeyAutomatically = enablesReturnKeyAutomatically
        self.hasText = hasText
    }

    /// Port of the Android privacy rule (`AiKeyboardController`: anything that is not a plain text field, a
    /// password, or a field that asks not to be learned from), plus what iOS adds: secure entry and the
    /// content types that hold secrets. Numeric fields (number, phone, decimal pad) never go to AI.
    ///
    /// Deviations, recorded in docs/IOS_PLAN.md section 15: iOS has no "do not personalise" flag, and
    /// `autocorrectionType == .no` is too common (code editors, search boxes) to mean "private"; Android's check
    /// for its own package has no iOS equivalent (the app's key field is secure entry anyway).
    public var isPrivate: Bool {
        if isSecure || hasSensitiveContentType { return true }
        switch layout {
        case .numberPad, .phonePad, .decimalPad: return true
        case .text, .numbersAndPunctuation, .email, .url: return false
        }
    }

    /// Fields that only take Latin text or digits: the keyboard switches to EN there (and back afterwards).
    public var forcesEnglish: Bool {
        if isSecure { return true }
        switch layout {
        case .numberPad, .phonePad, .decimalPad, .email, .url: return true
        case .text, .numbersAndPunctuation: return false
        }
    }

    /// The number / phone / decimal pad replaces the whole key area.
    public var isNumericPad: Bool {
        switch layout {
        case .numberPad, .phonePad, .decimalPad: return true
        default: return false
        }
    }

    /// The return key is greyed out while the field is empty when the host asks for that
    /// (`enablesReturnKeyAutomatically`).
    public var returnEnabled: Bool { !(enablesReturnKeyAutomatically && !hasText) }
}

/// Auto-capitalisation (`autocapitalizationType`): whether the next English letter is a capital.
public enum AutoCapitalization {
    private static let terminators: Set<Character> = [".", "!", "?", "。", "！", "？", "｡"]

    public static func wantsShift(_ kind: TextTraits.Capitalization, before: String?) -> Bool {
        let text = before ?? ""
        switch kind {
        case .none: return false
        case .allCharacters: return true
        case .words:
            guard let last = text.last else { return true }
            return last.isWhitespace || last.isNewline
        case .sentences:
            guard let last = text.last else { return true }
            if last.isNewline { return true }
            guard last.isWhitespace else { return false }
            // After a terminator and white space ("Hello. "), not after a plain space.
            let trimmed = text.reversed().drop { $0.isWhitespace && !$0.isNewline }
            if trimmed.isEmpty { return true }
            guard let previous = trimmed.first else { return true }
            return previous.isNewline || terminators.contains(previous)
        }
    }
}

/// Tells a change in the document that the person made (moved the caret, edited elsewhere) from one the
/// keyboard made itself. The document proxy reports its changes late (at the next `textDidChange`, sometimes
/// twice), so an own change is remembered and attributed to the first notification that shows a different
/// context; a notification with the same context is never a change.
public struct HostChangeTracker: Sendable {
    private var observed: String?
    private var pending = 0
    private var pendingSince: TimeInterval = 0
    /// How long an own change waits for its notification before it stops masking the next real change.
    public static let patience: TimeInterval = 1.0

    public init() {}

    private static func key(_ before: String?, _ after: String?) -> String { (before ?? "") + "\u{0}" + (after ?? "") }

    /// The keyboard inserted or deleted something.
    public mutating func ownChange(now: TimeInterval) {
        pending += 1
        pendingSince = now
    }

    /// Forgets everything (a new field, the keyboard appeared).
    public mutating func reset(before: String?, after: String?) {
        observed = Self.key(before, after)
        pending = 0
    }

    /// True when the context changed and the keyboard did not do it.
    public mutating func observe(before: String?, after: String?, now: TimeInterval) -> Bool {
        let context = Self.key(before, after)
        defer { observed = context }
        guard let observed, observed != context else { return false }
        if pending > 0 && now - pendingSince <= Self.patience {
            pending -= 1
            return false
        }
        pending = 0
        return true
    }
}
