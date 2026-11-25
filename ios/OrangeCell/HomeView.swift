// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import SwiftUI
import UIKit

struct HomeView: View {
    @State private var trialText = ""
    @Environment(\.openURL) private var openURL

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("橘脑一颗 OrangeCell")
                        .font(.title2.bold())
                    Text("iOS 版 · 预览 \(versionText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("拼音输入、万象词库离线可用；在线 AI 纠错、助手和表情候选需要在「AI 云端候选」里配置自己的 Key。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("启用键盘") {
                step(1, "打开「设置」→「通用」→「键盘」→「键盘」→「添加新键盘…」，选择「橘脑一颗」。")
                step(2, "点进已添加的「橘脑一颗」，打开「允许完全访问」。离线输入不需要；在线 AI 联网时才需要。")
                step(3, "回到任意输入框，点系统键盘上的地球键（或长按它），切换到「橘脑一颗」。")
                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("oc.home.openSettings")
            }

            Section("关于「完全访问」") {
                Text("不开完全访问：离线拼音输入照常使用；学到的词只保存在键盘自己的私有目录，键盘不联网，AI 行显示一句提示。")
                Text("开启后：本应用的设置（含 AI 配置）和部署结果能让键盘读到；键盘才能联网请求 AI。用户词库仍只在键盘自己的私有目录。键入内容只在你同意云端 AI 之后才会发送，密码、验证码和纯数字输入框永远不发送。")
            }
            .font(.footnote)

            Section("试打区") {
                TextField("在这里试一试键盘", text: $trialText)
                    .accessibilityIdentifier("oc.home.trial")
            }

            Section {
                NavigationLink(value: Route.ai) {
                    Label("AI 云端候选", systemImage: "sparkles")
                }
                .accessibilityIdentifier("oc.home.ai")
                NavigationLink(value: Route.diagnostics) {
                    Label("诊断", systemImage: "stethoscope")
                }
                .accessibilityIdentifier("oc.home.diagnostics")
                NavigationLink(value: Route.licenses) {
                    Label("致谢与开源许可", systemImage: "doc.text")
                }
                .accessibilityIdentifier("oc.home.licenses")
            } footer: {
                Text("诊断页显示 App Group 是否可用、Key 存储方式、描述文件到期时间、词库数据和键盘的运行状态。")
            }
        }
        .navigationTitle("橘脑一颗")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.orange))
            Text(text)
        }
        .padding(.vertical, 2)
    }
}
