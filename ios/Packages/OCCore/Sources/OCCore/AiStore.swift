// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Where the AI configuration lives: App Group `config/ai-config.json` (no keys in it), written by the app,
/// read by the keyboard. `state/config-stamp` changes with every write so the keyboard can reload.
public enum AiConfigFile {
    public static let fileName = "ai-config.json"

    public static func fileURL(in context: AppGroupContext) -> URL? {
        context.sharedDirectory("config")?.appendingPathComponent(fileName)
    }

    public static func stampURL(in context: AppGroupContext) -> URL? {
        context.sharedDirectory("state")?.appendingPathComponent("config-stamp")
    }

    public static func readStamp(in context: AppGroupContext) -> String? {
        guard let url = stampURL(in: context), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Keyboard side: read-only. `nil` when there is no group or no configuration yet.
    public static func read(in context: AppGroupContext) -> AiConfig? {
        guard let url = fileURL(in: context), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AiConfig.self, from: data)
    }
}

public struct AiStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// The app side of the configuration: loading, validated updates, policies. Mirrors Android `AiStore`.
public final class AiStore: @unchecked Sendable {
    public static let maxPolicies = 20
    private let lock = NSLock()
    private let file: URL
    private let stamp: URL?
    private var current: AiConfig

    public init(file: URL, stamp: URL? = nil) {
        self.file = file
        self.stamp = stamp
        if let data = try? Data(contentsOf: file), let loaded = try? JSONDecoder().decode(AiConfig.self, from: data) {
            current = loaded
        } else {
            current = AiConfig()
        }
        migrate()
    }

    public convenience init?(context: AppGroupContext) {
        guard let file = AiConfigFile.fileURL(in: context) else { return nil }
        self.init(file: file, stamp: AiConfigFile.stampURL(in: context))
    }

