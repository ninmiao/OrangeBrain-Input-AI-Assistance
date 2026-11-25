// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Settings the main app writes and the keyboard reads (App Group `config/keyboard.json`).
/// Without Full Access the keyboard cannot see the group and uses the defaults.
public struct KeyboardSettings: Codable, Equatable, Sendable {
    /// The 1-0 row above qwerty. On by default, as on Android.
    public var numberRow: Bool = true

    public init(numberRow: Bool = true) {
        self.numberRow = numberRow
    }

    public static let fileName = "keyboard.json"

    public static func fileURL(in context: AppGroupContext) -> URL? {
        context.sharedDirectory("config")?.appendingPathComponent(fileName)
    }

    public static func load(in context: AppGroupContext) -> KeyboardSettings {
        guard let url = fileURL(in: context),
              let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(KeyboardSettings.self, from: data)
        else { return KeyboardSettings() }
        return settings
    }

    @discardableResult
    public func save(in context: AppGroupContext) -> Bool {
        guard let url = Self.fileURL(in: context), let data = try? JSONEncoder().encode(self) else { return false }
        return (try? data.write(to: url, options: [.atomic])) != nil
    }
}
