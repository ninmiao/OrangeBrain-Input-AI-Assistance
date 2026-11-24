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

/// Where the Rime data lives at run time (docs/IOS_PLAN.md section 4.3).
///
/// * shared data (read-only): `rime-shared/` inside the app bundle. The keyboard
///   extension sits in `OrangeCell.app/PlugIns/`, so it reads its host app's copy.
/// * user data (read-write): `rime-user/` in the App Group when Full Access allows
///   it, otherwise a private folder of the extension (docs/IOS_PLAN.md section 2).
public enum RimeDataLocator {
    public static let bundleFolderName = "rime-shared"
    public static let userFolderName = "rime-user"
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

    public struct UserDirectory: Equatable, Sendable {
        public var url: URL
        /// True when it lives in the App Group (shared with the app).
        public var isShared: Bool
    }

    /// Shared container when Full Access is on and the group is available, else the process's private folder.
    public static func userDataDirectory(
        context: AppGroupContext,
        hasFullAccess: Bool,
        fileManager: FileManager = .default
    ) -> UserDirectory? {
        if hasFullAccess, let container = context.containerURL {
            let url = container.appendingPathComponent(userFolderName, isDirectory: true)
            if (try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)) != nil {
                return UserDirectory(url: url, isShared: true)
            }
        }
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = support.appendingPathComponent(userFolderName, isDirectory: true)
        guard (try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)) != nil else { return nil }
        return UserDirectory(url: url, isShared: false)
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
