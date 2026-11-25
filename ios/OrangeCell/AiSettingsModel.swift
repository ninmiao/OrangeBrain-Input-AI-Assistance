// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import OCCore
import SwiftUI

/// The app side of the AI configuration: edits go through `AiStore` (validated like Android, written to the App
/// Group for the keyboard to read), keys through `CredentialVault` (the backend chosen by the diagnostics,
/// docs/IOS_PLAN.md section 4.6), and every change of a key needs the passcode or Face ID.
@MainActor
final class AiSettingsModel: ObservableObject {
    @Published private(set) var config = AiConfig()
    @Published private(set) var storeAvailable = false
    @Published private(set) var keyPresent: [String: Bool] = [:]
    @Published private(set) var latency: [String: String] = [:]
    @Published private(set) var testing: Set<String> = []
    @Published private(set) var backendName = "—"
    @Published var notice = ""
    @Published var numberRow = true
    /// The cloud consent dialog is up (Android: "允许发送到云端 AI").
    @Published var showConsent = false

    let context: AppGroupContext
    private let store: AiStore?
    private var vault: CredentialVault?
    private var pendingChange: ((inout AiConfig) -> Void)?

    init() {
        let context = AppGroupContext.detect()
        self.context = context
        store = AiStore(context: context)
        vault = CredentialVault(context: context)
        storeAvailable = store != nil
        reload()
    }

    // MARK: reading

    func reload() {
        if let store { config = store.config }
        numberRow = KeyboardSettings.load(in: context).numberRow
        vault = CredentialVault(context: context)
        backendName = vault?.backendName ?? "—"
        refreshKeys()
    }

    private func refreshKeys() {
        var present: [String: Bool] = [:]
        for policy in config.policies { present[policy.id] = vault?.has(policyID: policy.id) ?? false }
        keyPresent = present
    }

    var selectedPolicy: AiPolicy? { config.policies.first { $0.id == config.selectedPolicyId } }

    func policy(_ id: String) -> AiPolicy? { config.policies.first { $0.id == id } }

    /// The policy flattened into a configuration (what the keyboard would use if it were selected).
    func configuration(for id: String) -> AiConfig? { store?.configForPolicy(id) }

