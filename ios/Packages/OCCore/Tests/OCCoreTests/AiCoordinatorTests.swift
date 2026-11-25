// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import OCCore

/// Polls until the condition holds (main actor); the AI logic hops through tasks and timers.
@MainActor
func eventually(timeout: TimeInterval = 5, _ message: @autoclosure () -> String = "condition", _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

/// A transport the test steers: every request waits until the test completes, fails or streams it.
final class ScriptedTransport: @unchecked Sendable {
    struct Pending {
        let request: AiRequest
        let continuation: CheckedContinuation<AiResult, Error>
        let onPartial: @Sendable (AiResult) -> Void
    }

    private let lock = NSLock()
    private var pendings: [Pending] = []
    private var started: [AiRequest] = []

    var requests: [AiRequest] { lock.lock(); defer { lock.unlock() }; return started }
    var count: Int { requests.count }

    var call: AiTransportCall {
        { [self] request, onPartial in
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    started.append(request)
                    pendings.append(Pending(request: request, continuation: continuation, onPartial: onPartial))
                    lock.unlock()
                }
            } onCancel: {
                self.cancelAll()
            }
        }
    }

    private func cancelAll() {
        lock.lock()
        let all = pendings
        pendings = []
        lock.unlock()
        for pending in all { pending.continuation.resume(throwing: CancellationError()) }
    }

    func pending(at index: Int) -> Pending? {
        lock.lock(); defer { lock.unlock() }
        return pendings.indices.contains(index) ? pendings[index] : nil
    }

    func partial(_ index: Int, _ result: AiResult) { pending(at: index)?.onPartial(result) }

    func complete(_ index: Int, _ result: AiResult) {
        lock.lock()
        guard pendings.indices.contains(index) else { lock.unlock(); return }
        let pending = pendings.remove(at: index)
        lock.unlock()
        pending.continuation.resume(returning: result)
    }

    func fail(_ index: Int, _ error: Error) {
        lock.lock()
        guard pendings.indices.contains(index) else { lock.unlock(); return }
        let pending = pendings.remove(at: index)
        lock.unlock()
        pending.continuation.resume(throwing: error)
    }
}

@MainActor
final class AiRequestCoordinatorTests: XCTestCase {
    private var transport = ScriptedTransport()
    private var states: [AiState] = []
    private var coordinator: AiRequestCoordinator!

    override func setUp() async throws {
        transport = ScriptedTransport()
        states = []
        coordinator = AiRequestCoordinator(transport: transport.call, publish: { [unowned self] in self.states.append($0) })
    }

    private func request(_ input: String, revision: Int64 = 1) -> AiRequest {
        AiRequest(stamp: RequestStamp(editorSession: 1, inputRevision: revision, promptGeneration: 1, keyboardGeneration: 1, apiGeneration: 1),
                  input: AiInput(input: input), systemPrompt: "p")
    }

    private var last: AiState? { states.last }

    func testASubmittedRequestIsLoadingThenReady() async {
        let request = request("nihao")
        coordinator.submit(request, enabled: true, sensitive: false, debounceMs: 0)
        XCTAssertEqual(states, [.idle], "submit starts by invalidating")
        let started = await eventually { transport.count == 1 }
        XCTAssertTrue(started)
        XCTAssertEqual(last, .loading)
        transport.complete(0, AiResult(candidates: ["你好"]))
        let published = await eventually { last == .ready(request, AiResult(candidates: ["你好"])) }
        XCTAssertTrue(published, "\(states)")
    }

    func testAnewSubmitCancelsTheRunningRequestAndItsLateResultIsDropped() async {
        let first = request("one", revision: 1)
        coordinator.submit(first, enabled: true, sensitive: false, debounceMs: 0)
        _ = await eventually { transport.count == 1 }
        let firstPartial = transport.pending(at: 0)!.onPartial
        let second = request("two", revision: 2)
        coordinator.submit(second, enabled: true, sensitive: false, debounceMs: 0)
        _ = await eventually { transport.count == 2 }
        // The first request was cancelled by the second submit; data its transport still delivers is dropped.
        firstPartial(AiResult(candidates: ["late partial"], streaming: true))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotEqual(last, .ready(first, AiResult(candidates: ["late partial"], streaming: true)))
        transport.complete(0, AiResult(candidates: ["two"]))   // the second request is the one left
        let published = await eventually { last == .ready(second, AiResult(candidates: ["two"])) }
        XCTAssertTrue(published, "\(states)")
        XCTAssertFalse(states.contains { if case .ready(let r, _) = $0 { return r == first } else { return false } })
    }

