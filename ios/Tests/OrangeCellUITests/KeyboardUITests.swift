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
    private var app = XCUIApplication(bundleIdentifier: hostBundleID)

    /// Mirrors KeyboardView.metrics(landscape: false).
    private enum Metrics {
        static let top: CGFloat = 4, composition: CGFloat = 18, candidates: CGFloat = 40, aiBar: CGFloat = 30, keysGap: CGFloat = 6
        static let keyHeight: CGFloat = 40, rowGap: CGFloat = 8, keyGap: CGFloat = 6, side: CGFloat = 3
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

        /// The keyboard starts where the left margin first turns into the keyboard background colour
        /// (light 0xD1D3D9 or dark 0x2B2B2D) and stays that colour for a while. Below our view the system
        /// draws its own bar (globe, dictation), so scanning down from the top is the reliable direction.
        var keyboardTop: CGFloat? {
            let backgrounds: [(Int, Int, Int)] = [(0xD1, 0xD3, 0xD9), (0x2B, 0x2B, 0x2D)]
            func near(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool { abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) <= 12 }
            var y = 0
            while y < height - 24 {
                let here = color(x: 2, y: y)
                if let target = backgrounds.first(where: { near(here, $0) }),
                   (1...20).allSatisfy({ near(color(x: 2, y: y + $0), target) }) {
                    return CGFloat(y) / scale
                }
                y += 1
            }
            return nil
        }

        /// Horizontal centres (points) of the keys on the pixel row at `y` (points).
        func keyCenters(atY y: CGFloat) -> [CGFloat] {
            let row = min(max(Int(y * scale), 0), height - 1)
            let reference = color(x: 2, y: row)
            // Runs of pixels that differ from the keyboard background. A key label can cut a run in
            // pieces where anti-aliasing passes through the background colour, so runs closer than 4 pt
            // are merged (the gap between two keys is 6 pt or more).
            var runs: [(start: Int, end: Int)] = []
            var runStart: Int?
            for x in 0..<width {
                let isKey = differs(color(x: x, y: row), reference)
                if isKey, runStart == nil { runStart = x }
                if !isKey, let start = runStart {
                    runs.append((start, x))
                    runStart = nil
                }
            }
            var merged: [(start: Int, end: Int)] = []
            for run in runs {
                if let last = merged.last, CGFloat(run.start - last.end) < 4 * scale {
                    merged[merged.count - 1].end = run.end
                } else {
                    merged.append(run)
                }
            }
            return merged.filter { CGFloat($0.end - $0.start) > 20 * scale }.map { CGFloat($0.start + $0.end) / 2 / scale }
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
        // The keyboard can still be on its way in (first start after a reboot): look for it for a while.
        var fromPixels: CGFloat?
        let deadline = Date().addingTimeInterval(25)
        repeat {
            fromPixels = screen()?.keyboardTop
            if fromPixels != nil { break }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        if fromPixels == nil {
            // iOS sometimes brings up the system pinyin keyboard after the Full Access switch changed:
            // the globe key cycles to the next keyboard until ours shows.
            for _ in 0..<3 where fromPixels == nil {
                point(x: 41, y: app.windows.firstMatch.frame.height - 37).tap()
                Thread.sleep(forTimeInterval: 2.5)
                fromPixels = screen()?.keyboardTop
            }
        }
        note("keyboardTop pixels=\(fromPixels.map { String(describing: $0) } ?? "n/a") tree=\(fromTree) width=\(screenWidth)")
        if fromPixels == nil { saveShot("system-keyboard-not-found") }
        let value = fromPixels ?? fromTree
        keyboardTopCache = value
        return value
    }

    private var keysTop: CGFloat { keyboardTop + Metrics.top + Metrics.composition + Metrics.candidates + Metrics.aiBar + Metrics.keysGap }

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
        // Row 0 is the number row.
        if let i = topRow.firstIndex(of: c) { return keyPoint(row: 1, index: topRow.distance(from: topRow.startIndex, to: i), weights: ten) }
        if let i = middleRow.firstIndex(of: c) {
            return keyPoint(row: 2, index: 1 + middleRow.distance(from: middleRow.startIndex, to: i), weights: [5] + [CGFloat](repeating: 10, count: 9) + [5])
        }
        let i = bottomLetters.distance(from: bottomLetters.startIndex, to: bottomLetters.firstIndex(of: c)!)
        return keyPoint(row: 3, index: 1 + i, weights: [15] + [CGFloat](repeating: 10, count: 7) + [15])
    }

    private var deleteKey: XCUICoordinate { keyPoint(row: 3, index: 8, weights: [15] + [CGFloat](repeating: 10, count: 7) + [15]) }

    /// Bottom row: 123, [globe], 中/EN, space, return. Whether the globe is there is read from the screen.
    private var bottomRow: [CGFloat] {
        if bottomRowCache.count >= 4 { return bottomRowCache }
        let centers = screen()?.keyCenters(atY: rowCenterY(4)) ?? []
        note("bottom row key centres: \(centers.map { Int($0) })")
        XCTAssertTrue((4...5).contains(centers.count), "expected 4 or 5 keys on the bottom row, found \(centers.count)")
        bottomRowCache = centers
        return centers
    }

    private var languageKey: XCUICoordinate { point(x: bottomRow[bottomRow.count - 3], y: rowCenterY(4)) }
    private var spaceKey: XCUICoordinate { point(x: bottomRow[bottomRow.count - 2], y: rowCenterY(4)) }

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

    private func openHostAndFocus(secure: Bool = false) -> XCUIElement {
        app.launchArguments = ["-OCNoAutoFocus"] + (secure ? ["-OCSecureField"] : [])
        app.launch()
        let field = secure ? app.secureTextFields["oc.testhost.field"] : app.textFields["oc.testhost.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "host text field missing")
        field.tap()
        // The extension needs a moment to start; its first dictionary lookup follows.
        Thread.sleep(forTimeInterval: 8)
        keyboardTopCache = nil
        bottomRowCache = []
        return field
    }

    /// The first letter after a keyboard start: type it and take it back. If it ever lands in the
    /// document as plain text the delete removes it; the keyboard counts such letters
    /// (`unhandledLetters` in its report) and the end-to-end script checks that the count is 0.
    private func warmUp(_ field: XCUIElement) {
        _ = keyboardTop
        _ = bottomRow
        let before = fieldText(field)
        type("n")
        Thread.sleep(forTimeInterval: 1)
        deleteKey.tap(); Thread.sleep(forTimeInterval: 0.5)
        deleteKey.tap(); Thread.sleep(forTimeInterval: 0.5)
        note("warm-up: field before=\(before) after=\(fieldText(field))")
    }

    // MARK: typing

    func testRealExtensionTypesChineseAndEnglish() throws {
        let field = openHostAndFocus()
        saveShot("system-1-keyboard")
        dumpHierarchy(app, name: "system-host-hierarchy")
        warmUp(field)

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

    // MARK: user dictionary: one live place, whatever the Full Access switch says

    /// Which candidate to tap to teach the keyboard 拟好 for nihao. The phrase starts third and is first
    /// after one choice; RimeSessionTests asserts that (`learning.tapIndices` starts 2, 0).
    private let learnIndex = 2

    /// Phase A (no Full Access): teach the keyboard.
    func testLearnAPhrase() throws {
        let field = openHostAndFocus()
        warmUp(field)
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-learn-1-before")
        candidate(learnIndex).tap()
        waitForField(field, "candidate \(learnIndex) should have inserted 拟好") { $0 == "拟好" }
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-learn-2-learned")
        candidate(0).tap()
        waitForField(field, "after learning, 拟好 should be the first candidate") { $0 == "拟好拟好" }
        requestHelper("footprint-learned")
    }

    /// The learned phrase is first right now (a keyboard start after the Full Access switch changed).
    func testLearnedPhraseIsFirst() throws {
        let field = openHostAndFocus()
        warmUp(field)
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-learned-candidates")
        candidate(0).tap()
        waitForField(field, "the learned 拟好 should be first after the Full Access switch changed") { $0 == "拟好" }
    }

    /// Phase B (Full Access on): the learned phrase is still first, the app deploys while the keyboard runs,
    /// typing goes on, the keyboard process is killed, the new process still has the phrase first.
    func testLearnedPhraseSurvivesDeployAndKeyboardRestart() throws {
        var field = openHostAndFocus()
        warmUp(field)
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-learned-candidates")
        candidate(0).tap()
        waitForField(field, "the learned 拟好 should be first with Full Access on") { $0 == "拟好" }
        requestHelper("footprint-fullaccess")

        // the app deploys while the keyboard is up; typing goes on
        requestHelper("deploy")
        // The app came to the front for the deployment and was closed again: bring the host back.
        // The keyboard appears again and sees the new deploy stamp.
        app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the host did not come back after the deployment")
        field.tap()
        Thread.sleep(forTimeInterval: 4)
        saveShot("system-learn-3-after-deploy")
        type("woyaochihuoguo")
        Thread.sleep(forTimeInterval: 1)
        spaceKey.tap()
        waitForField(field, "typing must still work after the app deployed") { $0 == "拟好我要吃火锅" }

        // the keyboard process dies (as when the system reclaims memory); a new one starts
        requestHelper("kill-keyboard")
        app.terminate()
        field = openHostAndFocus()
        warmUp(field)
        saveShot("system-restart-1-keyboard")
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-restart-2-candidates")
        candidate(0).tap()
        waitForField(field, "the learned 拟好 should still be first after the restart") { $0 == "拟好" }
        requestHelper("footprint-restarted")
    }

    // MARK: two host apps, kills

    /// Where the candidate `index` sits when the first candidates are phrases of `characters[i]` characters
    /// (a phrase cell is 20 pt per character plus 22 pt of padding).
    private func candidate(_ index: Int, phraseLengths characters: [Int]) -> XCUICoordinate {
        var x: CGFloat = 4
        for position in 0..<index { x += CGFloat(characters[position] * 20 + 22) }
        x += CGFloat(characters[index] * 20 + 22) / 2
        return point(x: x, y: keyboardTop + Metrics.top + Metrics.composition + Metrics.candidates / 2)
    }

    private let host2 = XCUIApplication(bundleIdentifier: "io.github.ninmiao.orangecell.testhost2")

    /// Brings an already running host to the front and focuses its field (its keyboard process, if it still
    /// exists, is resumed rather than started anew).
    private func switchTo(_ host: XCUIApplication) -> XCUIElement {
        app = host
        host.activate()
        let field = host.textFields["oc.testhost.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "host text field missing")
        field.tap()
        Thread.sleep(forTimeInterval: 4)
        keyboardTopCache = nil
        bottomRowCache = []
        return field
    }

    /// The keyboard extension runs one process per host app. Two hosts take turns typing and learning; the
    /// user dictionary they share must stay intact and hold both phrases (the end-to-end script checks the
    /// folder for leftovers of a repair).
    func testLearningAcrossTwoHostApps() throws {
        let host1 = app
        // host 1 learns 拟好 (third candidate of nihao)
        app = host1
        var field1 = openHostAndFocus()
        warmUp(field1)
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        candidate(2).tap()
        waitForField(field1, "host 1: the third candidate should have inserted 拟好") { $0 == "拟好" }

        // host 2 (a second keyboard process) learns 种过 (second candidate of zhongguo)
        app = host2
        var field2 = openHostAndFocus()
        warmUp(field2)
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        candidate(0).tap()
        waitForField(field2, "host 2 should already see the phrase host 1 learned") { $0 == "拟好" }
        type("zhongguo")
        Thread.sleep(forTimeInterval: 1)
        candidate(1).tap()
        waitForField(field2, "host 2: the second candidate should have inserted 种过") { $0 == "拟好种过" }
        saveShot("system-hosts-2-learned")
        requestHelper("footprint-host2")

        // back to host 1 (its keyboard process was in the background): both phrases are first
        field1 = switchTo(host1)
        type("zhongguo")
        Thread.sleep(forTimeInterval: 1)
        candidate(0).tap()
        waitForField(field1, "host 1 should see the phrase host 2 learned") { $0 == "拟好种过" }
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        candidate(0).tap()
        waitForField(field1, "host 1 keeps its own phrase") { $0 == "拟好种过拟好" }
        saveShot("system-hosts-1-back")

        // and once more to host 2
        field2 = switchTo(host2)
        type("zhongguo")
        Thread.sleep(forTimeInterval: 1)
        candidate(0).tap()
        waitForField(field2, "host 2 still has both phrases first") { $0 == "拟好种过种过" }
        requestHelper("footprint-hosts-done")
    }

    /// What was committed last survives a kill -9 right after it, with no hide and no deployment in between.
    /// Needs a phrase learned in an earlier process (testLearnAPhrase or the two-host test) to check both.
    func testLearningSurvivesAKillRightAfterTheCommit() throws {
        app = XCUIApplication(bundleIdentifier: hostBundleID)
        // A process that learns 种过 and dies a moment later.
        var field = openHostAndFocus()
        warmUp(field)
        type("zhongguo")
        Thread.sleep(forTimeInterval: 1)
        candidate(1).tap()
        waitForField(field, "the second candidate should have inserted 种过") { $0 == "种过" }
        requestHelper("kill-keyboard")          // kill -9 at once: no hide, no deploy
        app.terminate()

        // The next process has the word learned just before the kill, and the one learned long before.
        field = openHostAndFocus()
        warmUp(field)
        type("zhongguo")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-kill-1-last-word")
        candidate(0).tap()
        waitForField(field, "the word committed right before the kill is missing") { $0 == "种过" }
        type("nihao")
        Thread.sleep(forTimeInterval: 1)
        saveShot("system-kill-2-earlier-word")
        candidate(0).tap()
        waitForField(field, "the word learned earlier is missing") { $0 == "种过拟好" }
    }

    // MARK: the AI row (the mock service, the made-up key and the routes are set up by e2e-sim.sh in mode ai)

    private var aiBarCenterY: CGFloat { keyboardTop + Metrics.top + Metrics.composition + Metrics.candidates + Metrics.aiBar / 2 }

    /// The AI candidates start at x = 24 pt (after the status dot); the first one is far wider than 60 pt.
    private func aiItem(_ index: Int, widths: [CGFloat] = []) -> XCUICoordinate {
        var x: CGFloat = 24
        for position in 0..<index { x += widths[position] }
        return point(x: x + 30, y: aiBarCenterY)
    }

    /// The two trigger keys at the right end of the row (38 pt wide, the sparkles one is the last).
    private var aiAssistantKey: XCUICoordinate { point(x: screenWidth - 21, y: aiBarCenterY) }
    private var aiEmojiKey: XCUICoordinate { point(x: screenWidth - 59, y: aiBarCenterY) }

    func testAiRowCorrectsAssistsAndPrefersTheEmojiKey() throws {
        let field = openHostAndFocus()
        warmUp(field)
        saveShot("ai-0-idle")

        // 1. A typo typed as pinyin: the correction streams in on its own and is adopted with a tap.
        type("woyaochihuogou")
        Thread.sleep(forTimeInterval: 3.5)
        saveShot("ai-1-correction-streamed")
        aiItem(0).tap()
        waitForField(field, "tapping the 纠错 candidate should put the corrected sentence into the field") { $0 == "我要吃火锅" }
        saveShot("ai-2-adopted")

        // 2. The assistant key starts a slow request; while it is still streaming the emoji key takes over.
        Thread.sleep(forTimeInterval: 1.5)
        aiAssistantKey.tap()
        Thread.sleep(forTimeInterval: 1.0)
        saveShot("ai-3-assistant-streaming")
        aiEmojiKey.tap()
        Thread.sleep(forTimeInterval: 2.0)
        saveShot("ai-4-emoji-wins")
        // The slow second assistant candidate would have arrived by now; it must not replace the emoticons.
        Thread.sleep(forTimeInterval: 3.0)
        saveShot("ai-5-late-assistant-data-dropped")
        XCTAssertEqual(fieldText(field), "我要吃火锅", "nothing is inserted until a candidate is tapped")
        aiItem(0).tap()
        waitForField(field, "the first emoticon goes after the text, no assistant text") {
            $0.hasPrefix("我要吃火锅") && $0.count > 5 && !$0.contains("好啊") && !$0.contains("。")
        }
        saveShot("ai-6-emoticon-adopted")
        requestHelper("footprint-ai")
    }

    /// A password field: the keyboard switches to English, the row says nothing is sent, the keys do nothing.
    func testAiNeverSendsFromASecureField() throws {
        let field = openHostAndFocus(secure: true)
        _ = keyboardTop
        saveShot("ai-secure-0")
        type("secretpass")
        Thread.sleep(forTimeInterval: 2)
        saveShot("ai-secure-1-typed")
        aiAssistantKey.tap()
        Thread.sleep(forTimeInterval: 1)
        aiEmojiKey.tap()
        Thread.sleep(forTimeInterval: 2)
        saveShot("ai-secure-2-keys-pressed")
        let mirror = app.staticTexts["oc.testhost.mirror"].label
        XCTAssertTrue(mirror.contains("secretpass"), "the letters themselves still go in (\(mirror)); \(field.exists)")
        requestHelper("footprint-ai-secure")
    }

    /// Without Full Access the AI row says so in one line and the keys do nothing.
    func testAiNeedsFullAccess() throws {
        let field = openHostAndFocus()
        warmUp(field)
        type("nihao")
        Thread.sleep(forTimeInterval: 2)
        saveShot("ai-nofullaccess-1-hint")
        aiAssistantKey.tap()
        Thread.sleep(forTimeInterval: 1.5)
        aiEmojiKey.tap()
        Thread.sleep(forTimeInterval: 1.5)
        saveShot("ai-nofullaccess-2-keys-pressed")
        XCTAssertEqual(fieldText(field), "", "pressing the AI keys inserts nothing")
    }
}
