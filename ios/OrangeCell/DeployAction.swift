// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import OCCore
import OCRime

/// Deployment from the main app (docs/IOS_PLAN.md section 4.4): the keyboard never
/// deploys. The app recompiles `default.yaml` (with the iOS customization) and writes a new
/// `state/deploy-stamp`; the keyboard (Full Access) reads the result ahead of the prebuilt data and
/// opens a new session when it sees the stamp change. The compiled dictionary itself is read-only
/// inside the app bundle and is not rebuilt on the phone.
///
/// Safe by construction:
/// * the result is built in a temporary folder and renamed into place, so the keyboard never sees a
///   half-written build (it sees the old folder, no folder, or the new folder);
/// * `oc-build.json` ties the build to the app build and to the bundled data; the keyboard ignores a build
///   made for other data, and `removeStaleBuild` deletes it when the app starts after an update;
/// * the user dictionary is not touched: it lives in the keyboard.
enum DeployAction {
    struct Outcome: Codable, Equatable {
        var success: Bool
        var message: String
        var stamp: String?
        var userDirectory: String?
        var finishedAt: Date
    }

    static func run(bundle: Bundle = .main) -> Outcome {
        let now = Date()
        func fail(_ message: String) -> Outcome {
            Outcome(success: false, message: message, stamp: nil, userDirectory: nil, finishedAt: now)
        }
        let context = AppGroupContext.detect(bundle: bundle)
        guard let shared = RimeDataLocator.sharedDataDirectory(bundle: bundle) else {
            return fail("应用里没有找到编译好的词库")
        }
        guard let directories = RimeDataLocator.appDeployDirectories(context: context),
              let container = context.containerURL else {
            return fail("App Group 不可用：键盘读不到主应用的部署结果")
        }
        installCustomization(from: shared, into: directories.user)

        // Build in a temporary sibling folder, then swap it in.
        let fileManager = FileManager.default
        let staging = directories.staging
        let temporary = container.appendingPathComponent(RimeDataLocator.stagingFolderName + ".tmp-" + UUID().uuidString, isDirectory: true)
        try? fileManager.removeItem(at: temporary)
        guard RimeDeployer.deployConfigFile(sharedData: shared, userData: directories.user, stagingData: temporary) else {
            try? fileManager.removeItem(at: temporary)
            return fail("librime 部署 default.yaml 失败")
        }
        guard fileManager.fileExists(atPath: temporary.appendingPathComponent("default.yaml").path) else {
            try? fileManager.removeItem(at: temporary)
            return fail("部署没有产生 default.yaml")
        }
        let bundled = RimeDataLocator.dataStamp(sharedDirectory: shared)
        let build = RimeBuildStamp(
            appBuild: (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?",
            dataInputSha256: bundled?.inputSha256 ?? "",
            builtWithLibrime: bundled?.builtWithLibrime,
            deployedAt: ISO8601DateFormatter().string(from: now))
        do {
            try JSONEncoder().encode(build).write(to: temporary.appendingPathComponent(RimeBuildStamp.fileName), options: [.atomic])
            try swapIn(temporary, as: staging)
        } catch {
            try? fileManager.removeItem(at: temporary)
            return fail("无法放置部署结果：\(error.localizedDescription)")
        }
        do {
            let stamp = try DeployStamp.write(in: context)
            return Outcome(success: true, message: "已部署配置，键盘下次出现时重新载入", stamp: stamp,
                           userDirectory: staging.path, finishedAt: Date())
        } catch {
            return fail("部署成功，但无法写入部署戳：\(error.localizedDescription)")
        }
    }

    /// Replaces `destination` by `source` with two renames: the old folder is renamed away first, so a reader
    /// sees either the old folder, no folder, or the new one, never a mixture.
    static func swapIn(_ source: URL, as destination: URL) throws {
        let fileManager = FileManager.default
        let old = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".old-" + UUID().uuidString)
        var movedOld = false
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: destination, to: old)
            movedOld = true
        }
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            if movedOld { try? fileManager.moveItem(at: old, to: destination) }
            throw error
        }
        if movedOld { try? fileManager.removeItem(at: old) }
    }

    /// The iOS customization (Wanxiang only) travels with the data. It is refreshed when the bundled one
    /// changed *and* the copy in the group is still the one we installed; a copy somebody edited is kept.
    /// The bundled hash is recorded next to the file.
    static func installCustomization(from shared: URL, into user: URL) {
        let fileManager = FileManager.default
        let bundled = shared.appendingPathComponent("default.custom.yaml")
        let installed = user.appendingPathComponent("default.custom.yaml")
        let record = user.appendingPathComponent("default.custom.yaml.bundled-sha256")
        func hash(of url: URL) -> String? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        guard let bundledHash = hash(of: bundled) else { return }
        let recordedHash = (try? String(contentsOf: record, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let installedHash = hash(of: installed)
        let untouched = installedHash == nil || installedHash == recordedHash
        guard untouched, installedHash != bundledHash else {
            if installedHash == bundledHash { try? Data((bundledHash + "\n").utf8).write(to: record, options: [.atomic]) }
            return
        }
        try? fileManager.removeItem(at: installed)
        try? fileManager.copyItem(at: bundled, to: installed)
        try? Data((bundledHash + "\n").utf8).write(to: record, options: [.atomic])
    }

    /// After an app update: a deployment made for older bundled data is useless (the keyboard ignores it)
    /// and is removed so that the next deployment starts clean. Returns what was found.
    @discardableResult
    static func removeStaleBuild(bundle: Bundle = .main) -> RimeBuildStamp.Validity {
        let context = AppGroupContext.detect(bundle: bundle)
        guard let shared = RimeDataLocator.sharedDataDirectory(bundle: bundle),
              let container = context.containerURL else { return .missing }
        let staging = container.appendingPathComponent(RimeDataLocator.stagingFolderName, isDirectory: true)
        let validity = RimeBuildStamp.validate(stagingDirectory: staging, sharedDirectory: shared)
        if case .invalid = validity {
            try? FileManager.default.removeItem(at: staging)
            _ = try? DeployStamp.write(in: context)
        }
        return validity
    }

    /// Leaves the outcome where the CI run and the diagnostics page can read it.
    static func save(_ outcome: Outcome, bundle: Bundle = .main) {
        guard let data = try? DiagnosticsFiles.encoder().encode(outcome) else { return }
        let context = AppGroupContext.detect(bundle: bundle)
        let directories = [context.sharedDirectory(DiagnosticsFiles.directoryName), DiagnosticsFiles.privateDirectory()]
        for directory in directories.compactMap({ $0 }) {
            try? data.write(to: directory.appendingPathComponent("deploy-result.json"), options: [.atomic])
        }
    }
}
