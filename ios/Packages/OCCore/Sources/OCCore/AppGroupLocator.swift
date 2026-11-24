// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Finds the App Group that this build really owns.
///
/// The project asks for `group.io.github.ninmiao.orangecell`, but a free-account
/// sideloading tool re-registers it as `group.io.github.ninmiao.orangecell.<TEAMID>`.
/// The truth is in the embedded provisioning profile, so the name is never
/// hard-coded at the call sites.
public enum AppGroupLocator {
    public static let nominalGroup = "group.io.github.ninmiao.orangecell"

    public enum Source: String, Codable, Equatable, Sendable {
        /// The profile lists exactly the requested group.
        case profileExact
        /// The profile lists the requested group with a `.TEAMID` (or other) suffix.
        case profileSuffixed
        /// There is no profile to read (simulator, test bundle); the requested name is used.
        case nominalNoProfile
        /// A profile exists but contains no matching group: run in no-sharing mode.
        case missing
    }

    public struct Resolution: Equatable, Sendable {
        public let identifier: String?
        public let source: Source

        public init(identifier: String?, source: Source) {
            self.identifier = identifier
            self.source = source
        }
    }

    /// Pure function: picks the group from a profile's group list.
    public static func resolve(
        profile: ProvisioningProfile?,
        nominal: String = nominalGroup
    ) -> Resolution {
        guard let profile else {
            return Resolution(identifier: nominal, source: .nominalNoProfile)
        }
        let groups = profile.applicationGroups
        if groups.contains(nominal) {
            return Resolution(identifier: nominal, source: .profileExact)
        }
        let prefix = nominal + "."
        let suffixed = groups.filter { $0.hasPrefix(prefix) && $0.count > prefix.count }.sorted()
        if let team = profile.teamIdentifier, suffixed.contains(prefix + team) {
            return Resolution(identifier: prefix + team, source: .profileSuffixed)
        }
        if let first = suffixed.first {
            return Resolution(identifier: first, source: .profileSuffixed)
        }
        return Resolution(identifier: nil, source: .missing)
    }

    /// The shared container directory for a resolved group, or `nil` when the
    /// system does not hand one out (capability stripped, wrong signature).
    public static func containerURL(for resolution: Resolution) -> URL? {
        #if canImport(Darwin)
        guard let identifier = resolution.identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        return nil
        #endif
    }
}

/// Everything a process learns about its sharing situation at start-up.
public struct AppGroupContext: Sendable {
    public let profile: ProvisioningProfile?
    public let resolution: AppGroupLocator.Resolution
    public let containerURL: URL?

    public init(profile: ProvisioningProfile?, resolution: AppGroupLocator.Resolution, containerURL: URL?) {
        self.profile = profile
        self.resolution = resolution
        self.containerURL = containerURL
    }

    public static func detect(bundle: Bundle = .main) -> AppGroupContext {
        let profile = ProvisioningProfile.load(from: bundle)
        let resolution = AppGroupLocator.resolve(profile: profile)
        return AppGroupContext(
            profile: profile,
            resolution: resolution,
            containerURL: AppGroupLocator.containerURL(for: resolution)
        )
    }

    /// Directory for files shared between the app and the keyboard, created on demand.
    public func sharedDirectory(_ name: String) -> URL? {
        guard let base = containerURL else { return nil }
        let url = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
