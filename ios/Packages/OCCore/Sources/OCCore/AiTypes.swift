// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// The data model of the AI chain, shared by the app and the keyboard. JSON names and defaults are the ones
// of Android (`AiConfig`, `AiPolicy`, `ModelCatalog`, `PromptPackage` in kotlinx.serialization), so a
// configuration exported on one platform imports on the other.

// MARK: JSON primitive

/// A JSON number, string or boolean (kotlinx `JsonPrimitive`): the values of model parameters.
public enum JSONPrimitive: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int64.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    /// The text of the literal, like `JsonPrimitive.content`.
    public var content: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        }
    }

    /// Foundation form for `JSONSerialization` (the native-core arguments).
    public var foundation: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        }
    }
}

extension KeyedDecodingContainer {
    /// `decodeIfPresent` with a default: kotlinx `ignoreUnknownKeys` plus property defaults.
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback()
    }
}

// MARK: requests and results

public struct AiInput: Codable, Equatable, Sendable {
    public var input: String
    public var before: String
    public var after: String

    public init(input: String, before: String = "", after: String = "") {
        self.input = input
        self.before = before
        self.after = after
    }
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var input: Int?
    public var output: Int?
    public var reasoning: Int?
    public var cached: Int?
}

public struct AiResult: Codable, Equatable, Sendable {
    public var candidates: [String]
    public var completion: String
    public var usage: TokenUsage?
    public var recovered: Bool
    public var streaming: Bool
    public var streamError: String

    public init(candidates: [String], completion: String = "", usage: TokenUsage? = nil, recovered: Bool = false,
                streaming: Bool = false, streamError: String = "") {
        self.candidates = candidates
        self.completion = completion
        self.usage = usage
        self.recovered = recovered
        self.streaming = streaming
        self.streamError = streamError
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        candidates = try c.decode([String].self, forKey: .candidates)
        completion = try c.value(.completion, "")
        usage = try c.decodeIfPresent(TokenUsage.self, forKey: .usage)
        recovered = try c.value(.recovered, false)
        streaming = try c.value(.streaming, false)
        streamError = try c.value(.streamError, "")
    }
}

/// What a result was requested for. Any change of one of these makes an older result stale.
public struct RequestStamp: Equatable, Sendable {
    public var editorSession: Int64
    public var inputRevision: Int64
    public var promptGeneration: Int64
    public var keyboardGeneration: Int64
    public var apiGeneration: Int64

    public init(editorSession: Int64, inputRevision: Int64, promptGeneration: Int64, keyboardGeneration: Int64, apiGeneration: Int64) {
        self.editorSession = editorSession
        self.inputRevision = inputRevision
        self.promptGeneration = promptGeneration
        self.keyboardGeneration = keyboardGeneration
        self.apiGeneration = apiGeneration
    }
}

public struct AiRequest: Equatable, Sendable {
    public var stamp: RequestStamp
    public var input: AiInput
    public var systemPrompt: String
    public var completionEnabled: Bool
    public var candidateCount: Int
    public var outputTokenBudget: Int
    public var assistantEnabled: Bool
    public var maxCandidates: Int

    public init(stamp: RequestStamp, input: AiInput, systemPrompt: String, completionEnabled: Bool = false, candidateCount: Int = 1,
                outputTokenBudget: Int = 256, assistantEnabled: Bool = false, maxCandidates: Int = 0) {
        self.stamp = stamp
        self.input = input
        self.systemPrompt = systemPrompt
        self.completionEnabled = completionEnabled
        self.candidateCount = candidateCount
        self.outputTokenBudget = outputTokenBudget
        self.assistantEnabled = assistantEnabled
        self.maxCandidates = maxCandidates
    }
}

// MARK: failures

public enum RequestPhase: String, Sendable {
    case queued = "排队超时", dns = "域名解析超时", connect = "连接超时", tls = "安全连接超时"
    case sending = "发送超时", waiting = "等待服务响应超时", receiving = "接收结果超时"
}

/// Only fixed categories and status codes leave the transport: no response bodies, credentials or input.
public enum AiError: Error, Equatable, Sendable {
    case timeout(RequestPhase)
    case http(Int)
    case provider(Int?)
    case truncated
    case invalidResponse
    case network
    case missingCredential
    case invalidConfiguration
}

public enum AiFailure: Equatable, Sendable {
    case timeout, authentication, credit, rateLimit, provider, truncated, invalidResponse, network, unknown

    public var label: String {
        switch self {
        case .timeout: return "请求超时"
        case .authentication: return "Key 无效"
        case .credit: return "额度不足"
        case .rateLimit: return "请求受限"
        case .provider: return "服务商失败"
        case .truncated: return "返回被截断"
        case .invalidResponse: return "响应格式错误"
        case .network: return "网络连接失败"
        case .unknown: return "暂不可用"
        }
    }

