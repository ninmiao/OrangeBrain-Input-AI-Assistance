// SPDX-License-Identifier: GPL-3.0-or-later
import CRime
import Foundation

/// How the user dictionary is being used by this process.
public enum UserDictionaryMode: String, Equatable, Sendable {
    /// Opened (under the cross-process lock): words are learned and kept.
    case learning
    /// Another process holds the lock: this one runs without the user dictionary and learns nothing.
    case busy
    /// No session is open (or the user dictionary is switched off by configuration).
    case off
}

/// Keeps a schema configuration open with the user dictionary switched off. librime shares one parsed
/// configuration per schema while somebody holds it, so a session created in the meantime reads
/// `enable_user_dict: false` and never opens the LevelDB.
final class SchemaConfigHold {
    private let api: UnsafeMutablePointer<RimeApi>
    private var config = RimeConfig()
    private var isOpen = false

    init?(schemaID: String) {
        guard let api = rime_get_api() else { return nil }
        self.api = api
        guard schemaID.withCString({ api.pointee.schema_open($0, &config) }) != 0 else { return nil }
        isOpen = true
        _ = "translator/enable_user_dict".withCString { api.pointee.config_set_bool(&config, $0, 0) }
    }

    deinit {
        if isOpen { _ = api.pointee.config_close(&config) }
    }
}

/// The one librime engine of the process and the one serial queue every Rime call runs on.
///
/// librime and glog are process-global. iOS may create a new keyboard controller before it has released
/// the old one, so engine lifetime must not follow any controller. Services hold *leases* while they are
/// shown and create and destroy their own *sessions*; the engine is finalised only after the last lease
/// went away and nobody asked for it again for a while (the delayed finalise belongs to the runtime, so no
/// stale controller can finalise under a new one).
///
/// The user dictionary is open exactly as long as a session is, and only under a cross-process lock.
final class RimeRuntime {
    struct Configuration: Equatable {
        var sharedData: String
        var userData: String
        var modules: [String]?
        var stagingData: String? = nil
        var startDelay: TimeInterval = 0
    }

    static let shared = RimeRuntime()
    /// Seconds between the last lease going away and the engine being finalised (tests shorten it).
    nonisolated(unsafe) static var idleFinalizeDelay: TimeInterval = 8

    let queue = DispatchQueue(label: "io.github.ninmiao.orangecell.rime", qos: .userInteractive)

    private static let generationLock = NSLock()
    private nonisolated(unsafe) static var generationValue = 0
    /// Readable from any thread: a `RimeSession` checks it before it destroys its id.
    static var currentGeneration: Int {
        generationLock.lock(); defer { generationLock.unlock() }
        return generationValue
    }

    // Everything below is touched on `queue` only.
    private var engine: RimeEngine?
    private var configuration: Configuration?
    /// Bumped whenever the engine is (re)started or finalised; sessions of an older generation are gone.
    private(set) var generation = 0 {
        didSet {
            RimeRuntime.generationLock.lock()
            RimeRuntime.generationValue = generation
            RimeRuntime.generationLock.unlock()
        }
    }
    private var leases = 0
    private var idleToken = 0
    private var liveSessions = 0
    private var userdbLock: UserDictionaryLock?
    private(set) var userDictionaryMode = UserDictionaryMode.off

