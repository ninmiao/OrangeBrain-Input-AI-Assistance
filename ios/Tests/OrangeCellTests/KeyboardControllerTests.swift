// SPDX-License-Identifier: GPL-3.0-or-later
import OCRime
import XCTest
@testable import OCKeyboardUI

/// The keyboard logic against the real engine and the data CI compiles.
final class KeyboardControllerTests: XCTestCase {
    private func sharedDirectory() throws -> String {
        guard let path = ProcessInfo.processInfo.environment["OC_RIME_SHARED"], !path.isEmpty else {
            throw XCTSkip("OC_RIME_SHARED is not set")
        }
        return path
    }

    private func temporaryUserDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oc-kb-user-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Runs the main run loop until the condition holds (engine start and replay complete on main).
    private func spin(timeout: TimeInterval = 30, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    private struct Outcome {
        var inserted: [String]
        var unhandled: Int
        var compositionWhileWaiting: String
        var candidatesAfter: [String]
    }

    /// Types nihao right after the keyboard asked for its engine, then accepts the first candidate.
    private func typeNihao(startDelay: TimeInterval, waitForEngineFirst: Bool) throws -> Outcome {
        let output = ProxyFake()
        let service = RimeService(configuration: RimeServiceConfiguration(
            sharedDataDirectory: try sharedDirectory(), userDataDirectory: temporaryUserDirectory().path, startDelay: startDelay))
        let controller = KeyboardController(service: service, output: output)
        controller.prepare()
        if waitForEngineFirst { XCTAssertTrue(spin { controller.engineReady }, "the engine never became ready") }
        for letter in "nihao" { controller.handle(.character(String(letter))) }
        let waiting = controller.state.composition
        XCTAssertTrue(spin { controller.state.candidates.first?.text == "你好" }, "candidates never arrived: \(controller.state)")
        let candidates = controller.state.candidates.prefix(3).map(\.text)
        controller.handle(.space)
        XCTAssertTrue(spin { !output.inserted.isEmpty }, "space committed nothing")
        return Outcome(inserted: output.inserted, unhandled: controller.unhandledLetters,
                       compositionWhileWaiting: waiting, candidatesAfter: Array(candidates))
    }

    /// A slow device: the engine needs a second after the keyboard appeared. Typing immediately must give the
    /// same result as the normal path, and no letter may land in the document as plain text.
    func testKeysTypedBeforeTheEngineIsReadyGiveTheNormalResult() throws {
        let normal = try typeNihao(startDelay: 0, waitForEngineFirst: true)
        let slow = try typeNihao(startDelay: 1.0, waitForEngineFirst: false)
        XCTAssertEqual(normal.inserted, ["你好"])
        XCTAssertEqual(slow.inserted, normal.inserted, "typing before the engine was ready changed the result")
        XCTAssertEqual(slow.candidatesAfter, normal.candidatesAfter)
        XCTAssertEqual(slow.unhandled, 0, "a letter fell through to plain text")
        XCTAssertEqual(slow.compositionWhileWaiting, "nihao", "the typed letters show in the composition row while the engine starts")
        ocInfo("f1.slowStart.inserted=\(slow.inserted.joined()) unhandled=\(slow.unhandled)")
    }

    /// Backspace and clear edit the buffered letters, they do not reach the document.
    func testBackspaceEditsTheBufferedLettersWhileTheEngineStarts() throws {
        let output = ProxyFake()
        let service = RimeService(configuration: RimeServiceConfiguration(
            sharedDataDirectory: try sharedDirectory(), userDataDirectory: temporaryUserDirectory().path, startDelay: 1.0))
        let controller = KeyboardController(service: service, output: output)
        controller.prepare()
        for letter in "nix" { controller.handle(.character(String(letter))) }
        controller.handle(.delete)
        XCTAssertEqual(controller.state.composition, "ni")
        XCTAssertTrue(output.inserted.isEmpty)
        XCTAssertEqual(output.deletions, 0, "the document must not change while the engine starts")
        for letter in "hao" { controller.handle(.character(String(letter))) }
        XCTAssertTrue(spin { controller.state.candidates.first?.text == "你好" })
        XCTAssertEqual(controller.unhandledLetters, 0)
    }
}
