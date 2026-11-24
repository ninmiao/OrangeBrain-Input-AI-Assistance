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

/// With our keyboard enabled and selected, the test host shows it as soon as the
/// text field is focused. This is the end-to-end proof for milestone M0.
///
/// XCUITest cannot see inside a third-party keyboard extension (the keyboard is a
/// remote view; `app.keyboards` stays empty), so the keys are tapped by
/// coordinates. The keyboard view has a fixed layout for this (see
/// KeyboardViewController.buildInterface) and the effect is checked through the
/// host's text field, which XCUITest can read.
final class KeyboardUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: hostBundleID)

    /// Key centres as fractions of the screen (iPhone 17: 402 x 874 pt).
    private let keyNi = CGVector(dx: 0.101, dy: 0.773)
    private let keyHao = CGVector(dx: 0.283, dy: 0.773)
    private let keyDelete = CGVector(dx: 0.643, dy: 0.835)

    override func setUp() {
        continueAfterFailure = false
    }

    private func tap(_ point: CGVector, _ name: String) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: point).tap()
        note("tap \(name) at \(point.dx),\(point.dy)")
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func fieldText(_ field: XCUIElement) -> String {
        let value = (field.value as? String) ?? ""
        return value == "type here" ? "" : value
    }

    func testOurKeyboardAppearsInTheHostAndInsertsText() throws {
        app.launch()
        let field = app.textFields["oc.testhost.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "host text field missing")
        field.tap()
        // The extension needs a moment to start, run its Rime checks and repaint the banner.
        Thread.sleep(forTimeInterval: 10)
        saveShot("keyboard-m0")
        dumpHierarchy(app, name: "host-hierarchy")
        note("accessibility sees keyboards=\(app.keyboards.count)")

        tap(keyNi, "你")
        tap(keyHao, "好")
        let typed = fieldText(field)
        note("typed=\(typed)")
        saveShot("keyboard-typed")
        XCTAssertEqual(typed, "你好", "OrangeCell's keyboard did not insert 你好 (is it the one on screen?)")

        tap(keyDelete, "delete")
        XCTAssertEqual(fieldText(field), "你")
        saveShot("keyboard-after-delete")
    }
}