    public var config: AiConfig {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    // MARK: defaults and migrations (Android AiStore init, policyVersion 7)

    private func migrate() {
        guard current.policyVersion < 7 || current.policies.isEmpty else { return }
        var c = current
        c.remoteUrl = ""
        c.autoUpdate = false
        c.modelCatalogUrl = ""
        if c.model.isEmpty { c.endpoint = TerraDefaults.endpoint; c.model = TerraDefaults.model }
        if c.policies.isEmpty {
            c.policies = [c.snapshotPolicy(name: "OpenAI · 6.1 Terra")]
            c.policies.append(Self.openRouterPolicy())
            c.policies.append(Self.geminiPolicy())
        }
        c.contextEnabled = true
        c.assistantEnabled = c.enabled && c.assistantEnabled
        c.policyVersion = 7
        current = c
        try? persistLocked(c)
    }

    public static func openRouterPolicy() -> AiPolicy {
        AiPolicy(id: "openrouter", name: "OpenRouter · DeepSeek Flash", endpoint: ApiRouting.openRouter, model: ApiRouting.deepSeek,
                 catalog: ModelCatalog(models: [ModelDefinition(id: ApiRouting.deepSeek, parameters: [
                     ModelParameter(key: "reasoning_effort", label: "思考强度", choices: [
                         ParameterChoice(label: "无思考", value: "none"), ParameterChoice(label: "轻度", value: "low"),
                         ParameterChoice(label: "普通", value: "medium"), ParameterChoice(label: "深度", value: "high")]),
                     ModelParameter(key: "service_tier", label: "路由速度", choices: [
                         ParameterChoice(label: "普通", value: "default"), ParameterChoice(label: "优先低延迟", value: "priority")]),
                     ModelParameter(key: "max_tokens", label: "输出 Token 上限", type: "integer", min: 1, max: 32768),
                 ])]),
                 modelValues: [ApiRouting.deepSeek: ["reasoning_effort": .string("none"), "service_tier": .string("default")]],
                 provider: ApiRouting.wafer)
    }

    public static func geminiPolicy() -> AiPolicy {
        let definition = (try? NativeCore.call(op: "modelDefinition", args: [
            "endpoint": ApiRouting.gemini, "model": ApiRouting.hydrogen,
            "catalog": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(ModelCatalog()))) ?? [:],
        ])).flatMap { Self.decode(ModelDefinition.self, from: $0) }
        return AiPolicy(id: "gemini", name: "Gemini · Hydrogen", endpoint: ApiRouting.gemini, model: ApiRouting.hydrogen,
                        catalog: ModelCatalog(models: definition.map { [$0] } ?? []),
                        modelValues: [ApiRouting.hydrogen: ["reasoning_effort": .string("low"), "service_tier": .string("default")]])
    }

    static func decode<T: Decodable>(_ type: T.Type, from object: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: validated update

    /// Applies `transform`, validates the result the way Android does and writes it atomically (then the stamp).
    @discardableResult
    public func update(_ transform: (inout AiConfig) throws -> Void) throws -> AiConfig {
        lock.lock(); defer { lock.unlock() }
        let old = current
        var next = old
        try transform(&next)
        next.generation = old.generation + 1
        next.candidateCount = 1
        next.completion = false
        // Capabilities and values belong to this exact endpoint, not just a model name.
        if next.endpoint != old.endpoint && next.selectedPolicyId == old.selectedPolicyId {
            next.modelCatalog = ModelCatalog()
            next.discoveredModels = []
            next.modelValues = [:]
            next.modelCatalogUrl = ""
            if !ApiRouting.isOpenRouter(next.endpoint) { next.provider = "" }
        }
        try Self.validate(next.modelCatalog)
        var kept: [String: [String: JSONPrimitive]] = [:]
        for (model, values) in next.modelValues {
            guard let definition = Self.definition(endpoint: next.endpoint, model: model, catalog: next.modelCatalog) else { continue }
            let filtered = Self.filter(values, with: definition)
            try Self.validateWire(filtered)
            kept[model] = filtered
        }
        next.modelValues = kept
        guard (50...2000).contains(next.debounceMs), (1000...60000).contains(next.timeoutMs) else { throw AiStoreError("时间设置超出范围") }
        guard (1...300).contains(next.targetLimit) else { throw AiStoreError("当前输入上限需在 1–300") }
        guard (0...500).contains(next.beforeLength), (0...500).contains(next.afterLength), (1...65536).contains(next.outputTokenBudget)
        else { throw AiStoreError("前后文或 token 预算超出范围") }
        guard Set(next.policies.map(\.id)).count == next.policies.count else { throw AiStoreError("Policy 重复") }
        if let name = next.policies.first(where: { $0.id == next.selectedPolicyId })?.name {
            let snapshot = next.snapshotPolicy(name: name)
            next.policies = next.policies.map { $0.id == snapshot.id ? snapshot : $0 }
        }
        try persistLocked(next)
        current = next
        return next
    }

    private func persistLocked(_ config: AiConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(config)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic])
        if let stamp {
            try FileManager.default.createDirectory(at: stamp.deletingLastPathComponent(), withIntermediateDirectories: true)
            let value = ISO8601DateFormatter().string(from: Date()) + "-" + String(UUID().uuidString.prefix(8))
            try Data((value + "\n").utf8).write(to: stamp, options: [.atomic])
        }
    }

    // MARK: native-core helpers

    static func json<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    static func definition(endpoint: String, model: String, catalog: ModelCatalog) -> ModelDefinition? {
        guard let value = try? NativeCore.call(op: "modelDefinition", args: ["endpoint": endpoint, "model": model, "catalog": json(catalog)]),
              !(value is NSNull) else { return nil }
        return decode(ModelDefinition.self, from: value)
    }

    static func filter(_ values: [String: JSONPrimitive], with definition: ModelDefinition) -> [String: JSONPrimitive] {
        let wire = values.mapValues { $0.foundation }
        guard let filtered = (try? NativeCore.call(op: "filterValues", args: ["definition": json(definition), "values": wire])) as? [String: Any]
        else { return [:] }
        // Through JSON text: booleans, integers and strings keep their kind on every platform.
        guard JSONSerialization.isValidJSONObject(filtered), let data = try? JSONSerialization.data(withJSONObject: filtered),
              let out = try? JSONDecoder().decode([String: JSONPrimitive].self, from: data) else { return [:] }
        return out
    }

    static func validate(_ catalog: ModelCatalog) throws {
        do { _ = try NativeCore.call(op: "validateCatalog", args: json(catalog)) }
        catch { throw AiStoreError("模型与参数列表无效") }
    }

    static func validateWire(_ values: [String: JSONPrimitive]) throws {
        do { _ = try NativeCore.call(op: "validateParameters", args: values.mapValues { $0.foundation }) }
        catch { throw AiStoreError("模型参数无效") }
    }

    // MARK: policies

    /// The effective model parameters of a config: the stored values filtered by the model definition.
    public func parameters(_ c: AiConfig? = nil) -> [String: JSONPrimitive] {
        Self.parameters(for: c ?? config)
    }

    /// What the selected model can be asked (the list in the policy, completed by what the shared core knows
    /// about the service), or nil when nothing is known about it.
    public static func definition(for c: AiConfig) -> ModelDefinition? {
        definition(endpoint: c.endpoint, model: c.model, catalog: c.modelCatalog)
    }

    /// The same without a store (the keyboard only reads the configuration).
    public static func parameters(for c: AiConfig) -> [String: JSONPrimitive] {
        guard let definition = Self.definition(endpoint: c.endpoint, model: c.model, catalog: c.modelCatalog) else { return [:] }
        return Self.filter(c.modelValues[c.model] ?? [:], with: definition)
    }

    public func configForPolicy(_ id: String) -> AiConfig? {
        let c = config
        return c.policies.first { $0.id == id }.map { c.applying($0) }
    }

    public func selectPolicy(_ id: String) throws {
        try update { c in
            guard let policy = c.policies.first(where: { $0.id == id }) else { throw AiStoreError("没有这个 Policy") }
            c = c.applying(policy)
        }
    }

    public func renamePolicy(_ id: String, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { throw AiStoreError("名称需在 1–80 个字符") }
        try update { c in c.policies = c.policies.map { var p = $0; if p.id == id { p.name = trimmed }; return p } }
    }

    @discardableResult
    public func addPolicy(name: String) throws -> String {
        let id = UUID().uuidString.lowercased()
        try update { c in
            guard c.policies.count < Self.maxPolicies else { throw AiStoreError("最多保存 \(Self.maxPolicies) 个 Policy") }
            var fresh = AiConfig()
            fresh.selectedPolicyId = id
            c.policies.append(fresh.snapshotPolicy(name: name))
        }
        return id
    }

    /// A copy of a policy under a fresh id (the app copies its key too).
    @discardableResult
    public func duplicatePolicy(_ id: String) throws -> String {
        guard var copy = config.policies.first(where: { $0.id == id }) else { throw AiStoreError("没有这个 Policy") }
        copy.id = UUID().uuidString.lowercased()
        try update { c in
            guard c.policies.count < Self.maxPolicies else { throw AiStoreError("最多保存 \(Self.maxPolicies) 个 Policy") }
            copy.name = Self.uniqueName(copy.name + " 副本", in: c.policies)
            c.policies.append(copy)
        }
        return copy.id
    }

    static func uniqueName(_ base: String, in policies: [AiPolicy]) -> String {
        var name = base
        var suffix = 2
        while policies.contains(where: { $0.name == name }) { name = base + " \(suffix)"; suffix += 1 }
        return name
    }

    public func deletePolicy(_ id: String) throws {
        try update { c in
            guard c.policies.count > 1 else { throw AiStoreError("至少保留一个 Policy") }
            let remaining = c.policies.filter { $0.id != id }
            if c.selectedPolicyId == id, let first = remaining.first {
                c = c.applying(first)
            }
            c.policies = remaining
        }
    }

    /// Replaces the connection of one policy (edit screen): endpoint, model, provider, catalog and values.
    public func updatePolicy(_ id: String, _ transform: (inout AiPolicy) throws -> Void) throws {
        try update { c in
            guard let index = c.policies.firstIndex(where: { $0.id == id }) else { throw AiStoreError("没有这个 Policy") }
            let old = c.policies[index]
            var edited = old
            try transform(&edited)
            if edited.endpoint != old.endpoint {
                edited.catalog = ModelCatalog()
                edited.modelValues = [:]
                edited.discoveredModels = []
                if !ApiRouting.isOpenRouter(edited.endpoint) { edited.provider = "" }
            }
            c.policies[index] = edited
            if c.selectedPolicyId == id { c = c.applying(edited) }
        }
    }

    // MARK: export and import (same JSON as Android)

    /// The shape Android exports for one policy and imports back: the `AiPolicy` JSON (no key).
    public func exportPolicy(_ id: String) throws -> Data {
        guard let policy = config.policies.first(where: { $0.id == id }) else { throw AiStoreError("没有这个 Policy") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(policy)
    }

    /// Adds the policy of an exported file under a fresh id. Keys are never part of an export.
    @discardableResult
    public func importPolicy(_ data: Data) throws -> String {
        guard data.count <= 512 * 1024 else { throw AiStoreError("文件太大") }
        var policy = try JSONDecoder().decode(AiPolicy.self, from: data)
        guard policy.endpoint.hasPrefix("https://") else { throw AiStoreError("接口地址必须是 HTTPS") }
        try Self.validate(policy.catalog)
        let id = UUID().uuidString.lowercased()
        policy.id = id
        try update { c in
            guard c.policies.count < Self.maxPolicies else { throw AiStoreError("最多保存 \(Self.maxPolicies) 个 Policy") }
            let base = policy.name
            var suffix = 2
            while c.policies.contains(where: { $0.name == policy.name }) { policy.name = base + " \(suffix)"; suffix += 1 }
            c.policies.append(policy)
        }
        return id
    }

    /// The model and parameter list of one policy, as Android exports it ("orangecell-input-models.json"): no key,
    /// no address, no typed text.
    public func exportCatalog(policyID: String) throws -> Data {
        guard let policy = config.policies.first(where: { $0.id == policyID }) else { throw AiStoreError("没有这个 Policy") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(policy.catalog)
    }

    /// Replaces the model and parameter list of one policy; stored parameter values that the new list no longer
    /// allows are dropped, the others stay.
    public func importCatalog(_ data: Data, policyID: String) throws {
        guard data.count <= 512 * 1024 else { throw AiStoreError("文件太大") }
        let catalog: ModelCatalog
        do { catalog = try JSONDecoder().decode(ModelCatalog.self, from: data) }
        catch { throw AiStoreError("文件不是模型与参数列表") }
        try Self.validate(catalog)
        try updatePolicy(policyID) { $0.catalog = catalog }
    }

    /// The whole configuration as Android exports it (`ai-config.json`), without keys.
    public func exportConfig() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    /// The prompt package in force, for display.
    public func exportPromptPackage() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config.effectivePackage)
    }

    // MARK: prompts

    /// The text around the input that goes with a request, cut to the configured lengths by the shared core.
    public static func context(_ input: String, before: String, after: String, c: AiConfig) -> AiInput {
        let args: [String: Any] = ["before": before, "after": after, "enabled": c.contextEnabled,
                                   "beforeLimit": c.beforeLength, "afterLimit": c.afterLength]
        if let result = (try? NativeCore.call(op: "context", args: args)) as? [String: Any] {
            return AiInput(input: input, before: (result["before"] as? String) ?? "", after: (result["after"] as? String) ?? "")
        }
        return AiInput(input: input)
    }

    /// Composes the system prompt through native-core (`prompt` op) from the package rules.
    public static func systemPrompt(_ c: AiConfig, chinese: Bool, assistant: Bool) -> String {
        let rules = c.effectivePackage.keyboard_language_rules
        let args: [String: Any] = [
            "assistantEnabled": assistant, "chinese": chinese, "traditional": c.traditional,
            "custom": chinese ? rules.chinese : rules.non_chinese,
        ]
        return ((try? NativeCore.call(op: "prompt", args: args)) as? String) ?? ""
    }
}

