// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

enum Route: Hashable {
    case diagnostics
}

@main
struct OrangeCellApp: App {
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
