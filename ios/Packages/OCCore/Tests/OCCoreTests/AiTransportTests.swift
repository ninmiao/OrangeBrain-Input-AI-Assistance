// SPDX-License-Identifier: GPL-3.0-or-later
#if canImport(Darwin)
import Foundation
import XCTest
@testable import OCCore

/// A scripted server behind `URLSession` (no socket, no network): it answers with a status, then delivers the
/// chunks with delays, then finishes, stalls or breaks.
final class ScriptedServer: URLProtocol, @unchecked Sendable {
    struct Script {
        var status = 200
        var headers = ["Content-Type": "text/event-stream"]
        var chunks: [(delayMs: Int, data: Data)] = []
        /// false keeps the connection open without sending anything more.
        var finish = true
        var failure: URLError?
        /// true never answers at all (not even headers).
        var silent = false
        var redirectTo: URL?
    }

    private static let lock = NSLock()
    private static var script = Script()
    private static var seen: [URLRequest] = []
    private static var bodies: [Data] = []
    private static var stoppedCount = 0
    private static var deliveredCount = 0

    static func reset(_ script: Script) {
        lock.lock(); defer { lock.unlock() }
        self.script = script; seen = []; bodies = []; stoppedCount = 0; deliveredCount = 0
    }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    static var requestBodies: [Data] { lock.lock(); defer { lock.unlock() }; return bodies }
    static var stopped: Int { lock.lock(); defer { lock.unlock() }; return stoppedCount }
    static var delivered: Int { lock.lock(); defer { lock.unlock() }; return deliveredCount }

    private var cancelled = false
    private let state = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var isStopped: Bool { state.lock(); defer { state.unlock() }; return cancelled }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        Self.lock.lock()
        Self.seen.append(request)
        Self.bodies.append(body)
        let script = Self.script
        Self.lock.unlock()
        if script.silent { return }
        let url = request.url ?? URL(string: "https://invalid.example")!
        DispatchQueue.global().async { [self] in
            let response = HTTPURLResponse(url: url, statusCode: script.status, httpVersion: "HTTP/1.1", headerFields: script.headers)!
            if let target = script.redirectTo {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in script.chunks {
                if chunk.delayMs > 0 { Thread.sleep(forTimeInterval: Double(chunk.delayMs) / 1000) }
                if isStopped { return }
                client?.urlProtocol(self, didLoad: chunk.data)
                Self.lock.lock(); Self.deliveredCount += 1; Self.lock.unlock()
            }
            if let failure = script.failure {
                Thread.sleep(forTimeInterval: 0.3)   // a real connection breaks after the data was read
                client?.urlProtocol(self, didFailWithError: failure)
            } else if script.finish {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    override func stopLoading() {
        state.lock(); cancelled = true; state.unlock()
        Self.lock.lock(); Self.stoppedCount += 1; Self.lock.unlock()
    }
}

/// What a provider sends, in the three wire formats (copied from the shared core's own stream tests).
enum Wire {
    case openAI, openRouter, gemini

    var endpoint: String {
        switch self {
        case .openAI: return ApiRouting.openAI
        case .openRouter: return ApiRouting.openRouter
        case .gemini: return ApiRouting.gemini
        }
    }

    func event(_ object: [String: Any]) -> Data {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return Data(("data: " + String(decoding: data, as: UTF8.self) + "\r\n\r\n").utf8)
    }

    func start() -> Data {
        switch self {
        case .gemini:
            return Data(": heartbeat\r\n\r\n".utf8) + event(["event_type": "step.start", "index": 1, "step": ["type": "model_output", "content": [["type": "text", "text": ""]]]])
        default:
            return Data(": heartbeat\r\n\r\n".utf8)
        }
    }

    func delta(_ text: String) -> Data {
        switch self {
        case .gemini: return event(["event_type": "step.delta", "index": 1, "delta": ["type": "text", "text": text]])
        case .openAI: return event(["type": "response.output_text.delta", "delta": text])
        case .openRouter: return event(["choices": [["index": 0, "delta": ["content": text]]]])
        }
    }

    func end() -> Data {
        switch self {
        case .gemini:
            return event(["event_type": "interaction.completed", "interaction": ["status": "completed", "usage": ["total_input_tokens": 12, "total_output_tokens": 8]]])
        case .openAI:
            return event(["type": "response.completed", "response": ["usage": ["input_tokens": 12, "output_tokens": 8]]])
        case .openRouter:
            return event(["choices": [], "usage": ["prompt_tokens": 12, "completion_tokens": 8]]) + Data("data: [DONE]\n\n".utf8)
        }
    }
}

final class AiTransportTests: XCTestCase {
    private var client: AiChatClient!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedServer.self]
        client = AiChatClient(configuration: configuration)
        ScriptedServer.reset(ScriptedServer.Script())
    }

    private func call(_ wire: Wire = .openRouter, timeoutMs: Int = 5000, assistant: Bool = true, key: String = "sk-test-key-123") -> AiCall {
        let stamp = RequestStamp(editorSession: 1, inputRevision: 1, promptGeneration: 1, keyboardGeneration: 1, apiGeneration: 1)
        let request = AiRequest(stamp: stamp, input: AiInput(input: "woyaochihuogou", before: "你好。"), systemPrompt: "system prompt",
                                assistantEnabled: assistant)
        return AiCall(endpoint: wire.endpoint, key: key, model: wire == .gemini ? ApiRouting.hydrogen : "test-model", timeoutMs: timeoutMs,
                      parameters: [:], provider: "", request: request)
    }

    final class Partials: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [AiResult] = []
        func add(_ result: AiResult) { lock.lock(); items.append(result); lock.unlock() }
        var all: [AiResult] { lock.lock(); defer { lock.unlock() }; return items }
    }

