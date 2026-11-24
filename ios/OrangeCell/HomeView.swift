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
                    Text("iOS 版 · 诊断预览 \(versionText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("这一版只验证键盘能否加载，真正的拼音输入在下一阶段加入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("启用键盘") {
                step(1, "打开「设置」→「通用」→「键盘」→「键盘」→「添加新键盘…」，选择「橘脑一颗」。")
                step(2, "点进已添加的「橘脑一颗」，打开「允许完全访问」。离线输入不需要；在线 AI 联网时才需要。")
                step(3, "回到任意输入框，长按键盘左下角的地球键，选择「橘脑一颗」。")
                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("oc.home.openSettings")
            }

            Section("关于「完全访问」") {
                Text("不开完全访问：只使用离线输入，键盘不联网，也不能读写与本应用共享的数据。")
                Text("开启后：键盘才能请求在线 AI，并与主应用共享配置。键入内容只在你同意云端 AI 之后才会发送。")
            }
            .font(.footnote)

            Section("试打区") {
                TextField("在这里试一试键盘", text: $trialText)
                    .accessibilityIdentifier("oc.home.trial")
            }

            Section {
                NavigationLink(value: Route.diagnostics) {
                    Label("诊断", systemImage: "stethoscope")
                }
                .accessibilityIdentifier("oc.home.diagnostics")
            } footer: {
                Text("显示 App Group 是否可用、Key 存储方式、描述文件到期时间和键盘的运行状态。")
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
