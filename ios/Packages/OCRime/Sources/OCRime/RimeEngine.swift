// SPDX-License-Identifier: GPL-3.0-or-later
import CRime
import Foundation

public enum RimeEngineError: Error, Equatable {
    case apiUnavailable
    case sessionUnavailable
}

/// Swift handle on the librime process-global state: version, setup / initialise /
/// finalise and a look at which modules (lua, octagram, predict, ...) are
/// registered. Typing goes through `RimeSession` / `RimeService`.
///
/// Not thread-safe, and librime (like glog) is process-global: there is exactly one
/// engine per process, owned by `RimeRuntime`, and every call comes from its serial
/// queue. Nothing finalises the engine implicitly: a deinit never tears down a session
/// that belongs to somebody else.
public final class RimeEngine {
    /// Modules the prebuilt librime is expected to contain. `required` ones
    /// must be registered or the build is not what the plan assumes.
    public static let requiredModules = ["lua", "octagram", "predict"]
    public static let candidateModules = [
        "default", "core", "dict", "gears", "levers", "deployer",
        "lua", "octagram", "grammar", "predict", "qjs",
    ]
    /// What the keyboard loads at run time: the engine core (`default` expands to
    /// core, dict and gears). The shipped schema uses no Lua, no QuickJS and no
    /// grammar model, so those plugins stay registered (linked in) but are not
    /// initialised.
    public static let minimalModules = ["default"]

    public struct Directories: Equatable {
        public var sharedData: String
        public var userData: String
        /// `nil` or empty keeps glog on stderr only.
        public var log: String?

        public init(sharedData: String, userData: String, log: String? = nil) {
            self.sharedData = sharedData
            self.userData = userData
            self.log = log
        }
    }

    public private(set) var isInitialized = false
    private var traits = RimeTraits()
    private var moduleArray: UnsafeMutablePointer<UnsafePointer<CChar>?>?
    private let directories: Directories
    private let appName: String

    init(directories: Directories, appName: String = "rime.orangecell") {
        self.directories = directories
        self.appName = appName
    }

    deinit {
        // No finalize here on purpose (see the type's documentation). The module list is
        // only read while `initialize` runs, so it can go.
        moduleArray?.deallocate()
    }

    // MARK: static queries (no initialisation needed)

    /// `rime_get_api()->get_version()`, e.g. `1.17.0`.
    public static func version() -> String? {
        guard let api = rime_get_api(), let getVersion = api.pointee.get_version, let text = getVersion() else {
            return nil
        }
        return String(cString: text)
    }

    /// Whether a module of that name is currently registered with librime.
    public static func isModuleRegistered(_ name: String) -> Bool {
        guard let api = rime_get_api(), let find = api.pointee.find_module else { return false }
        return name.withCString { find($0) != nil }
    }

    /// The subset of `candidates` that is registered right now.
    public static func registeredModules(among candidates: [String] = candidateModules) -> [String] {
        candidates.filter { isModuleRegistered($0) }
    }

    // MARK: lifecycle

    /// Strings that librime may keep pointers to (glog keeps the application name for the
    /// life of the process) are copied once and never freed; the same text always maps
    /// to the same pointer, so restarting the engine does not grow memory.
    private static var interned: [String: UnsafePointer<CChar>] = [:]
    private static let internLock = NSLock()

    private func keep(_ string: String) -> UnsafePointer<CChar> {
        Self.internLock.lock()
        defer { Self.internLock.unlock() }
        if let existing = Self.interned[string] { return existing }
        let copy = UnsafePointer(strdup(string)!)
        Self.interned[string] = copy
        return copy
    }

    /// `setup` + `initialize`. Creates the directories first; librime does not.
    /// `modules == nil` loads librime's default list (everything that is linked in);
    /// pass `RimeEngine.minimalModules` to skip the plugins.
    func start(modules: [String]? = nil) throws {
        guard let api = rime_get_api() else { throw RimeEngineError.apiUnavailable }
        guard !isInitialized else { return }
        for path in [directories.sharedData, directories.userData] {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        var fresh = RimeTraits()
        fresh.data_size = Int32(MemoryLayout<RimeTraits>.size - MemoryLayout<Int32>.size)
        fresh.shared_data_dir = keep(directories.sharedData)
        fresh.user_data_dir = keep(directories.userData)
        fresh.distribution_name = keep("橘脑一颗")
        fresh.distribution_code_name = keep("OrangeCell")
        fresh.distribution_version = keep("0.2.0")
        fresh.app_name = keep(appName)
        fresh.min_log_level = 2
        fresh.log_dir = keep(directories.log ?? "")
        if let modules {
            moduleArray?.deallocate()
            moduleArray = nil
            let array = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: modules.count + 1)
            for (index, name) in modules.enumerated() { array[index] = keep(name) }
            array[modules.count] = nil
            moduleArray = array
            fresh.modules = array
        }
        traits = fresh

        api.pointee.setup(&traits)
        api.pointee.initialize(&traits)
        isInitialized = true
    }

    func finalize() {
        guard isInitialized, let api = rime_get_api() else { return }
        api.pointee.finalize()
        isInitialized = false
    }
}
