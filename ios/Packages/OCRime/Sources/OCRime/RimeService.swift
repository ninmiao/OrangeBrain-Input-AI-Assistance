// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Thread-safe front door to librime. Every call runs on one private serial queue,
/// so key presses are processed in order and never concurrently, whichever thread
/// they come from. The asynchronous methods deliver on the main queue; the `Sync`
/// variants block the caller and exist for tests and for shutdown.
///
/// The engine starts lazily on the first call (or explicitly with `start`) and can
/// be stopped (`stop`) to release memory and the user-dictionary lock; the next
/// call starts it again.
public final class RimeService {
    public let configuration: RimeServiceConfiguration
    private let queue = DispatchQueue(label: "io.github.ninmiao.orangecell.rime", qos: .userInteractive)
    // The following are touched on `queue` only.
    private var engine: RimeEngine?
    private var session: RimeSession?
    private var lastError: Error?

    public init(configuration: RimeServiceConfiguration) {
        self.configuration = configuration
    }

    // MARK: lifecycle

    /// Starts the engine now (otherwise it starts with the first key). Completion on main.
    public func start(completion: ((Error?) -> Void)? = nil) {
        queue.async { [self] in
            let error = startLocked()
            if let completion { DispatchQueue.main.async { completion(error) } }
        }
    }

    @discardableResult
    public func startSync() -> Error? {
        queue.sync { startLocked() }
    }

    /// Ends the session and finalises librime. Flushes and closes the user dictionary.
    public func stop(completion: (() -> Void)? = nil) {
        queue.async { [self] in
            stopLocked()
            if let completion { DispatchQueue.main.async { completion() } }
        }
    }

    public func stopSync() {
        queue.sync { stopLocked() }
    }

    public var isRunning: Bool {
        queue.sync { engine != nil && session != nil }
    }

    public var startError: Error? {
        queue.sync { lastError }
    }

    /// Releases memory when the system asks for it, unless a composition is in progress.
    public func handleMemoryWarning() {
        queue.async { [self] in
            guard let session else { return }
            var probe = RimeUpdate()
            session.snapshot(limit: 0, into: &probe)
            if !probe.isComposing { stopLocked() }
        }
    }

    // MARK: typing, asynchronous (completion on main)

    public func process(_ key: RimeKey, completion: @escaping (RimeUpdate) -> Void) {
        deliver(completion) { self.processLocked(key) }
    }

    public func select(candidateAt index: Int, completion: @escaping (RimeUpdate) -> Void) {
        deliver(completion) { self.selectLocked(index) }
    }

    public func changePage(backward: Bool, completion: @escaping (RimeUpdate) -> Void) {
        deliver(completion) { self.changePageLocked(backward) }
    }

    public func clear(completion: @escaping (RimeUpdate) -> Void) {
        deliver(completion) { self.clearLocked() }
    }

    public func setAsciiMode(_ enabled: Bool, completion: @escaping (RimeUpdate) -> Void) {
        deliver(completion) { self.setAsciiModeLocked(enabled) }
    }

    public func refresh(completion: @escaping (RimeUpdate) -> Void) {
        deliver(completion) { self.refreshLocked() }
    }

    // MARK: typing, synchronous

    public func processSync(_ key: RimeKey) -> RimeUpdate { queue.sync { processLocked(key) } }
    public func selectSync(candidateAt index: Int) -> RimeUpdate { queue.sync { selectLocked(index) } }
    public func changePageSync(backward: Bool) -> RimeUpdate { queue.sync { changePageLocked(backward) } }
    public func clearSync() -> RimeUpdate { queue.sync { clearLocked() } }
    public func setAsciiModeSync(_ enabled: Bool) -> RimeUpdate { queue.sync { setAsciiModeLocked(enabled) } }
    public func refreshSync() -> RimeUpdate { queue.sync { refreshLocked() } }

    /// Types a whole string key by key (letters, punctuation) and returns the last
    /// update, with every commit that happened along the way concatenated.
    public func typeSync(_ text: String) -> RimeUpdate {
        queue.sync {
            var last = RimeUpdate()
            var committed = ""
            for character in text {
                guard let key = RimeKey.character(character) else { continue }
                last = processLocked(key)
                if let commit = last.commit { committed += commit }
            }
            last.commit = committed.isEmpty ? nil : committed
            return last
        }
    }

    // MARK: implementation (queue only)

    private func deliver(_ completion: @escaping (RimeUpdate) -> Void, _ work: @escaping () -> RimeUpdate) {
        queue.async {
            let update = work()
            DispatchQueue.main.async { completion(update) }
        }
    }

    private func startLocked() -> Error? {
        if engine != nil, session != nil { return nil }
        stopLocked()
        let engine = RimeEngine(directories: .init(
            sharedData: configuration.sharedDataDirectory,
            userData: configuration.userDataDirectory
        ))
        do {
            try engine.start(modules: configuration.modules)
            guard let session = RimeSession() else { throw RimeEngineError.sessionUnavailable }
            if let schemaID = configuration.schemaID, session.currentSchema() != schemaID {
                _ = session.selectSchema(schemaID)
            }
            self.engine = engine
            self.session = session
            lastError = nil
            return nil
        } catch {
            engine.finalize()
            lastError = error
            return error
        }
    }

    private func stopLocked() {
        session = nil          // destroys the librime session first
        engine?.finalize()
        engine = nil
    }

    private func activeSession() -> RimeSession? {
        _ = startLocked()
        return session
    }

    private func finish(_ session: RimeSession, handled: Bool) -> RimeUpdate {
        var update = RimeUpdate()
        update.handled = handled
        update.commit = session.takeCommit()
        session.snapshot(limit: configuration.maxCandidates, into: &update)
        return update
    }

    private func processLocked(_ key: RimeKey) -> RimeUpdate {
        guard let session = activeSession() else { return RimeUpdate() }
        return finish(session, handled: session.process(key))
    }

    private func selectLocked(_ index: Int) -> RimeUpdate {
        guard let session = activeSession() else { return RimeUpdate() }
        return finish(session, handled: session.selectCandidate(at: index))
    }

    private func changePageLocked(_ backward: Bool) -> RimeUpdate {
        guard let session = activeSession() else { return RimeUpdate() }
        return finish(session, handled: session.changePage(backward: backward))
    }

    private func clearLocked() -> RimeUpdate {
        guard let session = activeSession() else { return RimeUpdate() }
        session.clearComposition()
        return finish(session, handled: true)
    }

    private func setAsciiModeLocked(_ enabled: Bool) -> RimeUpdate {
        guard let session = activeSession() else { return RimeUpdate() }
        session.setOption("ascii_mode", enabled)
        return finish(session, handled: true)
    }

    private func refreshLocked() -> RimeUpdate {
        guard let session = activeSession() else { return RimeUpdate() }
        return finish(session, handled: true)
    }
}