    public static func from(_ error: Error) -> AiFailure {
        guard let error = error as? AiError else {
            return (error as? URLError) != nil ? .network : .unknown
        }
        switch error {
        case .timeout: return .timeout
        case .http(let status), .provider(let status?):
            switch status {
            case 401, 403: return .authentication
            case 402: return .credit
            case 429: return .rateLimit
            default: return .provider
            }
        case .provider(nil): return .provider
        case .truncated: return .truncated
        case .invalidResponse: return .invalidResponse
        case .network: return .network
        case .missingCredential: return .authentication
        case .invalidConfiguration: return .unknown
        }
    }

    /// The detail shown behind the status dot: the phase of a timeout, else the label.
    public static func detail(_ error: Error) -> String {
        if let error = error as? AiError, case .timeout(let phase) = error { return phase.rawValue }
        return from(error).label
    }
}

// MARK: models and prompts

public struct ParameterChoice: Codable, Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ModelParameter: Codable, Equatable, Sendable {
    public var key: String
    public var label: String
    public var type: String
    public var choices: [ParameterChoice]
    public var min: Double?
    public var max: Double?

    public init(key: String, label: String, type: String = "enum", choices: [ParameterChoice] = [], min: Double? = nil, max: Double? = nil) {
        self.key = key
        self.label = label
        self.type = type
        self.choices = choices
        self.min = min
        self.max = max
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decode(String.self, forKey: .label)
        type = try c.value(.type, "enum")
        choices = try c.value(.choices, [])
        min = try c.decodeIfPresent(Double.self, forKey: .min)
        max = try c.decodeIfPresent(Double.self, forKey: .max)
    }
}

public struct ModelDefinition: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var parameters: [ModelParameter]

    public init(id: String, name: String? = nil, parameters: [ModelParameter] = []) {
        self.id = id
        self.name = name ?? id
        self.parameters = parameters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.value(.name, id)
        parameters = try c.value(.parameters, [])
    }
}

public struct ModelCatalog: Codable, Equatable, Sendable {
    public var schema_version: Int
    public var version: String
    public var models: [ModelDefinition]

    public init(schema_version: Int = 1, version: String = "local-1", models: [ModelDefinition] = []) {
        self.schema_version = schema_version
        self.version = version
        self.models = models
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema_version = try c.value(.schema_version, 1)
        version = try c.value(.version, "local-1")
        models = try c.value(.models, [])
    }
}

public struct LanguageRules: Codable, Equatable, Sendable {
    public var chinese: String
    public var non_chinese: String

    public init(chinese: String = "", non_chinese: String = "") {
        self.chinese = chinese
        self.non_chinese = non_chinese
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chinese = try c.value(.chinese, "")
        non_chinese = try c.value(.non_chinese, "")
    }
}

/// The prompt package (rules for Chinese and other input). The system prompt itself is composed by
/// native-core (`prompt` op) from these rules.
public struct PromptPackage: Codable, Equatable, Sendable {
    public var schema_version: Int
    public var package_id: String
    public var version: String
    public var revision: Int64
    public var response_schema_version: Int
    public var keyboard_language_rules: LanguageRules

    public init(schema_version: Int = 3, package_id: String = "orangecell-input", version: String = "5.0.0", revision: Int64 = 14,
                response_schema_version: Int = 3, keyboard_language_rules: LanguageRules = LanguageRules()) {
        self.schema_version = schema_version
        self.package_id = package_id
        self.version = version
        self.revision = revision
        self.response_schema_version = response_schema_version
        self.keyboard_language_rules = keyboard_language_rules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema_version = try c.value(.schema_version, 3)
        package_id = try c.value(.package_id, "orangecell-input")
        version = try c.value(.version, "5.0.0")
        revision = try c.value(.revision, Int64(14))
        response_schema_version = try c.value(.response_schema_version, 3)
        keyboard_language_rules = try c.value(.keyboard_language_rules, LanguageRules())
    }

    /// The package shipped in the app: same values as `shared/ai-core/.../default-prompts.json`.
    public static let builtin = PromptPackage()

    public func upgraded() -> PromptPackage {
        revision < 14 || response_schema_version < 3 ? PromptPackage(package_id: package_id) : self
    }

    /// The emoticon request has its own fixed prompt (Android `EMOJI_PROMPT`).
    public static let emojiPrompt = "i is input; b/a context. Return only a JSON array of 5 strings: emoticons for the mood or meaning of i (use b/a if i is empty or unclear). Give each a different style, such as cute, smug, crying, excited or deadpan. Exactly one item is a standard emoji (one or a short sequence); the other four are kaomoji, e.g. (,,・ω・,,) or („ಡωಡ„). No words, no explanations."