// MARK: keys

/// One key per policy, bound to the origin of the endpoint it was entered for (like Android
/// `CredentialStore`: AES-GCM with the origin as authenticated data). The backend is the one chosen in
/// `config/key-backend.txt` (docs/IOS_PLAN.md section 4.6), the encrypted file in the App Group by default.
public struct CredentialVault {
    public static let backendFileName = "key-backend.txt"
    private let stores: [any SecretStore]

    /// App side: write to the chosen backend. Keyboard side: read from the chosen backend first, then the others.
    public init(context: AppGroupContext) {
        let all = KeyStorageSelfTest.stores(context: context)
        let chosen = Self.chosenBackend(in: context) ?? "encrypted-file"
        let ordered = all.filter { $0.backendName == chosen } + all.filter { $0.backendName != chosen && $0.backendName != "keychain-default" }
        stores = ordered.isEmpty ? all : ordered
    }

    public init(stores: [any SecretStore]) {
        self.stores = stores
    }

    public static func chosenBackend(in context: AppGroupContext) -> String? {
        guard let url = context.sharedDirectory("config")?.appendingPathComponent(backendFileName),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Records the backend once (the first key saved); later keys follow it.
    public static func chooseBackend(_ backend: String, in context: AppGroupContext) {
        guard chosenBackend(in: context) == nil,
              let url = context.sharedDirectory("config")?.appendingPathComponent(backendFileName) else { return }
        try? Data((backend + "\n").utf8).write(to: url, options: [.atomic])
    }

    public var backendName: String { stores.first?.backendName ?? "none" }

    private func account(_ policyID: String) -> String { "ai-key." + policyID }

    /// `https://host:port` of an endpoint; refuses anything but a plain HTTPS address.
    public static func origin(of endpoint: String) throws -> String {
        guard let url = URL(string: endpoint), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.query == nil, url.fragment == nil
        else { throw AiStoreError("请输入完整 HTTPS 地址，不能包含查询参数") }
        return "https://\(host.lowercased()):\(url.port ?? 443)"
    }

    public func save(policyID: String, endpoint: String, secret: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains("\r") else { throw AiStoreError("Key 不能为空或含换行") }
        let value = try Self.origin(of: endpoint) + "\n" + trimmed
        guard let store = stores.first else { throw AiStoreError("没有可用的 Key 存储") }
        try store.set(Data(value.utf8), account: account(policyID))
    }

    /// The key, only when it was entered for this endpoint origin.
    public func read(policyID: String, endpoint: String) -> String? {
        guard let origin = try? Self.origin(of: endpoint) else { return nil }
        for store in stores {
            guard let data = try? store.get(account: account(policyID)),
                  let text = String(data: data, encoding: .utf8),
                  let newline = text.firstIndex(of: "\n") else { continue }
            guard text[text.startIndex..<newline] == origin else { return nil }
            return String(text[text.index(after: newline)...])
        }
        return nil
    }

    public func has(policyID: String) -> Bool {
        stores.contains { ((try? $0.get(account: account(policyID))) ?? nil) != nil }
    }

    public func remove(policyID: String) {
        for store in stores { try? store.remove(account: account(policyID)) }
    }

    /// Copies the key of one policy to another (the policy copy of the app also copies its key).
    public func copy(from source: String, to destination: String, endpoint: String) throws {
        guard let secret = read(policyID: source, endpoint: endpoint) else { throw AiStoreError("原 Policy 密钥无法读取，请重新配置后再复制") }
        try save(policyID: destination, endpoint: endpoint, secret: secret)
    }
}
