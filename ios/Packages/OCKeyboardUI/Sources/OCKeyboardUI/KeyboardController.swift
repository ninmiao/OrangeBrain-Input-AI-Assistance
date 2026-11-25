// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import OCCore
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
    /// The longer candidate list of the expanded grid (asked for when the grid opens), nil otherwise.
    public var moreCandidates: [RimeCandidate]?
    /// Shown instead of the composition while nothing is composed: the dictionary cannot be used, the
    /// engine failed, the user dictionary is busy.
    public var notice: String?
    /// The AI row under the candidates.
    public var ai = AiBarState.disabled
    /// What the host field is (keyboard type, secure entry, capitalisation, ...).
    public var traits = TextTraits()

    public init() {}
}

/// Taps on the AI row, answered by the AI controller (`AiKeyboardController`).
public protocol AiBarHandler: AnyObject {
    func aiItemTapped(_ index: Int)
    func aiAssistantTapped()
    func aiEmojiTapped()
    func aiCancelTapped()
    func aiAdoptTapped(_ index: Int)
    func aiDismissExpanded()
}

/// What the AI logic wants to hear from the keyboard (`AiKeyboardController`). All calls come on the main
/// thread.
public protocol KeyboardAiEvents: AnyObject {
    /// A key, a candidate tap or anything else the person did.
    func keyboardUserInput()
    /// Text went into the document (a commit from Rime, a plain character, a symbol).
    func keyboardCommitted(_ text: String)
    /// Rime composition or candidates changed.
    func keyboardCompositionChanged()
}

/// Start-up numbers for the CI report: how long after the keyboard appeared the engine was ready and the
/// first candidates were on screen.
public struct KeyboardTimings: Equatable, Sendable {
    public var engineReadyMs: Double?
    public var firstCandidatesMs: Double?
}

/// Input logic: turns taps into text for the document and into key events for Rime
/// (docs/IOS_PLAN.md section 2). Main thread only.
///
/// Every Rime call is asynchronous. A key is sent to the engine queue at once and the screen shows what was
/// typed (letters waiting for their answer) without waiting; answers arrive in the order the keys were sent,
/// every commit is inserted in that order, and only the answer to the newest operation is rendered. While the
/// engine is still starting (the first start after the keyboard appeared takes a while on a phone) the keys
/// simply queue behind it: a letter never goes into the document as plain text in 中 mode, except when the
/// engine cannot start at all (then the person is told and the letters are counted).
public final class KeyboardController {
    public private(set) var state = KeyboardState() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((KeyboardState) -> Void)?
    /// Called after text was inserted or removed (the keyboard extension uses it to
    /// refresh its diagnostics a little later).
    public var onActivity: (() -> Void)?
    public weak var aiHandler: AiBarHandler?
    public weak var aiEvents: KeyboardAiEvents?
    /// Letters that went into the document as plain text although 中 mode (or the dictionary) was meant:
    /// Rime did not take them, or there was no working engine. The CI gate requires 0.
    public private(set) var unhandledLetters = 0
    public private(set) var timings = KeyboardTimings()
    /// True once the engine reported ready after the keyboard appeared.
    public private(set) var engineReady = false

    private var service: RimeService?
    private var output: KeyboardTextOutput?
    /// Tells changes made by the host from changes made by the keyboard (a composition is dropped when the
    /// person moves the caret).
    private var hostTracker = HostChangeTracker()
    /// The language before a Latin-only field (email, URL, password, digits) switched the keyboard to EN.
    private var modeBeforeForcing: InputMode?
    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var lastShiftTap: TimeInterval = -.infinity
    /// Two taps on shift within this time (in seconds of touch time) lock caps.
    static let doubleTapInterval: TimeInterval = 0.4

