// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import OCRime
import XCTest

/// Memory of the engine with the shipped dictionary, stage by stage. CI runs this in
/// Release and Debug, once with the minimal module list and once with everything
/// that is linked in (OC_RIME_MODULES=all), so the cost of Lua / QuickJS / the
/// octagram and predict plugins is a measured number (docs/IOS_PLAN.md section 15).
/// The absolute values include the XCTest runner; the budget is checked in the real
/// keyboard process by the end-to-end run, the deltas here say where memory goes.
final class MemoryBudgetTests: XCTestCase {
    func testFootprintStagesWithTheShippedDictionary() throws {
        guard let shared = ProcessInfo.processInfo.environment["OC_RIME_SHARED"], !shared.isEmpty else {
            throw XCTSkip("OC_RIME_SHARED is not set")
        }
        let all = ProcessInfo.processInfo.environment["OC_RIME_MODULES"] == "all"
        let label = all ? "all" : "minimal"
        func stage(_ name: String) {
            ocInfo("memory.\(label).\(name)=\(MemoryProbe.physFootprintMB().map { String($0) } ?? "n/a")")
        }
        let user = FileManager.default.temporaryDirectory
            .appendingPathComponent("oc-rime-memory-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: user) }

        stage("0-baseline")
        let service = RimeService(configuration: RimeServiceConfiguration(
            sharedDataDirectory: shared,
            userDataDirectory: user.path,
            modules: all ? nil : RimeEngine.minimalModules
        ))
        XCTAssertNil(service.startSync())
        stage("1-engine-and-session")
        _ = service.typeSync("woyaochihuoguo")
        stage("2-first-sentence-typed")
        XCTAssertEqual(service.processSync(.space).commit, "我要吃火锅")
        stage("3-committed")
        for phrase in ["jintiantianqihenhao", "womenmingtiankaihui", "zhongguorenminyinhang", "nihao", "xiexie"] {
            _ = service.typeSync(phrase)
            _ = service.selectSync(candidateAt: 0)
        }
        stage("4-five-more-phrases")
        service.stopSync()
        stage("5-stopped")
    }
}
