// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The Rime composition the person is typing: what was typed, and what Rime shows for it.
public struct AiComposition: Equatable, Sendable {
    public var raw: String
    public var preedit: String

    public init(raw: String, preedit: String) {
        self.raw = raw
        self.preedit = preedit
    }
}

/// What the AI logic needs from the keyboard and the text around it (the document proxy on a device, a fake
/// in the tests). The proxy lags: after the keyboard inserted or deleted something, its `documentContext…`
/// catches up with the next `textDidChange`, so `valid`/adoption wait for that.
@MainActor
public protocol AiEditor: AnyObject {
    /// 中 mode (Rime `ascii_mode` off).
    var isChinese: Bool { get }
    var composition: AiComposition? { get }
    var contextBefore: String { get }
    var contextAfter: String { get }
    var selectedText: String? { get }
    var hasFullAccess: Bool { get }
    func clearComposition()
    func insert(_ text: String)
    func deleteBackward(_ count: Int)
}

/// The text the AI works on in one request, with what surrounded it when it was captured. A result is adopted
/// only while the same capture is still true.
public struct AiTarget: Equatable, Sendable {
    public var input: AiInput
    public var composing: Bool
    /// What a committed target replaces (the sentence before the caret, or the selection); empty when composing.
    public var original: String
    public var contextBefore: String
    public var contextAfter: String
    public var selection: String
    public var manual: Bool
}

/// Sentence capture for text that is already in the document: the last sentence before the caret.
///
/// The boundaries follow UAX #29 for the cases that matter on a keyboard: a terminator (`。！？!?`), a full stop
/// followed by white space, a line break. Closing quotes and brackets stay with their sentence and white space
/// after a terminator belongs to the sentence before it. Android uses `BreakIterator`; the rules are written
/// out here so the iOS keyboard and the Linux tests agree. The work is done on grapheme clusters, so a boundary
/// never cuts an emoji sequence or a combining mark.
public enum AiEditorRanges {
    private static let terminators: Set<Character> = ["。", "！", "？", "!", "?", "｡", "‼", "⁇", "⁈", "⁉"]
    private static let closers: Set<Character> = ["\"", "'", ")", "]", "}", "\u{201D}", "\u{2019}", "\u{300D}", "\u{300F}", "\u{FF09}", "\u{3011}", "\u{300B}"]

    /// The last sentence of `before` (up to the caret), if it is non-blank and no longer than `limit`
    /// characters; never truncated.
    public static func trailingSentence(in before: String, limit: Int) -> String? {
        let chars = Array(before)
        guard !chars.isEmpty else { return nil }
        var start = 0
        var index = 0
        while index < chars.count {
            let character = chars[index]
            var boundary: Int?
            if character.isNewline || terminators.contains(character) {
                boundary = index + 1
            } else if character == "." || character == "\u{FF0E}" {
                // A full stop ends a sentence only before white space (so 3.14 and a.b stay whole).
                var next = index + 1
                while next < chars.count, closers.contains(chars[next]) { next += 1 }
                if next < chars.count, chars[next].isWhitespace { boundary = next }
            }
            guard var next = boundary else { index += 1; continue }
            while next < chars.count, terminators.contains(chars[next]) || closers.contains(chars[next]) { next += 1 }
            var begin = next
            while begin < chars.count, chars[begin].isWhitespace { begin += 1 }
            if begin < chars.count { start = begin }
            index = max(next, index + 1)
        }
        let value = String(chars[start...])
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= limit else { return nil }
        return value
    }
}

private final class CallStore: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [RequestStamp: AiCall] = [:]

    func put(_ call: AiCall) {
        lock.lock(); defer { lock.unlock() }
        calls[call.request.stamp] = call
        if calls.count > 8 { calls = calls.filter { $0.key.inputRevision >= call.request.stamp.inputRevision - 4 } }
    }

    func take(_ stamp: RequestStamp) -> AiCall? {
        lock.lock(); defer { lock.unlock() }
        return calls.removeValue(forKey: stamp)
    }
}

