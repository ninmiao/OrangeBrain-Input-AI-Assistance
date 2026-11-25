// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What `ios/scripts/build-rime-data.sh` records next to the compiled data
/// (`rime-shared/oc-data.json`): which librime built it, from which inputs.
public struct RimeDataStamp: Codable, Equatable, Sendable {
    public struct DictionaryInfo: Codable, Equatable, Sendable {
        public var name: String
        public var version: String
        public var assetSha256: String
        public var license: String
    }

    public struct File: Codable, Equatable, Sendable {
        public var path: String
        public var size: Int
    }

    public var format: Int
    public var builtWithLibrime: String?
    public var schema: String
    public var dictionary: DictionaryInfo
    public var grammarModel: Bool
    public var inputSha256: String
    public var builtAtUtc: String
    public var files: [File]

    public var totalBytes: Int { files.reduce(0) { $0 + $1.size } }

    /// Size of the biggest compiled table (the dictionary proper), for the diagnostics screen.
    public var dictionaryBytes: Int {
        files.filter { $0.path.hasSuffix(".table.bin") }.reduce(0) { $0 + $1.size }
    }
}

//// Where the Rime data lives at run time (docs/IOS_PLAN.md section 4.3).
///
/// * shared data (read-only): `rime-shared/` inside the app bundle. The keyboard
///   extension sits in `OrangeCell.app/PlugIns/`, so it reads its host app's copy.
/// * user data (read-write, the live user dictionary): always the keyboard's own
///   `Application Support/rime-user`, whatever the Full Access switch says. Only the keyboard
///   opens it, so learned words do not depend on a setting the user can flip.
/// * staging (Full Access): `rime-build/` in the App Group. The app deploys its compiled
///   configuration there, the keyboard reads it ahead of the prebuilt files.
/// * snapshot export (Full Access): `rime-sync/` in the App Group, text snapshots of the user
///   dictionary the keyboard writes when it goes idle, for the app to show or back up.
public enum RimeDataLocator {
    public static let bundleFolderName = "rime-shared"
    public static let userFolderName = "rime-user"
    public static let stagingFolderName = "rime-build"
    public static let syncFolderName = "rime-sync"
    /// The app scratch directory for deployments (it holds `default.custom.yaml`).
    public static let appFolderName = "rime-app"
    public static let stampFileName = "oc-data.json"

    /// `Bundle.main/rime-shared` for the app, `../../rime-shared` for an app extension.
    public static func sharedDataDirectory(bundle: Bundle = .main, fileManager: FileManager = .default) -> URL? {
        var candidates = [bundle.bundleURL.appendingPathComponent(bundleFolderName, isDirectory: true)]
        if bundle.bundleURL.pathExtension == "appex" {
            candidates.append(
                bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent(bundleFolderName, isDirectory: true)
            )
        }
        return candidates.first { fileManager.fileExists(atPath: $0.appendingPathComponent("build").path) }
    }

    public static func dataStamp(sharedDirectory: URL) -> RimeDataStamp? {
        guard let data = try? Data(contentsOf: sharedDirectory.appendingPathComponent(stampFileName)) else { return nil }
        return try? JSONDecoder().decode(RimeDataStamp.self, from: data)
    }

    /// The directories one keyboard process hands to librime.
    public struct KeyboardDirectories: Equatable, Sendable {
        /// Live user dictionary (LevelDB), `user.yaml`, `installation.yaml`; private to the extension.
        public var user: URL
        /// App Group `rime-build`, only with Full Access and a usable group.
        public var staging: URL?
        /// App Group `rime-sync`, only with Full Access and a usable group.
        public var syncExport: URL?
        /// App Group `rime-user` of an M1 build, if there is one to migrate.
        public var legacyUser: URL?
    }

    /// `Application Support/rime-user` of this process.
    public static func privateUserDirectory(fileManager: FileManager = .default) -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = support.appendingPathComponent(userFolderName, isDirectory: true)
        guard (try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)) != nil else { return nil }
        return url
    }

    public static func keyboardDirectories(
        context: AppGroupContext,
        hasFullAccess: Bool,
        privateUser: URL? = nil,
        fileManager: FileManager = .default
    ) -> KeyboardDirectories? {
        guard let user = privateUser ?? privateUserDirectory(fileManager: fileManager) else { return nil }
        var directories = KeyboardDirectories(user: user, staging: nil, syncExport: nil, legacyUser: nil)
        if hasFullAccess, let container = context.containerURL {
            directories.staging = container.appendingPathComponent(stagingFolderName, isDirectory: true)
            directories.syncExport = container.appendingPathComponent(syncFolderName, isDirectory: true)
            directories.legacyUser = container.appendingPathComponent(userFolderName, isDirectory: true)
        }
        return directories
    }

    /// The app directories for a deployment: a scratch user directory with the customisation
    /// and the staging directory the keyboard reads. Needs the App Group.
    public static func appDeployDirectories(context: AppGroupContext, fileManager: FileManager = .default) -> (user: URL, staging: URL)? {
        guard let container = context.containerURL else { return nil }
        let user = container.appendingPathComponent(appFolderName, isDirectory: true)
        let staging = container.appendingPathComponent(stagingFolderName, isDirectory: true)
        for url in [user, staging] {
            guard (try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)) != nil else { return nil }
        }
        return (user, staging)
    }
}

/// M1 builds kept the live user dictionary in the App Group when Full Access was on. From M2 on it
/// lives in the keyboard private folder in every case; a dictionary found in the group is moved
/// there once, if the private folder has none yet.
public enum UserDictionaryMigration {
    public enum Result: Equatable, Sendable {
        case notNeeded
        case moved([String])
        case failed(String)

