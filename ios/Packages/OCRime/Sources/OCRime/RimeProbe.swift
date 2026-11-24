// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What the M0 spike wants to know about the linked librime: its version, which
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
    /// Starts librime in `workingDirectory` (private, writable) and reports.
    /// With `keepRunning` the initialised engine is returned so a caller can
    /// measure memory with Rime resident; otherwise it is finalised first.
    public static func run(workingDirectory: URL, keepRunning: Bool = false) -> (result: RimeProbeResult, engine: RimeEngine?) {
        let before = RimeEngine.registeredModules()
        let engine = RimeEngine(directories: .init(
            sharedData: workingDirectory.appendingPathComponent("shared").path,
            userData: workingDirectory.appendingPathComponent("user").path
        ))
        var started = false
        var errorText: String?
        do {
            try engine.start()
            started = true
        } catch {
            errorText = String(describing: error)
        }
        let after = RimeEngine.registeredModules()
        let combined = Set(before).union(after)
        let result = RimeProbeResult(
            version: RimeEngine.version(),
            modulesBeforeStart: before,
            modulesAfterStart: after,
            started: started,
            error: errorText,
            missingRequired: RimeEngine.requiredModules.filter { !combined.contains($0) }
        )
        if keepRunning, started { return (result, engine) }
        engine.finalize()
        return (result, nil)
    }
}