/// The AI behaviour of the keyboard, a port of Android `AiKeyboardController` (1.12.1 rules):
///
/// * one request at a time; manual keys (assistant, emoji) take over any running request and late data of the
///   old one is dropped;
/// * background events (Rime echoing its state, the document changing under us) never start a request while a
///   manual request owns the bar (`manualHold`);
/// * a key press, a candidate tap or a caret move clears the hold;
/// * every request carries a stamp (editor session, input revision, config generation, keyboard generation);
///   a result is adopted only while its stamp is current and the capture is still true;
/// * automatic requests wait for the person to stop typing (debounce) and are kinds `纠错` (one candidate) or
///   `纠错 + 助手` (two); the emoji request asks for five.
///
/// Nothing is sent from a sensitive field or before the person consented.
@MainActor
public final class AiController {
    public enum Kind: Equatable, Sendable { case auto, assistant, emoji }

    public typealias Send = @Sendable (AiCall, @escaping @Sendable (AiResult) -> Void) async throws -> AiResult

    private let editor: AiEditor
    private let configProvider: () -> AiConfig
    private let credential: (AiConfig) -> String?
    private let parameters: (AiConfig) -> [String: JSONPrimitive]
    private let notice: (String) -> Void
    private let render: (AiBarState) -> Void
    private let calls = CallStore()
    private var coordinator: AiRequestCoordinator!

    // Android: session, revision, keyboardGeneration, chinese, active, sensitive, ...
    private var session: Int64 = 0
    private var revision: Int64 = 0
    private var keyboardGeneration: Int64 = 0
    private var chinese = true
    private var active = false
    private var sensitive = true
    private var suppress = false
    private var applying = false
    private var directTarget: AiTarget?
    private var target: AiTarget?
    private(set) var state: AiState = .idle
    private var ready: (request: AiRequest, result: AiResult)?
    private(set) var lastKind = Kind.auto
    private var emojiStamp: RequestStamp?
    private var manualHold = false
    private var awaitingStart = false
    private var captureTask: Task<Void, Never>?
    private var noticeText: String?
    private var noticeTask: Task<Void, Never>?
    private var expandedIndex: Int?
    private var observedContext = ""

    public init(editor: AiEditor, config: @escaping () -> AiConfig, credential: @escaping (AiConfig) -> String?,
                parameters: @escaping (AiConfig) -> [String: JSONPrimitive], send: @escaping Send,
                notice: @escaping (String) -> Void, render: @escaping (AiBarState) -> Void) {
        self.editor = editor
        self.configProvider = config
        self.credential = credential
        self.parameters = parameters
        self.notice = notice
        self.render = render
        let store = calls
        coordinator = AiRequestCoordinator(
            transport: { request, onPartial in
                guard let call = store.take(request.stamp) else { throw AiError.invalidConfiguration }
                return try await send(call, onPartial)
            },
            publish: { [weak self] update in self?.published(update) })
    }

    private var config: AiConfig { configProvider() }

    // MARK: events from the keyboard

    /// A text field was focused. `sensitive` is the verdict of the privacy rules for that field.
    public func start(sensitive: Bool) {
        session += 1; revision += 1; active = true; suppress = false; applying = false; manualHold = false
        directTarget = nil; target = nil; captureTask?.cancel(); commitTask?.cancel()
        chinese = editor.isChinese
        keyboardGeneration += 1
        self.sensitive = sensitive
        observedContext = editor.contextBefore + "\u{0}" + editor.contextAfter
        coordinator.invalidate()
        draw()
    }

    public func finish() {
        active = false; session += 1; revision += 1; manualHold = false
        captureTask?.cancel(); commitTask?.cancel(); coordinator.invalidate()
        target = nil; directTarget = nil
    }

    /// The configuration changed (the app wrote it): nothing running matches it any more.
    public func configChanged() {
        revision += 1
        coordinator.invalidate()
        if active && !suppress { refresh(manual: false) }
        draw()
    }

    /// A key, a candidate tap or anything else the person did: it ends a manual hold and drops what is running.
    public func userInput() {
        suppress = false; directTarget = nil; revision += 1; manualHold = false
        captureTask?.cancel(); commitTask?.cancel(); coordinator.invalidate()
    }

