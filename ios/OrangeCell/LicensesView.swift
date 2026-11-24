// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 致谢与开源许可: every component that ships in the app, with its full license text
/// from the `licenses` folder (ios/Resources/licenses) and the data licenses that travel
/// with the compiled dictionary (`rime-shared/licenses`).
struct LicenseComponent: Decodable, Identifiable {
    let id: String
    let name: String
    let license: String
    let url: String
    let files: [String]
    let folder: String?
}

struct LicenseIndex: Decodable {
    let components: [LicenseComponent]
    let data: [LicenseComponent]
}

enum LicenseStore {
    static var root: URL? { Bundle.main.url(forResource: "licenses", withExtension: nil) }

    static func loadIndex() -> LicenseIndex? {
        guard let url = root?.appendingPathComponent("index.json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(LicenseIndex.self, from: data)
    }

    /// Texts of one component, in file order. A missing file is reported, not hidden.
    static func texts(for component: LicenseComponent, isData: Bool) -> [(file: String, text: String)] {
        let folder: URL?
        if isData, let relative = component.folder {
            folder = Bundle.main.bundleURL.appendingPathComponent(relative, isDirectory: true)
        } else {
            folder = root?.appendingPathComponent(component.id, isDirectory: true)
        }
        return component.files.map { name in
            let text = folder.flatMap { try? String(contentsOf: $0.appendingPathComponent(name), encoding: .utf8) }
            return (name, text ?? "（缺少许可文件 \(name)）")
        }
    }
}

struct LicensesView: View {
    private let index = LicenseStore.loadIndex()

    var body: some View {
        List {
            Section {
                Text("橘脑一颗是自由软件，按 GPL-3.0-or-later 发布。下面是随应用分发的第三方代码和数据，以及它们各自的许可证原文。")
                    .font(.footnote)
            }
            if let index {
                Section("代码与库") {
                    ForEach(index.components) { row($0, isData: false) }
                }
                Section("词库数据") {
                    ForEach(index.data) { row($0, isData: true) }
                }
            } else {
                Section { Text("没有找到许可证清单（licenses/index.json）。").foregroundStyle(.red) }
            }
        }
        .navigationTitle("致谢与开源许可")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("oc.licenses.list")
    }

    private func row(_ component: LicenseComponent, isData: Bool) -> some View {
        NavigationLink {
            LicenseTextView(component: component, isData: isData)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(component.name)
                Text(component.license).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct LicenseTextView: View {
    let component: LicenseComponent
    let isData: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(component.license).font(.headline)
                if let url = URL(string: component.url) {
                    Link(component.url, destination: url).font(.footnote)
                }
                ForEach(LicenseStore.texts(for: component, isData: isData), id: \.file) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.file).font(.caption.bold()).foregroundStyle(.secondary)
                        Text(item.text)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(component.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
