// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The parts of `embedded.mobileprovision` that matter for sideloading: which
/// App Group the signing tool really registered, the team, and when the
/// profile (and therefore the installed keyboard) stops working.
public struct ProvisioningProfile: Equatable, Sendable {
    public var name: String?
    public var uuid: String?
    public var teamIdentifier: String?
    public var applicationIdentifier: String?
    public var applicationGroups: [String]
    public var keychainAccessGroups: [String]
    public var creationDate: Date?
    public var expirationDate: Date?
    public var getTaskAllow: Bool?

    public enum ParseError: Error, Equatable {
        /// No `<?xml ... </plist>` span (and not a bare plist either).
        case noPropertyList
        /// The span is there but is not a property-list dictionary.
        case malformed
    }

    public init(
        name: String? = nil,
        uuid: String? = nil,
        teamIdentifier: String? = nil,
        applicationIdentifier: String? = nil,
        applicationGroups: [String] = [],
        keychainAccessGroups: [String] = [],
        creationDate: Date? = nil,
        expirationDate: Date? = nil,
        getTaskAllow: Bool? = nil
    ) {
        self.name = name
        self.uuid = uuid
        self.teamIdentifier = teamIdentifier
        self.applicationIdentifier = applicationIdentifier
        self.applicationGroups = applicationGroups
        self.keychainAccessGroups = keychainAccessGroups
        self.creationDate = creationDate
        self.expirationDate = expirationDate
        self.getTaskAllow = getTaskAllow
    }

    /// A provisioning profile is a CMS (PKCS#7) envelope around an XML property
    /// list. The XML is stored in clear, so cutting out the span from
    /// `<?xml` to the closing `</plist>` is enough; no signature check is
    /// attempted (the system already verified it when it launched the app).
    public static func extractPropertyList(from data: Data) -> Data? {
        let open = Data("<?xml".utf8)
        let close = Data("</plist>".utf8)
        if let start = data.range(of: open),
           let end = data.range(of: close, options: [], in: start.lowerBound..<data.endIndex) {
            return data.subdata(in: start.lowerBound..<end.upperBound)
        }
        // A binary plist handed over without the CMS wrapper.
        if data.starts(with: Data("bplist".utf8)) { return data }
        return nil
    }

    public static func parse(_ data: Data) throws -> ProvisioningProfile {
        guard let plist = extractPropertyList(from: data) else { throw ParseError.noPropertyList }
        guard let object = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil),
              let root = object as? [String: Any]
        else { throw ParseError.malformed }

        let entitlements = root["Entitlements"] as? [String: Any] ?? [:]
        var team: String? = (root["TeamIdentifier"] as? [String])?.first
        if team == nil { team = entitlements["com.apple.developer.team-identifier"] as? String }
        return ProvisioningProfile(
            name: root["Name"] as? String,
            uuid: root["UUID"] as? String,
            teamIdentifier: team,
            applicationIdentifier: entitlements["application-identifier"] as? String,
            applicationGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
            keychainAccessGroups: entitlements["keychain-access-groups"] as? [String] ?? [],
            creationDate: root["CreationDate"] as? Date,
            expirationDate: root["ExpirationDate"] as? Date,
            getTaskAllow: entitlements["get-task-allow"] as? Bool
        )
    }

    /// Reads `embedded.mobileprovision` from a bundle. Simulator builds and
    /// Mac-run test bundles have none, which is reported as `nil`.
    public static func load(from bundle: Bundle) -> ProvisioningProfile? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? parse(data)
    }

    /// Seconds until the profile expires; negative once expired; `nil` when unknown.
    public func secondsRemaining(now: Date = Date()) -> TimeInterval? {
        expirationDate.map { $0.timeIntervalSince(now) }
    }

    /// Whole days left, rounded down (never below zero). `nil` when unknown.
    public func daysRemaining(now: Date = Date()) -> Int? {
        secondsRemaining(now: now).map { max(0, Int(($0 / 86_400).rounded(.down))) }
    }

    /// True when fewer than `threshold` days are left (or already expired).
    public func isExpiring(within threshold: Int = 2, now: Date = Date()) -> Bool {
        guard let seconds = secondsRemaining(now: now) else { return false }
        return seconds < Double(threshold) * 86_400
    }
}