    /// Text was committed into the document (a candidate, a plain character). Starts an automatic request on it
    /// when the settings say so. The document proxy catches up with an insert only at the next `textDidChange`,
    /// so the capture waits (briefly) until the text before the caret ends with what was inserted.
    public func textCommitted(_ text: String) {
        directTarget = nil
        commitTask?.cancel()
        let c = config
        guard active, !sensitive, c.consent, !suppress, !applying, !manualHold, c.automatic,
              c.enabled || c.assistantEnabled, !text.isEmpty else { return }
        let session = self.session
        commitTask = Task { [weak self] in
            for _ in 0..<10 {
                guard let self, !Task.isCancelled else { return }
                if self.editor.contextBefore.hasSuffix(text) { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let self, !Task.isCancelled, self.session == session, self.active, !self.manualHold, !self.suppress, !self.applying else { return }
            self.directTarget = self.captureDirect(manual: false).flatMap { $0.input.input.hasSuffix(text) ? $0 : nil }
            if self.directTarget != nil {
                self.revision += 1
                self.refresh(manual: false)
            }
        }
    }

    private var commitTask: Task<Void, Never>?

    /// The document around the caret changed (`textDidChange`). If it was not us, the caret moved: a manual
    /// request no longer matches the text.
    public func contextChanged() {
        let context = editor.contextBefore + "\u{0}" + editor.contextAfter
        guard context != observedContext else { return }
        observedContext = context
        if let target, target.contextBefore + "\u{0}" + target.contextAfter == context { return }
        if let directTarget, directTarget.contextBefore + "\u{0}" + directTarget.contextAfter == context { return }
        manualHold = false
        directTarget = nil
        revision += 1
        captureTask?.cancel(); coordinator.invalidate()
    }

    /// Rime's state changed (composition, option, commit). While a manual request holds the bar this is only
    /// Rime echoing itself and must not replace the manual request.
    public func compositionChanged() {
        if applying || !active || manualHold { return }
        let language = editor.isChinese
        if language != chinese {
            chinese = language; keyboardGeneration += 1; suppress = false; directTarget = nil
        }
        revision += 1
        coordinator.invalidate()
        if !suppress { refresh(manual: false) }
    }

    // MARK: the AI keys

    public func requestAssistant() { request(.assistant) }
    public func requestEmoji() { request(.emoji) }

    public var isBusy: Bool { awaitingStart || state == .loading || ready?.result.streaming == true }

    private func request(_ kind: Kind) {
        let c = config
        if !active || sensitive {
            show("此输入框不允许发送到 AI")
        } else if !editor.hasFullAccess {
            show("AI 需要在系统设置里开启「允许完全访问」")
        } else if !c.consent {
            show("请先在橘脑一颗里允许使用云端 AI")
        } else if isBusy && kind == lastKind {
            // The same key again keeps its running request.
            show("AI 请求中，请稍候（长按可取消）")
        } else {
            // Any other key takes over: the running correction / assistant / emoji request is cancelled and its
            // late replies are dropped.
            lastKind = kind; awaitingStart = true
            // Until the person types, edits or moves the caret, background Rime and editor events must not
            // start an automatic request that would replace this one.
            manualHold = true
            awaitingTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard let self, !Task.isCancelled, self.awaitingStart else { return }
                self.awaitingStart = false
                self.draw()
            }
            revision += 1
            refresh(manual: true, emoji: kind == .emoji)
            draw()
        }
    }

    private var awaitingTask: Task<Void, Never>?

    /// Long press on an AI key.
    public func cancelRequest() {
        guard isBusy else { return }
        awaitingStart = false; manualHold = false; captureTask?.cancel(); coordinator.invalidate()
        show("已取消 AI 请求")
    }

    // MARK: capture

    private func capture(manual: Bool) -> AiTarget? {
        let c = config
        guard active, !sensitive, c.consent, manual || c.enabled || c.assistantEnabled, editor.hasFullAccess else { return nil }
        if let composition = editor.composition, !composition.raw.isEmpty {
            if composition.raw.count > c.targetLimit { return nil }
            // Segments Rime already confirmed are part of this composition, not surrounding text.
            let hasHan = composition.preedit.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
            var input = chinese && hasHan ? composition.preedit : composition.raw
            if c.wordSegmentation && chinese { input = input.replacingOccurrences(of: "'", with: " ") }
            let before = c.contextEnabled && c.beforeLength > 0 ? editor.contextBefore : ""
            let after = c.contextEnabled && c.afterLength > 0 ? editor.contextAfter : ""
            let snapshot = context(input, before: before, after: after, c: c)
            return AiTarget(input: snapshot, composing: true, original: "", contextBefore: editor.contextBefore,
                            contextAfter: editor.contextAfter, selection: "", manual: manual)
        }
        if !manual && directTarget == nil { return nil }
        guard let direct = captureDirect(manual: manual) else { return nil }
        return manual || direct == directTarget ? direct : nil
    }

    private func captureDirect(manual: Bool) -> AiTarget? {
        let c = config
        let before = editor.contextBefore
        let after = editor.contextAfter
        let selected = editor.selectedText ?? ""
        let original: String
        let precedingContext: String
        if !selected.isEmpty {
            // A selection is only worked on when the person asked (manual); the replacement is the selection.
            guard manual, selected.count <= c.targetLimit else { return nil }
            original = selected
            precedingContext = before
        } else {
            guard let sentence = AiEditorRanges.trailingSentence(in: before, limit: c.targetLimit) else { return nil }
            original = sentence
            precedingContext = String(before.dropLast(sentence.count))
        }
        let snapshot = context(original, before: precedingContext, after: after, c: c)
        return AiTarget(input: snapshot, composing: false, original: original, contextBefore: before, contextAfter: after,
                        selection: selected, manual: manual)
    }

    private func context(_ input: String, before: String, after: String, c: AiConfig) -> AiInput {
        AiStore.context(input, before: before, after: after, c: c)
    }

    // MARK: request

    private func refresh(manual: Bool, emoji: Bool = false) {
        captureTask?.cancel()
        coordinator.invalidate()
        captureTask = Task { [weak self] in
            await Task.yield()   // let the text and Rime state settle after the event that brought us here
            guard let self, !Task.isCancelled else { return }
            let c = self.config
            if !manual && !c.automatic { return }
            self.target = self.capture(manual: manual)
            guard let snapshot = self.target, !snapshot.input.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if manual && self.active { self.show("请先输入或选中文字") }
                self.awaitingStart = false
                self.draw()
                return
            }
            let assistant = manual || c.assistantEnabled
            if !manual { self.lastKind = .auto }
            let stamp = RequestStamp(editorSession: self.session, inputRevision: self.revision, promptGeneration: c.generation,
                                     keyboardGeneration: self.keyboardGeneration, apiGeneration: c.generation)
            let prompt = emoji ? PromptPackage.emojiPrompt : AiStore.systemPrompt(c, chinese: self.chinese, assistant: assistant)
            let request = AiRequest(stamp: stamp, input: snapshot.input, systemPrompt: prompt, completionEnabled: !emoji && c.completion,
                                    candidateCount: emoji ? 5 : c.candidateCount, outputTokenBudget: c.outputTokenBudget,
                                    assistantEnabled: assistant, maxCandidates: emoji ? 5 : 0)
            self.emojiStamp = emoji ? stamp : nil
            guard let key = self.credential(c) else {
                self.published(.failed(.authentication, AiFailure.authentication.label))
                return
            }
            self.calls.put(AiCall(endpoint: c.endpoint, key: key, model: c.model, timeoutMs: c.timeoutMs,
                                  parameters: self.parameters(c), provider: c.provider, request: request))
            self.coordinator.submit(request, enabled: true, sensitive: self.sensitive, debounceMs: manual ? 0 : c.debounceMs)
        }
    }

