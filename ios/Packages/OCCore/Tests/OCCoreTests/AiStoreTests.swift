// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import OCCore

final class MemorySecretStore: SecretStore {
    let backendName: String
    private var items: [String: Data] = [:]

    init(_ name: String = "memory") { backendName = name }

    func set(_ value: Data, account: String) throws { items[account] = value }
    func get(account: String) throws -> Data? { items[account] }
    func remove(account: String) throws { items[account] = nil }
}

final class AiStoreTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oc-ai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeStore() throws -> AiStore {
        let root = try directory()
        return AiStore(file: root.appendingPathComponent("ai-config.json"), stamp: root.appendingPathComponent("config-stamp"))
    }

    private func context(_ root: URL) -> AppGroupContext {
        AppGroupContext(profile: nil, resolution: AppGroupLocator.Resolution(identifier: "group.test", source: .nominalNoProfile), containerURL: root)
    }

    // MARK: defaults

    func testAFreshStoreStartsWithTheThreeDefaultPoliciesAndNothingSwitchedOn() throws {
        let store = try makeStore()
        let c = store.config
        XCTAssertEqual(c.policies.map(\.id), ["default", "openrouter", "gemini"])
        XCTAssertEqual(c.policyVersion, 7)
        XCTAssertEqual(c.selectedPolicyId, "default")
        XCTAssertEqual(c.endpoint, ApiRouting.openAI)
        XCTAssertEqual(c.model, TerraDefaults.model)
        XCTAssertFalse(c.enabled)
        XCTAssertFalse(c.consent, "nothing is sent until the person agrees")
        XCTAssertTrue(c.contextEnabled)
        XCTAssertEqual(c.targetLimit, 300)
        XCTAssertEqual(c.debounceMs, 200)
        XCTAssertEqual(c.timeoutMs, 10000)
    }

    func testTheStoreReadsBackWhatItWroteAndTheKeyboardSideReadsTheSameFile() throws {
        let root = try directory()
        let group = context(root)
        let store = try XCTUnwrap(AiStore(context: group))
        XCTAssertNotNil(AiConfigFile.readStamp(in: group), "the first start already wrote a stamp")
        try store.update { $0.enabled = true; $0.consent = true }
        let keyboard = try XCTUnwrap(AiConfigFile.read(in: group))
        XCTAssertEqual(keyboard, store.config)
        let first = try XCTUnwrap(AiConfigFile.readStamp(in: group))
        try store.update { $0.automatic = false }
        let second = try XCTUnwrap(AiConfigFile.readStamp(in: group))
        XCTAssertNotEqual(first, second, "every write changes the stamp so the keyboard reloads")
        XCTAssertEqual(AiStore(file: try XCTUnwrap(AiConfigFile.fileURL(in: group))).config, store.config)
    }

    func testAnUpdateIsValidatedAndRejectedWithoutChangingAnything() throws {
        let store = try makeStore()
        let before = store.config
        XCTAssertThrowsError(try store.update { $0.debounceMs = 10 })
        XCTAssertThrowsError(try store.update { $0.timeoutMs = 500 })
        XCTAssertThrowsError(try store.update { $0.targetLimit = 0 })
        XCTAssertThrowsError(try store.update { $0.beforeLength = 501 })
        XCTAssertThrowsError(try store.update { $0.outputTokenBudget = 0 })
        XCTAssertEqual(store.config, before)
        let updated = try store.update { $0.automatic = false }
        XCTAssertEqual(updated.generation, before.generation + 1, "every accepted change makes older results stale")
        XCTAssertFalse(store.config.automatic)
    }

    func testChangingTheEndpointDropsTheCapabilitiesOfTheOldOne() throws {
        let store = try makeStore()
        XCTAssertFalse(store.config.modelCatalog.models.isEmpty)
        try store.updatePolicy("default") { $0.endpoint = "https://api.example.com/v1/chat/completions"; $0.model = "other-model" }
        let c = store.config
        XCTAssertEqual(c.endpoint, "https://api.example.com/v1/chat/completions")
        XCTAssertTrue(c.modelCatalog.models.isEmpty)
        XCTAssertTrue(c.modelValues.isEmpty)
        XCTAssertEqual(c.provider, "")
    }

    // MARK: Android compatibility

    func testAnAndroidConfigWithMissingAndUnknownKeysDecodes() throws {
        let json = """
        {"enabled":true,"consent":true,"debounceMs":300,"futureSetting":{"a":1},
         "endpoint":"https://openrouter.ai/api/v1/chat/completions","model":"x/y",
         "modelValues":{"x/y":{"temperature":0.5,"service_tier":"default","enable_thinking":false,"max_tokens":128}},
         "selectedPolicyId":"default","policies":[{"id":"default","name":"P","endpoint":"https://api.openai.com/v1/responses","model":"m"}]}
        """
        let c = try JSONDecoder().decode(AiConfig.self, from: Data(json.utf8))
        XCTAssertTrue(c.enabled)
        XCTAssertEqual(c.debounceMs, 300)
        XCTAssertTrue(c.automatic, "an absent key takes the Android default")
        XCTAssertEqual(c.targetLimit, 300)
        XCTAssertEqual(c.modelValues["x/y"]?["temperature"], .double(0.5))
        XCTAssertEqual(c.modelValues["x/y"]?["enable_thinking"], .bool(false))
        XCTAssertEqual(c.modelValues["x/y"]?["max_tokens"], .int(128))
        XCTAssertEqual(c.modelValues["x/y"]?["service_tier"], .string("default"))
        XCTAssertEqual(c.policies.first?.catalog, ModelCatalog())
    }

    func testTheWholeConfigurationSurvivesAJsonRoundTrip() throws {
        let store = try makeStore()
        try store.update { $0.enabled = true; $0.assistantEnabled = true; $0.consent = true; $0.traditional = true; $0.debounceMs = 321 }
        let data = try store.exportConfig()
        let back = try JSONDecoder().decode(AiConfig.self, from: data)
        XCTAssertEqual(back, store.config)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"selectedPolicyId\""))
        XCTAssertTrue(text.contains("\"modelCatalog\""))
    }

    // MARK: policies

    func testPoliciesCanBeAddedSelectedRenamedAndDeleted() throws {
        let store = try makeStore()
        let id = try store.addPolicy(name: "我的服务")
        XCTAssertEqual(store.config.policies.count, 4)
        try store.selectPolicy(id)
        XCTAssertEqual(store.config.selectedPolicyId, id)
        try store.renamePolicy(id, to: "  新名字 ")
        XCTAssertEqual(store.config.policies.first { $0.id == id }?.name, "新名字")
        XCTAssertThrowsError(try store.renamePolicy(id, to: "   "))
        try store.deletePolicy(id)
        XCTAssertEqual(store.config.policies.map(\.id), ["default", "openrouter", "gemini"])
        XCTAssertEqual(store.config.selectedPolicyId, "default", "deleting the selected policy selects another")
    }

    func testTheLastPolicyCannotBeDeletedAndTheListIsCapped() throws {
        let store = try makeStore()
        for _ in 0..<(AiStore.maxPolicies - 3) { try store.addPolicy(name: "x") }
        XCTAssertEqual(store.config.policies.count, AiStore.maxPolicies)
        XCTAssertThrowsError(try store.addPolicy(name: "one too many"))
        for policy in store.config.policies.dropFirst() { try store.deletePolicy(policy.id) }
        XCTAssertEqual(store.config.policies.count, 1)
        XCTAssertThrowsError(try store.deletePolicy(store.config.policies[0].id))
    }

    func testSelectingOpenRouterBringsItsEndpointModelAndParameters() throws {
        let store = try makeStore()
        try store.selectPolicy("openrouter")
        let c = store.config
        XCTAssertEqual(c.endpoint, ApiRouting.openRouter)
        XCTAssertEqual(c.model, ApiRouting.deepSeek)
        XCTAssertEqual(c.provider, ApiRouting.wafer)
        XCTAssertEqual(store.parameters()["service_tier"], .string("default"))
    }

    func testAPolicyExportHasNoKeyAndImportsUnderAFreshIdWithAUniqueName() throws {
        let store = try makeStore()
        let vault = CredentialVault(stores: [MemorySecretStore()])
        try vault.save(policyID: "openrouter", endpoint: ApiRouting.openRouter, secret: "sk-sentinel-1234567890")
        let data = try store.exportPolicy("openrouter")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("sk-sentinel"), "an export never carries a key")
        let id = try store.importPolicy(data)
        XCTAssertNotEqual(id, "openrouter")
        let imported = try XCTUnwrap(store.config.policies.first { $0.id == id })
        let original = try XCTUnwrap(store.config.policies.first { $0.id == "openrouter" })
        XCTAssertEqual(imported.name, original.name + " 2")
        XCTAssertEqual(imported.endpoint, original.endpoint)
        XCTAssertEqual(imported.catalog, original.catalog)
        XCTAssertEqual(imported.modelValues, original.modelValues)
        XCTAssertNil(vault.read(policyID: id, endpoint: ApiRouting.openRouter), "the key stays with the original policy")
    }

    func testImportRefusesPlainHttpOversizedAndBrokenFiles() throws {
        let store = try makeStore()
        var policy = try XCTUnwrap(store.config.policies.first)
        policy.endpoint = "http://api.example.com/v1/chat/completions"
        XCTAssertThrowsError(try store.importPolicy(try JSONEncoder().encode(policy)))
        XCTAssertThrowsError(try store.importPolicy(Data(count: 600 * 1024)))
        XCTAssertThrowsError(try store.importPolicy(Data("{not json".utf8)))
        XCTAssertEqual(store.config.policies.count, 3)
    }

    func testTheModelListExportsAndImportsAndDropsValuesItNoLongerAllows() throws {
        let store = try makeStore()
        // A service the shared core knows nothing about: the list in the policy is the only source of capabilities.
        let id = try store.addPolicy(name: "自定义")
        try store.updatePolicy(id) { $0.endpoint = "https://api.example.com/v1/chat/completions"; $0.model = "my-model" }
        try store.selectPolicy(id)
        let tier = ModelParameter(key: "service_tier", label: "服务档位", choices: [ParameterChoice(label: "普通", value: "default"),
                                                                                  ParameterChoice(label: "优先", value: "priority")])
        let wide = ModelCatalog(models: [ModelDefinition(id: "my-model", parameters: [
            ModelParameter(key: "temperature", label: "Temperature", type: "number", min: 0, max: 2), tier])])
        try store.updatePolicy(id) {
            $0.catalog = wide
            $0.modelValues = ["my-model": ["temperature": .double(0.7), "service_tier": .string("priority")]]
        }
        XCTAssertEqual(store.config.modelValues["my-model"]?["temperature"], .double(0.7))
        XCTAssertEqual(store.parameters()["service_tier"], .string("priority"))

        let data = try store.exportCatalog(policyID: id)
        XCTAssertEqual(try JSONDecoder().decode(ModelCatalog.self, from: data), wide)

        // A list that only knows the service tier: the stored temperature goes, the tier stays.
        let narrow = ModelCatalog(models: [ModelDefinition(id: "my-model", parameters: [tier])])
        try store.importCatalog(try JSONEncoder().encode(narrow), policyID: id)
        XCTAssertEqual(store.config.modelCatalog, narrow)
        XCTAssertEqual(store.config.modelValues["my-model"]?["service_tier"], .string("priority"))
        XCTAssertNil(store.config.modelValues["my-model"]?["temperature"])

        let invalid = ModelCatalog(models: [ModelDefinition(id: "m", parameters: [ModelParameter(key: "not_allowed", label: "x", choices: [ParameterChoice(label: "a", value: "b")])])])
        XCTAssertThrowsError(try store.importCatalog(try JSONEncoder().encode(invalid), policyID: id))
        XCTAssertEqual(store.config.modelCatalog, narrow, "a rejected list changes nothing")
    }

    // MARK: prompts

    func testThePromptPackageIsUpgradedAndTheLimitsHold() throws {
        let old = #"{"schema_version":3,"package_id":"orangecell-input","version":"4.0.0","revision":3,"response_schema_version":2,"keyboard_language_rules":{"chinese":"x"}}"#
        let upgraded = try PromptPackage.parse(Data(old.utf8))
        XCTAssertEqual(upgraded, PromptPackage())
        XCTAssertThrowsError(try PromptPackage.parse(Data(#"{"schema_version":9}"#.utf8)))
        XCTAssertThrowsError(try PromptPackage.parse(Data(count: 129 * 1024)))
        let current = try PromptPackage.parse(Data(#"{"revision":20,"keyboard_language_rules":{"chinese":"保留标点"}}"#.utf8))
        XCTAssertEqual(current.revision, 20)
        XCTAssertEqual(current.keyboard_language_rules.chinese, "保留标点")
    }

    func testTheSystemPromptComesFromTheSharedCore() {
        let c = AiConfig()
        let plain = AiStore.systemPrompt(c, chinese: true, assistant: false)
        let assistant = AiStore.systemPrompt(c, chinese: true, assistant: true)
        XCTAssertFalse(plain.isEmpty)
        XCTAssertFalse(assistant.isEmpty)
        XCTAssertNotEqual(plain, assistant)
    }

    // MARK: keys

    func testAKeyBelongsToTheOriginItWasEnteredFor() throws {
        let vault = CredentialVault(stores: [MemorySecretStore()])
        try vault.save(policyID: "default", endpoint: "https://api.openai.com/v1/responses", secret: "  sk-abc \n")
        XCTAssertTrue(vault.has(policyID: "default"))
        XCTAssertEqual(vault.read(policyID: "default", endpoint: "https://api.openai.com/v1/responses"), "sk-abc")
        XCTAssertEqual(vault.read(policyID: "default", endpoint: "https://api.openai.com/v1/chat/completions"), "sk-abc", "the path does not matter")
        XCTAssertNil(vault.read(policyID: "default", endpoint: "https://evil.example.com/v1/responses"), "another host never gets the key")
        XCTAssertNil(vault.read(policyID: "default", endpoint: "https://api.openai.com:8443/v1/responses"), "nor does another port")
        XCTAssertNil(vault.read(policyID: "other", endpoint: "https://api.openai.com/v1/responses"))
        vault.remove(policyID: "default")
        XCTAssertFalse(vault.has(policyID: "default"))
    }

    func testKeysThatAreNotPlainSingleLineSecretsOrEndpointsThatAreNotHttpsAreRefused() throws {
        let vault = CredentialVault(stores: [MemorySecretStore()])
        XCTAssertThrowsError(try vault.save(policyID: "p", endpoint: "https://api.openai.com/v1/responses", secret: "   "))
        XCTAssertThrowsError(try vault.save(policyID: "p", endpoint: "https://api.openai.com/v1/responses", secret: "a\nb"))
        XCTAssertThrowsError(try vault.save(policyID: "p", endpoint: "http://api.openai.com/v1/responses", secret: "k"))
        XCTAssertThrowsError(try vault.save(policyID: "p", endpoint: "https://api.openai.com/v1/responses?x=1", secret: "k"))
        XCTAssertThrowsError(try vault.save(policyID: "p", endpoint: "https://user:pass@api.openai.com/v1/responses", secret: "k"))
        XCTAssertFalse(vault.has(policyID: "p"))
    }

    func testCopyingAPolicyCopiesItsKey() throws {
        let vault = CredentialVault(stores: [MemorySecretStore()])
        let endpoint = "https://api.openai.com/v1/responses"
        XCTAssertThrowsError(try vault.copy(from: "a", to: "b", endpoint: endpoint), "nothing to copy yet")
        try vault.save(policyID: "a", endpoint: endpoint, secret: "sk-copy")
        try vault.copy(from: "a", to: "b", endpoint: endpoint)
        XCTAssertEqual(vault.read(policyID: "b", endpoint: endpoint), "sk-copy")
    }

    func testTheVaultFallsBackToTheNextBackendWhenTheChosenOneHasNoKey() throws {
        let first = MemorySecretStore("keychain-shared")
        let second = MemorySecretStore("encrypted-file")
        let endpoint = "https://api.openai.com/v1/responses"
        try CredentialVault(stores: [second]).save(policyID: "p", endpoint: endpoint, secret: "sk-in-second")
        let vault = CredentialVault(stores: [first, second])
        XCTAssertEqual(vault.backendName, "keychain-shared")
        XCTAssertEqual(vault.read(policyID: "p", endpoint: endpoint), "sk-in-second")
    }

    func testTheChosenBackendIsRecordedOnceAndFollowed() throws {
        let root = try directory()
        let group = context(root)
        XCTAssertNil(CredentialVault.chosenBackend(in: group))
        CredentialVault.chooseBackend("encrypted-file", in: group)
        CredentialVault.chooseBackend("keychain-shared", in: group)
        XCTAssertEqual(CredentialVault.chosenBackend(in: group), "encrypted-file", "the first choice stays, so a key is never stranded")
    }
}
