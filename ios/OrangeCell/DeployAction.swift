// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import OCCore
import OCRime

/// Deployment from the main app (docs/IOS_PLAN.md section 4.4): the keyboard never
/// deploys. The app recompiles `default.yaml` (with the iOS customization) into the
/// App Group's `rime-user/build` and writes a new `state/deploy-stamp`; the keyboard
/// restarts its engine when it sees the stamp change. The compiled dictionary itself
/// is read-only inside the app bundle and is not rebuilt on the phone.
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
        guard let user = RimeDataLocator.userDataDirectory(context: context, hasFullAccess: true), user.isShared else {
            return fail("App Group 不可用：键盘读不到主应用的部署结果")
        }
        // The iOS customization (Wanxiang only) travels with the data; copy it once, never overwrite edits.
        let custom = user.url.appendingPathComponent("default.custom.yaml")
        if !FileManager.default.fileExists(atPath: custom.path) {
            try? FileManager.default.copyItem(at: shared.appendingPathComponent("default.custom.yaml"), to: custom)
        }
        guard RimeDeployer.deployConfigFile(sharedData: shared, userData: user.url) else {
            return fail("librime 部署 default.yaml 失败")
        }
        do {
            let stamp = try DeployStamp.write(in: context)
            return Outcome(success: true, message: "已部署配置，键盘下次出现时重新载入", stamp: stamp,
                           userDirectory: user.url.path, finishedAt: Date())
        } catch {
            return fail("部署成功，但无法写入部署戳：\(error.localizedDescription)")
        }
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