    func testInvalidatePublishesIdleAndDropsLateData() async {
        let request = request("nihao")
        coordinator.submit(request, enabled: true, sensitive: false, debounceMs: 0)
        _ = await eventually { transport.count == 1 }
        coordinator.invalidate()
        XCTAssertEqual(last, .idle)
        transport.complete(0, AiResult(candidates: ["too late"]))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(last, .idle, "a result after invalidate must not be published")
    }

    func testTheDebounceDelaysTheSendAndInvalidateWithinItSendsNothing() async {
        coordinator.submit(request("a"), enabled: true, sensitive: false, debounceMs: 150)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(transport.count, 0, "nothing is sent while the debounce runs")
        coordinator.invalidate()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(transport.count, 0, "an invalidated request never reaches the network")

        coordinator.submit(request("b"), enabled: true, sensitive: false, debounceMs: 100)
        let sent = await eventually { transport.count == 1 }
        XCTAssertTrue(sent)
    }

    func testNothingIsSentWhenDisabledSensitiveOrBlank() async {
        coordinator.submit(request("x"), enabled: false, sensitive: false, debounceMs: 0)
        coordinator.submit(request("x"), enabled: true, sensitive: true, debounceMs: 0)
        coordinator.submit(request("   "), enabled: true, sensitive: false, debounceMs: 0)
        coordinator.submit(nil, enabled: true, sensitive: false, debounceMs: 0)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(transport.count, 0)
        XCTAssertEqual(last, .idle)
    }

    func testPartialResultsStreamIntoReadyUntilTheFinalOneAndLaterOnesAreDropped() async {
        let request = request("nihao")
        coordinator.submit(request, enabled: true, sensitive: false, debounceMs: 0)
        _ = await eventually { transport.count == 1 }
        let partial = AiResult(candidates: ["你"], streaming: true)
        transport.partial(0, partial)
        let streamed = await eventually { last == .ready(request, partial) }
        XCTAssertTrue(streamed, "\(states)")
        let final = AiResult(candidates: ["你好"])
        transport.complete(0, final)
        _ = await eventually { last == .ready(request, final) }
        // A partial that arrives after the final result (a straggler task) changes nothing.
        transport.partial(0, AiResult(candidates: ["straggler"], streaming: true))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(last, .ready(request, final))
    }

    func testFailuresAreCategorisedAndATimeoutNamesItsPhase() async {
        coordinator.submit(request("a", revision: 1), enabled: true, sensitive: false, debounceMs: 0)
        _ = await eventually { transport.count == 1 }
        transport.fail(0, AiError.http(401))
        let auth = await eventually { last == .failed(.authentication, "Key 无效") }
        XCTAssertTrue(auth, "\(states)")

        coordinator.submit(request("b", revision: 2), enabled: true, sensitive: false, debounceMs: 0)
        _ = await eventually { transport.count == 2 }
        transport.fail(0, AiError.timeout(.waiting))
        let timeout = await eventually { last == .failed(.timeout, "等待服务响应超时") }
        XCTAssertTrue(timeout, "\(states)")

        coordinator.submit(request("c", revision: 3), enabled: true, sensitive: false, debounceMs: 0)
        _ = await eventually { transport.count == 3 }
        transport.fail(0, AiError.http(429))
        let limited = await eventually { last == .failed(.rateLimit, "请求受限") }
        XCTAssertTrue(limited)
    }

    func testACancelledRequestPublishesNoFailure() async {
        coordinator.submit(request("a"), enabled: true, sensitive: false, debounceMs: 0)
        _ = await eventually { transport.count == 1 }
        coordinator.invalidate()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(states.contains { if case .failed = $0 { return true } else { return false } }, "\(states)")
    }
}