    /// One line about what a policy sends and with which parameters (the Android list row).
    func summary(_ policy: AiPolicy) -> String {
        guard let applied = store?.configForPolicy(policy.id) else { return policy.model }
        var parts = [policy.model]
        if ApiRouting.isOpenRouter(policy.endpoint) { parts.append("供应商：" + (policy.provider.isEmpty ? "自动" : policy.provider)) }
        let values = AiStore.parameters(for: applied)
        if let definition = AiStore.definition(for: applied) {
            for parameter in definition.parameters {
                guard let value = values[parameter.key] else { continue }
                let shown = parameter.choices.first { $0.value == value.content }?.label ?? value.content
                parts.append("\(parameter.label) \(shown)")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: validated writes

    @discardableResult
    func update(_ saved: String = "已保存并生效", _ transform: (inout AiConfig) throws -> Void) -> Bool {
        guard let store else {
            notice = "App Group 不可用，设置无法保存，键盘也读不到"
            return false
        }
        do {
            config = try store.update(transform)
            notice = saved
            refreshKeys()
            return true
        } catch {
            config = store.config
            notice = "尚未保存：" + ((error as? AiStoreError)?.message ?? "请检查输入；原设置仍有效")
            return false
        }
    }

    /// The Android rule: turning the cloud on asks once, with this wording. Cancel leaves everything as it was.
    func change(needsConsent: Bool, _ transform: @escaping (inout AiConfig) -> Void) {
        if needsConsent && !config.consent {
            pendingChange = transform
            showConsent = true
        } else {
            update { transform(&$0) }
        }
    }

    func confirmConsent() {
        let transform = pendingChange
        pendingChange = nil
        update { c in
            transform?(&c)
            c.consent = true
        }
    }

    func cancelConsent() {
        pendingChange = nil
        reload()
    }

    func setMode(_ mode: AiMode) {
        guard mode != AiMode.of(config) || (mode != .none && !config.consent) else { return }
        change(needsConsent: mode != .none) { $0 = mode.applying(to: $0) }
    }

    func setConsent(_ value: Bool) {
        change(needsConsent: value) { $0.consent = value }
    }

    func setNumberRow(_ value: Bool) {
        numberRow = value
        KeyboardSettings(numberRow: value).save(in: context)
        notice = "数字行设置已保存，下次打开键盘生效"
    }

    // MARK: policies

    func select(_ id: String) {
        guard id != config.selectedPolicyId else { return }
        run("已切换 Policy") { try $0.selectPolicy(id) }
    }

    @discardableResult
    func addPolicy() -> String? {
        guard let store else { return nil }
        do {
            let id = try store.addPolicy(name: "Policy \(store.config.policies.count + 1)")
            reload()
            notice = "已新增 Policy"
            return id
        } catch {
            notice = (error as? AiStoreError)?.message ?? "无法新增"
            return nil
        }
    }

    func rename(_ id: String, to name: String) {
        run("名称已保存") { try $0.renamePolicy(id, to: name) }
    }

    func duplicate(_ id: String) async -> String? {
        guard let store else { return nil }
        let hasKey = keyPresent[id] ?? false
        if hasKey, !(await verify("验证身份以复制 Policy 的密钥")) { return nil }
        do {
            let copy = try store.duplicatePolicy(id)
            if hasKey, let policy = store.config.policies.first(where: { $0.id == id }) {
                try vault?.copy(from: id, to: copy, endpoint: policy.endpoint)
            }
            reload()
            notice = "已复制 Policy（含 Key）"
            return copy
        } catch {
            reload()
            notice = (error as? AiStoreError)?.message ?? "复制失败"
            return nil
        }
    }

    func delete(_ id: String) async -> Bool {
        guard let store, await verify("验证身份以删除 Policy 及其密钥") else { return false }
        do {
            try store.deletePolicy(id)
            vault?.remove(policyID: id)
            reload()
            notice = "已删除"
            return true
        } catch {
            notice = (error as? AiStoreError)?.message ?? "删除失败"
            return false
        }
    }

    func editPolicy(_ id: String, _ saved: String = "已保存并生效", _ transform: @escaping (inout AiPolicy) throws -> Void) {
        run(saved) { try $0.updatePolicy(id, transform) }
    }

    func setParameter(policy id: String, model: String, key: String, value: JSONPrimitive?) {
        editPolicy(id, "参数已保存") { policy in
            var values = policy.modelValues[model] ?? [:]
            if let value { values[key] = value } else { values.removeValue(forKey: key) }
            policy.modelValues[model] = values
        }
    }

    private func run(_ saved: String, _ body: (AiStore) throws -> Void) {
        guard let store else { notice = "App Group 不可用，设置无法保存"; return }
        do {
            try body(store)
            reload()
            notice = saved
        } catch {
            reload()
            notice = "尚未保存：" + ((error as? AiStoreError)?.message ?? "请检查输入；原设置仍有效")
        }
    }

    // MARK: keys

    func verify(_ reason: String) async -> Bool {
        switch await Authenticator.verify(reason: reason) {
        case .verified: return true
        case .unavailable:
            notice = "请先设置系统锁屏 PIN 或密码"
            return false
        case .failed:
            notice = "身份验证未通过"
            return false
        }
    }

    /// Saves the endpoint and, when one is given, the key (after the person proved who they are). A blank key keeps
    /// the stored one; a key is only ever kept for the origin it was entered for.
    func saveConnection(policy id: String, endpoint: String, secret: String) async -> Bool {
        let url = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSecret = !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard await verify("验证身份以修改 Policy 密钥") else { return false }
        do {
            _ = try CredentialVault.origin(of: url)
            if hasSecret {
                chooseBackendIfNeeded()
                vault = CredentialVault(context: context)
                try vault?.save(policyID: id, endpoint: url, secret: secret)
            } else if vault?.read(policyID: id, endpoint: url) == nil {
                throw AiStoreError("请输入 API Key")
            }
            if let store {
                try store.updatePolicy(id) { $0.endpoint = url }
            }
            reload()
            notice = "连接配置已加密保存"
            return true
        } catch {
            reload()
            notice = (error as? AiStoreError)?.message ?? "无法保存：\(error)"
            return false
        }
    }

    func clearKey(policy id: String) async {
        guard await verify("验证身份以清除 Policy 密钥") else { return }
        vault?.remove(policyID: id)
        if config.selectedPolicyId == id { update("本 Policy 密钥已清除") { $0.enabled = false; $0.assistantEnabled = false } }
        else { reload(); notice = "本 Policy 密钥已清除" }
    }

    /// The first key decides where all keys go: the Keychain group when the keyboard proved it can read it,
    /// otherwise the encrypted file in the App Group (works whatever the signing allows).
    private func chooseBackendIfNeeded() {
        guard CredentialVault.chosenBackend(in: context) == nil else { return }
        let keyboard = DiagnosticsCollector.loadReport(role: "keyboard")
        var backend = KeyStorageSelfTest.chooseBackend(keyboardProbes: keyboard?.keyStorage ?? [])
        if backend == "none" { backend = "encrypted-file" }
        CredentialVault.chooseBackend(backend, in: context)
    }

    // MARK: import and export

    func exportPolicy(_ id: String) -> Data? { try? store?.exportPolicy(id) }
    func exportCatalog(_ id: String) -> Data? { try? store?.exportCatalog(policyID: id) }
    func exportConfig() -> Data? { try? store?.exportConfig() }
    func exportPrompt() -> Data? { try? store?.exportPromptPackage() }

    func importPolicy(_ data: Data) {
        run("Policy 已导入（不含 Key，请重新保存）") { _ = try $0.importPolicy(data) }
    }

    func importCatalog(_ data: Data, policy id: String) {
        run("列表已导入；不再有效的旧参数已清除，其他选择保留") { try $0.importCatalog(data, policyID: id) }
    }

    func savePrompt(_ text: String, policy id: String) {
        run("本 Policy 提示词已保存") { store in
            let package = try PromptPackage.parse(Data(text.utf8))
            try store.updatePolicy(id) { $0.localOverride = package }
        }
    }

    func restorePrompt(policy id: String) {
        run("已恢复内置提示词") { try $0.updatePolicy(id) { $0.active = nil; $0.localOverride = nil } }
    }

    func prompt(_ id: String) -> PromptPackage {
        (policy(id)?.localOverride ?? policy(id)?.active?.pack ?? PromptPackage.builtin).upgraded()
    }

    // MARK: latency test

    func testLatency(_ id: String) {
        guard !testing.contains(id), let store, let c = store.configForPolicy(id) else { return }
        let name = policy(id)?.name ?? id
        guard let key = vault?.read(policyID: id, endpoint: c.endpoint) else {
            latency[id] = "\(name) · 请先为这个 Policy 保存 Key"
            return
        }
        testing.insert(id)
        latency[id] = "正在测试 \(name)…（一次请求）"
        let request = AiRequest(
            stamp: RequestStamp(editorSession: 0, inputRevision: 0, promptGeneration: c.generation, keyboardGeneration: 0, apiGeneration: c.generation),
            input: AiLatencySamples.input(chinese: true, c),
            systemPrompt: AiStore.systemPrompt(c, chinese: true, assistant: c.assistantEnabled),
            completionEnabled: c.completion, candidateCount: c.candidateCount, outputTokenBudget: c.outputTokenBudget,
            assistantEnabled: c.assistantEnabled)
        let call = AiCall(endpoint: c.endpoint, key: key, model: c.model, timeoutMs: c.timeoutMs, parameters: AiStore.parameters(for: c),
                          provider: c.provider, request: request)
        let routes = AiLoopbackRoutes.load(in: context)
        let line = summary(policy(id) ?? c.snapshotPolicy(name: name))
        Task {
            let started = ContinuousClock.now
            func milliseconds() -> Int {
                let elapsed = ContinuousClock.now - started
                return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
            }
            do {
                let sentAt = ContinuousClock.now
                let result = try await AiChatClient(routes: routes).send(call, onPartial: { _ in })
                let elapsed = ContinuousClock.now - sentAt
                let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
                latency[id] = "\(name) · \(line)\n\(ms) ms（完整候选返回）\n\(result.candidates.first ?? "")"
            } catch {
                let reason: String
                if let error = error as? AiError, case .http(let status) = error { reason = "HTTP \(status)" }
                else { reason = AiFailure.detail(error) }
                latency[id] = "\(name) · 测试失败：\(reason)（\(milliseconds()) ms）"
            }
            testing.remove(id)
        }
    }
}