    // Async bookkeeping.
    private enum Outstanding: Equatable {
        case letter(Character)
        case backspace
        case other
    }
    private var outstanding: [Outstanding] = []
    private var issued = 0
    private var completed = 0
    /// Bumped when the service is replaced or the screen state is reset: answers of older epochs commit text
    /// but are not rendered.
    private var epoch = 0
    private var lastApplied = RimeUpdate()
    private var shownAt: Date?
    /// True while the keyboard is English only because there is no engine at all.
    private var englishOnlyBecauseNoEngine = false

    public init(service: RimeService?, output: KeyboardTextOutput?, notice: String? = nil) {
        self.service = service
        self.output = output
        state.notice = service == nil ? (notice ?? "没有找到词库，当前只能输入英文") : notice
        if service == nil {
            state.mode = .english
            englishOnlyBecauseNoEngine = true
        }
    }

    public func attach(output: KeyboardTextOutput?) {
        self.output = output
    }

    /// Swaps the engine front door (data found, user directory changed). Clears the
    /// composition; a `nil` service turns the keyboard into a plain English one.
    public func setService(_ service: RimeService?, notice: String? = nil) {
        let old = self.service
        self.service = service
        engineReady = false
        resetComposition()
        state.notice = service == nil ? (notice ?? "没有找到词库，当前只能输入英文") : nil
        if service == nil {
            state.mode = .english
            englishOnlyBecauseNoEngine = true
        } else if englishOnlyBecauseNoEngine {
            englishOnlyBecauseNoEngine = false
            state.mode = .chinese
            state.shift = .off
            service?.setAsciiMode(false) { _ in }
        } else if state.mode == .english {
            service?.setAsciiMode(true) { _ in }
        }
        if service != nil, state.traits.forcesEnglish, state.mode == .chinese {
            modeBeforeForcing = .chinese
            state.mode = .english
            service?.setAsciiMode(true) { _ in }
        }
        if let old, old !== service { old.deactivate() }
    }

    public var rimeService: RimeService? { service }

    public func setAi(_ ai: AiBarState) { state.ai = ai }

    // MARK: what the AI logic reads and does

    /// The composition for the AI logic: what was typed and what Rime shows for it.
    public var aiComposition: AiComposition? {
        guard state.isComposing, !lastApplied.rawInput.isEmpty else { return nil }
        return AiComposition(raw: lastApplied.rawInput, preedit: state.composition)
    }

    public var isChineseMode: Bool { state.mode == .chinese }

    /// Inserts text for the AI logic (an adopted candidate): not a key press, nothing to tell the AI about.
    public func insertForAi(_ text: String) {
        output?.insertText(text)
        hostTracker.ownChange(now: Self.now())
        onActivity?()
    }

    public func deleteForAi(_ count: Int) {
        for _ in 0..<max(count, 0) {
            output?.deleteBackward()
            hostTracker.ownChange(now: Self.now())
        }
        onActivity?()
    }

    // MARK: the host field

    /// The host moved to another field (or the keyboard appeared): the traits decide the language, the panel,
    /// the capitals and the return key. A field of the same kind keeps the language the person chose.
    public func setTraits(_ traits: TextTraits, contextBefore: String?, contextAfter: String?) {
        let old = state.traits
        state.traits = traits
        hostTracker.reset(before: contextBefore, after: contextAfter)
        // Latin-only fields (email, URL, password, digits) switch to EN and the language comes back afterwards.
        if traits.forcesEnglish {
            if !old.forcesEnglish { modeBeforeForcing = state.mode }
            if state.mode == .chinese, service != nil { setMode(.english) }
        } else if old.forcesEnglish, let saved = modeBeforeForcing {
            modeBeforeForcing = nil
            if saved != state.mode, service != nil { setMode(saved) }
        }
        if traits.isNumericPad {
            state.panel = .numeric
        } else if traits.layout == .numbersAndPunctuation && old.layout != .numbersAndPunctuation {
            state.panel = .numbers
        } else if state.panel == .numeric {
            state.panel = .letters
        }
        if old.capitalization != traits.capitalization, state.shift != .locked { state.shift = .off }
        applyAutoCapitalization(before: contextBefore)
    }

