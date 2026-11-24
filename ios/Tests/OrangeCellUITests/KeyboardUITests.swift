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

    /// The end-to-end script does things the test cannot do from inside the simulator: measure the
    /// keyboard process (`footprint-<label>`), let the app deploy (`deploy`), kill the keyboard
    /// process (`kill-keyboard`). The test writes `request-<name>` into the shot directory and
    /// waits for the script to answer with `done-<name>`.
    @discardableResult
    func requestHelper(_ name: String, timeout: TimeInterval = 120) -> Bool {
        guard let directory = shotDirectory else { return false }
        FileManager.default.createFile(atPath: directory.appendingPathComponent("request-" + name).path, contents: Data())
        let done = directory.appendingPathComponent("done-" + name).path
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !FileManager.default.fileExists(atPath: done) { Thread.sleep(forTimeInterval: 0.5) }
        let answered = FileManager.default.fileExists(atPath: done)
        note("helper \(name): " + (answered ? "answered" : "NO ANSWER"))
        return answered
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
/// remote view; `app.keyboards` stays empty), so the keys are tapped by coordinates.
/// They come from the keyboard's own layout rules (KeyboardView.metrics / KeyboardLayout,
/// portrait) and from the screenshot: where the keyboard starts and where the keys of the
/// bottom row are (with or without the globe key) is read from pixels, because that
/// depends on how many keyboards the system lists. The effect of every tap is checked
/// through the host text field. The in-process tests (EmbeddedKeyboardUITests) cover
/// everything else by identifier.
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

    // MARK: reading the screen

    private struct Screen {
        let width: Int
        let height: Int
        let scale: CGFloat
        private let pixels: [UInt8]

        init?(image: UIImage, pointWidth: CGFloat) {
            guard let cg = image.cgImage else { return nil }
            width = cg.width
            height = cg.height
            scale = CGFloat(cg.width) / pointWidth
            var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                    bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                return true
            }
            guard drawn else { return nil }
            pixels = data
        }

        func color(x: Int, y: Int) -> (Int, Int, Int) {
            let index = (y * width + x) * 4
            return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
        }

        func differs(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool {
            abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) > 24
        }

        /// The keyboard background runs up from the bottom edge along the left margin
        /// (the separator under the candidates is one pixel and is skipped).
        var keyboardTop: CGFloat {
            let reference = color(x: 2, y: height - 2)
            var top = height - 1
            var misses = 0
            var y = height - 1
            while y >= 0 {
                if differs(color(x: 2, y: y), reference) {
                    misses += 1
                    if misses > 8 { break }
                } else {
                    top = y
                    misses = 0
                }
                y -= 1
            }
            return CGFloat(top) / scale
        }

        /// Horizontal centres (points) of the keys on the pixel row at `y` (points).
        func keyCenters(atY y: CGFloat) -> [CGFloat] {
            let row = min(max(Int(y * scale), 0), height - 1)
            let reference = color(x: 2, y: row)
            var centers: [CGFloat] = []
            var runStart: Int?
            for x in 0..<width {
                let isKey = differs(color(x: x, y: row), reference)
                if isKey, runStart == nil { runStart = x }
                if !isKey, let start = runStart {
                    if CGFloat(x - start) > 20 * scale { centers.append(CGFloat(start + x) / 2 / scale) }
                    runStart = nil
                }
            }
            return centers
        }
    }

    private func screen() -> Screen? {
        Screen(image: XCUIScreen.main.screenshot().image, pointWidth: screenWidth)
    }

    private var keyboardTopCache: CGFloat?
    private var bottomRowCache: [CGFloat] = []

    /// Top of the keyboard area, from the screenshot (the element tree is the fallback).
    private var keyboardTop: CGFloat {
        if let cached = keyboardTopCache { return cached }
        let container = app.otherElements["inputView"]
        let fromTree = container.exists ? container.frame.minY : app.windows.firstMatch.frame.height - 282
        let fromPixels = screen()?.keyboardTop
        note("keyboardTop pixels=\(fromPixels.map { String(describing: $0) } ?? "n/a") tree=\(fromTree) width=\(screenWidth)")
        let value = fromPixels ?? fromTree
        keyboardTopCache = value
        return value
    }

    private var keysTop: CGFloat { keyboardTop + Metrics.top + Metrics.composition + Metrics.candidates + Metrics.keysGap }

    private func rowCenterY(_ row: Int) -> CGFloat {
        keysTop + CGFloat(row) * (Metrics.keyHeight + Metrics.rowGap) + Metrics.keyHeight / 2
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
        return point(x: x, y: rowCenterY(row))
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

    /// Bottom row: 123, [globe], 中/EN, space, return. Whether the globe is there is read from the screen.
    private var bottomRow: [CGFloat] {
        if bottomRowCache.count >= 4 { return bottomRowCache }
        let centers = screen()?.keyCenters(atY: rowCenterY(3)) ?? []
        note("bottom row key centres: \(centers.map { Int($0) })")
        XCTAssertTrue((4...5).contains(centers.count), "expected 4 or 5 keys on the bottom row, found \(centers.count)")
        bottomRowCache = centers
        return centers
    }

    private var languageKey: XCUICoordinate { point(x: bottomRow[bottomRow.count - 3], y: rowCenterY(3)) }
    private var spaceKey: XCUICoordinate { point(x: bottomRow[bottomRow.count - 2], y: rowCenterY(3)) }

    /// Candidate cells are as wide as their text: a two-character phrase is 62 pt (20 pt font, 22 pt
    /// padding) and phrases carry no comment, so the first cells of a phrase list are all this wide.
    private func candidate(_ index: Int) -> XCUICoordinate {
        point(x: 4 + 62 * CGFloat(index) + 31, y: keyboardTop + Metrics.top + Metrics.composition + Metrics.candidates / 2)
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

    private func openHostAndFocus() -> XCUIElement {
        app.launch()
        let field = app.textFields["oc.testhost.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "host text field missing")
        field.tap()
        // The extension needs a moment to start; its first dictionary lookup follows.
        Thread.sleep(forTimeInterval: 8)
        keyboardTopCache = nil
        bottomRowCache = []
        return field
    }

    // MARK: typing

    func testRealExtensionTypesChineseAndEnglish() throws {
        let field = openHostAndFocus()
        saveShot("system-1-keyboard")
        dumpHierarchy(app, name: "system-host-hierarchy")
        _ = keyboardTop
        _ = bottomRow

        // nihao, choose the first candidate by tapping it
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-2-nihao")
        candidate(0).tap()
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
        requestHelper("footprint-typing")
    }

    // MARK: user dictionary across the app deployment and a keyboard restart

    /// Which candidate to tap in each round to teach the keyboard 拟好 for nihao. The phrase starts third
    /// and is first after one choice; RimeSessionTests asserts that (`learning.tapIndices` starts 2, 0).
    private let learnSchedule: [Int] = (ProcessInfo.processInfo.environment["OC_LEARN_SCHEDULE"] ?? "2")
        .split(separator: ",").compactMap { Int($0) }

    func testUserDictionaryAcrossDeployAndKeyboardRestart() throws {
        var field = openHostAndFocus()
        _ = keyboardTop
        _ = bottomRow

        // 1. teach the keyboard
        var expected = ""
        for (round, index) in learnSchedule.enumerated() {
            type("nihao")
            Thread.sleep(forTimeInterval: 1)
            if round == 0 { saveShot("system-learn-1-before") }
            candidate(index).tap()
            expected += "拟好"
            waitForField(field, "round \(round + 1): candidate \(index) should have inserted 拟好") { $0 == expected }
        }
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-learn-2-learned")
        candidate(0).tap()
        expected += "拟好"
        waitForField(field, "after learning, 拟好 should be the first candidate") { $0 == expected }
        requestHelper("footprint-learned")

        // 2. the app deploys while the keyboard is up; typing goes on
        requestHelper("deploy")
        type("woyaochihuoguo")
        Thread.sleep(forTimeInterval: 1)
        spaceKey.tap()
        expected += "我要吃火锅"
        waitForField(field, "typing must still work after the app deployed") { $0 == expected }

        // 3. the keyboard process dies (as when the system reclaims memory); a new one starts
        requestHelper("kill-keyboard")
        app.terminate()
        field = openHostAndFocus()
        saveShot("system-restart-1-keyboard")
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-restart-2-candidates")
        candidate(0).tap()
        waitForField(field, "the learned 拟好 should still be first after the restart") { $0 == "拟好" }
        requestHelper("footprint-restarted")
    }
}
