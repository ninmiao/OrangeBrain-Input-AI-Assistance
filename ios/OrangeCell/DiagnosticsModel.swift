// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import OCCore
import OCRime

/// Collects what the diagnostics screen shows: this process's own report, the
/// keyboard's report (if it has run and can write to the shared container), the
/// Rime link check and the key-storage backend that follows from them.
@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published private(set) var app: DiagnosticsReport?
    @Published private(set) var keyboard: DiagnosticsReport?
    @Published private(set) var rime: RimeProbeResult?
    @Published private(set) var chosenBackend = "…"
    @Published private(set) var isLoading = false
    @Published private(set) var savedTo: [String] = []

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
                self.savedTo = work.saved
                self.isLoading = false
            }
        }
    }

    private struct Work {
        var app: DiagnosticsReport
        var keyboard: DiagnosticsReport?
        var rime: RimeProbeResult
        var backend: String
        var saved: [String]
    }

    nonisolated private static func collect() -> Work {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let probe = RimeProbe.run(workingDirectory: caches.appendingPathComponent("rime-m0-app", isDirectory: true))
        let report = DiagnosticsCollector.collect(
            role: "app",
            peerRole: "keyboard",
            writesKeySample: true,
            rimeVersion: probe.version,
            rimeModules: probe.modules
        )
        let saved = DiagnosticsCollector.save(report)
        let keyboard = DiagnosticsCollector.loadReport(role: "keyboard")
        let backend = KeyStorageSelfTest.chooseBackend(keyboardProbes: keyboard?.keyStorage ?? [])
        return Work(app: report, keyboard: keyboard, rime: probe, backend: backend, saved: saved)
    }
}
