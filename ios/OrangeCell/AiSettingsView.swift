// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import SwiftUI
import UniformTypeIdentifiers

/// A JSON file for `fileExporter` / `fileImporter`.
struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// A number the person types: saved by itself shortly after they stop typing (like Android); a value that
/// does not pass the range check is not saved and the old setting stays in force.
struct NumberSetting: View {
    let title: String
    let value: Int
    /// 1 for plain numbers, 1000 for seconds shown over milliseconds.
    var scale = 1
    let identifier: String
    let save: (Int) -> Void

    @State private var text = ""
    @State private var pending: Task<Void, Never>?

    var body: some View {
        LabeledContent(title) {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                .accessibilityIdentifier(identifier)
        }
        .onAppear { text = String(value / scale) }
        .onChange(of: value) { _, new in
            let shown = String(new / scale)
            if shown != text && Int(text) != new / scale { text = shown }
        }
        .onChange(of: text) { _, new in
            pending?.cancel()
            guard let number = Int(new), number * scale != value else { return }
            pending = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if !Task.isCancelled { save(number * scale) }
            }
        }
    }
}

struct AiSettingsView: View {
    @StateObject private var model = AiSettingsModel()
    @State private var importing = false
    @State private var exporting: JSONFile?
    @State private var exportName = "orangecell-config.json"

