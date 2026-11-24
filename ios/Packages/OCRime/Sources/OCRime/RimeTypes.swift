// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// One key as librime sees it: an X11 keysym and a modifier mask.
public struct RimeKey: Equatable, Sendable {
    public var code: Int32
    public var mask: Int32

    public init(code: Int32, mask: Int32 = 0) {
        self.code = code
        self.mask = mask
    }

    public static let shiftMask: Int32 = 1 << 0
    public static let lockMask: Int32 = 1 << 1
    public static let controlMask: Int32 = 1 << 2

    public static let backspace = RimeKey(code: 0xFF08)
    public static let tab = RimeKey(code: 0xFF09)
    public static let enter = RimeKey(code: 0xFF0D)
    public static let escape = RimeKey(code: 0xFF1B)
    public static let space = RimeKey(code: 0x20)
    public static let left = RimeKey(code: 0xFF51)
    public static let up = RimeKey(code: 0xFF52)
    public static let right = RimeKey(code: 0xFF53)
    public static let down = RimeKey(code: 0xFF54)
    public static let pageUp = RimeKey(code: 0xFF55)
    public static let pageDown = RimeKey(code: 0xFF56)

    /// Printable keys: ASCII keysyms are the character code, anything else is a
    /// Unicode keysym (0x01000000 + code point).
    public static func character(_ character: Character, mask: Int32 = 0) -> RimeKey? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        let value = scalar.value
        let code: Int32 = value < 0x80 ? Int32(value) : Int32(0x0100_0000 + value)
        return RimeKey(code: code, mask: mask)
    }
}

public struct RimeCandidate: Equatable, Sendable {
    public var text: String
    public var comment: String

    public init(text: String, comment: String = "") {
        self.text = text
        self.comment = comment
    }
}

/// Everything the keyboard needs to redraw after one operation.
public struct RimeUpdate: Equatable, Sendable {
    /// Whether librime consumed the key. `false` means the caller handles it
    /// (typically by inserting the character itself).
    public var handled: Bool = false
    /// Text that must be inserted into the document now, if any.
    public var commit: String?
    /// The composition (what the user has typed so far, shown above the candidates).
    public var preedit: String = ""
    /// Caret position in `preedit`, in characters.
    public var cursor: Int = 0
    public var selectionStart: Int = 0
    public var selectionEnd: Int = 0
    /// Candidates from the top of the list, at most `RimeService.Configuration.maxCandidates`.
    public var candidates: [RimeCandidate] = []
    /// Index of the highlighted candidate in `candidates`.
    public var highlighted: Int = 0
    public var pageNumber: Int = 0
    public var pageSize: Int = 0
    public var isLastPage: Bool = true
    public var isComposing: Bool = false
    public var asciiMode: Bool = false

    public init() {}
}

public struct RimeServiceConfiguration: Equatable, Sendable {
    public var sharedDataDirectory: String
    public var userDataDirectory: String
    public var maxCandidates: Int
    /// `nil` loads everything that is linked in; the keyboard passes `RimeEngine.minimalModules`.
    public var modules: [String]?
    /// Schema to select after the session is created (`nil` keeps the first of schema_list).
    public var schemaID: String?

    public init(
        sharedDataDirectory: String,
        userDataDirectory: String,
        maxCandidates: Int = 30,
        modules: [String]? = RimeEngine.minimalModules,
        schemaID: String? = nil
    ) {
        self.sharedDataDirectory = sharedDataDirectory
        self.userDataDirectory = userDataDirectory
        self.maxCandidates = maxCandidates
        self.modules = modules
        self.schemaID = schemaID
    }
}