    /// The host reported a change (`textDidChange`, `selectionDidChange`). A change the keyboard did not make
    /// while something is being composed means the person moved the caret or edited elsewhere: the composition
    /// no longer belongs to that place and is dropped (Android does the same). The traits are read again too
    /// (the host may change them without changing the field).
    public func hostContextChanged(traits: TextTraits, contextBefore: String?, contextAfter: String?) {
        let external = hostTracker.observe(before: contextBefore, after: contextAfter, now: Self.now())
        var comparable = traits
        comparable.hasText = state.traits.hasText
        if comparable != state.traits {
            setTraits(traits, contextBefore: contextBefore, contextAfter: contextAfter)
        } else {
            // Only "has text" changed (the field filled or emptied): the return key may follow, nothing else.
            if traits.hasText != state.traits.hasText { state.traits.hasText = traits.hasText }
            applyAutoCapitalization(before: contextBefore)
        }
        if external, composingNow { clearComposition() }
    }

    private func applyAutoCapitalization(before: String?) {
        guard state.mode == .english else { return }
        switch state.traits.capitalization {
        case .allCharacters:
            if state.shift != .locked { state.shift = .locked }
        case .none:
            break
        case .words, .sentences:
            if state.shift == .locked { return }
            let target: ShiftState = AutoCapitalization.wantsShift(state.traits.capitalization, before: before) ? .once : .off
            if state.shift != target { state.shift = target }
        }
    }

    func aiItemTapped(_ index: Int) { aiHandler?.aiItemTapped(index) }
    func aiAssistantTapped() { aiHandler?.aiAssistantTapped() }
    func aiEmojiTapped() { aiHandler?.aiEmojiTapped() }
    func aiCancelTapped() { aiHandler?.aiCancelTapped() }
    func aiAdoptTapped(_ index: Int) { aiHandler?.aiAdoptTapped(index) }
    func aiDismissExpanded() { aiHandler?.aiDismissExpanded() }

    // MARK: lifecycle

    /// The keyboard appeared: asks for the engine and the session in the background. Keys typed before it is
    /// ready are queued behind it.
    public func prepare() {
        guard let started = service else { return }
        engineReady = false
        shownAt = Date()
        timings = KeyboardTimings()
        started.start { [weak self] error in
            guard let self, self.service === started else { return }
            if let shownAt = self.shownAt { self.timings.engineReadyMs = Date().timeIntervalSince(shownAt) * 1000 }
            if let error {
                self.state.notice = "词库载入失败，字母会按原样输入（\(error)）"
            } else {
                self.engineReady = true
                if started.userDictionaryMode == .busy {
                    self.state.notice = "用户词库正被另一个窗口使用，这次不记忆新词"
                } else if self.state.notice != nil && !self.englishOnlyBecauseNoEngine {
                    self.state.notice = nil
                }
            }
        }
    }

    /// The keyboard went away: the session is closed, which flushes and closes the user dictionary.
    public func deactivate() {
        epoch += 1
        outstanding = []
        engineReady = false
        resetScreen()
        service?.deactivate()
    }

    public func handleMemoryWarning() {
        service?.handleMemoryWarning()
    }

    // MARK: keys

    /// `timestamp` is when the touch happened (UITouch clock); it only matters for double taps.
    func handle(_ action: KeyAction, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        aiEvents?.keyboardUserInput()
        switch action {
        case .character(let text): tapCharacter(text)
        case .space: tapSpace()
        case .enter: tapReturn()
        case .delete: tapDelete()
        case .shift: tapShift(at: timestamp)
        case .panel(let panel): show(panel)
        case .language: toggleLanguage()
        case .globe: break   // handled by the view controller (input mode list)
        }
    }

    /// Something is being composed, or a key that starts a composition is on its way to the engine.
    private var composingNow: Bool { state.isComposing || outstanding.contains { if case .letter = $0 { return true } else { return false } } }