    // MARK: requests

    func testTheRequestCarriesTheKeyInTheHeaderOnlyAndTheBodyComesFromTheSharedCore() async throws {
        for wire in [Wire.openAI, .openRouter, .gemini] {
            ScriptedServer.reset(.init(chunks: [(0, wire.start() + wire.delta("[\"你好\"]") + wire.end())]))
            _ = try await client.send(call(wire, key: "sk-secret-value"), onPartial: { _ in })
            let request = try XCTUnwrap(ScriptedServer.requests.last)
            XCTAssertEqual(request.httpMethod, "POST")
            if wire == .gemini {
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "sk-secret-value")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-secret-value")
            }
            let body = try XCTUnwrap(ScriptedServer.requestBodies.last)
            let text = String(decoding: body, as: UTF8.self)
            XCTAssertFalse(text.contains("sk-secret-value"), "the key is never in the body")
            XCTAssertTrue(text.contains("woyaochihuogou"))
            XCTAssertTrue(text.contains("system prompt") || text.contains("system_instruction"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            if wire != .gemini { XCTAssertEqual(object["stream"] as? Bool, true) }
        }
    }

    func testAnEndpointThatIsNotPlainHttpsOrAKeyWithANewlineIsRefusedBeforeAnythingIsSent() async {
        var plain = call()
        plain.endpoint = "http://api.example.com/v1/chat/completions"
        var newline = call()
        newline.key = "a\nb"
        var shortTimeout = call()
        shortTimeout.timeoutMs = 10
        for refused in [plain, newline, shortTimeout] {
            do {
                _ = try await client.send(refused, onPartial: { _ in })
                XCTFail("must be refused")
            } catch {
                XCTAssertEqual(error as? AiError, .invalidConfiguration)
            }
        }
        XCTAssertTrue(ScriptedServer.requests.isEmpty)
    }

    // MARK: streaming

    func testChunkedStreamShowsOnlyClosedCandidatesAndTheFinalResultHasBoth() async throws {
        for wire in [Wire.openAI, .openRouter, .gemini] {
            let first = wire.start() + wire.delta("[\"你好🍜\"")
            let second = wire.delta(",\"say \\\"hi\\\" \\ud83d\\ude00\"]") + wire.end()
            // Split inside a UTF-8 character of the first event and inside a line of the second.
            let cut = first.count - 9
            let chunks: [(Int, Data)] = [(0, first.prefix(cut)), (20, first.suffix(from: cut) + second.prefix(5)), (20, second.suffix(from: 5))]
            ScriptedServer.reset(.init(chunks: chunks.map { (delayMs: $0.0, data: Data($0.1)) }))
            let partials = Partials()
            let final = try await client.send(call(wire), onPartial: { partials.add($0) })
            XCTAssertEqual(final.candidates, ["你好🍜", "say \"hi\" 😀"], "\(wire)")
            XCTAssertFalse(final.streaming)
            XCTAssertEqual(final.usage?.input, 12)
            XCTAssertEqual(final.usage?.output, 8)
            let seen = partials.all.map(\.candidates)
            XCTAssertTrue(seen.contains(["你好🍜"]), "the first candidate shows before the second one exists: \(seen)")
            XCTAssertFalse(seen.contains { $0.contains { $0.hasPrefix("say") && !$0.hasSuffix("😀") } }, "a half-written candidate is never shown: \(seen)")
            XCTAssertEqual(partials.all.first?.streaming, true)
        }
    }

    func testAPlainJsonAnswerIsAcceptedWhenAGatewayIgnoresStreaming() async throws {
        let body = #"{"choices":[{"message":{"content":"[\"你好\",\"你好呀\"]"}}],"usage":{"prompt_tokens":3,"completion_tokens":4}}"#
        ScriptedServer.reset(.init(headers: ["Content-Type": "application/json"], chunks: [(0, Data(body.utf8))]))
        let final = try await client.send(call(.openRouter), onPartial: { _ in })
        XCTAssertEqual(final.candidates, ["你好", "你好呀"])
    }

    // MARK: failures

    func testHttpFailuresAreReportedByStatusAndNeverWithTheBody() async {
        for status in [401, 402, 429, 500] {
            ScriptedServer.reset(.init(status: status, headers: ["Content-Type": "application/json"], chunks: [(0, Data(#"{"error":"secret detail"}"#.utf8))]))
            do {
                _ = try await client.send(call(), onPartial: { _ in })
                XCTFail("must fail")
            } catch {
                XCTAssertEqual(error as? AiError, .http(status))
                XCTAssertFalse(String(describing: error).contains("secret"))
            }
        }
        XCTAssertEqual(AiFailure.from(AiError.http(401)), .authentication)
        XCTAssertEqual(AiFailure.from(AiError.http(402)), .credit)
        XCTAssertEqual(AiFailure.from(AiError.http(429)), .rateLimit)
        XCTAssertEqual(AiFailure.from(AiError.http(500)), .provider)
    }

    func testABrokenStreamKeepsWhatAlreadyArrived() async throws {
        let wire = Wire.openRouter
        ScriptedServer.reset(.init(chunks: [(0, wire.start() + wire.delta("[\"你好\",\"未完"))], failure: URLError(.networkConnectionLost)))
        let final = try await client.send(call(wire), onPartial: { _ in })
        XCTAssertEqual(final.candidates, ["你好"], "the complete candidate survives, the half one does not")
        XCTAssertFalse(final.streaming)
        XCTAssertFalse(final.streamError.isEmpty)
        XCTAssertTrue(final.recovered)
    }

    func testABrokenStreamWithNothingBeforeItIsANetworkFailure() async {
        ScriptedServer.reset(.init(chunks: [], failure: URLError(.networkConnectionLost)))
        do {
            _ = try await client.send(call(), onPartial: { _ in })
            XCTFail("must fail")
        } catch {
            XCTAssertEqual(error as? AiError, .network)
        }
    }

    func testAStreamThatEndsWithoutAnyAnswerIsAnInvalidResponse() async {
        ScriptedServer.reset(.init(chunks: [(0, Wire.openRouter.start())]))
        do {
            _ = try await client.send(call(), onPartial: { _ in })
            XCTFail("must fail")
        } catch {
            XCTAssertNotNil(error as? AiError)
        }
    }

    func testTheTimeoutNamesWhereItHappened() async {
        // Nothing at all: waiting for the service.
        ScriptedServer.reset(.init(silent: true))
        let started = Date()
        do {
            _ = try await client.send(call(timeoutMs: 1000), onPartial: { _ in })
            XCTFail("must time out")
        } catch {
            XCTAssertEqual(error as? AiError, .timeout(.waiting))
            XCTAssertEqual(AiFailure.detail(error), "等待服务响应超时")
        }
        XCTAssertGreaterThan(Date().timeIntervalSince(started), 0.9)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
        // Headers but no body: receiving.
        ScriptedServer.reset(.init(chunks: [], finish: false))
        do {
            _ = try await client.send(call(timeoutMs: 1000), onPartial: { _ in })
            XCTFail("must time out")
        } catch {
            XCTAssertEqual(error as? AiError, .timeout(.receiving))
        }
    }

    func testATimeoutAfterTheFirstCandidateKeepsIt() async throws {
        let wire = Wire.openRouter
        ScriptedServer.reset(.init(chunks: [(0, wire.start() + wire.delta("[\"你好\",\"还没写"))], finish: false))
        let final = try await client.send(call(wire, timeoutMs: 1000), onPartial: { _ in })
        XCTAssertEqual(final.candidates, ["你好"])
        XCTAssertEqual(final.streamError, "timeout")
        XCTAssertTrue(final.recovered)
        XCTAssertFalse(final.streaming)
    }

    // MARK: cancel and redirects

    func testCancellingStopsTheConnectionAndDropsEverythingThatComesLater() async throws {
        let wire = Wire.openRouter
        let late = (1...20).map { (delayMs: 50, data: wire.delta("\($0)")) }
        ScriptedServer.reset(.init(chunks: [(delayMs: 0, data: wire.start() + wire.delta("[\"你好\""))] + late, finish: false))
        let partials = Partials()
        let client = self.client!
        let request = call(wire, timeoutMs: 30000)
        let task = Task { try await client.send(request, onPartial: { partials.add($0) }) }
        for _ in 0..<200 where partials.all.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(partials.all.isEmpty, "the first candidate arrived")
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled request returns nothing")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        let count = partials.all.count
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(partials.all.count, count, "nothing is delivered after the cancel")
        XCTAssertGreaterThanOrEqual(ScriptedServer.stopped, 1, "the connection was closed")
    }

    func testARedirectIsNeverFollowed() async {
        ScriptedServer.reset(.init(status: 307, headers: ["Location": "https://elsewhere.example/steal"], silent: false,
                                   redirectTo: URL(string: "https://elsewhere.example/steal")))
        do {
            _ = try await client.send(call(timeoutMs: 1500), onPartial: { _ in })
            XCTFail("must fail")
        } catch {
            XCTAssertNotNil(error as? AiError, "\(error)")
        }
        XCTAssertEqual(ScriptedServer.requests.count, 1, "the key was sent once, to the address the person configured")
    }

    // MARK: loopback routes (simulator tests only)

    func testALoopbackRouteSendsToTheLocalServerWithTheSameBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedServer.self]
        let routed = AiChatClient(configuration: configuration, routes: [ApiRouting.openRouter: "http://127.0.0.1:18080/v1/chat/completions"])
        let wire = Wire.openRouter
        ScriptedServer.reset(.init(chunks: [(0, wire.start() + wire.delta("[\"你好\"]") + wire.end())]))
        _ = try await routed.send(call(wire), onPartial: { _ in })
        XCTAssertEqual(ScriptedServer.requests.last?.url?.absoluteString, "http://127.0.0.1:18080/v1/chat/completions")
    }
}
#endif