    var leaseCount: Int { leases }
    var sessionCount: Int { liveSessions }

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
        liveSessions = 0
        userdbLock?.release()
        userdbLock = nil
        userDictionaryMode = .off
    }

    var isRunning: Bool { engine?.isInitialized == true }

    @discardableResult
    func syncUserDataLocked() -> Bool { engine?.syncUserData() ?? false }

    // MARK: leases

    func retainLease() {
        leases += 1
        idleToken += 1   // a pending idle finalise is void
    }

    func releaseLease(exportSnapshot: Bool) {
        leases = max(0, leases - 1)
        guard leases == 0 else { return }
        idleToken += 1
        let token = idleToken
        queue.asyncAfter(deadline: .now() + Self.idleFinalizeDelay) { [self] in
            guard token == idleToken, leases == 0, liveSessions == 0 else { return }
            if exportSnapshot { syncUserDataLocked() }
            finalizeLocked()
        }
    }

    // MARK: sessions and the user dictionary

    /// Opens a session. The first session of the process takes the cross-process lock; without it the
    /// session is created while the schema configuration says "no user dictionary".
    func openSession(_ service: RimeServiceConfiguration) -> RimeSession? {
        var tookLock = false
        if liveSessions == 0 {
            userdbLock?.release()
            userdbLock = nil
            if service.useUserDictionary {
                if let lock = UserDictionaryLock.acquire(path: service.userDictionaryLockPath, timeout: 0.3) {
                    userdbLock = lock
                    userDictionaryMode = .learning
                    tookLock = true
                } else {
                    userDictionaryMode = .busy
                }
            } else {
                userDictionaryMode = .off
            }
        }
        let hold = userDictionaryMode == .learning ? nil : SchemaConfigHold(schemaID: service.userDictionarySchema)
        guard let session = RimeSession(generation: generation) else {
            if tookLock { userdbLock?.release(); userdbLock = nil; userDictionaryMode = .off }
            return nil
        }
        withExtendedLifetime(hold) {}
        session.onClose = { [weak self] closedGeneration in
            self?.queue.async { self?.sessionClosed(generation: closedGeneration) }
        }
        liveSessions += 1
        return session
    }

    private func sessionClosed(generation closed: Int) {
        guard closed == generation else { return }
        liveSessions = max(0, liveSessions - 1)
        if liveSessions == 0 {
            // The last session is gone, so librime closed the LevelDB: now the lock can go.
            userdbLock?.release()
            userdbLock = nil
            userDictionaryMode = .off
        }
    }
}

/// Thread-safe front door to librime for one keyboard (one session at a time). Every call runs on the shared
/// serial queue, so key presses are processed in order and never concurrently, whichever thread they come
/// from. The asynchronous methods deliver on the main queue in the order they were issued; the `Sync`
/// variants block the caller (tests, tools).
///
/// `start` (keyboard shown) takes a lease and opens the session; `deactivate` (keyboard hidden) closes the
/// session, which closes and flushes the user dictionary, and gives the lease back.
public final class RimeService {
    public let configuration: RimeServiceConfiguration
    private let runtime = RimeRuntime.shared
    // Touched on the runtime queue only.
    private var session: RimeSession?
    private var sessionGeneration = -1
    private var lastError: Error?
    private var leased = false

    public init(configuration: RimeServiceConfiguration) {
        self.configuration = configuration
    }

    deinit {
        // On the Rime queue: the session goes (and with it the user dictionary), the lease goes back. The
        // engine stays up; another controller may already be using it.
        let leftover = session
        let wasLeased = leased
        let export = configuration.exportSnapshotOnIdle
        runtime.queue.async { [runtime] in
            withExtendedLifetime(leftover) {}
            if wasLeased { runtime.releaseLease(exportSnapshot: export) }
        }
    }

    private var runtimeConfiguration: RimeRuntime.Configuration {
        .init(sharedData: configuration.sharedDataDirectory, userData: configuration.userDataDirectory,
              modules: configuration.modules, stagingData: configuration.stagingDirectory,
              startDelay: configuration.startDelay)
    }

    // MARK: lifecycle

    /// Starts the engine and opens the session now (otherwise they start with the first key). Completion on main.
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

    /// The keyboard went away: closes the session (the user dictionary is flushed and closed) and gives the
    /// lease back. The engine itself is finalised later, by the runtime, if nobody needs it.
    public func deactivate(completion: (() -> Void)? = nil) {
        runtime.queue.async { [self] in
            deactivateLocked()
            if let completion { DispatchQueue.main.async { completion() } }
        }
    }

    public func deactivateSync() {
        runtime.queue.sync { deactivateLocked() }
    }

    /// Explicit stop: deactivate and finalise the engine now when nobody else uses it (tests, tools).
    public func stop(completion: (() -> Void)? = nil) {
        runtime.queue.async { [self] in
            stopLocked(exportSnapshot: false)
            if let completion { DispatchQueue.main.async { completion() } }
        }
    }

    public func stopSync(exportSnapshot: Bool = false) {
        runtime.queue.sync { stopLocked(exportSnapshot: exportSnapshot) }
    }

    public var isRunning: Bool {
        runtime.queue.sync { runtime.isRunning && session != nil && sessionGeneration == runtime.generation }
    }

    public var startError: Error? {
        runtime.queue.sync { lastError }
    }

    /// Whether this process learns (`learning`) or runs without the user dictionary (`busy`).
    public var userDictionaryMode: UserDictionaryMode {
        runtime.queue.sync { runtime.userDictionaryMode }
    }

