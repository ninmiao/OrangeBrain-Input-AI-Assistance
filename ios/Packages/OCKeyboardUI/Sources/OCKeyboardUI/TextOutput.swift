// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import UIKit

/// What the keyboard needs from the text it types into. In the keyboard extension
/// this is the `UITextDocumentProxy`; in the test host it is the text view whose
/// `inputView` the keyboard is.
public protocol KeyboardTextOutput: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    var returnKeyKind: ReturnKeyKind { get }
    /// The text before and after the caret as the host reports it: nil when empty, limited by the host (often to
    /// the current paragraph), and late (it catches up with an insert at the next `textDidChange`).
    var contextBefore: String? { get }
    var contextAfter: String? { get }
    /// The selected text, if any.
    var selectedText: String? { get }
    /// What the field is (keyboard type, secure entry, capitalisation, ...).
    var textTraits: TextTraits { get }
    /// Changes when the host moves to another field.
    var documentIdentifier: UUID? { get }
}

extension KeyboardTextOutput {
    public var contextBefore: String? { nil }
    public var contextAfter: String? { nil }
    public var selectedText: String? { nil }
    public var textTraits: TextTraits { TextTraits() }
    public var documentIdentifier: UUID? { nil }
}

public enum ReturnKeyKind: Equatable {
    case standard, go, search, send, done, next

    init(_ type: UIReturnKeyType) {
        switch type {
        case .go: self = .go
        case .search, .google, .yahoo: self = .search
        case .send: self = .send
        case .done: self = .done
        case .next: self = .next
        default: self = .standard
        }
    }

    /// Label on the return key when it is not the plain arrow.
    var title: String? {
        switch self {
        case .standard: return nil
        case .go: return "前往"
        case .search: return "搜索"
        case .send: return "发送"
        case .done: return "完成"
        case .next: return "下一个"
        }
    }
}

/// Adapts anything that is `UIKeyInput` (a text view, the document proxy).
public final class KeyInputTextOutput: KeyboardTextOutput {
    private let input: UIKeyInput & UITextInputTraits

    public init(_ input: UIKeyInput & UITextInputTraits) {
        self.input = input
    }

    public func insertText(_ text: String) { input.insertText(text) }
    public func deleteBackward() { input.deleteBackward() }
    public var returnKeyKind: ReturnKeyKind { ReturnKeyKind(input.returnKeyType ?? .default) }

    private var textInput: UITextInput? { input as? UITextInput }

    public var contextBefore: String? {
        guard let text = textInput, let caret = text.selectedTextRange,
              let range = text.textRange(from: text.beginningOfDocument, to: caret.start),
              let value = text.text(in: range), !value.isEmpty else { return nil }
        return value
    }

    public var contextAfter: String? {
        guard let text = textInput, let caret = text.selectedTextRange,
              let range = text.textRange(from: caret.end, to: text.endOfDocument),
              let value = text.text(in: range), !value.isEmpty else { return nil }
        return value
    }

    public var selectedText: String? {
        guard let text = textInput, let caret = text.selectedTextRange, !caret.isEmpty,
              let value = text.text(in: caret), !value.isEmpty else { return nil }
        return value
    }

    public var textTraits: TextTraits { TextTraits(input, hasText: input.hasText) }
}
