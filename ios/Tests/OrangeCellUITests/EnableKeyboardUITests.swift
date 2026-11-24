// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// Plan section 8, method 2: drive the Settings app to add OrangeCell's keyboard
/// and switch on Full Access. Used when pre-seeding the simulator preferences
/// (method 1) does not make the system offer the keyboard. Every step leaves a
/// screenshot and a hierarchy dump so a failed run explains itself.
final class EnableKeyboardUITests: XCTestCase {
    private var settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private var stepNumber = 0
    private let ourName = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS[c] %@", "橘脑", "OrangeCell")

    override func setUp() {
        continueAfterFailure = true
    }

    private func snap(_ name: String) {
        stepNumber += 1
        let label = String(format: "settings-%02d-%@", stepNumber, name)
        saveShot(label)
        dumpHierarchy(settings, name: label + "-tree")
    }

    private func row(matching predicate: NSPredicate) -> XCUIElement? {
        for query in [settings.cells, settings.buttons, settings.staticTexts] {
            let match = query.matching(predicate).firstMatch
            if match.exists { return match }
        }
        return nil
    }

    private func titlePredicate(_ title: String) -> NSPredicate {
        NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title)
    }

    /// Taps the first row that matches, scrolling down when it is not on screen yet.
    @discardableResult
    private func open(_ title: String, predicate custom: NSPredicate? = nil) -> Bool {
        let predicate = custom ?? titlePredicate(title)
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if let element = row(matching: predicate), element.isHittable {
                element.tap()
                note("settings.open \(title) ok")
                Thread.sleep(forTimeInterval: 1.2)
                return true
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        for _ in 0..<8 {
            if let element = row(matching: predicate), element.isHittable {
                element.tap()
                note("settings.open \(title) ok after scroll")
                Thread.sleep(forTimeInterval: 1.2)
                return true
            }
            settings.swipeUp()
        }
        note("settings.open \(title) FAILED")
        return false
    }

    func testAddOrangeCellKeyboardAndAllowFullAccess() throws {
        settings.terminate()
        settings.launch()
        _ = settings.wait(for: .runningForeground, timeout: 20)
        snap("launch")

        guard open("General") else { snap("no-general"); return XCTFail("General not found") }
        guard open("Keyboard") else { snap("no-keyboard"); return XCTFail("Keyboard not found") }
        snap("keyboard-page")
        guard open("Keyboards") else { snap("no-keyboards"); return XCTFail("Keyboards not found") }
        snap("keyboards-list")

        let alreadyThere = row(matching: ourName) != nil
        note("settings.alreadyListed=\(alreadyThere)")
        if !alreadyThere {
            guard open("Add New Keyboard…", predicate: titlePredicate("Add New Keyboard")) else {
                snap("no-add"); return XCTFail("Add New Keyboard not found")
            }
            snap("add-list")
            guard open("OrangeCell", predicate: ourName) else {
                snap("no-ours-in-add-list"); return XCTFail("our keyboard is not offered under third-party keyboards")
            }
            snap("after-add")
        }

        // Back in the Keyboards list: open our entry to reach the Full Access switch.
        guard open("OrangeCell", predicate: ourName) else {
            snap("no-ours-in-list"); return XCTFail("our keyboard row missing after adding")
        }
        snap("our-keyboard-page")

        let toggle = settings.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", "Full Access")).firstMatch
        if toggle.waitForExistence(timeout: 6) {
            let before = (toggle.value as? String) ?? "?"
            note("settings.fullAccess.before=\(before)")
            if before != "1" {
                // The element spans the whole row; the visible switch is at its right end.
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
                Thread.sleep(forTimeInterval: 1)
                snap("full-access-alert")
                let alert = settings.alerts.firstMatch
                if alert.waitForExistence(timeout: 5) {
                    let allow = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Allow")).firstMatch
                    if allow.exists { allow.tap() } else { alert.buttons.element(boundBy: alert.buttons.count - 1).tap() }
                    Thread.sleep(forTimeInterval: 1)
                } else {
                    note("settings.fullAccess.noAlert")
                }
            }
            snap("full-access-done")
            note("settings.fullAccess.after=\((toggle.value as? String) ?? "?")")
        } else {
            note("settings.fullAccess.switchMissing")
            snap("no-full-access-switch")
            XCTFail("Allow Full Access switch not found")
        }
    }
}
