// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What the diagnostics want to know about the linked librime: its version, which
/// plugin modules survived static linking, and whether `setup` + `initialize`
/// run at all inside an app or keyboard extension.
public struct RimeProbeResult: Codable, Equatable, Sendable {
    public var version: String?
    public var modulesBeforeStart: [String]
    public var modulesAfterStart: [String]
    public var started: Bool
    public var error: String?
    public var missingRequired: [String]

    public var modules: [String] { modulesAfterStart.isEmpty ? modulesBeforeStart : modulesAfterStart }
}

public enum RimeProbe {
    /// Starts the process's engine in `workingDirectory` (private, writable) with every
    /// linked module and reports. The engine is finalised afterwards unless `keepRunning`.
    /// Do not use it while a keyboard service of the same process is typing: it restarts
    /// the engine with different directories.
    public static func run(workingDirectory: URL, keepRunning: Bool = false) -> RimeProbeResult {
        let runtime = RimeRuntime.shared
        return runtime.queue.sync {
            let before = RimeEngine.registeredModules()
            let configuration = RimeRuntime.Configuration(
                sharedData: workingDirectory.appendingPathComponent("shared").path,
                userData: workingDirectory.appendingPathComponent("user").path,
                modules: nil
            )
            for path in [configuration.sharedData, configuration.userData] {
                try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            }
            let error = runtime.ensureStarted(configuration)
            let after = RimeEngine.registeredModules()
            let combined = Set(before).union(after)
            let result = RimeProbeResult(
                version: RimeEngine.version(),
                modulesBeforeStart: before,
                modulesAfterStart: after,
                started: error == nil,
                error: error.map { String(describing: $0) },
                missingRequired: RimeEngine.requiredModules.filter { !combined.contains($0) }
            )
            if !keepRunning { runtime.finalizeLocked() }
            return result
        }
    }
}
