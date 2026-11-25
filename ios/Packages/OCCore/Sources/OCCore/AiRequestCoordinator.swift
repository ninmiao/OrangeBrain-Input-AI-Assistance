// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum AiState: Equatable, Sendable {
    case idle
    case loading
    case ready(AiRequest, AiResult)
    case failed(AiFailure, String)
}

/// Sends one request and reports growing partial results. Implementations do the network and parsing
/// work away from the main actor.
public typealias AiTransportCall = @Sendable (AiRequest, @escaping @Sendable (AiResult) -> Void) async throws -> AiResult

private final class FinishedFlag: @unchecked Sendable {
    var value = false
}

/// One request at a time (Android `AiRequestCoordinator`). Every submit and every invalidate bumps a
/// generation: a request that is no longer current can neither publish a partial nor a final result, and
/// invalidating cancels the transport. All methods run on the main actor.
@MainActor
public final class AiRequestCoordinator {
    private var generation: Int64 = 0
    private var current: AiRequest?
    private var task: Task<Void, Never>?
    private let transport: AiTransportCall
    private let publish: (AiState) -> Void

    public init(transport: @escaping AiTransportCall, publish: @escaping (AiState) -> Void) {
        self.transport = transport
        self.publish = publish
    }

    /// True while a request is waiting for its debounce or running.
    public var isBusy: Bool { task != nil }

    public func invalidate() {
        generation += 1
        current = nil
        task?.cancel()
        task = nil
        publish(.idle)
    }

    /// `debounceMs` is 0 (manual keys) or 50...2000 (a configuration file that says otherwise is clamped).
    /// Nothing is sent when AI is not enabled, the field is sensitive or the input is blank; the previous
    /// request is always dropped first.
    public func submit(_ request: AiRequest?, enabled: Bool, sensitive: Bool, debounceMs: Int64 = 200) {
        let debounceMs: Int64 = debounceMs <= 0 ? 0 : min(max(debounceMs, 50), 2000)
        invalidate()
        guard enabled, !sensitive, let request,
              !request.input.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        current = request
        let token = generation
        let flag = FinishedFlag()
        let transport = transport
        task = Task { [weak self] in
            if debounceMs > 0 { try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000) }
            guard let self, !Task.isCancelled, token == self.generation else { return }
            self.publish(.loading)
            do {
                let result = try await transport(request) { partial in
                    Task { @MainActor [weak self] in
                        guard let self, !flag.value, token == self.generation, self.current == request else { return }
                        self.publish(.ready(request, partial))
                    }
                }
                flag.value = true
                if token == self.generation, self.current == request {
                    self.task = nil
                    self.publish(.ready(request, result))
                }
            } catch {
                flag.value = true
                guard token == self.generation, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
                self.task = nil
                self.publish(.failed(AiFailure.from(error), AiFailure.detail(error)))
            }
        }
    }
}
