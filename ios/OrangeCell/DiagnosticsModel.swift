// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import OCCore
import OCRime

/// Collects what the diagnostics screen shows: this process's own report, the
/// keyboard's report (if it has run and can write to the shared container), the
/// Rime link check and the key-storage backend that follows from them. Looking at the
/// page changes nothing on disk except the app's probe file; the key-storage writer
/// self-test and the deployment are explicit buttons.
@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published private(set) var app: DiagnosticsReport?
    @Published private(set) var keyboard: DiagnosticsReport?
    @Published private(set) var rime: RimeProbeResult?
    @Published private(set) var chosenBackend = "…"
    @Published private(set) var isLoading = false
    @Published private(set) var deployOutcome: DeployAction.Outcome?
    @Published private(set) var selfTestProbes: [KeyStorageProbe] = []
    /// The AI configuration in words (no key, nothing typed): what is switched on and where the key lives.
    @Published private(set) var aiLines: [AiLine] = []

    struct AiLine: Hashable {
        let title: String
        let value: String
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let work = Self.collect()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.app = work.app
                self.keyboard = work.keyboard
                self.rime = work.rime
                self.chosenBackend = work.backend
                self.aiLines = work.ai
                self.isLoading = false
            }
        }
    }

    /// Explicit action: writes the test value into every key-storage backend (the keyboard
    /// then proves it can read it back). Never runs on its own.
    func runKeySelfTest() {
        Task.detached(priority: .userInitiated) {
            let context = AppGroupContext.detect()
            let probes = KeyStorageSelfTest.writeAndVerifyLocally(context: context)
            await MainActor.run { [weak self] in
                self?.selfTestProbes = probes
                self?.isLoading = false
                self?.refresh()
            }
        }
    }

    /// Explicit action: recompile the configuration into the App Group and tell the keyboard.
    func deploy() {
        Task.detached(priority: .userInitiated) {
            let outcome = DeployAction.run()
            DeployAction.save(outcome)
            await MainActor.run { [weak self] in
                self?.deployOutcome = outcome
                self?.isLoading = false
                self?.refresh()
            }
        }
    }

    private struct Work {
        var app: DiagnosticsReport
        var keyboard: DiagnosticsReport?
        var rime: RimeProbeResult
        var backend: String
        var ai: [AiLine]
    }

    nonisolated private static func collect() -> Work {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let probe = RimeProbe.run(workingDirectory: caches.appendingPathComponent("rime-probe", isDirectory: true))
        let report = DiagnosticsCollector.collect(
            role: "app",
            peerRole: "keyboard",
            writesKeySample: false,
            rimeVersion: probe.version,
            rimeModules: probe.modules
        )
        DiagnosticsCollector.save(report)
        let keyboard = DiagnosticsCollector.loadReport(role: "keyboard")
        let backend = KeyStorageSelfTest.chooseBackend(keyboardProbes: keyboard?.keyStorage ?? [])
        return Work(app: report, keyboard: keyboard, rime: probe, backend: backend, ai: aiLines())
    }

    nonisolated private static func aiLines() -> [AiLine] {
        let context = AppGroupContext.detect()
        guard let config = AiConfigFile.read(in: context) else {
            return [AiLine(title: "AI 配置", value: "还没有（打开「AI 云端候选」后生成）")]
        }
        let vault = CredentialVault(context: context)
        let policy = config.policies.first { $0.id == config.selectedPolicyId }
        return [
            AiLine(title: "云端同意", value: config.consent ? "已同意" : "未同意"),
            AiLine(title: "自动模式", value: AiMode.of(config).title),
            AiLine(title: "当前 Policy", value: policy?.name ?? config.selectedPolicyId),
            AiLine(title: "模型", value: config.model),
            AiLine(title: "接口域名", value: URL(string: config.endpoint)?.host ?? "—"),
            AiLine(title: "当前 Policy 的 Key", value: vault.has(policyID: config.selectedPolicyId) ? "已保存" : "尚未配置"),
            AiLine(title: "Key 存储（实际使用）", value: vault.backendName),
            AiLine(title: "配置戳", value: AiConfigFile.readStamp(in: context) ?? "—"),
        ]
    }
}
