// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The keyboard view runs inside OCTestHost as the input view of a text view
/// (`-OCEmbeddedKeyboard`), so these tests tap the real keys by accessibility
/// identifier: no coordinates, no system keyboard, no extension process. The
/// extension itself is covered by KeyboardUITests (system-level).
final class EmbeddedKeyboardUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: hostBundleID)

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(dark: Bool = false) {
        app.launchArguments = ["-OCEmbeddedKeyboard", "-OCNoAutoFocus", "-OCAppearance", dark ? "dark" : "light"]
        if let shared = ProcessInfo.processInfo.environment["OC_RIME_SHARED"] {
            app.launchEnvironment["OC_RIME_SHARED"] = shared
        }
        app.launch()
        let field = app.textViews["oc.testhost.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "host text view missing")
        field.tap()
        XCTAssertTrue(key("space").waitForExistence(timeout: 20), "the keyboard did not appear")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func key(_ id: String) -> XCUIElement { element("oc.key." + id) }

    private func type(_ letters: String) {
        for letter in letters { key(String(letter)).tap() }
    }

    private var fieldText: String {
        let value = (app.textViews["oc.testhost.field"].value as? String) ?? ""
        return value
    }

    private var composition: String { element("oc.composition").label.replacingOccurrences(of: " ", with: "") }

    /// Waits until `condition` holds (the first candidates arrive asynchronously after the engine starts).
    private func wait(_ message: String, timeout: TimeInterval = 20, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail(message)
    }

    // MARK: typing

    func testNihaoThenChooseTheFirstCandidate() {
        launch()
        type("nihao")
        wait("candidate 0 never showed") { self.element("oc.candidate.0").exists }
        wait("the composition should show nihao") { self.composition == "nihao" }
        XCTAssertEqual(element("oc.candidate.0").label, "你好")
        saveShot("embedded-nihao-light")
        element("oc.candidate.0").tap()
        wait("你好 was not inserted") { self.fieldText == "你好" }
        XCTAssertEqual(composition, "")
        XCTAssertFalse(element("oc.candidate.0").exists, "candidates must disappear after committing")
    }

    func testSentenceIsCommittedBySpace() {
        launch()
        type("woyaochihuoguo")
        wait("candidates never showed") { self.element("oc.candidate.0").exists }
        saveShot("embedded-sentence-light")
        key("space").tap()
        wait("space did not commit the first candidate") { self.fieldText == "我要吃火锅" }
    }

    func testDeleteEditsCompositionThenDocument() {
        launch()
        key("language").tap()                     // EN
        type("ab")
        XCTAssertEqual(fieldText, "ab")
        key("language").tap()                     // 中
        type("niha")
        wait("composition missing") { self.composition == "niha" }
        key("delete").tap()
        wait("backspace did not shorten the composition") { self.composition == "nih" }
        XCTAssertEqual(fieldText, "ab", "the document must not change while composing")
        key("delete").tap(); key("delete").tap(); key("delete").tap()
        wait("composition should be empty") { self.composition == "" }
        key("delete").tap()
        wait("delete should now remove from the document") { self.fieldText == "a" }
    }

    func testReturnCommitsTheRawInputWhileComposing() {
        launch()
        type("niha")
        wait("composition missing") { self.composition == "niha" }
        key("return").tap()
        wait("return did not commit") { self.fieldText.replacingOccurrences(of: " ", with: "") == "niha" }
        XCTAssertEqual(composition, "")
        key("return").tap()
        wait("return should insert a newline") { self.fieldText.hasSuffix("\n") }
    }

    func testChineseEnglishToggleAndShift() {
        launch()
        XCTAssertEqual(key("language").label, "中")
        key("language").tap()
        XCTAssertEqual(key("language").label, "EN")
        type("hello")
        XCTAssertEqual(fieldText, "hello")
        XCTAssertEqual(composition, "", "English letters must not compose")
        key("shift").tap()
        key("w").tap()
        XCTAssertEqual(fieldText, "helloW")
        key("o").tap()
        XCTAssertEqual(fieldText, "helloWo", "shift applies to one letter only")
        key("shift").doubleTap()    // double tap: caps lock
        type("ab")
        XCTAssertEqual(fieldText, "helloWoAB")
        saveShot("embedded-english-light")
        key("language").tap()
        XCTAssertEqual(key("language").label, "中")
        type("ni")
        wait("candidates should be back in 中 mode") { self.element("oc.candidate.0").exists }
    }

    func testNumbersAndSymbolsPanels() {
        launch()
        key("numbers").tap()
        XCTAssertTrue(key("sym.1").waitForExistence(timeout: 5))
        key("sym.1").tap(); key("sym.2").tap()
        wait("digits were not inserted") { self.fieldText == "12" }
        // 中 mode: the key goes through Rime's punctuator, which makes the full-width mark.
        key("sym.，").tap()
        wait("the Chinese comma was not inserted") { self.fieldText == "12，" }
        // ... but a hyphen stays a hyphen, so dates and URLs are not broken.
        key("sym.-").tap()
        key("sym.3").tap()
        wait("the hyphen was changed or lost") { self.fieldText == "12，-3" }
        // Quotes pair up.
        key("sym.\"").tap()
        key("sym.\"").tap()
        wait("the quotes did not pair") { self.fieldText == "12，-3“”" }
        saveShot("embedded-numbers-light")
        key("symbols").tap()
        XCTAssertTrue(key("sym.#").waitForExistence(timeout: 5))
        key("sym.#").tap()
        wait("# was not inserted") { self.fieldText == "12，-3“”#" }
        key("letters").tap()
        XCTAssertTrue(key("q").waitForExistence(timeout: 5))
        // English mode: ASCII punctuation as it is.
        key("language").tap()
        key("numbers").tap()
        key("sym.,").tap()
        wait("the ASCII comma was not inserted") { self.fieldText == "12，-3“”#," }
    }

    func testNumberRowTypesDigitsInBothModes() {
        launch()
        key("d1").tap(); key("d2").tap()
        XCTAssertEqual(fieldText, "12")
        key("language").tap()                     // EN
        key("d3").tap()
        XCTAssertEqual(fieldText, "123")
        saveShot("embedded-number-row-light")
    }

    /// ⌄ opens the candidate grid, a tap selects, ⌃ closes it.
    func testExpandedCandidateGrid() {
        launch()
        type("ni")
        wait("candidates never showed") { self.element("oc.candidate.1").exists }
        element("oc.expand").tap()
        wait("the grid did not open") { self.element("oc.grid.item.1").exists }
        saveShot("embedded-grid-light")
        let second = element("oc.grid.item.1").label
        element("oc.grid.item.1").tap()
        wait("the second candidate was not inserted") { self.fieldText == second }
        XCTAssertFalse(element("oc.grid").exists && element("oc.grid").isHittable, "the grid must close after a selection")
        // ⌃ closes the grid without selecting.
        type("ni")
        wait("candidates never showed again") { self.element("oc.candidate.1").exists }
        element("oc.expand").tap()
        wait("the grid did not open again") { self.element("oc.grid.item.0").exists }
        element("oc.expand").tap()
        wait("the grid did not close") { !self.element("oc.grid.item.0").exists || !self.element("oc.grid.item.0").isHittable }
    }

    func testDeleteRepeatsWhenHeld() {
        launch()
        key("language").tap()
        type("abcdefghij")
        XCTAssertEqual(fieldText.count, 10)
        key("delete").press(forDuration: 2.0)
        note("delete.afterHold remaining=\(fieldText.count) of 10")
        saveShot("embedded-delete-hold")
        wait("holding delete should remove several characters") { self.fieldText.count < 5 }
    }

    // MARK: screenshots (light and dark)

    /// The landscape layout (shorter keys, smaller candidate bar) in the same host.
    func testScreenshotLandscape() {
        launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(key("space").waitForExistence(timeout: 10))
        type("ni")
        wait("candidate bar never filled in landscape") { self.element("oc.candidate.0").exists }
        saveShot("embedded-landscape-1-zh-candidates")
        key("delete").tap(); key("delete").tap()
        key("language").tap()
        type("hello")
        saveShot("embedded-landscape-2-en")
        XCUIDevice.shared.orientation = .portrait
    }

    func testScreenshotsLight() { screenshots(dark: false) }
    func testScreenshotsDark() { screenshots(dark: true) }

    private func screenshots(dark: Bool) {
        let name = dark ? "dark" : "light"
        launch(dark: dark)
        saveShot("embedded-\(name)-1-zh-idle")
        type("ni")
        wait("candidate bar never filled") { self.element("oc.candidate.5").exists }
        saveShot("embedded-\(name)-2-zh-candidates")
        key("delete").tap(); key("delete").tap()
        key("language").tap()
        type("hello")
        saveShot("embedded-\(name)-3-en")
        key("numbers").tap()
        saveShot("embedded-\(name)-4-123")
        key("symbols").tap()
        saveShot("embedded-\(name)-5-symbols")
    }
}