    public static func parse(_ data: Data) throws -> PromptPackage {
        guard data.count <= 128 * 1024 else { throw AiError.invalidConfiguration }
        let package = try JSONDecoder().decode(PromptPackage.self, from: data)
        guard (1...3).contains(package.schema_version), (1...3).contains(package.response_schema_version), package.revision >= 0,
              package.keyboard_language_rules.chinese.count <= 8192, package.keyboard_language_rules.non_chinese.count <= 8192
        else { throw AiError.invalidConfiguration }
        return package.upgraded()
    }
}

public struct PromptVersion: Codable, Equatable, Sendable {
    public var pack: PromptPackage
    public var source: String

    public init(pack: PromptPackage, source: String) {
        self.pack = pack
        self.source = source
    }
}

// MARK: policies and configuration

public enum ApiRouting {
    public static let openAI = "https://api.openai.com/v1/responses"
    public static let openRouter = "https://openrouter.ai/api/v1/chat/completions"
    public static let gemini = "https://generativelanguage.googleapis.com/v1beta/interactions"
    public static let hydrogen = "gemini-4-hydrogen"
    public static let deepSeek = "deepseek/deepseek-v4-flash-0731"
    public static let wafer = "wafer/us"

    private static func routing(_ endpoint: String) -> [String: Any]? {
        (try? NativeCore.call(op: "routing", args: ["endpoint": endpoint])) as? [String: Any]
    }

    public static func api(_ endpoint: String) -> String { (routing(endpoint)?["api"] as? String) ?? "openai" }
    public static func isGemini(_ endpoint: String) -> Bool { api(endpoint) == "gemini" }
    public static func isOpenRouter(_ endpoint: String) -> Bool { api(endpoint) == "openrouter" }
    public static func requestURL(_ endpoint: String) -> String { (routing(endpoint)?["url"] as? String) ?? endpoint }
}

public enum TerraDefaults {
    public static let model = "gpt-6.1-terra"
    public static let endpoint = ApiRouting.openAI

    public static func catalog() -> ModelCatalog {
        let effort = ModelParameter(key: "reasoning_effort", label: "推理强度", choices: [
            ParameterChoice(label: "关闭（仅支持 none 的模型）", value: "none"), ParameterChoice(label: "轻度", value: "low"),
            ParameterChoice(label: "普通", value: "medium"), ParameterChoice(label: "深度", value: "high"),
            ParameterChoice(label: "很高", value: "xhigh"), ParameterChoice(label: "最高", value: "max"),
        ])
        let tier = ModelParameter(key: "service_tier", label: "服务档位", choices: [
            ParameterChoice(label: "普通", value: "default"), ParameterChoice(label: "Fast / 优先处理（可能额外计费）", value: "priority"),
            ParameterChoice(label: "跟随服务端项目设置", value: "auto"),
        ])
        let tokens = ModelParameter(key: "max_completion_tokens", label: "输出 Token 上限（包含推理）", type: "integer", min: 1, max: 131072)
        return ModelCatalog(models: [ModelDefinition(id: model, parameters: [tier, effort, tokens])])
    }

    public static func values() -> [String: [String: JSONPrimitive]] {
        [model: ["reasoning_effort": .string("low"), "service_tier": .string("priority")]]
    }
}

public struct AiPolicy: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var endpoint: String
    public var model: String
    public var catalog: ModelCatalog
    public var discoveredModels: [String]
    public var modelValues: [String: [String: JSONPrimitive]]
    public var active: PromptVersion?
    public var localOverride: PromptPackage?
    public var history: [PromptVersion]
    public var provider: String

    public init(id: String, name: String, endpoint: String, model: String, catalog: ModelCatalog = ModelCatalog(),
                discoveredModels: [String] = [], modelValues: [String: [String: JSONPrimitive]] = [:],
                active: PromptVersion? = nil, localOverride: PromptPackage? = nil, history: [PromptVersion] = [], provider: String = "") {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.model = model
        self.catalog = catalog
        self.discoveredModels = discoveredModels
        self.modelValues = modelValues
        self.active = active
        self.localOverride = localOverride
        self.history = history
        self.provider = provider
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        endpoint = try c.decode(String.self, forKey: .endpoint)
        model = try c.decode(String.self, forKey: .model)
        catalog = try c.value(.catalog, ModelCatalog())
        discoveredModels = try c.value(.discoveredModels, [])
        modelValues = try c.value(.modelValues, [:])
        active = try c.decodeIfPresent(PromptVersion.self, forKey: .active)
        localOverride = try c.decodeIfPresent(PromptPackage.self, forKey: .localOverride)
        history = try c.value(.history, [])
        provider = try c.value(.provider, "")
    }
}

