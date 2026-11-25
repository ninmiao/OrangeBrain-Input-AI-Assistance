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
        let baseline = MemoryProbe.physFootprintMB() ?? 0
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
        // The engine, the dictionary and six sentences take a few MB over the runner baseline, not tens.
        XCTAssertLessThan((MemoryProbe.physFootprintMB() ?? 0) - baseline, 12, "engine and dictionary cost too much memory")
        service.stopSync()
        stage("5-stopped")
    }

    /// A keyboard that has been used for a long time: a user dictionary with thousands of entries, a pinyin
    /// string of more than 30 letters, and then the candidates an expanded grid shows (100). LevelDB opens
    /// with its default options (an 8 MB block cache, a 4 MB write buffer), so this is measured, not assumed.
    func testMatureUserDictionaryAndAVeryLongInput() throws {
        guard let shared = ProcessInfo.processInfo.environment["OC_RIME_SHARED"], !shared.isEmpty else {
            throw XCTSkip("OC_RIME_SHARED is not set")
        }
        let user = FileManager.default.temporaryDirectory
            .appendingPathComponent("oc-rime-mature-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: user) }
        func megabytes() -> Double { MemoryProbe.physFootprintMB() ?? 0 }

        let baseline = megabytes()
        let service = RimeService(configuration: RimeServiceConfiguration(sharedDataDirectory: shared, userDataDirectory: user.path))
        XCTAssertNil(service.startSync())
        // About 3000 entries: every pair of 55 common syllables, first candidate committed.
        let syllables = ["ni", "hao", "wo", "men", "ta", "de", "shi", "zai", "you", "he", "bu", "le", "ren", "da", "zhong", "guo",
                         "xue", "sheng", "lao", "peng", "gong", "zuo", "xiang", "mu", "jin", "tian", "ming", "shang", "wu", "xia",
                         "chi", "fan", "kai", "hui", "dian", "nao", "shou", "ji", "ke", "yi", "dui", "mei", "zhe", "na", "wei",
                         "she", "me", "dou", "neng", "hen", "xiao", "duo", "shao", "lai", "qu"]
        var commits = 0
        for first in syllables {
            for second in syllables {
                _ = service.typeSync(first + second)
                if service.selectSync(candidateAt: 0).commit != nil { commits += 1 }
            }
        }
        service.deactivateSync()
        let userdbBytes = (FileManager.default.enumerator(at: user, includingPropertiesForKeys: [.fileSizeKey])?
            .compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0, +)) ?? 0
        ocInfo("memory.mature.commits=\(commits) userdbBytes=\(userdbBytes)")
        XCTAssertGreaterThan(commits, 2000, "the fixture did not become a mature dictionary")

        // The keyboard is shown again on that dictionary.
        XCTAssertNil(service.startSync())
        let afterStart = megabytes()
        let longInput = "jintiantianqihenhaowomenyiqichifanhaoma"
        XCTAssertGreaterThan(longInput.count, 30)
        let typed = service.typeSync(longInput)
        XCTAssertFalse(typed.candidates.isEmpty, "a long input must still give candidates")
        XCTAssertGreaterThan(typed.candidates.count, 10)
        let afterLongInput = megabytes()
        // What an expanded grid reads: the whole candidate list again, a hundred times over.
        for _ in 0..<100 { _ = service.refreshSync() }
        let afterGrid = megabytes()
        ocInfo("memory.mature.baseline=\(baseline) afterStart=\(afterStart) afterLongInput=\(afterLongInput) afterGrid=\(afterGrid) candidates=\(typed.candidates.count)")
        // The keyboard process has about 46 MB with an empty user dictionary and a budget of 55: the engine,
        // the dictionary and a mature user dictionary may not take more than this over the baseline.
        XCTAssertLessThan(afterGrid - baseline, 12, "engine, dictionary and a mature user dictionary cost too much")
        service.stopSync()
    }
}
