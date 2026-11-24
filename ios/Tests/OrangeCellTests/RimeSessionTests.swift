// SPDX-License-Identifier: GPL-3.0-or-later
import OCCore
import OCRime
import XCTest

/// Real typing against the data CI compiles (ios/scripts/build-rime-data.sh).
/// The tests find it through OC_RIME_SHARED (TEST_RUNNER_OC_RIME_SHARED for xcodebuild).
final class RimeSessionTests: XCTestCase {
    private var sharedDirectory: String {
        get throws {
            guard let path = ProcessInfo.processInfo.environment["OC_RIME_SHARED"], !path.isEmpty else {
                throw XCTSkip("OC_RIME_SHARED is not set")
            }
            return path
        }
    }

    private func makeService(userData: URL, modules: [String]? = RimeEngine.minimalModules) throws -> RimeService {
        let shared = try sharedDirectory
        return RimeService(configuration: RimeServiceConfiguration(
            sharedDataDirectory: shared,
            userDataDirectory: userData.path,
            modules: modules
        ))
    }

    private func temporaryUserDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oc-rime-user-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testDataBundleMatchesTheLinkedLibrime() throws {
        let stampURL = URL(fileURLWithPath: try sharedDirectory).appendingPathComponent("oc-data.json")
        let data = try Data(contentsOf: stampURL)
        let stamp = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        ocInfo("data.builtWithLibrime=\(stamp["builtWithLibrime"] ?? "nil") linked=\(RimeEngine.version() ?? "nil")")
        XCTAssertEqual(stamp["schema"] as? String, "orangecell_wanxiang")
        XCTAssertEqual(stamp["grammarModel"] as? Bool, false)
        XCTAssertEqual(stamp["builtWithLibrime"] as? String, RimeEngine.version(),
                       "the data was compiled by a different librime than the one linked into the app")
    }

    func testNihaoGivesNiHaoAndCommitsIt() throws {
        let service = try makeService(userData: temporaryUserDirectory())
        XCTAssertNil(service.startSync(), "start failed")
        let update = service.typeSync("nihao")
        ocInfo("nihao.candidates=\(update.candidates.prefix(8).map(\.text).joined(separator: "|"))")
        ocInfo("nihao.preedit=\(update.preedit)")
        XCTAssertTrue(update.isComposing)
        XCTAssertEqual(update.candidates.first?.text, "你好")
        XCTAssertGreaterThan(update.candidates.count, 5)

        let committed = service.selectSync(candidateAt: 0)
        XCTAssertEqual(committed.commit, "你好")
        XCTAssertFalse(committed.isComposing)
        XCTAssertTrue(committed.candidates.isEmpty)
        service.stopSync()
    }

    func testSentenceCommitsWithSpace() throws {
        let service = try makeService(userData: temporaryUserDirectory())
        let update = service.typeSync("woyaochihuoguo")
        ocInfo("woyaochihuoguo.candidates=\(update.candidates.prefix(5).map(\.text).joined(separator: "|"))")
        XCTAssertEqual(update.candidates.first?.text, "我要吃火锅")
        let committed = service.processSync(.space)
        XCTAssertEqual(committed.commit, "我要吃火锅")
        XCTAssertFalse(committed.isComposing)
        service.stopSync()
    }

    func testBackspaceEditsTheCompositionAndEnterCommitsRawInput() throws {
        let service = try makeService(userData: temporaryUserDirectory())
        _ = service.typeSync("nihao")
        let shorter = service.processSync(.backspace)
        XCTAssertTrue(shorter.isComposing)
        XCTAssertEqual(shorter.preedit.replacingOccurrences(of: " ", with: ""), "niha")
        let committed = service.processSync(.enter)
        XCTAssertEqual(committed.commit?.replacingOccurrences(of: " ", with: ""), "niha")
        XCTAssertFalse(committed.isComposing)
        // Nothing is composing any more: backspace is not for librime to handle.
        XCTAssertFalse(service.processSync(.backspace).handled)
        service.stopSync()
    }

    func testPagingMovesTheHighlight() throws {
        let service = try makeService(userData: temporaryUserDirectory())
        let first = service.typeSync("ni")
        XCTAssertEqual(first.pageNumber, 0)
        XCTAssertFalse(first.isLastPage)
        XCTAssertGreaterThan(first.pageSize, 0)
        let next = service.changePageSync(backward: false)
        XCTAssertEqual(next.pageNumber, 1)
        XCTAssertEqual(next.highlighted, first.pageSize)
        let back = service.changePageSync(backward: true)
        XCTAssertEqual(back.pageNumber, 0)
        let cleared = service.clearSync()
        XCTAssertFalse(cleared.isComposing)
        XCTAssertEqual(cleared.preedit, "")
        service.stopSync()
    }

    func testAsciiModeIsAnOptionOfTheSession() throws {
        let service = try makeService(userData: temporaryUserDirectory())
        XCTAssertFalse(service.refreshSync().asciiMode)
        XCTAssertTrue(service.setAsciiModeSync(true).asciiMode)
        XCTAssertFalse(service.setAsciiModeSync(false).asciiMode)
        service.stopSync()
    }

    func testSelectingAnotherCandidateTeachesTheUserDictionaryAndSurvivesARestart() throws {
        let userData = temporaryUserDirectory()
        let service = try makeService(userData: userData)
        let before = service.typeSync("nihao")
        XCTAssertGreaterThan(before.candidates.count, 3)
        let learned = before.candidates[2].text
        ocInfo("learning.before=\(before.candidates.prefix(5).map(\.text).joined(separator: "|")) learn=\(learned)")
        XCTAssertNotEqual(before.candidates.first?.text, learned)
        _ = service.clearSync()

        for _ in 0..<6 {
            let typed = service.typeSync("nihao")
            guard let index = typed.candidates.firstIndex(where: { $0.text == learned }) else {
                return XCTFail("\(learned) disappeared from the candidates")
            }
            XCTAssertEqual(service.selectSync(candidateAt: index).commit, learned)
        }
        let after = service.typeSync("nihao")
        ocInfo("learning.after=\(after.candidates.prefix(5).map(\.text).joined(separator: "|"))")
        XCTAssertEqual(after.candidates.first?.text, learned, "the learned candidate did not move to the top")
        _ = service.clearSync()

        // Stop = finalise = the user dictionary is closed and flushed. A new service
        // on the same directory must see what was learned.
        service.stopSync()
        let restarted = try makeService(userData: userData)
        let again = restarted.typeSync("nihao")
        XCTAssertEqual(again.candidates.first?.text, learned, "learning was lost across a restart")
        restarted.stopSync()
    }

    func testChinesePunctuationAndCommitDoNotComposeWithoutInput() throws {
        let service = try makeService(userData: temporaryUserDirectory())
        let comma = service.processSync(RimeKey.character(",")!)
        ocInfo("comma.handled=\(comma.handled) commit=\(comma.commit ?? "nil") composing=\(comma.isComposing)")
        XCTAssertFalse(comma.isComposing && comma.commit == nil && !comma.handled)
        service.stopSync()
    }
}
