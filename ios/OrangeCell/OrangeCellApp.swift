// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import SwiftUI

enum Route: Hashable {
    case diagnostics
}

@main
struct OrangeCellApp: App {
    init() {
        // Leave the shared-container evidence on every launch (not only when the
        // diagnostics page is open): the probe file and the key-storage sample are
        // what the keyboard looks for to prove it shares the app's container.
        Task.detached(priority: .utility) {
            let context = AppGroupContext.detect()
            AppGroupProbe.write(role: "app", context: context, bundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            _ = KeyStorageSelfTest.writeAndVerifyLocally(context: context)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    /// `-OCOpenDiagnostics` (launch argument) lands straight on the diagnostics
    /// page; the CI screenshots use it.
    @State private var path: [Route] =
        ProcessInfo.processInfo.arguments.contains("-OCOpenDiagnostics") ? [.diagnostics] : []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .diagnostics:
                        DiagnosticsView()
                    }
                }
        }
    }
}
