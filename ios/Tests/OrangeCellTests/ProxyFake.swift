// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import OCCore
import XCTest
@testable import OCKeyboardUI

/// A stand-in for `UITextDocumentProxy` that models what the real one does (and what makes keyboards fail):
/// the context before and after the caret is nil when empty and limited to the current paragraph, it lags
/// behind the keyboard's own inserts and deletes until `textDidChange` (`settle()`), and `deleteBackward`
/// removes one grapheme cluster.
final class ProxyFake: KeyboardTextOutput {
    /// The document as it really is.
    private(set) var before = ""
    private(set) var after = ""
    /// What the proxy reports (stale until `settle()` while `lag` is on).
    private var shownBefore = ""
    private var shownAfter = ""
    var lag = true
    var traits = TextTraits()
    let identifier = UUID()
    private(set) var inserted: [String] = []
    private(set) var deletions = 0
    var returnKeyKind: ReturnKeyKind { .standard }

    func insertText(_ text: String) {
        inserted.append(text)
        before += text
        if !lag { settle() }
    }

    func deleteBackward() {
        deletions += 1
        if !before.isEmpty { before.removeLast() }
        if !lag { settle() }
    }

    /// The next `textDidChange`: the proxy catches up.
    func settle() {
        shownBefore = before
        shownAfter = after
    }

    /// The person moves the caret `count` characters to the left (a host-side change, reported at once).
    func moveCaretLeft(_ count: Int) {
        for _ in 0..<count where !before.isEmpty {
            after = String(before.removeLast()) + after
        }
        settle()
    }

    /// The person types or edits in the document, not through the keyboard.
    func replaceDocument(before newBefore: String, after newAfter: String = "") {
        before = newBefore
        after = newAfter
        settle()
    }

    private func paragraphBefore(_ text: String) -> String? {
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return line.isEmpty ? nil : line
    }

    private func paragraphAfter(_ text: String) -> String? {
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return line.isEmpty ? nil : line
    }

    var contextBefore: String? { paragraphBefore(shownBefore) }
    var contextAfter: String? { paragraphAfter(shownAfter) }
    var selectedText: String? { nil }

    var textTraits: TextTraits {
        var value = traits
        value.hasText = !(before + after).isEmpty
        return value
    }

    var documentIdentifier: UUID? { identifier }
}
