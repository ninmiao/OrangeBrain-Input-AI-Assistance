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

        var orderAfterEachRound: [String] = []
        var tapIndices: [Int] = []
        var roundsToTop: Int?
        for round in 1...6 {
            let typed = service.typeSync("nihao")
            guard let index = typed.candidates.firstIndex(where: { $0.text == learned }) else {
                return XCTFail("\(learned) disappeared from the candidates")
            }
            tapIndices.append(index)
            XCTAssertEqual(service.selectSync(candidateAt: index).commit, learned)
            let order = service.typeSync("nihao")
            orderAfterEachRound.append(order.candidates.prefix(3).map(\.text).joined(separator: ","))
            if roundsToTop == nil, order.candidates.first?.text == learned { roundsToTop = round }
            _ = service.clearSync()
        }
        // The end-to-end run learns the same way through the real keyboard and needs this number.
        ocInfo("learning.orderAfterEachRound=\(orderAfterEachRound.joined(separator: " | "))")
        ocInfo("learning.tapIndices=\(tapIndices.map(String.init).joined(separator: ","))")
        // The system-level end-to-end test (KeyboardUITests) taps the third candidate once and expects
        // the phrase to be first afterwards.
        XCTAssertEqual(Array(tapIndices.prefix(2)), [2, 0], "the end-to-end learning schedule no longer matches the dictionary")
        ocInfo("learning.roundsToTop=\(roundsToTop.map(String.init) ?? "never")")
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

    /// Proof that the linked Lua plugin really loads and runs: a schema that asks for a Lua translator
    /// (the shipped Wanxiang schema uses no plugin, so a tiny one is built in a temporary user directory)
    /// gets its candidate from the script.
    func testLuaPluginRunsATranslatorFromASchema() throws {
        let shared = try sharedDirectory
        let user = temporaryUserDirectory()
        try FileManager.default.createDirectory(at: user.appendingPathComponent("lua"), withIntermediateDirectories: true)
        let schema = [
            "schema:", "  schema_id: oc_lua_probe", "  name: OC Lua probe", "  version: \"1\"",
            "engine:", "  processors:", "    - ascii_composer", "    - key_binder", "    - speller", "    - selector",
            "    - navigator", "    - express_editor", "  segmentors:", "    - abc_segmentor", "  translators:",
            "    - lua_translator@*oc_probe", "speller:", "  alphabet: \"abcdefghijklmnopqrstuvwxyz\"", "",
        ].joined(separator: "\n")
        let script = [
            "local function translator(input, seg)", "  if input == \"luaprobe\" then",
            "    yield(Candidate(\"lua\", seg.start, seg._end, \"LUA-OK\", \"\"))", "  end", "end", "return translator", "",
        ].joined(separator: "\n")
        try schema.write(to: user.appendingPathComponent("oc_lua_probe.schema.yaml"), atomically: true, encoding: .utf8)
        try script.write(to: user.appendingPathComponent("lua/oc_probe.lua"), atomically: true, encoding: .utf8)
        let deployed = RimeDeployer.deployConfigFile(
            sharedData: URL(fileURLWithPath: shared), userData: user, file: "oc_lua_probe.schema.yaml", versionKey: "schema_version")
        ocInfo("lua.deployed=\(deployed)")
        let service = RimeService(configuration: RimeServiceConfiguration(
            sharedDataDirectory: shared, userDataDirectory: user.path, modules: ["default", "lua"], schemaID: "oc_lua_probe"))
        let update = service.typeSync("luaprobe")
        ocInfo("lua.candidates=\(update.candidates.map(\.text).joined(separator: "|")) composing=\(update.isComposing)")
        service.stopSync()
        XCTAssertTrue(deployed, "the probe schema could not be compiled")
        XCTAssertEqual(update.candidates.first?.text, "LUA-OK", "the Lua translator did not run: the plugin is not loaded")
    }

    func testChinesePunctuationAndCommitDoNotComposeWithoutInput() throws {
        let service = try makeService(userData: temporaryUserDirectory())
        let comma = service.processSync(RimeKey.character(",")!)
        ocInfo("comma.handled=\(comma.handled) commit=\(comma.commit ?? "nil") composing=\(comma.isComposing)")
        XCTAssertFalse(comma.isComposing && comma.commit == nil && !comma.handled)
        service.stopSync()
    }
}