    /// Releases memory when the system asks for it, unless a composition is in progress: the session
    /// (and the dictionary mapped by it) goes, the next key opens a new one.
    public func handleMemoryWarning() {
        runtime.queue.async { [self] in
            guard let session, sessionGeneration == runtime.generation else { return }
            var probe = RimeUpdate()
            session.snapshot(limit: 0, into: &probe)
            if !probe.isComposing { self.session = nil }
        }
    }

    // MARK: typing, asynchronous (completion on main, in issue order)

    public func process(_ key: RimeKey, completion: @escaping (RimeUpdate) -> Void) {
        deliver(completion) { self.processLocked(key) }
    }

    /// Selects the candidate at `index`. With `expecting`, nothing is selected when the candidate at that
    /// index is not the one the person saw (the list moved on in the meantime).
    public func select(candidateAt index: Int, expecting: String? = nil, completion: @escaping (RimeUpdate) -> Void) {
        deliver(completion) { self.selectLocked(index, expecting: expecting) }
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

    /// The state again with up to `limit` candidates (the expanded candidate grid asks for more than the bar shows).
    public func refresh(limit: Int, completion: @escaping (RimeUpdate) -> Void) {
        deliver(completion) { self.refreshLocked(limit: limit) }
    }

    // MARK: typing, synchronous

    public func processSync(_ key: RimeKey) -> RimeUpdate { runtime.queue.sync { processLocked(key) } }
    public func selectSync(candidateAt index: Int) -> RimeUpdate { runtime.queue.sync { selectLocked(index, expecting: nil) } }
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
        if !leased {
            runtime.retainLease()
            leased = true
        }
        if let error = runtime.ensureStarted(runtimeConfiguration) {
            lastError = error
            session?.markStale()
            session = nil
            return error
        }
        if session != nil, sessionGeneration == runtime.generation { return nil }
        session?.markStale()   // the engine was restarted since this session was created
        session = nil
        guard let fresh = runtime.openSession(configuration) else {
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

    private func deactivateLocked() {
        session = nil          // destroys this service's librime session: the user dictionary is flushed and closed
        if leased {
            runtime.releaseLease(exportSnapshot: configuration.exportSnapshotOnIdle)
            leased = false
        }
    }

    private func stopLocked(exportSnapshot: Bool) {
        session = nil
        if leased {
            runtime.releaseLease(exportSnapshot: false)
            leased = false
        }
        guard runtime.leaseCount == 0 else { return }
        if exportSnapshot { runtime.syncUserDataLocked() }
        runtime.finalizeLocked()
    }

    /// What a key gets back when the engine or its session cannot start: nothing handled, `engineFailed` set.
    private static var failedUpdate: RimeUpdate {
        var update = RimeUpdate()
        update.engineFailed = true
        return update
    }

    private func activeSession() -> RimeSession? {
        _ = startLocked()
        return session
    }

    /// The state after an operation. A commit is followed by the flush key, so what was learned is
    /// on disk before the next key (a killed keyboard process keeps it).
    private func finish(_ session: RimeSession, handled: Bool, limit: Int? = nil) -> RimeUpdate {
        var update = RimeUpdate()
        update.handled = handled
        update.commit = session.takeCommit()
        session.snapshot(limit: limit ?? configuration.maxCandidates, into: &update)
        if update.commit != nil { session.flushLearning() }
        return update
    }

    private func processLocked(_ key: RimeKey) -> RimeUpdate {
        guard let session = activeSession() else { return Self.failedUpdate }
        return finish(session, handled: session.process(key))
    }

    private func selectLocked(_ index: Int, expecting: String?) -> RimeUpdate {
        guard let session = activeSession() else { return Self.failedUpdate }
        if let expecting, session.candidateText(at: index) != expecting {
            return finish(session, handled: false)
        }
        return finish(session, handled: session.selectCandidate(at: index))
    }

    private func changePageLocked(_ backward: Bool) -> RimeUpdate {
        guard let session = activeSession() else { return Self.failedUpdate }
        return finish(session, handled: session.changePage(backward: backward))
    }

    private func clearLocked() -> RimeUpdate {
        guard let session = activeSession() else { return Self.failedUpdate }
        session.clearComposition()
        return finish(session, handled: true)
    }

    private func setAsciiModeLocked(_ enabled: Bool) -> RimeUpdate {
        guard let session = activeSession() else { return Self.failedUpdate }
        session.setOption("ascii_mode", enabled)
        return finish(session, handled: true)
    }

    private func refreshLocked(limit: Int? = nil) -> RimeUpdate {
        guard let session = activeSession() else { return Self.failedUpdate }
        return finish(session, handled: true, limit: limit)
    }
}
