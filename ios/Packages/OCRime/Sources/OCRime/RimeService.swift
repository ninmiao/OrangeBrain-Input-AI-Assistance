// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The one librime engine of the process and the one serial queue every Rime call runs on.
///
/// librime and glog are process-global. iOS may create a new keyboard controller before it
/// has released the old one, so engine lifetime must not follow any controller: services
/// create and destroy their own *sessions*, and the engine is only ever finalised by an
/// explicit `stop` (idle timeout, memory warning, changed user directory), never by a
/// deinit.
final class RimeRuntime {
    struct Configuration: Equatable {
        var sharedData: String
        var userData: String
        var modules: [String]?
        var stagingData: String? = nil
        var startDelay: TimeInterval = 0
    }

    static let shared = RimeRuntime()
    let queue = DispatchQueue(label: "io.github.ninmiao.orangecell.rime", qos: .userInteractive)

    // Everything below is touched on `queue` only.
    private var engine: RimeEngine?
    private var configuration: Configuration?
    /// Bumped whenever the engine is (re)started or finalised; sessions of an older
    /// generation are gone.
    private(set) var generation = 0

    /// Starts the engine, or restarts it when the directories or module list changed.
    func ensureStarted(_ wanted: Configuration) -> Error? {
        if let engine, engine.isInitialized, configuration == wanted { return nil }
        finalizeLocked()
        if wanted.startDelay > 0 { Thread.sleep(forTimeInterval: wanted.startDelay) }
        let engine = RimeEngine(directories: .init(sharedData: wanted.sharedData, userData: wanted.userData,
                                                   stagingData: wanted.stagingData))
        do {
            try engine.start(modules: wanted.modules)
        } catch {
            engine.finalize()
            return error
        }
        self.engine = engine
        configuration = wanted
        generation += 1
        return nil
    }

    func finalizeLocked() {
        guard let engine else { return }
        engine.finalize()
        self.engine = nil
        configuration = nil
        generation += 1
    }

    var isRunning: Bool { engine?.isInitialized == true }

    @discardableResult
    func syncUserDataLocked() -> Bool { engine?.syncUserData() ?? false }
}

/// Thread-safe front door to librime for one keyboard (one session). Every call runs
/// on the shared serial queue, so key presses are processed in order and never
/// concurrently, whichever thread they come from. The asynchronous methods deliver on
/// the main queue; the `Sync` variants block the caller.
///
/// The engine starts lazily on the first call (or explicitly with `start`) and can be
/// stopped (`stop`) to release memory and the user-dictionary lock; the next call starts
/// it again.
public final class RimeService {
    public let configuration: RimeServiceConfiguration
    private let runtime = RimeRuntime.shared
    // Touched on the runtime queue only.
    private var session: RimeSession?
    private var sessionGeneration = -1
    private var lastError: Error?

    public init(configuration: RimeServiceConfiguration) {
        self.configuration = configuration
    }

    deinit {
        // Destroys this service's session on the Rime queue. The engine stays up: another
        // controller may already be using it.
        let leftover = session
        runtime.queue.async { withExtendedLifetime(leftover) {} }
    }

    private var runtimeConfiguration: RimeRuntime.Configuration {
        .init(sharedData: configuration.sharedDataDirectory, userData: configuration.userDataDirectory,
              modules: configuration.modules, stagingData: configuration.stagingDirectory,
              startDelay: configuration.startDelay)
    }

    // MARK: lifecycle

    /// Starts the engine now (otherwise it starts with the first key). Completion on main.
    public func start(completion: ((Error?) -> Void)? = nil) {
        runtime.queue.async { [self] in
            let error = startLocked()
            if let completion { DispatchQueue.main.async { completion(error) } }
        }
    }

    @discardableResult
    public func startSync() -> Error? {
        runtime.queue.sync { startLocked() }
    }

    /// Ends the session and finalises librime: flushes and closes the user dictionary and
    /// frees the memory. The next call starts it again.
    public func stop(completion: (() -> Void)? = nil) {
        runtime.queue.async { [self] in
            stopLocked()
            if let completion { DispatchQueue.main.async { completion() } }
        }
    }

    public func stopSync(exportSnapshot: Bool = false) {
        runtime.queue.sync { stopLocked(exportSnapshot: exportSnapshot) }
    }

    /// Like `stop`, after writing the user dictionary as text snapshots into the sync directory
    /// of `installation.yaml` (Full Access: the app can show or back them up).
    public func stopExportingSnapshot(completion: (() -> Void)? = nil) {
        runtime.queue.async { [self] in
            stopLocked(exportSnapshot: true)
            if let completion { DispatchQueue.main.async { completion() } }
        }
    }

    public var isRunning: Bool {
        runtime.queue.sync { runtime.isRunning && session != nil && sessionGeneration == runtime.generation }
    }

    public var startError: Error? {
        runtime.queue.sync { lastError }
    }

    /// Releases memory when the system asks for it, unless a composition is in progress.
    public func handleMemoryWarning() {
        runtime.queue.async { [self] in
            guard let session, sessionGeneration == runtime.generation else { return }
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

    public func processSync(_ key: RimeKey) -> RimeUpdate { runtime.queue.sync { processLocked(key) } }
    public func selectSync(candidateAt index: Int) -> RimeUpdate { runtime.queue.sync { selectLocked(index) } }
    public func changePageSync(backward: Bool) -> RimeUpdate { runtime.queue.sync { changePageLocked(backward) } }
    public func clearSync() -> RimeUpdate { runtime.queue.sync { clearLocked() } }
    public func setAsciiModeSync(_ enabled: Bool) -> RimeUpdate { runtime.queue.sync { setAsciiModeLocked(enabled) } }
    public func refreshSync() -> RimeUpdate { runtime.queue.sync { refreshLocked() } }

    /// Types a whole string key by key (letters, punctuation) and returns the last
    /// update, with every commit that happened along the way concatenated.
    public func typeSync(_ text: String) -> RimeUpdate {
        runtime.queue.sync {
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

    // MARK: implementation (runtime queue only)

    private func deliver(_ completion: @escaping (RimeUpdate) -> Void, _ work: @escaping () -> RimeUpdate) {
        runtime.queue.async {
            let update = work()
            DispatchQueue.main.async { completion(update) }
        }
    }

    private func startLocked() -> Error? {
        if let error = runtime.ensureStarted(runtimeConfiguration) {
            lastError = error
            session?.markStale()
            session = nil
            return error
        }
        if session != nil, sessionGeneration == runtime.generation { return nil }
        session?.markStale()   // the engine was restarted since this session was created
        session = nil
        guard let fresh = RimeSession() else {
            lastError = RimeEngineError.sessionUnavailable
            return lastError
        }
        if let schemaID = configuration.schemaID, fresh.currentSchema() != schemaID {
            _ = fresh.selectSchema(schemaID)
        }
        session = fresh
        sessionGeneration = runtime.generation
        lastError = nil
        return nil
    }

    private func stopLocked(exportSnapshot: Bool = false) {
        session = nil          // destroys this service's librime session first
        if exportSnapshot { runtime.syncUserDataLocked() }
        runtime.finalizeLocked()
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
