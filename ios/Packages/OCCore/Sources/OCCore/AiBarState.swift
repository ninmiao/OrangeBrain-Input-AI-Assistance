// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What the AI bar (the second row under the Rime candidates, as on Android) shows. The AI controller
/// builds it, the view only draws it.
public struct AiBarState: Equatable {
    public enum Phase: Equatable {
        case idle, waiting, streaming, done, failed
    }

    public struct Item: Equatable {
        /// "纠错", "助手" or "" (emoticons and plain candidates have no role).
        public var role: String
        public var text: String
        public var isEmoji: Bool

        public init(role: String, text: String, isEmoji: Bool = false) {
            self.role = role
            self.text = text
            self.isEmoji = isEmoji
        }

        /// The label on the bar: role, text cut at 45 characters.
        public var label: String {
            let prefix = role.isEmpty ? "" : role + "："
            let shown = text.count > AiBarState.longTextLimit ? String(text.prefix(AiBarState.longTextLimit)) + "…" : text
            return prefix + shown
        }

        public var isLong: Bool { text.count > AiBarState.longTextLimit }
    }

    /// Candidates longer than this open the expanded view instead of being adopted at once (Android: dialog).
    public static let longTextLimit = 45

    /// The status text behind the dot ("待请求", "请求中…", ...).
    public var indicator: String = "AI 未启用"
    public var phase: Phase = .idle
    /// Which button shows the running request: the assistant sparkle or the emoji key.
    public var emojiShown = false
    public var items: [Item] = []
    /// "助手：生成中…" and friends, shown after the items.
    public var placeholder: String?
    /// One line instead of candidates when the AI cannot be used (no Full Access, not consented, secure field).
    public var hint: String?
    /// False greys the trigger buttons out.
    public var enabled = false
    public var busy = false
    /// The long candidate that is open in the text panel (adopt / cancel), if any.
    public var expandedIndex: Int?

    public init() {}

    public static let disabled = AiBarState()
}
