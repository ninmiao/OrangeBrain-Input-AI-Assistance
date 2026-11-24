// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

let hostBundleID = "io.github.ninmiao.orangecell.testhost"

/// Shared helpers: screenshots and notes go both into the xcresult and, when the
/// CI passes TEST_RUNNER_OC_SHOT_DIR, into plain files the workflow can publish.
extension XCTestCase {
    var shotDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["OC_SHOT_DIR"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func saveShot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = shotDirectory {
            try? shot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    func note(_ text: String) {
        print("OCUI \(text)")
        guard let directory = shotDirectory else { return }
        let file = directory.appendingPathComponent("ui-notes.txt")
        let line = Data((text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: file)
        }
    }

    func dumpHierarchy(_ app: XCUIApplication, name: String) {
        let text = app.debugDescription
        add({
            let attachment = XCTAttachment(string: text)
            attachment.name = name
            attachment.lifetime = .keepAlways
            return attachment
        }())
        if let directory = shotDirectory {
            try? text.write(to: directory.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
        }
    }
}

/// With our keyboard enabled and selected, the test host shows the real extension as
/// soon as the text field is focused. This is the system-level end-to-end check.
///
/// XCUITest cannot see inside a third-party keyboard extension (the keyboard is a
/// remote view; `app.keyboards` stays empty), so the keys are tapped by coordinates
/// computed from the keyboard's own layout rules (KeyboardView.metrics / KeyboardLayout,
/// portrait, no globe key) and the effect is checked through the host's text field.
/// The in-process tests (EmbeddedKeyboardUITests) cover everything else by identifier.
final class KeyboardUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: hostBundleID)

    /// Mirrors KeyboardView.metrics(landscape: false).
    private enum Metrics {
        static let top: CGFloat = 4, composition: CGFloat = 18, candidates: CGFloat = 40, keysGap: CGFloat = 6
        static let keyHeight: CGFloat = 44, rowGap: CGFloat = 10, keyGap: CGFloat = 6, side: CGFloat = 3
    }

    override func setUp() {
        continueAfterFailure = false
    }

    private var screenWidth: CGFloat { app.windows.firstMatch.frame.width }

    /// Top of the keyboard area: the system's `inputView` container starts where our view starts.
    private var keyboardTop: CGFloat {
        let container = app.otherElements["inputView"]
        if container.exists { return container.frame.minY }
        return app.windows.firstMatch.frame.height - 357
    }

    private func point(x: CGFloat, y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    /// Centre of key `index` in a row whose items have these weights (spacers included).
    private func keyPoint(row: Int, index: Int, weights: [CGFloat]) -> XCUICoordinate {
        let gaps = CGFloat(weights.count - 1) * Metrics.keyGap
        let unit = (screenWidth - 2 * Metrics.side - gaps) / weights.reduce(0, +)
        var x = Metrics.side
        for position in 0..<index { x += unit * weights[position] + Metrics.keyGap }
        x += unit * weights[index] / 2
        let keysTop = keyboardTop + Metrics.top + Metrics.composition + Metrics.candidates + Metrics.keysGap
        let y = keysTop + CGFloat(row) * (Metrics.keyHeight + Metrics.rowGap) + Metrics.keyHeight / 2
        return point(x: x, y: y)
    }

    private let topRow = "qwertyuiop"
    private let middleRow = "asdfghjkl"
    private let bottomLetters = "zxcvbnm"

    private func letter(_ c: Character) -> XCUICoordinate {
        let ten = [CGFloat](repeating: 10, count: 10)
        if let i = topRow.firstIndex(of: c) { return keyPoint(row: 0, index: topRow.distance(from: topRow.startIndex, to: i), weights: ten) }
        if let i = middleRow.firstIndex(of: c) {
            return keyPoint(row: 1, index: 1 + middleRow.distance(from: middleRow.startIndex, to: i), weights: [5] + [CGFloat](repeating: 10, count: 9) + [5])
        }
        let i = bottomLetters.distance(from: bottomLetters.startIndex, to: bottomLetters.firstIndex(of: c)!)
        return keyPoint(row: 2, index: 1 + i, weights: [15] + [CGFloat](repeating: 10, count: 7) + [15])
    }

    private var deleteKey: XCUICoordinate { keyPoint(row: 2, index: 8, weights: [15] + [CGFloat](repeating: 10, count: 7) + [15]) }
    private let bottomWeights: [CGFloat] = [12, 12, 46, 22]
    private var languageKey: XCUICoordinate { keyPoint(row: 3, index: 1, weights: bottomWeights) }
    private var spaceKey: XCUICoordinate { keyPoint(row: 3, index: 2, weights: bottomWeights) }

    /// The first candidate starts at the left edge of the bar.
    private var firstCandidate: XCUICoordinate {
        point(x: 34, y: keyboardTop + Metrics.top + Metrics.composition + Metrics.candidates / 2)
    }

    private func type(_ letters: String) {
        for c in letters {
            letter(c).tap()
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private func fieldText(_ field: XCUIElement) -> String {
        let value = (field.value as? String) ?? ""
        return value == "type here" ? "" : value
    }

    private func waitForField(_ field: XCUIElement, _ message: String, timeout: TimeInterval = 15, _ condition: (String) -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition(fieldText(field)) { return }
            Thread.sleep(forTimeInterval: 0.4)
        }
        saveShot("failure")
        note("field=\(fieldText(field))")
        XCTFail(message)
    }

    func testRealExtensionTypesChineseAndEnglish() throws {
        app.launch()
        let field = app.textFields["oc.testhost.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "host text field missing")
        field.tap()
        // The extension needs a moment to start; its first dictionary lookup follows.
        Thread.sleep(forTimeInterval: 8)
        saveShot("system-1-keyboard")
        dumpHierarchy(app, name: "system-host-hierarchy")
        note("keyboardTop=\(keyboardTop) width=\(screenWidth)")

        // nihao, choose the first candidate by tapping it
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-2-nihao")
        firstCandidate.tap()
        waitForField(field, "tapping the first candidate should insert 你好") { $0 == "你好" }

        // woyaochihuoguo, then space commits the first candidate
        type("woyaochihuoguo")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-3-sentence")
        spaceKey.tap()
        waitForField(field, "space should commit 我要吃火锅") { $0 == "你好我要吃火锅" }
        saveShot("system-4-committed")

        // backspace while composing edits the composition, not the document
        type("wo")
        deleteKey.tap(); Thread.sleep(forTimeInterval: 0.4)
        deleteKey.tap(); Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(fieldText(field), "你好我要吃火锅", "the document must be untouched while composing")
        deleteKey.tap()
        waitForField(field, "with nothing composing, delete removes a character") { $0 == "你好我要吃火" }

        // 中 / EN: switch to English and type hello
        languageKey.tap(); Thread.sleep(forTimeInterval: 0.6)
        type("hello")
        waitForField(field, "English mode should insert the letters directly") { $0 == "你好我要吃火hello" }
        saveShot("system-5-english")
    }
}
