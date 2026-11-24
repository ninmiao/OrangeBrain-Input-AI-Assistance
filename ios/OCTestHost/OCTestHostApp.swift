// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Simulator-only host with a single text field that grabs focus at launch, so
/// the system shows whatever keyboard is selected (ideally ours) without a tap.
@main
struct OCTestHostApp: App {
    var body: some Scene {
        WindowGroup {
            HostView()
        }
    }
}

struct HostView: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OCTestHost")
                .font(.headline)
            TextField("type here", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("oc.testhost.field")
            Text("typed: \(text)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("oc.testhost.mirror")
            Spacer()
        }
        .padding()
        .task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            focused = true
        }
    }
}