    private func published(_ update: AiState) {
        state = update
        if case .ready(let request, let result) = update { ready = (request, result) } else { ready = nil }
        if update != .idle { awaitingStart = false }
        draw()
    }

    // MARK: adoption

    /// True while the request is still the current one and the capture still matches the text.
    private func valid(_ result: (request: AiRequest, result: AiResult), _ snapshot: AiTarget) -> Bool {
        let c = config
        let current = RequestStamp(editorSession: session, inputRevision: revision, promptGeneration: c.generation,
                                   keyboardGeneration: keyboardGeneration, apiGeneration: c.generation)
        return active && !sensitive && c.consent && result.request.stamp == current && capture(manual: snapshot.manual) == snapshot
    }

    /// Adopts candidate `index`: composing, the composition is cleared and the text inserted; committed text is
    /// replaced (delete the original, insert the text) after checking that the text before the caret still ends
    /// with it; emoticons go after the text. Anything that does not check out is dropped, not guessed.
    public func adopt(_ index: Int) {
        guard let current = ready, let snapshot = target, current.result.candidates.indices.contains(index) else { return }
        let text = current.result.candidates[index]
        manualHold = false
        expandedIndex = nil
        guard ready?.request.stamp == current.request.stamp, valid(current, snapshot) else {
            coordinator.invalidate()
            return
        }
        applying = true; suppress = true; directTarget = nil; coordinator.invalidate()
        defer {
            applying = false
            revision += 1
            target = nil
            draw()
        }
        if snapshot.composing {
            editor.clearComposition()
            editor.insert(text)
        } else if current.request.stamp == emojiStamp {
            // Emoticons describe committed text, so they go after it instead of replacing it.
            editor.insert(text)
        } else if snapshot.selection.isEmpty {
            guard editor.contextBefore.hasSuffix(snapshot.original) else { return }
            editor.deleteBackward(snapshot.original.count)
            editor.insert(text)
        } else {
            guard editor.selectedText == snapshot.selection else { return }
            editor.insert(text)   // replaces the selection
        }
    }

