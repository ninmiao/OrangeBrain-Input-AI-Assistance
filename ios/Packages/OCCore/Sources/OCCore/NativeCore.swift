// SPDX-License-Identifier: GPL-3.0-or-later
import CNativeCore
import Foundation

/// Failure reported by the shared C++ core (`{"error": ..., "status": ...}`).
public struct NativeCoreError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public let status: Int
    public var description: String { "native core error: \(message) (status \(status))" }
}

/// Swift face of the shared native core (`shared/native-core`), reached through
/// the C API `oc_invoke` / `oc_free`. Input and output are UTF-8 JSON, identical
/// to what Android (JNI) and Windows (direct call) exchange with the same code.
public enum NativeCore {
    /// Runs one raw command and returns the raw JSON reply.
    public static func invoke(_ command: String) -> String {
        let reply: String? = command.withCString { pointer in
            guard let raw = oc_invoke(pointer) else { return nil }
            defer { oc_free(raw) }
            return String(cString: raw)
        }
        return reply ?? #"{"error":"response"}"#
    }

    /// Runs `{"op": op, "args": args}` and returns the value under `"ok"`.
    public static func call(op: String, args: [String: Any] = [:]) throws -> Any {
        let request: [String: Any] = ["op": op, "args": args]
        let data = try JSONSerialization.data(withJSONObject: request, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw NativeCoreError(message: "request", status: 0)
        }
        let reply = invoke(text)
        guard let object = try JSONSerialization.jsonObject(with: Data(reply.utf8), options: [.fragmentsAllowed]) as? [String: Any]
        else { throw NativeCoreError(message: "response", status: 0) }
        if let error = object["error"] as? String {
            throw NativeCoreError(message: error, status: (object["status"] as? Int) ?? 0)
        }
        guard let ok = object["ok"] else { throw NativeCoreError(message: "response", status: 0) }
        return ok
    }

    /// The `encode` operation: wire form of one request, e.g. `{"i":"nihao","b":"previous"}`.
    public static func encode(input: String, before: String = "", after: String = "") throws -> [String: String] {
        var args: [String: Any] = ["input": input]
        if !before.isEmpty { args["before"] = before }
        if !after.isEmpty { args["after"] = after }
        guard let wire = try call(op: "encode", args: args) as? String,
              let object = try JSONSerialization.jsonObject(with: Data(wire.utf8)) as? [String: String]
        else { throw NativeCoreError(message: "response", status: 0) }
        return object
    }

    /// The `decode` operation applied to model output; returns the accepted candidates.
    public static func decode(text: String, truncated: Bool = false, assistantEnabled: Bool = false) throws -> [String] {
        let args: [String: Any] = ["text": text, "truncated": truncated, "assistantEnabled": assistantEnabled]
        guard let ok = try call(op: "decode", args: args) as? [String: Any],
              let candidates = ok["candidates"] as? [String]
        else { throw NativeCoreError(message: "response", status: 0) }
        return candidates
    }

    /// One encode round trip, used by the diagnostics screens and the keyboard banner.
    public static func selfTest() -> Bool {
        guard let wire = try? encode(input: "nihao", before: "previous") else { return false }
        return wire == ["i": "nihao", "b": "previous"]
    }
}
