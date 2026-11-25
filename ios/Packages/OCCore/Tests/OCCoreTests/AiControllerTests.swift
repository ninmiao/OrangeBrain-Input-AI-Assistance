// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import OCCore

/// A document proxy that behaves like the real one: `documentContext…` is nil when empty, lags behind inserts
/// until `settle()` (the next `textDidChange`), and `deleteBackward` removes one grapheme cluster.
@MainActor
final class FakeEditor: AiEditor {
    var isChinese = true
    var composition: AiComposition?
    var hasFullAccess = true
    var selectedText: String?
    /// The document as it really is.
    private(set) var before = ""
    private(set) var after = ""
    /// What the proxy reports (stale until `settle()`).
    private var visibleBefore = ""
    private var visibleAfter = ""
    var lag = false
    var cleared = 0
    var inserted: [String] = []

    var contextBefore: String { visibleBefore }
    var contextAfter: String { visibleAfter }

    func setDocument(before: String, after: String = "") {
        self.before = before
        self.after = after
        settle()
    }

    func settle() {
        visibleBefore = before
        visibleAfter = after
    }

    func clearComposition() { composition = nil; cleared += 1 }

    func insert(_ text: String) {
        before += text
        inserted.append(text)
        if !lag { settle() }
    }

    func deleteBackward(_ count: Int) {
        for _ in 0..<count where !before.isEmpty { before.removeLast() }
        if !lag { settle() }
    }
}

@MainActor
final class AiControllerTests: XCTestCase {
    private var editor = FakeEditor()
    private var transport = ScriptedTransport()
    private var config = AiConfig()
    private var bars: [AiBarState] = []
    private var notices: [String] = []
    private var controller: AiController!
    private var calls: [AiCall] { calls_.value }
    private let calls_ = CallLog()