    var body: some View {
        List {
            if !model.storeAvailable {
                Section {
                    Text("App Group 不可用（见「诊断」页）：这里的设置无法保存，键盘也读不到。")
                        .foregroundStyle(.red)
                }
            }
            cloudSection
            typingSection
            keyboardSection
            policySection
            transferSection
            if !model.notice.isEmpty {
                Section { Text(model.notice).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("oc.ai.notice") }
            }
        }
        .navigationTitle("AI 云端候选")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("oc.ai.settings")
        .onAppear { model.reload() }
        .alert("允许发送到云端 AI", isPresented: $model.showConsent) {
            Button("允许") { model.confirmConsent() }
            Button("取消", role: .cancel) { model.cancelConsent() }
        } message: {
            Text("AI 会把当前输入及已启用的前后文发送到所选 Policy，可能产生 API 费用。")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { model.importPolicy(data) } else { model.notice = "无法读取这个文件" }
        }
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                      document: exporting, contentType: .json, defaultFilename: exportName) { result in
            if case .success = result { model.notice = "已导出，文件不含 Key" } else { model.notice = "导出没有完成" }
        }
    }

    // MARK: sections

    private var cloudSection: some View {
        Section {
            Picker("AI 增强（自动）", selection: Binding(get: { AiMode.of(model.config) }, set: { model.setMode($0) })) {
                ForEach(AiMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("oc.ai.mode")
            Toggle("允许使用云端 AI（含手动请求）", isOn: Binding(get: { model.config.consent }, set: { model.setConsent($0) }))
                .accessibilityIdentifier("oc.ai.consent")
        } header: {
            Text("云端")
        } footer: {
            Text("选「无」时只在点键盘上的星光或表情键后才请求。键盘需要开启「完全访问」才能联网；密码、验证码和纯数字输入框永远不会发送。")
        }
    }

    private var typingSection: some View {
        Section {
            Toggle("空格分词（中文键盘）", isOn: Binding(get: { model.config.wordSegmentation }, set: { value in model.update { $0.wordSegmentation = value } }))
            NumberSetting(title: "停手等待（毫秒，50–2000）", value: Int(model.config.debounceMs), identifier: "oc.ai.debounce") { number in
                model.update { $0.debounceMs = Int64(number) }
            }
            NumberSetting(title: "请求超时（秒，1–60）", value: model.config.timeoutMs, scale: 1000, identifier: "oc.ai.timeout") { number in
                model.update { $0.timeoutMs = number }
            }
            NumberSetting(title: "当前输入上限（字符，1–300）", value: model.config.targetLimit, identifier: "oc.ai.target") { number in
                model.update { $0.targetLimit = number }
            }
            Toggle("参考前后文", isOn: Binding(get: { model.config.contextEnabled }, set: { value in model.update { $0.contextEnabled = value } }))
            NumberSetting(title: "前文字符数（0–500）", value: model.config.beforeLength, identifier: "oc.ai.before") { number in
                model.update { $0.beforeLength = number }
            }
            NumberSetting(title: "后文字符数（0–500）", value: model.config.afterLength, identifier: "oc.ai.after") { number in
                model.update { $0.afterLength = number }
            }
            NumberSetting(title: "输出 token 软预算（1–65536）", value: model.config.outputTokenBudget, identifier: "oc.ai.budget") { number in
                model.update { $0.outputTokenBudget = number }
            }
        } header: {
            Text("请求")
        } footer: {
            Text("默认前 50、后 0；只改当前输入。预算不足时优先保留完整候选。数值超出范围时不保存，原设置仍有效。")
        }
    }

    private var keyboardSection: some View {
        Section {
            Toggle("字母键盘顶部数字行", isOn: Binding(get: { model.numberRow }, set: { model.setNumberRow($0) }))
                .accessibilityIdentifier("oc.ai.numberrow")
        } header: {
            Text("键盘")
        } footer: {
            Text("按键震动和按键音跟随系统「键盘」设置里的触感与声音，需要开启「完全访问」。")
        }
    }

    private var policySection: some View {
        Section {
            ForEach(model.config.policies, id: \.id) { policy in
                let selected = policy.id == model.config.selectedPolicyId
                NavigationLink(value: Route.policy(policy.id)) {
                    HStack(spacing: 12) {
                        Button { model.select(policy.id) } label: {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .imageScale(.large)
                                .foregroundStyle(selected ? Color.orange : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("选择 Policy \(policy.name)")
                        .accessibilityIdentifier("oc.ai.policy.select." + policy.id)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(policy.name)
                            Text(model.summary(policy)).font(.caption).foregroundStyle(.secondary)
                            Text((model.keyPresent[policy.id] ?? false) ? "Key 已加密保存" : "Key 尚未配置")
                                .font(.caption2)
                                .foregroundStyle((model.keyPresent[policy.id] ?? false) ? Color.green : Color.orange)
                        }
                    }
                }
                .accessibilityIdentifier("oc.ai.policy." + policy.id)
            }
            Button("新增 Policy") { _ = model.addPolicy() }
                .accessibilityIdentifier("oc.ai.addpolicy")
        } header: {
            Text("Policy")
        } footer: {
            Text("勾选一个使用。每个 Policy 分别保存接口、加密 Key、模型参数及提示词。")
        }
    }

    private var transferSection: some View {
        Section {
            Button("导入 Policy（JSON，不含 Key）") { importing = true }
            Button("导出全部配置（JSON，不含 Key）") {
                if let data = model.exportConfig() { exportName = "orangecell-ai-config.json"; exporting = JSONFile(data: data) }
            }
        } header: {
            Text("导入与导出")
        } footer: {
            Text("文件格式与 Android 版相同，两个平台的配置可以互相导入。Key 永远不会写进文件。")
        }
    }
}

// MARK: one policy

struct PolicyEditorView: View {
    let policyID: String
    @StateObject private var model = AiSettingsModel()
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var model_ = ""
    @State private var provider = ""
    @State private var showConnection = false
    @State private var showPrompt = false
    @State private var confirmDelete = false
    @State private var importingCatalog = false
    @State private var exporting: JSONFile?
    @State private var exportName = "orangecell-input-models.json"

    private var policy: AiPolicy? { model.policy(policyID) }

    var body: some View {
        List {
            if let policy {
                nameSection(policy)
                connectionSection(policy)
                parametersSection(policy)
                promptSection(policy)
                testSection(policy)
                transferSection
                if model.config.policies.count > 1 {
                    Section {
                        Button("删除此 Policy", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("oc.policy.delete")
                    }
                }
                if !model.notice.isEmpty {
                    Section { Text(model.notice).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("oc.policy.notice") }
                }
            } else {
                Text("这个 Policy 已不存在。")
            }
        }
        .navigationTitle(policy?.name ?? "Policy")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("oc.policy.editor")
        .onAppear {
            model.reload()
            name = policy?.name ?? ""
            model_ = policy?.model ?? ""
            provider = policy?.provider ?? ""
        }
        .sheet(isPresented: $showConnection) {
            ConnectionSheet(model: model, policyID: policyID, endpoint: policy?.endpoint ?? "") { showConnection = false }
        }
        .sheet(isPresented: $showPrompt) {
            PromptSheet(model: model, policyID: policyID) { showPrompt = false }
        }
        .confirmationDialog("删除 \(policy?.name ?? "")？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除（含加密 Key）", role: .destructive) {
                Task { if await model.delete(policyID) { dismiss() } }
            }
        } message: {
            Text("将删除本 Policy 及其加密 Key。")
        }
        .fileImporter(isPresented: $importingCatalog, allowedContentTypes: [.json, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { model.importCatalog(data, policy: policyID) } else { model.notice = "无法读取这个文件" }
        }
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                      document: exporting, contentType: .json, defaultFilename: exportName) { result in
            if case .success = result { model.notice = "已导出，文件不含 Key、连接地址或输入文字" } else { model.notice = "导出没有完成" }
        }
    }

    // MARK: sections

    private func nameSection(_ policy: AiPolicy) -> some View {
        Section {
            TextField("Policy 名称", text: $name)
                .accessibilityIdentifier("oc.policy.name")
                .onSubmit { model.rename(policyID, to: name) }
            if policyID == model.config.selectedPolicyId {
                Label("正在使用", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("使用此 Policy") { model.select(policyID) }
                    .accessibilityIdentifier("oc.policy.use")
            }
            Button("复制此 Policy（含 Key）") {
                Task { _ = await model.duplicate(policyID) }
            }
        } footer: {
            Text("改名后按键盘上的「完成」保存。")
        }
    }

    private func connectionSection(_ policy: AiPolicy) -> some View {
        Section {
            LabeledContent("接口") { Text(policy.endpoint).font(.footnote).multilineTextAlignment(.trailing).textSelection(.enabled) }
            TextField("模型", text: $model_)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("oc.policy.model")
                .onSubmit { model.editPolicy(policyID, "模型已保存") { $0.model = model_.trimmingCharacters(in: .whitespacesAndNewlines) } }
            if ApiRouting.isOpenRouter(policy.endpoint) {
                TextField("供应商（留空自动路由）", text: $provider)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { model.editPolicy(policyID, "供应商已保存") { $0.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines) } }
            }
            LabeledContent("Key") {
                Text((model.keyPresent[policyID] ?? false) ? "已加密保存" : "尚未配置")
                    .foregroundStyle((model.keyPresent[policyID] ?? false) ? Color.green : Color.orange)
                    .accessibilityIdentifier("oc.policy.keystatus")
            }
            LabeledContent("Key 存储") { Text(model.backendName).font(.footnote) }
            Button("验证身份并配置连接 / 密钥") { showConnection = true }
                .accessibilityIdentifier("oc.policy.connection")
            if model.keyPresent[policyID] ?? false {
                Button("验证身份并清除本 Policy 密钥", role: .destructive) { Task { await model.clearKey(policy: policyID) } }
            }
        } header: {
            Text("连接与模型")
        } footer: {
            Text("模型和供应商输入后按键盘上的「完成」保存。Key 与接口的域名绑定：换成别的域名后旧 Key 不会被发送过去。")
        }
    }

    @ViewBuilder
    private func parametersSection(_ policy: AiPolicy) -> some View {
        if let applied = model.configuration(for: policyID), let definition = AiStore.definition(for: applied), !definition.parameters.isEmpty {
            Section {
                ForEach(definition.parameters, id: \.key) { parameter in
                    ParameterRow(parameter: parameter, value: policy.modelValues[policy.model]?[parameter.key]) { value in
                        model.setParameter(policy: policyID, model: policy.model, key: parameter.key, value: value)
                    }
                }
            } header: {
                Text("模型与参数（速度 / 推理强度）")
            } footer: {
                Text("只列出这个模型支持的参数；选「服务端默认」就不发送该参数。")
            }
        } else {
            Section {
                Text("尚未维护此模型的参数能力。可导入服务商对应的列表（见下方）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("模型与参数")
            }
        }
    }

    private func promptSection(_ policy: AiPolicy) -> some View {
        Section {
            LabeledContent("版本") { Text(model.prompt(policyID).version).font(.footnote) }
            Button("编辑中英短提示词") { showPrompt = true }
            Button("恢复本 Policy 内置提示词") { model.restorePrompt(policy: policyID) }
        } header: {
            Text("提示词")
        } footer: {
            Text("本 Policy 的修改独立保存；繁简随键盘切换，模型输出紧凑 JSON 候选数组。")
        }
    }

    private func testSection(_ policy: AiPolicy) -> some View {
        Section {
            Button(model.testing.contains(policyID) ? "测试中…" : "测试当前 Policy 延迟") { model.testLatency(policyID) }
                .disabled(model.testing.contains(policyID))
                .accessibilityIdentifier("oc.policy.latency")
            if let text = model.latency[policyID] {
                Text(text).font(.footnote).textSelection(.enabled).accessibilityIdentifier("oc.policy.latency.result")
            }
        } header: {
            Text("测试")
        } footer: {
            Text("用这个 Policy 的实际模型、参数、提供商和超时发出一次请求，发送的是内置的长输入样例，不是你输入的文字。")
        }
    }

    private var transferSection: some View {
        Section {
            Button("导出此 Policy（JSON，不含 Key）") {
                if let data = model.exportPolicy(policyID) { exportName = "orangecell-policy.json"; exporting = JSONFile(data: data) }
            }
            Button("导出模型与参数列表") {
                if let data = model.exportCatalog(policyID) { exportName = "orangecell-input-models.json"; exporting = JSONFile(data: data) }
            }
            Button("导入模型与参数列表 JSON") { importingCatalog = true }
        } header: {
            Text("导入与导出")
        }
    }
}

/// One model parameter: a choice, a number or a switch, or "服务端默认" (not sent).
struct ParameterRow: View {
    let parameter: ModelParameter
    let value: JSONPrimitive?
    let save: (JSONPrimitive?) -> Void

    @State private var text = ""

    var body: some View {
        switch parameter.type {
        case "enum":
            Picker(parameter.label, selection: Binding(
                get: { value?.content ?? "" },
                set: { choice in save(choice.isEmpty ? nil : .string(choice)) })) {
                Text("服务端默认").tag("")
                ForEach(parameter.choices, id: \.value) { Text($0.label).tag($0.value) }
            }
            .accessibilityIdentifier("oc.param." + parameter.key)
        case "boolean":
            Picker(parameter.label, selection: Binding(
                get: { value.map { $0.content } ?? "" },
                set: { choice in save(choice.isEmpty ? nil : .bool(choice == "true")) })) {
                Text("服务端默认").tag("")
                Text("开").tag("true")
                Text("关").tag("false")
            }
        default:
            LabeledContent(parameter.label) {
                TextField("服务端默认", text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .onSubmit(commit)
            }
            .onAppear { text = value?.content ?? "" }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { save(nil); return }
        if parameter.type == "integer", let number = Int64(trimmed) { save(.int(number)) }
        else if let number = Double(trimmed) { save(.double(number)) }
    }
}

/// The key and the address: asks who the person is before anything is written (the app only).
struct ConnectionSheet: View {
    @ObservedObject var model: AiSettingsModel
    let policyID: String
    @State var endpoint: String
    let done: () -> Void
    @State private var secret = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("完整 HTTPS API 地址", text: $endpoint)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .accessibilityIdentifier("oc.connection.endpoint")
                    SecureField("新 API Key（同域名留空保留）", text: $secret)
                        .textContentType(.password)
                        .accessibilityIdentifier("oc.connection.key")
                } footer: {
                    Text("Responses / Chat Completions / Interactions 的完整地址，不能含查询参数。Key 加密保存，只发送到这个域名。")
                }
                if !model.notice.isEmpty {
                    Section { Text(model.notice).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("连接配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { secret = ""; done() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        working = true
                        Task {
                            let saved = await model.saveConnection(policy: policyID, endpoint: endpoint, secret: secret)
                            secret = ""
                            working = false
                            if saved { done() }
                        }
                    }
                    .disabled(working)
                    .accessibilityIdentifier("oc.connection.save")
                }
            }
        }
        .onDisappear { secret = "" }
    }
}

/// The short Chinese and English prompt rules of one policy, as the JSON Android uses.
struct PromptSheet: View {
    @ObservedObject var model: AiSettingsModel
    let policyID: String
    let done: () -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
                .navigationTitle("提示词")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { done() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { model.savePrompt(text, policy: policyID); done() }
                    }
                }
        }
        .onAppear {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            text = (try? encoder.encode(model.prompt(policyID))).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
    }
}
