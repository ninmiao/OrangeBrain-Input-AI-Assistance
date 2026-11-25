// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// One request to a provider: the connection of the selected policy plus the snapshot to convert.
public struct AiCall: Sendable {
    public var endpoint: String
    public var key: String
    public var model: String
    public var timeoutMs: Int
    public var parameters: [String: JSONPrimitive]
    public var provider: String
    public var request: AiRequest

    public init(endpoint: String, key: String, model: String, timeoutMs: Int, parameters: [String: JSONPrimitive],
                provider: String, request: AiRequest) {
        self.endpoint = endpoint
        self.key = key
        self.model = model
        self.timeoutMs = timeoutMs
        self.parameters = parameters
        self.provider = provider
        self.request = request
    }
}

/// Where a request for a logical endpoint really goes. In the simulator a test can point an endpoint at a
/// loopback server (`config/loopback-routes.json` in the App Group); on a device the map is never read.
public enum AiLoopbackRoutes {
    public static let fileName = "loopback-routes.json"

    public static func load(in context: AppGroupContext) -> [String: String] {
        #if targetEnvironment(simulator)
        guard let url = context.sharedDirectory("config")?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        // Only loopback destinations: a route can never send a key or text off the machine.
        return map.filter { entry in
            guard let target = URL(string: entry.value), let host = target.host else { return false }
            return host == "127.0.0.1" || host == "localhost" || host == "::1"
        }
        #else
        return [:]
        #endif
    }
}