    /// A key from the letters panel or the symbol panels.
    func tapCharacter(_ text: String) {
        let isLetter = text.count == 1 && text.unicodeScalars.allSatisfy { ("a"..."z").contains(Character($0)) || ("A"..."Z").contains(Character($0)) }
        if state.panel == .letters, isLetter, state.mode == .chinese, service != nil,
           let letter = text.lowercased().first, let key = RimeKey.character(letter) {
            send(key, outstanding: .letter(letter), rawFallback: text)
            return
        }
        // 中 mode: punctuation goes through Rime's punctuator (full-width marks, paired quotes, candidate lists),
        // like on Android. If Rime does not take the key the character is inserted as it is.
        if state.mode == .chinese, service != nil, text.count == 1, let scalar = text.unicodeScalars.first,
           scalar.isASCII, !isLetter, !("0"..."9").contains(Character(scalar)), let key = RimeKey.character(Character(scalar)) {
            send(key, outstanding: .other, rawFallback: text)
            return
        }
        // Everything else is plain text; a composition on its way is committed first, and the text follows
        // that commit (the answers arrive in order).
        if isLetter, englishOnlyBecauseNoEngine { unhandledLetters += 1 }
        if composingNow, service != nil {
            commitFirstCandidate(then: { [weak self] in self?.insert(text) })
        } else {
            insert(text)
        }
        if state.mode == .english, state.shift == .once, isLetter { state.shift = .off }
    }

    func tapSpace() {
        if composingNow, let service {
            send(.space, outstanding: .other, rawFallback: nil, service: service)
        } else {
            insert(" ")
        }
    }

    func tapReturn() {
        guard state.traits.returnEnabled || composingNow else { return }
        if composingNow, service != nil {
            // Return confirms the typed letters as they are (Rime commits the raw input).
            send(.enter, outstanding: .other, rawFallback: nil)
        } else {
            insert("\n")
        }
    }

    func tapDelete() {
        if composingNow, service != nil {
            send(.backspace, outstanding: .backspace, rawFallback: nil)
        } else {
            output?.deleteBackward()
            hostTracker.ownChange(now: Self.now())
            onActivity?()
        }
    }

    func tapShift(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard state.mode == .english else { return }
        defer { lastShiftTap = now }
        let isDoubleTap = now - lastShiftTap < Self.doubleTapInterval
        switch state.shift {
        case .locked:
            state.shift = .off
        case .once:
            state.shift = isDoubleTap ? .locked : .off
        case .off:
            state.shift = isDoubleTap ? .locked : .once
        }
    }

    func show(_ panel: Panel) {
        // The pad of a digits-only field is the only panel there.
        guard state.panel != .numeric else { return }
        state.panel = panel
    }

    func toggleLanguage() {
        guard service != nil, !state.traits.forcesEnglish else { return }
        setMode(state.mode == .chinese ? .english : .chinese)
    }

    /// Switches 中 / EN: drops what is being composed and tells Rime.
    private func setMode(_ next: InputMode) {
        guard let service else { return }
        epoch += 1
        outstanding = []
        service.clear { _ in }
        service.setAsciiMode(next == .english) { _ in }
        state.mode = next
        state.shift = .off
        resetScreen()
        applyAutoCapitalization(before: output?.contextBefore)
        aiEvents?.keyboardCompositionChanged()
    }

    // MARK: candidates

    public func selectCandidate(at index: Int) {
        guard let service, state.candidates.indices.contains(index) else { return }
        aiEvents?.keyboardUserInput()
        let expected = state.candidates[index].text
        issued += 1
        let myEpoch = epoch
        service.select(candidateAt: index, expecting: expected) { [weak self] update in
            self?.answered(update, epoch: myEpoch, letter: nil, rawFallback: nil)
        }
    }

    /// The expanded grid wants every candidate Rime offers (the bar only holds the first few).
    public func expandCandidates() {
        guard let service, state.isComposing else { return }
        let myEpoch = epoch
        service.refresh(limit: 120) { [weak self] update in
            guard let self, myEpoch == self.epoch, self.completed == self.issued, update.isComposing else { return }
            self.state.moreCandidates = update.candidates
        }
    }

