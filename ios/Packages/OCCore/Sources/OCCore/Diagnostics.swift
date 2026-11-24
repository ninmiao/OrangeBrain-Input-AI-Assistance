// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Process memory as the system's jetsam accounting sees it (`phys_footprint`).
public enum MemoryProbe {
    public static func physFootprintBytes() -> UInt64? {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
        #else
        return nil
        #endif
    }

    public static func physFootprintMB() -> Double? {
        physFootprintBytes().map { (Double($0) / 1_048_576 * 10).rounded() / 10 }
    }
}

/// A small file one process leaves in the App Group so the other can prove it
/// sees the same directory.
public struct ProbeRecord: Codable, Equatable, Sendable {
    public var role: String
    public var groupIdentifier: String
    public var writtenAt: Date
    public var processID: Int32
    public var bundleIdentifier: String
    public var nonce: String

    public init(role: String, groupIdentifier: String, writtenAt: Date, processID: Int32, bundleIdentifier: String, nonce: String) {
        self.role = role
        self.groupIdentifier = groupIdentifier
        self.writtenAt = writtenAt
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.nonce = nonce
    }
}

public enum DiagnosticsFiles {
    public static let directoryName = "diagnostics"

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func directory(in context: AppGroupContext) -> URL? {
        context.sharedDirectory(directoryName)
    }

    /// The process's own cache folder, readable by a test harness on the simulator
    /// even when the shared container is not available.
    public static func privateDirectory() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = caches.appendingPathComponent("oc-diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

public enum AppGroupProbe {
    /// Writes `probe-<role>.json` into the shared container. `nil` when there is
    /// no container or the write failed.
    @discardableResult
    public static func write(role: String, context: AppGroupContext, bundleIdentifier: String) -> ProbeRecord? {
        guard let identifier = context.resolution.identifier,
              let directory = DiagnosticsFiles.directory(in: context)
        else { return nil }
        let record = ProbeRecord(
            role: role,
            groupIdentifier: identifier,
            writtenAt: Date(),
            processID: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            nonce: UUID().uuidString
        )
        do {
            let data = try DiagnosticsFiles.encoder().encode(record)
            try data.write(to: directory.appendingPathComponent("probe-\(role).json"), options: [.atomic])
            return record
        } catch {
            return nil
        }
    }

    /// Reads the other role's probe, if it is visible from this process.
    public static func read(role: String, context: AppGroupContext) -> ProbeRecord? {
        guard let directory = DiagnosticsFiles.directory(in: context),
              let data = try? Data(contentsOf: directory.appendingPathComponent("probe-\(role).json"))
        else { return nil }
        return try? DiagnosticsFiles.decoder().decode(ProbeRecord.self, from: data)
    }
}

/// Everything the diagnostics screen (and the CI summary) wants to know about one process.
public struct DiagnosticsReport: Codable, Equatable, Sendable {
    public var role: String
    public var generatedAt: Date
    public var bundleIdentifier: String
    public var appVersion: String
    public var fullAccess: Bool?

    public var groupNominal: String
    public var groupResolved: String?
    public var groupSource: String
    public var containerPath: String?
    public var containerWritable: Bool
    public var probeWritten: Bool
    public var peerProbe: ProbeRecord?

    public var profileName: String?
    public var teamIdentifier: String?
    public var profileGroups: [String]
    public var profileExpires: Date?
    public var profileDaysRemaining: Int?

    public var keyStorage: [KeyStorageProbe]
    public var footprintMB: Double?
    public var rimeVersion: String?
    public var rimeModules: [String]
    public var ocCoreOK: Bool
    public var notes: [String]
}

public enum DiagnosticsCollector {
    /// - Parameters:
    ///   - role: `"app"` or `"keyboard"`.
    ///   - peerRole: the role whose probe file should be looked for.
    ///   - writesKeySample: the app stores the key-storage sample, the keyboard only reads it.
    public static func collect(
        role: String,
        peerRole: String,
        bundle: Bundle = .main,
        fullAccess: Bool? = nil,
        writesKeySample: Bool,
        rimeVersion: String?,
        rimeModules: [String],
        now: Date = Date()
    ) -> DiagnosticsReport {
        let context = AppGroupContext.detect(bundle: bundle)
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
            + " (" + (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?") + ")"
        var notes: [String] = []

        let probeWritten = AppGroupProbe.write(role: role, context: context, bundleIdentifier: bundleID) != nil
        if context.containerURL == nil {
            notes.append("App Group container unavailable: sharing between app and keyboard is off")
        }
        let peer = AppGroupProbe.read(role: peerRole, context: context)

        let keyProbes = writesKeySample
            ? KeyStorageSelfTest.writeAndVerifyLocally(context: context)
            : KeyStorageSelfTest.readAcrossProcesses(context: context)

        let profile = context.profile
        if profile == nil { notes.append("no embedded.mobileprovision (simulator or test bundle)") }

        return DiagnosticsReport(
            role: role,
            generatedAt: now,
            bundleIdentifier: bundleID,
            appVersion: version,
            fullAccess: fullAccess,
            groupNominal: AppGroupLocator.nominalGroup,
            groupResolved: context.resolution.identifier,
            groupSource: context.resolution.source.rawValue,
            containerPath: context.containerURL?.path,
            containerWritable: probeWritten,
            probeWritten: probeWritten,
            peerProbe: peer,
            profileName: profile?.name,
            teamIdentifier: profile?.teamIdentifier,
            profileGroups: profile?.applicationGroups ?? [],
            profileExpires: profile?.expirationDate,
            profileDaysRemaining: profile?.daysRemaining(now: now),
            keyStorage: keyProbes,
            footprintMB: MemoryProbe.physFootprintMB(),
            rimeVersion: rimeVersion,
            rimeModules: rimeModules,
            ocCoreOK: NativeCore.selfTest(),
            notes: notes
        )
    }

    /// Writes `report-<role>.json` to the shared container and to the process's
    /// private cache folder. Returns the paths that were written.
    @discardableResult
    public static func save(_ report: DiagnosticsReport, bundle: Bundle = .main) -> [String] {
        guard let data = try? DiagnosticsFiles.encoder().encode(report) else { return [] }
        var written: [String] = []
        let context = AppGroupContext.detect(bundle: bundle)
        var targets: [URL] = []
        if let shared = DiagnosticsFiles.directory(in: context) { targets.append(shared) }
        if let local = DiagnosticsFiles.privateDirectory() { targets.append(local) }
        for directory in targets {
            let url = directory.appendingPathComponent("report-\(report.role).json")
            if (try? data.write(to: url, options: [.atomic])) != nil { written.append(url.path) }
        }
        return written
    }

    /// Reads another process's report from the shared container.
    public static func loadReport(role: String, bundle: Bundle = .main) -> DiagnosticsReport? {
        let context = AppGroupContext.detect(bundle: bundle)
        guard let directory = DiagnosticsFiles.directory(in: context),
              let data = try? Data(contentsOf: directory.appendingPathComponent("report-\(role).json"))
        else { return nil }
        return try? DiagnosticsFiles.decoder().decode(DiagnosticsReport.self, from: data)
    }

    /// The report as pretty JSON, for sharing from the diagnostics screen.
    public static func json(_ report: DiagnosticsReport) -> String {
        guard let data = try? DiagnosticsFiles.encoder().encode(report) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