        public var summary: String {
            switch self {
            case .notNeeded: return "not needed"
            case .moved(let names): return "moved " + names.joined(separator: ",")
            case .failed(let reason): return "failed " + reason
            }
        }
    }

    private static func userdbs(in directory: URL, fileManager: FileManager) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".userdb") }.sorted()
    }

    @discardableResult
    public static func migrate(from legacy: URL, to privateUser: URL, fileManager: FileManager = .default) -> Result {
        let old = userdbs(in: legacy, fileManager: fileManager)
        guard !old.isEmpty, userdbs(in: privateUser, fileManager: fileManager).isEmpty else { return .notNeeded }
        do {
            try fileManager.createDirectory(at: privateUser, withIntermediateDirectories: true)
            var moved: [String] = []
            for name in old {
                let source = legacy.appendingPathComponent(name, isDirectory: true)
                let target = privateUser.appendingPathComponent(name, isDirectory: true)
                do {
                    try fileManager.moveItem(at: source, to: target)
                } catch {
                    // Another volume, or a file that cannot be renamed: copy, then remove the original.
                    try fileManager.copyItem(at: source, to: target)
                    try? fileManager.removeItem(at: source)
                }
                moved.append(name)
            }
            return .moved(moved)
        } catch {
            return .failed(String(describing: error))
        }
    }
}

/// `installation.yaml` tells librime where `sync_user_data` exports to. The keyboard writes the
/// sync directory (App Group `rime-sync`) into it before the engine starts.
public enum RimeInstallation {
    public static let installationID = "orangecell-ios"

    /// Creates or updates `installation.yaml` so that `sync_dir` is `syncDirectory`. Returns whether it changed.
    @discardableResult
    public static func prepare(userDirectory: URL, syncDirectory: URL?, fileManager: FileManager = .default) -> Bool {
        let file = userDirectory.appendingPathComponent("installation.yaml")
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        func set(_ key: String, _ value: String?) {
            lines.removeAll { $0.hasPrefix(key + ":") }
            if let value { lines.append(key + ": \"" + value + "\"") }
        }
        if !lines.contains(where: { $0.hasPrefix("installation_id:") }) { set("installation_id", installationID) }
        set("sync_dir", syncDirectory?.path)
        let text = lines.joined(separator: "\n") + "\n"
        guard text != existing else { return false }
        try? fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        if let syncDirectory { try? fileManager.createDirectory(at: syncDirectory, withIntermediateDirectories: true) }
        return (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil
    }
}

/// `state/deploy-stamp` in the App Group: the app writes a new value after every
/// deployment, the keyboard compares it whenever it appears and restarts Rime when
/// it changed (docs/IOS_PLAN.md section 4.4).
public enum DeployStamp {
    public static func fileURL(in context: AppGroupContext) -> URL? {
        context.sharedDirectory("state")?.appendingPathComponent("deploy-stamp")
    }

    public static func read(in context: AppGroupContext) -> String? {
        guard let url = fileURL(in: context),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Atomically replaces the stamp. Returns the value written.
    @discardableResult
    public static func write(in context: AppGroupContext, now: Date = Date()) throws -> String {
        guard let url = fileURL(in: context) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let value = ISO8601DateFormatter().string(from: now) + "-" + String(UUID().uuidString.prefix(8))
        try Data((value + "\n").utf8).write(to: url, options: [.atomic])
        return value
    }
}

/// `oc-build.json` next to the compiled files the app deploys into App Group `rime-build`. librime reads
/// that folder ahead of the prebuilt data, so the keyboard must be sure the files belong to the data bundled
/// with this version of the app (an app update with new data makes an older deployment stale) and are
/// complete (the app builds into a temporary folder and renames it, but a file can still be damaged).
public struct RimeBuildStamp: Codable, Equatable, Sendable {
    public var appBuild: String
    /// `inputSha256` of the `oc-data.json` the deployment was made against.
    public var dataInputSha256: String
    public var builtWithLibrime: String?
    public var deployedAt: String

    public static let fileName = "oc-build.json"

    public init(appBuild: String, dataInputSha256: String, builtWithLibrime: String?, deployedAt: String) {
        self.appBuild = appBuild
        self.dataInputSha256 = dataInputSha256
        self.builtWithLibrime = builtWithLibrime
        self.deployedAt = deployedAt
    }

    public enum Validity: Equatable, Sendable {
        case valid
        /// Nothing deployed (no `default.yaml`): the prebuilt files are used.
        case missing
        /// Deployed, but not usable: the keyboard ignores it (the app removes or rebuilds it).
        case invalid(String)

        public var summary: String {
            switch self {
            case .valid: return "valid"
            case .missing: return "none"
            case .invalid(let reason): return "ignored: " + reason
            }
        }
    }

    public static func validate(stagingDirectory: URL, sharedDirectory: URL, fileManager: FileManager = .default) -> Validity {
        let compiled = stagingDirectory.appendingPathComponent("default.yaml")
        guard fileManager.fileExists(atPath: compiled.path) else { return .missing }
        guard let data = try? Data(contentsOf: stagingDirectory.appendingPathComponent(fileName)),
              let stamp = try? JSONDecoder().decode(RimeBuildStamp.self, from: data)
        else { return .invalid("no build stamp") }
        guard let bundled = RimeDataLocator.dataStamp(sharedDirectory: sharedDirectory) else { return .invalid("no bundled data stamp") }
        guard stamp.dataInputSha256 == bundled.inputSha256 else { return .invalid("made for older bundled data") }
        guard let text = try? String(contentsOf: compiled, encoding: .utf8), text.contains("schema_list") else {
            return .invalid("default.yaml unreadable")
        }
        return .valid
    }
}
