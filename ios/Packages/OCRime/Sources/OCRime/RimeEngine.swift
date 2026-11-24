// SPDX-License-Identifier: GPL-3.0-or-later
import CRime
import Foundation

public enum RimeEngineError: Error, Equatable {
    case apiUnavailable
}

/// Minimal Swift handle on librime: version, set-up / initialise / finalise and
/// a look at which modules (lua, octagram, predict, ...) are registered.
/// Sessions, candidates and deployment arrive with milestone M1.
public final class RimeEngine {
    /// Modules the prebuilt librime is expected to contain. `required` ones
    /// must be registered or the build is not what the plan assumes.
    public static let requiredModules = ["lua", "octagram", "predict"]
    public static let candidateModules = [
        "default", "core", "dict", "gears", "levers", "deployer",
        "lua", "octagram", "grammar", "predict", "qjs",
    ]

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
    private var ownedStrings: [UnsafeMutablePointer<CChar>] = []
    private let directories: Directories
    private let appName: String

    public init(directories: Directories, appName: String = "rime.orangecell") {
        self.directories = directories
        self.appName = appName
    }

    deinit {
        if isInitialized { finalize() }
        ownedStrings.forEach { free($0) }
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

    private func keep(_ string: String) -> UnsafePointer<CChar> {
        let copy = strdup(string)!
        ownedStrings.append(copy)
        return UnsafePointer(copy)
    }

    /// `setup` + `initialize`. Creates the directories first; librime does not.
    public func start() throws {
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
        fresh.distribution_version = keep("0.1.0")
        fresh.app_name = keep(appName)
        fresh.min_log_level = 2
        fresh.log_dir = keep(directories.log ?? "")
        traits = fresh

        api.pointee.setup(&traits)
        api.pointee.initialize(&traits)
        isInitialized = true
    }

    public func finalize() {
        guard isInitialized, let api = rime_get_api() else { return }
        api.pointee.finalize()
        isInitialized = false
    }
}
