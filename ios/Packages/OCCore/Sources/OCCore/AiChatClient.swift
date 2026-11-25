// SPDX-License-Identifier: GPL-3.0-or-later
#if canImport(Darwin)
import Foundation

/// The transport of Android `ChatCompletionsClient` for iOS: HTTPS (OpenAI Responses, OpenRouter chat, Gemini
/// Interactions), one streaming POST read with `URLSession.bytes(for:)`, the bytes handed to native-core's
/// `stream` operation as they come, so only complete candidate strings are published. Request bodies, routing
/// and parsing are native-core's: the same code as Android and Windows.
///
/// No redirects, no retries (a sent POST is never resent), no logging; cancellation closes the connection.
public final class AiChatClient: @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let routes: [String: String]

    public init(configuration: URLSessionConfiguration = .ephemeral, routes: [String: String] = [:]) {
        configuration.waitsForConnectivity = false
        configuration.httpShouldUsePipelining = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.configuration = configuration
        self.routes = routes
    }

    // MARK: request construction

    /// The request body: native-core builds it from the snapshot, the prompt and the parameters.
    public func payload(_ call: AiCall) throws -> Data {
        let input = call.request.input
        let args: [String: Any] = [
            "model": call.model, "endpoint": call.endpoint, "provider": call.provider,
            "parameters": call.parameters.mapValues { $0.foundation },
            "request": [
                "input": ["input": input.input, "before": input.before, "after": input.after],
                "systemPrompt": call.request.systemPrompt,
                "assistantEnabled": call.request.assistantEnabled,
                "outputTokenBudget": call.request.outputTokenBudget,
            ] as [String: Any],
        ]
        do {
            let body = try NativeCore.call(op: "payload", args: args)
            return try JSONSerialization.data(withJSONObject: body)
        } catch let error as NativeCoreError {
            throw Self.map(error)
        }
    }

    func urlRequest(_ call: AiCall) throws -> URLRequest {
        guard let url = URL(string: call.endpoint), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.query == nil, url.fragment == nil,
              !call.key.isEmpty, !call.key.contains("\r"), !call.key.contains("\n"), !call.model.isEmpty,
              (1000...60000).contains(call.timeoutMs)
        else { throw AiError.invalidConfiguration }
        let target = routes[call.endpoint].flatMap(URL.init(string:)) ?? URL(string: ApiRouting.requestURL(call.endpoint))
        guard let target else { throw AiError.invalidConfiguration }
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.httpBody = try payload(call)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if ApiRouting.isGemini(call.endpoint) {
            request.setValue(call.key, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("2026-05-20", forHTTPHeaderField: "Api-Revision")
        } else {
            request.setValue("Bearer " + call.key, forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = TimeInterval(call.timeoutMs) / 1000
        return request
    }

    static func map(_ error: NativeCoreError) -> AiError {
        switch error.message {
        case "truncated": return .truncated
        case "provider": return .provider(error.status > 0 ? error.status : nil)
        case "response": return .invalidResponse
        default: return .invalidConfiguration
        }
    }

    // MARK: sending

    private final class Phase: @unchecked Sendable {
        private let lock = NSLock()
        private var value = RequestPhase.waiting
        var current: RequestPhase { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ phase: RequestPhase) { lock.lock(); value = phase; lock.unlock() }
    }

    private final class Latest: @unchecked Sendable {
        private let lock = NSLock()
        private var value: AiResult?
        var current: AiResult? { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ result: AiResult) { lock.lock(); value = result; lock.unlock() }
    }

    /// Refuses every redirect: a provider never moves a request (and its key) somewhere else.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    /// Sends the request and returns the final result. `onPartial` gets every growing set of complete
    /// candidates. When the stream breaks or the deadline passes after something arrived, that is returned
    /// with `streamError` set (the person keeps what is there); with nothing, the error is thrown.
    public func send(_ call: AiCall, onPartial: @escaping @Sendable (AiResult) -> Void) async throws -> AiResult {
        let request = try urlRequest(call)
        let phase = Phase()
        let latest = Latest()
        do {
            return try await withThrowingTaskGroup(of: AiResult?.self) { group in
                group.addTask { [self] in
                    try await receive(request, call: call, phase: phase, latest: latest, onPartial: onPartial)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(call.timeoutMs) * 1_000_000)
                    return nil   // the deadline
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw AiError.network }
                if let result = first { return result }
                // The deadline came first.
                if var partial = latest.current {
                    partial.streaming = false
                    partial.streamError = "timeout"
                    partial.recovered = true
                    return partial
                }
                throw AiError.timeout(phase.current)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AiError {
            throw error
        } catch let error as NativeCoreError {
            throw Self.map(error)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if let partial = latest.current {
                var recovered = partial
                recovered.streaming = false
                recovered.streamError = "interrupted"
                recovered.recovered = true
                return recovered
            }
            throw error.code == .timedOut ? AiError.timeout(phase.current) : AiError.network
        }
    }

    private func receive(_ request: URLRequest, call: AiCall, phase: Phase, latest: Latest,
                         onPartial: @escaping @Sendable (AiResult) -> Void) async throws -> AiResult? {
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirects())
        phase.set(.receiving)
        guard let http = response as? HTTPURLResponse else { throw AiError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AiError.http(http.statusCode) }

        var state: Any = [String: Any]()
        var done = false
        var published: [String]?
        func feed(_ chunk: [UInt8], finish: Bool) throws -> AiResult? {
            let hex = chunk.map { String(format: "%02x", $0) }.joined()
            let args: [String: Any] = [
                "endpoint": call.endpoint, "assistantEnabled": call.request.assistantEnabled,
                "slots": call.request.maxCandidates, "state": state, "chunkHex": hex, "finish": finish,
            ]
            guard let reply = try NativeCore.call(op: "stream", args: args) as? [String: Any],
                  let newState = reply["state"] else { throw AiError.invalidResponse }
            state = newState
            done = (reply["done"] as? Bool) ?? false
            guard let result = reply["result"], !(result is NSNull),
                  JSONSerialization.isValidJSONObject(result),
                  let data = try? JSONSerialization.data(withJSONObject: result),
                  let value = try? JSONDecoder().decode(AiResult.self, from: data) else { return nil }
            latest.set(value)
            if value.candidates != published {
                published = value.candidates
                onPartial(value)
            }
            return value
        }

        // Lines are handed over as they complete: an SSE event is a few short lines, a plain JSON body one long one.
        var buffer: [UInt8] = []
        buffer.reserveCapacity(4096)
        for try await byte in bytes {
            buffer.append(byte)
            if byte == 0x0A || buffer.count >= 4096 {
                _ = try feed(buffer, finish: false)
                buffer.removeAll(keepingCapacity: true)
                if done { break }
            }
            try Task.checkCancellation()
        }
        if !done {
            if !buffer.isEmpty { _ = try feed(buffer, finish: false) }
            if !done { _ = try feed([], finish: true) }
        }
        guard let result = latest.current else { throw AiError.invalidResponse }
        return result
    }
}
#endif