    /// A tap on an AI candidate: a long one opens the full text first.
    public func itemTapped(_ index: Int) {
        guard let current = ready, current.result.candidates.indices.contains(index) else { return }
        if current.result.candidates[index].count > AiBarState.longTextLimit && current.request.stamp != emojiStamp {
            expandedIndex = index
            draw()
        } else {
            adopt(index)
        }
    }

    public func dismissExpanded() {
        expandedIndex = nil
        draw()
    }

    // MARK: drawing

    private func show(_ text: String) {
        noticeText = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.noticeText = nil
            self.draw()
        }
        notice(text)
        draw()
    }

    /// The status the bar shows, like the Android indicator.
    var indicator: String {
        let c = config
        if sensitive { return "隐私字段" }
        if !editor.hasFullAccess { return "需要完全访问" }
        if !c.consent { return "未授权" }
        if state == .loading { return "请求中…" }
        if case .failed(_, let detail) = state { return detail }
        if let result = ready?.result {
            if !result.streamError.isEmpty { return "部分返回" }
            if result.streaming { return "生成中…" }
            return "已返回"
        }
        if !c.automatic || (!c.enabled && !c.assistantEnabled) { return "手动触发" }
        return "待请求"
    }

    public func draw() {
        var bar = AiBarState()
        let c = config
        bar.indicator = indicator
        bar.enabled = active && !sensitive && editor.hasFullAccess && c.consent
        bar.busy = isBusy
        bar.emojiShown = lastKind == .emoji
        bar.expandedIndex = expandedIndex
        let failed: Bool
        if case .failed = state { failed = true } else { failed = false }
        if sensitive || !c.consent || !editor.hasFullAccess {
            bar.phase = .idle
        } else if failed || ready?.result.streamError.isEmpty == false {
            bar.phase = .failed
        } else if state == .loading || awaitingStart {
            bar.phase = .waiting
        } else if ready?.result.streaming == true {
            bar.phase = .streaming
        } else if ready != nil {
            bar.phase = .done
        }
        if let noticeText {
            bar.hint = noticeText
        } else if !editor.hasFullAccess {
            bar.hint = "AI 需要在系统设置里开启「允许完全访问」"
        } else if sensitive {
            bar.hint = "隐私字段：不发送 AI"
        } else if !c.consent {
            bar.hint = "未授权：在橘脑一颗里允许云端 AI"
        }
        if bar.hint == nil, let current = ready {
            let isEmoji = current.request.stamp == emojiStamp
            if isEmoji {
                bar.items = current.result.candidates.map { AiBarState.Item(role: "", text: $0, isEmoji: true) }
                if current.result.streaming { bar.placeholder = "表情生成中…" }
            } else {
                let roles = current.request.assistantEnabled
                bar.items = current.result.candidates.enumerated().map { index, text in
                    AiBarState.Item(role: roles ? (index == 0 ? "纠错" : "助手") : "", text: text)
                }
                if roles && current.result.candidates.count == 1 {
                    bar.placeholder = current.result.streaming ? "助手：生成中…" : "助手：未完成"
                }
                if !current.result.completion.trimmingCharacters(in: .whitespaces).isEmpty {
                    bar.items.append(AiBarState.Item(role: "补全", text: current.result.completion))
                }
            }
        }
        render(bar)
    }
}