    final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [AiCall] = []
        var value: [AiCall] { lock.lock(); defer { lock.unlock() }; return items }
        func append(_ call: AiCall) { lock.lock(); items.append(call); lock.unlock() }
    }

    override func setUp() async throws {
        editor = FakeEditor()
        transport = ScriptedTransport()
        bars = []
        notices = []
        config = AiConfig()
        config.consent = true
        config.enabled = true
        config.assistantEnabled = true
        config.automatic = true
        config.debounceMs = 50
        let log = calls_
        let scripted = transport
        controller = AiController(
            editor: editor, config: { [unowned self] in self.config }, credential: { _ in "test-key" }, parameters: { _ in [:] },
            send: { call, onPartial in
                log.append(call)
                return try await scripted.call(call.request, onPartial)
            },
            notice: { [unowned self] in self.notices.append($0) }, render: { [unowned self] in self.bars.append($0) })
        controller.start(sensitive: false)
    }

    private var bar: AiBarState { bars.last ?? AiBarState() }

    private func compose(_ raw: String, preedit: String? = nil) {
        editor.composition = AiComposition(raw: raw, preedit: preedit ?? raw)
        controller.compositionChanged()
    }

    // MARK: automatic requests and the privacy / consent gates

    func testNothingIsSentWithoutConsentFromASensitiveFieldOrWithoutFullAccess() async {
        config.consent = false
        compose("nihao")
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(transport.count, 0, "no consent, nothing sent")

        config.consent = true
        controller.start(sensitive: true)
        compose("nihao")
        controller.requestEmoji()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(transport.count, 0, "a secure field never sends")
        XCTAssertEqual(bar.indicator, "隐私字段")

        controller.start(sensitive: false)
        editor.hasFullAccess = false
        compose("nihao")
        controller.requestAssistant()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(transport.count, 0, "without Full Access the AI controls are disabled")
        XCTAssertFalse(bar.enabled)
        XCTAssertNotNil(bar.hint)
    }

    func testACompositionStartsAnAutomaticCorrectionAfterTheDebounce() async {
        compose("woyaochihuogou")
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(transport.count, 0, "the debounce has not passed")
        let sent = await eventually { transport.count == 1 }
        XCTAssertTrue(sent)
        XCTAssertEqual(transport.requests[0].input.input, "woyaochihuogou")
        XCTAssertEqual(calls[0].key, "test-key")
        XCTAssertEqual(controller.lastKind, .auto)
        transport.complete(0, AiResult(candidates: ["我要吃火锅", "好啊"]))
        let shown = await eventually { bar.items.count == 2 }
        XCTAssertTrue(shown)
        XCTAssertEqual(bar.items.map(\.role), ["纠错", "助手"])
        XCTAssertEqual(bar.phase, .done)
    }

    // MARK: the 1.12.1 rules

    func testAManualAssistantKeyTakesOverTheRunningAutomaticRequestAndItsLateDataIsDropped() async {
        compose("nihao")
        _ = await eventually { transport.count == 1 }
        let autoPartial = transport.pending(at: 0)!.onPartial
        controller.requestAssistant()
        _ = await eventually { transport.count == 2 }
        XCTAssertEqual(controller.lastKind, .assistant)
        autoPartial(AiResult(candidates: ["from the old request"], streaming: true))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(bar.items.contains { $0.text == "from the old request" }, "late data of the replaced request must not show")
        transport.complete(0, AiResult(candidates: ["你好", "你好呀"]))
        let shown = await eventually { bar.items.map(\.text) == ["你好", "你好呀"] }
        XCTAssertTrue(shown, "\(bar)")
    }

    func testTheEmojiKeyTakesOverARunningAssistantRequestAndTheLateAssistantDataIsDropped() async {
        editor.setDocument(before: "我要吃火锅")
        controller.requestAssistant()
        _ = await eventually { transport.count == 1 }
        XCTAssertEqual(transport.requests[0].assistantEnabled, true)
        let assistantPartial = transport.pending(at: 0)!.onPartial
        transport.partial(0, AiResult(candidates: ["我要吃火锅"], streaming: true))
        _ = await eventually { bar.items.count == 1 }

        controller.requestEmoji()
        _ = await eventually { transport.count == 2 }
        XCTAssertEqual(controller.lastKind, .emoji)
        XCTAssertEqual(transport.requests[1].systemPrompt, PromptPackage.emojiPrompt)
        XCTAssertEqual(transport.requests[1].maxCandidates, 5)
        // The assistant's stream is still talking: its data must be dropped.
        assistantPartial(AiResult(candidates: ["我要吃火锅", "好啊，一起去"], streaming: true))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(bar.items.contains { $0.text.contains("一起去") }, "the late assistant data must not reach the bar")

        let emoji = ["(≧▽≦)", "(｡•̀ᴗ-)", "٩(◕‿◕｡)۶", "(^_^)", "😋"]
        transport.complete(0, AiResult(candidates: emoji))
        let shown = await eventually { bar.items.map(\.text) == emoji }
        XCTAssertTrue(shown, "\(bar)")
        XCTAssertTrue(bar.items.allSatisfy(\.isEmoji))
        XCTAssertTrue(bar.emojiShown)
        // Late assistant data after the emoji result is dropped as well.
        assistantPartial(AiResult(candidates: ["too late"], streaming: false))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(bar.items.map(\.text), emoji)
    }

    func testPressingTheSameKeyAgainKeepsTheRunningRequest() async {
        editor.setDocument(before: "你好")
        controller.requestAssistant()
        _ = await eventually { transport.count == 1 }
        controller.requestAssistant()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(transport.count, 1, "the same key again keeps its running request")
        XCTAssertTrue(notices.contains { $0.contains("请稍候") })
    }

    func testBackgroundEventsNeverReplaceAManualRequest() async {
        compose("nihao")
        _ = await eventually { transport.count == 1 }
        controller.requestEmoji()
        _ = await eventually { transport.count == 2 }
        // Rime echoes its own state and the document reports itself: neither may start a request.
        controller.compositionChanged()
        controller.compositionChanged()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(transport.count, 2, "background events must not start requests while a manual one owns the bar")
        XCTAssertEqual(controller.lastKind, .emoji)
    }

    func testAKeyPressAndACandidateTapEndTheManualHoldAndDropTheRequest() async {
        compose("nihao")
        _ = await eventually { transport.count == 1 }
        controller.requestAssistant()
        _ = await eventually { transport.count == 2 }
        controller.userInput()     // a key press or a candidate tap
        XCTAssertFalse(controller.isBusy)
        compose("nihaoa")          // the hold is gone: Rime's change starts an automatic request again
        let sent = await eventually { transport.count == 3 }
        XCTAssertTrue(sent)
        XCTAssertEqual(controller.lastKind, .auto)
    }

    func testACaretMoveFromOutsideClearsTheHold() async {
        editor.setDocument(before: "我要吃火锅")
        controller.requestAssistant()
        _ = await eventually { transport.count == 1 }
        transport.complete(0, AiResult(candidates: ["我要吃火锅。", "好"]))
        _ = await eventually { bar.items.count == 2 }
        // Not us: the text around the caret changed (the person moved the caret or typed elsewhere).
        editor.setDocument(before: "我要", after: "吃火锅")
        controller.contextChanged()
        controller.adopt(0)
        XCTAssertTrue(editor.inserted.isEmpty, "after the caret moved, the old result must not be adopted")
        XCTAssertEqual(editor.before, "我要")
    }

    func testAResultOfAnOlderRevisionIsNeverAdopted() async {
        editor.setDocument(before: "我要吃火锅")
        controller.requestAssistant()
        _ = await eventually { transport.count == 1 }
        transport.complete(0, AiResult(candidates: ["我要吃火锅。"]))
        _ = await eventually { bar.items.count == 1 }
        controller.userInput()      // revision moves on
        controller.adopt(0)
        XCTAssertTrue(editor.inserted.isEmpty)
        config.generation += 1      // the app changed the configuration
        controller.configChanged()
        controller.adopt(0)
        XCTAssertTrue(editor.inserted.isEmpty)
    }

    // MARK: adoption

    func testAdoptingWhileComposingClearsTheCompositionThenInserts() async {
        compose("woyaochihuogou")
        _ = await eventually { transport.count == 1 }
        transport.complete(0, AiResult(candidates: ["我要吃火锅"]))
        _ = await eventually { bar.items.count == 1 }
        controller.adopt(0)
        XCTAssertEqual(editor.cleared, 1)
        XCTAssertEqual(editor.inserted, ["我要吃火锅"])
        XCTAssertEqual(editor.before, "我要吃火锅")
    }

    func testAdoptingCommittedTextReplacesTheSentenceAfterCheckingTheProxy() async {
        editor.setDocument(before: "你好。我要吃火锅")
        controller.requestAssistant()
        _ = await eventually { transport.count == 1 }
        XCTAssertEqual(transport.requests[0].input.input, "我要吃火锅", "the last sentence before the caret")
        XCTAssertEqual(transport.requests[0].input.before, "你好。")
        transport.complete(0, AiResult(candidates: ["我要吃火锅。", "好啊"]))
        _ = await eventually { bar.items.count == 2 }
        controller.adopt(0)
        XCTAssertEqual(editor.before, "你好。我要吃火锅。")
    }

    func testAdoptionAbortsWhenTheTextBeforeTheCaretNoLongerEndsWithTheOriginal() async {
        editor.setDocument(before: "我要吃火锅")
        controller.requestAssistant()
        _ = await eventually { transport.count == 1 }
        transport.complete(0, AiResult(candidates: ["我要吃火锅。"]))
        _ = await eventually { bar.items.count == 1 }
        // The proxy says something else than at capture time (a host that edits behind our back).
        editor.setDocument(before: "我要吃火")
        controller.adopt(0)
        XCTAssertEqual(editor.before, "我要吃火", "nothing is deleted or inserted when the check fails")
        XCTAssertTrue(editor.inserted.isEmpty)
    }

    func testEmoticonsGoAfterTheCommittedTextInsteadOfReplacingIt() async {
        editor.setDocument(before: "今天好开心")
        controller.requestEmoji()
        _ = await eventually { transport.count == 1 }
        transport.complete(0, AiResult(candidates: ["(≧▽≦)", "😋"]))
        _ = await eventually { bar.items.count == 2 }
        controller.adopt(0)
        XCTAssertEqual(editor.before, "今天好开心(≧▽≦)")
    }

    func testALongCandidateOpensTheFullTextBeforeItIsAdopted() async {
        editor.setDocument(before: "你好")
        controller.requestAssistant()
        _ = await eventually { transport.count == 1 }
        let long = String(repeating: "很长的助手回复。", count: 8)
        XCTAssertGreaterThan(long.count, AiBarState.longTextLimit)
        transport.complete(0, AiResult(candidates: ["你好。", long]))
        _ = await eventually { bar.items.count == 2 }
        XCTAssertTrue(bar.items[1].isLong)
        XCTAssertLessThan(bar.items[1].label.count, long.count, "the bar shows it cut")
        controller.itemTapped(1)
        XCTAssertEqual(bar.expandedIndex, 1, "a long candidate opens the full text first")
        XCTAssertTrue(editor.inserted.isEmpty)
        controller.adopt(1)
        XCTAssertEqual(editor.before.hasSuffix(long), true)
        XCTAssertNil(bar.expandedIndex)
    }

    func testALongPressCancelsTheRequest() async {
        editor.setDocument(before: "你好")
        controller.requestAssistant()
        _ = await eventually { transport.count == 1 }
        controller.cancelRequest()
        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(notices.contains { $0.contains("已取消") })
    }

    // MARK: the proxy lags

    func testAnAutomaticRequestAfterACommitWaitsForTheProxyToCatchUp() async {
        editor.lag = true
        editor.setDocument(before: "")
        editor.insert("我要吃火锅")      // the proxy still shows nothing
        controller.textCommitted("我要吃火锅")
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(transport.count, 0, "the capture must not use a stale proxy")
        editor.settle()               // textDidChange
        let sent = await eventually { transport.count == 1 }
        XCTAssertTrue(sent)
        XCTAssertEqual(transport.requests[0].input.input, "我要吃火锅")
    }

    // MARK: the sentence capture

    func testTrailingSentence() {
        XCTAssertEqual(AiEditorRanges.trailingSentence(in: "你好。我要吃火锅", limit: 300), "我要吃火锅")
        XCTAssertEqual(AiEditorRanges.trailingSentence(in: "no stop here", limit: 300), "no stop here")
        XCTAssertNil(AiEditorRanges.trailingSentence(in: "", limit: 300))
        XCTAssertNil(AiEditorRanges.trailingSentence(in: "   ", limit: 300))
        XCTAssertNil(AiEditorRanges.trailingSentence(in: String(repeating: "字", count: 301), limit: 300), "never truncates a target")
    }
}
