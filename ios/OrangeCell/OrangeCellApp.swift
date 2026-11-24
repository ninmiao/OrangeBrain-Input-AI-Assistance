// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import SwiftUI

enum Route: Hashable {
    case diagnostics
    case licenses
}

@main
struct OrangeCellApp: App {
    init() {
        // Nothing runs at a normal launch: no self-test, no key writes, no deployment.
        // The CI end-to-end run asks for them with launch arguments.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-OCRunSelfTest") {
            Task.detached(priority: .utility) {
                let context = AppGroupContext.detect()
                AppGroupProbe.write(role: "app", context: context, bundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                _ = KeyStorageSelfTest.writeAndVerifyLocally(context: context)
            }
        }
        if arguments.contains("-OCDeploy") {
            Task.detached(priority: .utility) {
                DeployAction.save(DeployAction.run())
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    /// `-OCOpenDiagnostics` / `-OCOpenLicenses` (launch arguments) land straight on that
    /// page; the CI screenshots use them.
    @State private var path: [Route] = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-OCOpenDiagnostics") { return [.diagnostics] }
        if arguments.contains("-OCOpenLicenses") { return [.licenses] }
        return []
    }()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .diagnostics:
                        DiagnosticsView()
                    case .licenses:
                        LicensesView()
                    }
                }
        }
    }
}
