// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import OCRime
import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @StateObject private var model = DiagnosticsModel()
    @State private var copied = false

    var body: some View {
        List {
            if let app = model.app {
                appGroupSection(app)
                probeSection(app)
                keyStorageSection(app)
                aiSection
                profileSection(app)
                rimeSection(app)
                rimeDataSection(app)
                deploySection(app)
                keyboardSection
                shareSection(app)
            } else {
                Section { ProgressView("检测中…") }
            }
        }
        .navigationTitle("诊断")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("oc.diagnostics.list")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("重新检测") { model.refresh() }
                    .disabled(model.isLoading)
            }
        }
        .task { model.refresh() }
    }

    // MARK: sections

    private func appGroupSection(_ report: DiagnosticsReport) -> some View {
        Section("App Group") {
            row("请求的名称", report.groupNominal)
            row("实际使用", report.groupResolved ?? "无（不共享）", id: "oc.diag.group")
            row("来源", sourceText(report.groupSource))
            row("共享目录", report.containerPath ?? "不可用")
            status("共享目录可写", report.containerWritable)
        }
    }

    private func probeSection(_ report: DiagnosticsReport) -> some View {
        Section("探针文件（主应用与键盘互通）") {
            status("主应用已写入探针", report.probeWritten)
            if let peer = report.peerProbe {
                status("看到键盘写入的探针", true)
                row("键盘探针时间", peer.writtenAt.formatted(date: .abbreviated, time: .standard))
                row("键盘进程", "\(peer.processID)")
            } else {
                status("看到键盘写入的探针", false)
                Text("还没有键盘写入的探针：先在任意输入框切换到「橘脑一颗」键盘，再回到这里重新检测。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func keyStorageSection(_ report: DiagnosticsReport) -> some View {
        Section("Key 存储") {
            ForEach(report.keyStorage, id: \.backend) { probe in
                VStack(alignment: .leading, spacing: 2) {
                    Text(probe.backend).font(.subheadline.bold())
                    Text("本进程写入 \(mark(probe.wroteOK)) · 读回 \(mark(probe.readBackOK))")
                        .font(.footnote)
                    if let group = probe.accessGroup {
                        Text("访问组 \(group)").font(.caption).foregroundStyle(.secondary)
                    }
                    if !probe.detail.isEmpty {
                        Text(probe.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    if let keyboard = model.keyboard?.keyStorage.first(where: { $0.backend == probe.backend }) {
                        Text("键盘读取 \(mark(keyboard.crossProcessReadOK))")
                            .font(.footnote)
                    }
                }
            }
            row("按键盘读取结果选用", model.chosenBackend, id: "oc.diag.backend")
            Button("运行 Key 存储自检（写入测试值）") { model.runKeySelfTest() }
                .accessibilityIdentifier("oc.diag.selftest")
            Text("自检只写入一个固定的测试值，不涉及你的 Key；之后在键盘里用一次再回来检测，即可看到键盘能否读到。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if model.keyboard == nil {
                Text("需要键盘运行过一次，才能判断跨进程读取。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aiSection: some View {
        Section("AI 配置（不含 Key）") {
            ForEach(model.aiLines, id: \.self) { line in
                row(line.title, line.value)
            }
        }
    }

    private func profileSection(_ report: DiagnosticsReport) -> some View {
        Section("描述文件（embedded.mobileprovision）") {
            if let expires = report.profileExpires {
                row("名称", report.profileName ?? "—")
                row("团队 ID", report.teamIdentifier ?? "—")
                row("到期时间", expires.formatted(date: .abbreviated, time: .shortened), id: "oc.diag.expiry")
                row("剩余天数", report.profileDaysRemaining.map { "\($0) 天" } ?? "—")
                ForEach(report.profileGroups, id: \.self) { Text($0).font(.caption) }
            } else if report.groupSource == AppGroupLocator.Source.profileParseFailed.rawValue {
                Text("描述文件存在但无法解析，App Group 的真实名字无法确认，已尝试原名。" + (report.notes.first { $0.contains("mobileprovision") } ?? ""))
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                Text("没有描述文件（模拟器或测试包）。侧载安装后这里显示到期时间。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rimeSection(_ report: DiagnosticsReport) -> some View {
        Section("librime 与 AI 核心") {
            row("librime 版本", model.rime?.version ?? "—", id: "oc.diag.rime")
            row("已加载模块", model.rime?.modules.joined(separator: " ") ?? "—")
            if let missing = model.rime?.missingRequired, !missing.isEmpty {
                row("缺少模块", missing.joined(separator: " "))
            }
            status("Rime 启动", model.rime?.started ?? false)
            status("oc_core 往返", report.ocCoreOK)
            row("本进程内存", report.footprintMB.map { String(format: "%.1f MB", $0) } ?? "—")
        }
    }

    private func rimeDataSection(_ report: DiagnosticsReport) -> some View {
        Section("词库数据（随应用打包）") {
            row("方案", report.rimeDataSchema ?? "—", id: "oc.diag.schema")
            row("词库", report.rimeDataDictionary ?? "—")
            row("编译所用 librime", report.rimeDataBuiltWithLibrime ?? "—")
            row("数据总大小", report.rimeDataBytes.map { Self.megabytes($0) } ?? "—")
            row("词典表大小", report.rimeDictionaryBytes.map { Self.megabytes($0) } ?? "—")
            row("用户词库目录", report.userDataDirectory ?? "—")
            row("用户词库位置", report.userDataShared.map { $0 ? "App Group（与键盘共享）" : "应用私有" } ?? "—")
            if let built = report.rimeDataBuiltWithLibrime, let linked = report.rimeVersion, built != linked {
                Text("词库是用 librime \(built) 编译的，当前链接的是 \(linked)：版本不一致，只记录告警。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func deploySection(_ report: DiagnosticsReport) -> some View {
        Section("部署") {
            row("部署戳", report.deployStamp ?? "还没有部署过", id: "oc.diag.stamp")
            Button("部署配置并通知键盘") { model.deploy() }
                .accessibilityIdentifier("oc.diag.deploy")
            if let outcome = model.deployOutcome {
                Text(outcome.message)
                    .font(.footnote)
                    .foregroundStyle(outcome.success ? Color.green : Color.red)
            }
            Text("只重新编译配置（default.yaml），词库本身是编译好打进应用的。键盘下次出现时发现部署戳变了，会重新载入。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private var keyboardSection: some View {
        Section("键盘进程") {
            if let keyboard = model.keyboard {
                row("最近运行", keyboard.generatedAt.formatted(date: .abbreviated, time: .standard))
                row("完全访问", keyboard.fullAccess.map { $0 ? "已开启" : "未开启" } ?? "—")
                row("librime", keyboard.rimeVersion ?? "—")
                row("键盘内存", keyboard.footprintMB.map { String(format: "%.1f MB", $0) } ?? "—")
                row("共享目录", keyboard.containerPath ?? "不可用")
            } else {
                Text("还没有键盘的报告。启用并使用一次键盘后重新检测。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shareSection(_ report: DiagnosticsReport) -> some View {
        Section("回传结果") {
            Button("复制诊断信息") {
                UIPasteboard.general.string = shareText(report)
                copied = true
            }
            .accessibilityIdentifier("oc.diag.copy")
            if copied {
                Text("已复制到剪贴板。里面没有 Key，也没有你输入过的文字。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("oc.diag.copied")
            }
            ShareLink("分享诊断报告（JSON）", item: shareText(report))
        } footer: {
            Text("复制后可以粘贴到聊天或备忘录里发给开发者。")
        }
    }

    // MARK: pieces

    private func shareText(_ report: DiagnosticsReport) -> String {
        var text = DiagnosticsCollector.json(report)
        if let keyboard = model.keyboard {
            text += "\n" + DiagnosticsCollector.json(keyboard)
        }
        if !model.aiLines.isEmpty {
            text += "\nAI 配置（不含 Key）\n" + model.aiLines.map { "\($0.title)：\($0.value)" }.joined(separator: "\n")
        }
        return text
    }

    private func row(_ title: String, _ value: String, id: String? = nil) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.footnote)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityIdentifier(id ?? "")
    }

    private func status(_ title: String, _ ok: Bool) -> some View {
        LabeledContent(title) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Color.green : Color.red)
        }
    }

    private func mark(_ value: Bool?) -> String {
        switch value {
        case .some(true): return "成功"
        case .some(false): return "失败"
        case .none: return "未测"
        }
    }

    private func sourceText(_ raw: String) -> String {
        switch AppGroupLocator.Source(rawValue: raw) {
        case .profileExact: return "描述文件：原名"
        case .profileSuffixed: return "描述文件：带团队 ID 后缀"
        case .nominalNoProfile: return "无描述文件，用原名（模拟器）"
        case .missing: return "描述文件里没有这个组：不共享"
        case .profileParseFailed: return "描述文件无法解析（已尝试原名）"
        case .none: return raw
        }
    }
}