    public func collapseCandidates() {
        state.moreCandidates = nil
    }

    public func clearComposition() {
        guard state.isComposing || !outstanding.isEmpty else { return }
        epoch += 1
        outstanding = []
        resetScreen()
        service?.clear { _ in }
        aiEvents?.keyboardCompositionChanged()
    }

    // MARK: engine lifecycle

    /// The engine is restarted (deployment changed, memory) without losing the screen state.
    public func resetComposition() {
        epoch += 1
        outstanding = []
        resetScreen()
    }

    private func resetScreen() {
        state.composition = ""
        state.candidates = []
        state.isComposing = false
        state.highlighted = 0
        lastApplied = RimeUpdate()
    }

    // MARK: sending to the engine and handling the answers

    private func send(_ key: RimeKey, outstanding op: Outstanding, rawFallback: String?, service explicit: RimeService? = nil) {
        guard let service = explicit ?? self.service else { return }
        issued += 1
        outstanding.append(op)
        showOptimistic()
        let myEpoch = epoch
        var typedLetter: Character?
        if case .letter(let letter) = op { typedLetter = letter }
        service.process(key) { [weak self] update in
            self?.answered(update, epoch: myEpoch, letter: typedLetter, rawFallback: rawFallback)
        }
    }

    private func answered(_ update: RimeUpdate, epoch answeredEpoch: Int, letter: Character?, rawFallback: String?,
                          then: (() -> Void)? = nil) {
        completed += 1
        if answeredEpoch == epoch, !outstanding.isEmpty { outstanding.removeFirst() }
        if update.engineFailed {
            if state.notice == nil || !state.notice!.hasPrefix("输入引擎") {
                state.notice = "输入引擎没有启动，字母会按原样输入"
            }
        }
        if let commit = update.commit {
            insert(commit)
        } else if !update.handled, let fallback = rawFallback {
            // Rime did not take the key (or there was no engine): the person must not lose it. A letter that
            // falls through counts against the gate.
            if letter != nil { unhandledLetters += 1 }
            insert(fallback)
        }
        then?()
        guard answeredEpoch == epoch else { return }
        lastApplied = update
        if completed == issued {
            apply(update)
        } else {
            showOptimistic()
        }
    }

    /// While answers are outstanding the screen shows what was typed: the engine's last composition (as
    /// letters) with the waiting keys applied.
    private func showOptimistic() {
        var letters = Array(lastApplied.rawInput)
        for op in outstanding {
            switch op {
            case .letter(let letter): letters.append(letter)
            case .backspace: if !letters.isEmpty { letters.removeLast() }
            case .other: break
            }
        }
        guard !outstanding.isEmpty else { return }
        state.composition = String(letters)
        state.isComposing = true
    }

    private func apply(_ update: RimeUpdate) {
        state.moreCandidates = nil
        state.composition = update.preedit
        state.candidates = update.candidates
        state.highlighted = update.highlighted
        state.isComposing = update.isComposing
        if !update.candidates.isEmpty, timings.firstCandidatesMs == nil, let shownAt {
            timings.firstCandidatesMs = Date().timeIntervalSince(shownAt) * 1000
        }
        aiEvents?.keyboardCompositionChanged()
    }

    // MARK: helpers

    /// Commits the first candidate (a symbol or digit was tapped while composing).
    private func commitFirstCandidate(then: @escaping () -> Void) {
        guard let service else { then(); return }
        let expected = state.candidates.first?.text
        issued += 1
        let myEpoch = epoch
        service.select(candidateAt: 0, expecting: expected) { [weak self] update in
            self?.answered(update, epoch: myEpoch, letter: nil, rawFallback: nil, then: then)
        }
    }

    private func insert(_ text: String) {
        output?.insertText(text)
        hostTracker.ownChange(now: Self.now())
        onActivity?()
        aiEvents?.keyboardCommitted(text)
    }
}