public struct AiConfig: Codable, Equatable, Sendable {
    public var generation: Int64 = 0
    public var enabled = false
    public var assistantEnabled = false
    public var consent = false
    public var automatic = true
    public var wordSegmentation = true
    public var targetLimit = 300
    public var contextEnabled = true
    public var beforeLength = 50
    public var afterLength = 0
    public var outputTokenBudget = 256
    public var debounceMs: Int64 = 200
    public var timeoutMs = 10000
    public var endpoint = TerraDefaults.endpoint
    public var model = TerraDefaults.model
    public var modelCatalog = TerraDefaults.catalog()
    public var discoveredModels: [String] = []
    public var modelValues = TerraDefaults.values()
    public var modelCatalogUrl = ""
    public var completion = false
    public var candidateCount = 1
    public var remoteUrl = ""
    public var autoUpdate = false
    public var lastCheck: Int64 = 0
    public var active: PromptVersion?
    public var localOverride: PromptPackage?
    public var history: [PromptVersion] = []
    public var traditional = false
    public var selectedPolicyId = "default"
    public var policies: [AiPolicy] = []
    public var policyVersion = 0
    public var provider = ""
    /// Function keys at the right end of the AI bar (ids of Android `FunctionKey`); M3 builds the keys.
    public var functionKeys = ["clipboard", "script", "emoji", "assistant"]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generation = try c.value(.generation, Int64(0))
        enabled = try c.value(.enabled, false)
        assistantEnabled = try c.value(.assistantEnabled, false)
        consent = try c.value(.consent, false)
        automatic = try c.value(.automatic, true)
        wordSegmentation = try c.value(.wordSegmentation, true)
        targetLimit = try c.value(.targetLimit, 300)
        contextEnabled = try c.value(.contextEnabled, true)
        beforeLength = try c.value(.beforeLength, 50)
        afterLength = try c.value(.afterLength, 0)
        outputTokenBudget = try c.value(.outputTokenBudget, 256)
        debounceMs = try c.value(.debounceMs, Int64(200))
        timeoutMs = try c.value(.timeoutMs, 10000)
        endpoint = try c.value(.endpoint, TerraDefaults.endpoint)
        model = try c.value(.model, TerraDefaults.model)
        modelCatalog = try c.value(.modelCatalog, TerraDefaults.catalog())
        discoveredModels = try c.value(.discoveredModels, [])
        modelValues = try c.value(.modelValues, TerraDefaults.values())
        modelCatalogUrl = try c.value(.modelCatalogUrl, "")
        completion = try c.value(.completion, false)
        candidateCount = try c.value(.candidateCount, 1)
        remoteUrl = try c.value(.remoteUrl, "")
        autoUpdate = try c.value(.autoUpdate, false)
        lastCheck = try c.value(.lastCheck, Int64(0))
        active = try c.decodeIfPresent(PromptVersion.self, forKey: .active)
        localOverride = try c.decodeIfPresent(PromptPackage.self, forKey: .localOverride)
        history = try c.value(.history, [])
        traditional = try c.value(.traditional, false)
        selectedPolicyId = try c.value(.selectedPolicyId, "default")
        policies = try c.value(.policies, [])
        policyVersion = try c.value(.policyVersion, 0)
        provider = try c.value(.provider, "")
        functionKeys = try c.value(.functionKeys, ["clipboard", "script", "emoji", "assistant"])
    }

    /// The selected policy flattened into the config, like Android `AiPolicy.applyTo`.
    public func applying(_ policy: AiPolicy) -> AiConfig {
        var copy = self
        copy.selectedPolicyId = policy.id
        copy.endpoint = policy.endpoint
        copy.model = policy.model
        copy.provider = policy.provider
        copy.modelCatalog = policy.catalog
        copy.discoveredModels = policy.discoveredModels
        copy.modelValues = policy.modelValues
        copy.active = policy.active
        copy.localOverride = policy.localOverride
        copy.history = policy.history
        copy.remoteUrl = ""
        copy.autoUpdate = false
        copy.modelCatalogUrl = ""
        return copy
    }

    /// The selected connection as a policy snapshot.
    public func snapshotPolicy(name: String) -> AiPolicy {
        AiPolicy(id: selectedPolicyId, name: name, endpoint: endpoint, model: model, catalog: modelCatalog,
                 discoveredModels: discoveredModels, modelValues: modelValues, active: active, localOverride: localOverride,
                 history: history, provider: provider)
    }

    /// The prompt package in force: local override, else the active version, else the built-in one.
    public var effectivePackage: PromptPackage {
        (localOverride ?? active?.pack ?? PromptPackage.builtin).upgraded()
    }
}
