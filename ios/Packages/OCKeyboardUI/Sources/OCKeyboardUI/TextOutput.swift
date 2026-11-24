// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit

/// What the keyboard needs from the text it types into. In the keyboard extension
/// this is the `UITextDocumentProxy`; in the test host it is the text view whose
/// `inputView` the keyboard is.
public protocol KeyboardTextOutput: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    var returnKeyKind: ReturnKeyKind { get }
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
}
