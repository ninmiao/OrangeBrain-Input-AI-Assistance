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
final class KeyboardUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: hostBundleID)

    override func setUp() {
        continueAfterFailure = false
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testOurKeyboardAppearsInTheHostAndInsertsText() throws {
        app.launch()
        let field = app.textFields["oc.testhost.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "host text field missing")
        if !app.keyboards.firstMatch.waitForExistence(timeout: 8) {
            field.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 20), "no keyboard shown")

        let title = element("oc.m0.title")
        var ours = title.waitForExistence(timeout: 8)
        if !ours {
            // Another keyboard came up first: cycle with the system's globe key.
            saveShot("keyboard-first-seen")
            dumpHierarchy(app, name: "keyboard-first-seen-tree")
            for attempt in 1...4 where !ours {
                let next = app.keyboards.buttons["Next keyboard"]
                note("cycle attempt \(attempt): next-keyboard key exists=\(next.exists)")
                guard next.exists else { break }
                next.tap()
                ours = title.waitForExistence(timeout: 4)
            }
        }
        note("keyboard.ours=\(ours)")
        if ours { note("keyboard.title=\(title.label)") }
        saveShot("keyboard-m0")
        dumpHierarchy(app, name: "keyboard-hierarchy")
        XCTAssertTrue(ours, "the system showed a keyboard, but not OrangeCell's")

        // Give the extension a moment to finish its Rime checks and repaint the banner.
        Thread.sleep(forTimeInterval: 3)
        saveShot("keyboard-m0-settled")

        let niKey = element("oc.key.ni")
        XCTAssertTrue(niKey.waitForExistence(timeout: 5), "key 你 missing")
        niKey.tap()
        element("oc.key.hao").tap()
        let typed = (field.value as? String) ?? ""
        note("typed=\(typed)")
        saveShot("keyboard-typed")
        XCTAssertEqual(typed, "你好")

        element("oc.key.delete").tap()
        XCTAssertEqual((field.value as? String) ?? "", "你")
    }
}
