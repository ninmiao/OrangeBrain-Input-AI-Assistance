// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import OCRime

/// What the keyboard view shows. The controller owns it and publishes changes.
public struct KeyboardState: Equatable {
    public var mode: InputMode = .chinese
    public var shift: ShiftState = .off
    public var panel: Panel = .letters
    /// The composition (pinyin typed so far).
    public var composition: String = ""
    public var candidates: [RimeCandidate] = []
    public var highlighted: Int = 0
    public var isComposing: Bool = false
    /// Set when the dictionary cannot be used; the keyboard then types like a plain
    /// English keyboard and shows this text.
    public var notice: String?

    public init() {}
}

/// Input logic: turns taps into text for the document and into key events for Rime
/// (docs/IOS_PLAN.md section 2, M1). Main thread only.
///
/// Rime calls go through `RimeService`, which runs them on its serial queue; the
/// controller uses the synchronous variants so that the result of one key is in
/// place before the next key is looked at (a key takes milliseconds).
public final class KeyboardController {
    public private(set) var state = KeyboardState() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((KeyboardState) -> Void)?
    /// Called after text was inserted or removed (the keyboard extension uses it to
    /// refresh its diagnostics a little later).
    public var onActivity: (() -> Void)?

    private var service: RimeService?
    private var output: KeyboardTextOutput?
    private var lastShiftTap = Date.distantPast
    /// Two taps on shift within this time lock caps.
    static let doubleTapInterval: TimeInterval = 0.35

    public init(service: RimeService?, output: KeyboardTextOutput?, notice: String? = nil) {
        self.service = service
        self.output = output
        state.notice = service == nil ? (notice ?? "没有找到词库，当前只能输入英文") : notice
        if service == nil { state.mode = .english }
    }

    public func attach(output: KeyboardTextOutput?) {
        self.output = output
    }

    /// Swaps the engine front door (data found, user directory changed). Clears the
    /// composition; a `nil` service turns the keyboard into a plain English one.
    public func setService(_ service: RimeService?, notice: String? = nil) {
        self.service = service
        resetComposition()
        state.notice = service == nil ? (notice ?? "没有找到词库，当前只能输入英文") : nil
        if service == nil {
            state.mode = .english
        } else if state.mode == .english {
            _ = service?.setAsciiModeSync(true)
        }
    }

    public var rimeService: RimeService? { service }

    /// Starts the engine in the background so the first key does not wait for it.
    public func prepare() {
        service?.start(completion: nil)
    }

    // MARK: keys

    func handle(_ action: KeyAction) {
        switch action {
        case .character(let text): tapCharacter(text)
        case .space: tapSpace()
        case .enter: tapReturn()
        case .delete: tapDelete()
        case .shift: tapShift()
        case .panel(let panel): show(panel)
        case .language: toggleLanguage()
        case .globe: break   // handled by the view controller (input mode list)
        }
    }

    /// A key from the letters panel or the symbol panels.
    func tapCharacter(_ text: String) {
        let isLetter = text.count == 1 && text.unicodeScalars.allSatisfy { ("a"..."z").contains(Character($0)) || ("A"..."Z").contains(Character($0)) }
        if state.panel == .letters, isLetter, state.mode == .chinese, let service,
           let key = text.lowercased().first.flatMap({ RimeKey.character($0) }) {
            let update = service.processSync(key)
            apply(update)
            if !update.handled && update.commit == nil { insert(text) }
            return
        }
        // Everything else is plain text; a pending composition is committed first.
        resolveComposition()
        insert(text)
        if state.mode == .english, state.shift == .once, isLetter { state.shift = .off }
    }

    func tapSpace() {
        if state.isComposing, let service {
            apply(service.processSync(.space))
        } else {
            insert(" ")
        }
    }

    func tapReturn() {
        if state.isComposing, let service {
            // Return confirms the typed letters as they are (Rime commits the raw input).
            apply(service.processSync(.enter))
        } else {
            insert("\n")
        }
    }

    func tapDelete() {
        if state.isComposing, let service {
            apply(service.processSync(.backspace))
        } else {
            output?.deleteBackward()
            onActivity?()
        }
    }

    func tapShift(now: Date = Date()) {
        guard state.mode == .english else { return }
        defer { lastShiftTap = now }
        switch state.shift {
        case .locked:
            state.shift = .off
        case .once:
            state.shift = now.timeIntervalSince(lastShiftTap) < Self.doubleTapInterval ? .locked : .off
        case .off:
            state.shift = now.timeIntervalSince(lastShiftTap) < Self.doubleTapInterval ? .locked : .once
        }
    }

    func show(_ panel: Panel) {
        state.panel = panel
    }

    func toggleLanguage() {
        guard service != nil else { return }
        let next: InputMode = state.mode == .chinese ? .english : .chinese
        if let service {
            _ = service.clearSync()
            _ = service.setAsciiModeSync(next == .english)
        }
        state.mode = next
        state.shift = .off
        state.composition = ""
        state.candidates = []
        state.isComposing = false
        state.highlighted = 0
    }

    // MARK: candidates

    public func selectCandidate(at index: Int) {
        guard let service, state.candidates.indices.contains(index) else { return }
        apply(service.selectSync(candidateAt: index))
    }

    public func clearComposition() {
        guard let service, state.isComposing else { return }
        apply(service.clearSync())
    }

    // MARK: engine lifecycle

    /// The engine is restarted (deployment changed, memory) without losing the screen state.
    public func resetComposition() {
        state.composition = ""
        state.candidates = []
        state.isComposing = false
        state.highlighted = 0
    }

    // MARK: helpers

    /// Commits the first candidate (a symbol or digit was tapped while composing).
    private func resolveComposition() {
        guard state.isComposing, let service else { return }
        apply(service.selectSync(candidateAt: 0))
    }

    private func insert(_ text: String) {
        output?.insertText(text)
        onActivity?()
    }

    private func apply(_ update: RimeUpdate) {
        if let commit = update.commit { insert(commit) }
        state.composition = update.preedit
        state.candidates = update.candidates
        state.highlighted = update.highlighted
        state.isComposing = update.isComposing
    }
}
