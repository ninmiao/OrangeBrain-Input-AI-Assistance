// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import OCCore

final class TextTraitsTests: XCTestCase {
    // MARK: privacy (the Android rules plus the iOS ones)

    func testPlainTextEmailAndUrlFieldsMayUseAi() {
        XCTAssertFalse(TextTraits().isPrivate)
        XCTAssertFalse(TextTraits(layout: .email).isPrivate)
        XCTAssertFalse(TextTraits(layout: .url).isPrivate)
        XCTAssertFalse(TextTraits(layout: .numbersAndPunctuation).isPrivate)
    }

    func testSecretAndNumericFieldsNeverGoToAi() {
        XCTAssertTrue(TextTraits(isSecure: true).isPrivate, "secure text entry")
        XCTAssertTrue(TextTraits(hasSensitiveContentType: true).isPrivate, "password, one-time code, card number")
        XCTAssertTrue(TextTraits(layout: .numberPad).isPrivate, "Android: anything that is not a text class")
        XCTAssertTrue(TextTraits(layout: .phonePad).isPrivate)
        XCTAssertTrue(TextTraits(layout: .decimalPad).isPrivate)
        XCTAssertTrue(TextTraits(layout: .email, isSecure: true).isPrivate, "a secure email field is still secure")
    }

    // MARK: language and panels

    func testFieldsThatTakeOnlyLatinTextForceEnglishAndPadsTakeOverTheKeys() {
        XCTAssertFalse(TextTraits().forcesEnglish)
        XCTAssertFalse(TextTraits(layout: .numbersAndPunctuation).forcesEnglish)
        for layout in [TextTraits.Layout.email, .url, .numberPad, .phonePad, .decimalPad] {
            XCTAssertTrue(TextTraits(layout: layout).forcesEnglish, "\(layout)")
        }
        XCTAssertTrue(TextTraits(isSecure: true).forcesEnglish)
        XCTAssertTrue(TextTraits(layout: .numberPad).isNumericPad)
        XCTAssertTrue(TextTraits(layout: .phonePad).isNumericPad)
        XCTAssertTrue(TextTraits(layout: .decimalPad).isNumericPad)
        XCTAssertFalse(TextTraits(layout: .email).isNumericPad)
    }

    func testTheReturnKeyWaitsForTextOnlyWhenTheHostAsksForIt() {
        XCTAssertTrue(TextTraits(enablesReturnKeyAutomatically: false, hasText: false).returnEnabled)
        XCTAssertFalse(TextTraits(enablesReturnKeyAutomatically: true, hasText: false).returnEnabled)
        XCTAssertTrue(TextTraits(enablesReturnKeyAutomatically: true, hasText: true).returnEnabled)
    }

    // MARK: auto-capitalisation

    func testSentencesCapitaliseAtTheStartAfterATerminatorAndAfterANewline() {
        let s = TextTraits.Capitalization.sentences
        XCTAssertTrue(AutoCapitalization.wantsShift(s, before: nil))
        XCTAssertTrue(AutoCapitalization.wantsShift(s, before: ""))
        XCTAssertTrue(AutoCapitalization.wantsShift(s, before: "Hello. "))
        XCTAssertTrue(AutoCapitalization.wantsShift(s, before: "Really? "))
        XCTAssertTrue(AutoCapitalization.wantsShift(s, before: "你好。 "))
        XCTAssertTrue(AutoCapitalization.wantsShift(s, before: "first line\n"))
        XCTAssertTrue(AutoCapitalization.wantsShift(s, before: "a.\n"))
        XCTAssertFalse(AutoCapitalization.wantsShift(s, before: "Hello. W"))
        XCTAssertFalse(AutoCapitalization.wantsShift(s, before: "Hello "), "a plain space ends no sentence")
        XCTAssertFalse(AutoCapitalization.wantsShift(s, before: "Hello."), "no space after the stop yet")
        XCTAssertFalse(AutoCapitalization.wantsShift(s, before: "3.14"))
    }

    func testWordsCapitaliseAfterWhiteSpaceAndAllCharactersAlways() {
        XCTAssertTrue(AutoCapitalization.wantsShift(.words, before: ""))
        XCTAssertTrue(AutoCapitalization.wantsShift(.words, before: "hello "))
        XCTAssertFalse(AutoCapitalization.wantsShift(.words, before: "hello"))
        XCTAssertTrue(AutoCapitalization.wantsShift(.allCharacters, before: "anything"))
        XCTAssertFalse(AutoCapitalization.wantsShift(.none, before: ""))
        XCTAssertFalse(AutoCapitalization.wantsShift(.none, before: "Hello. "))
    }

    // MARK: own changes and the person's changes

    func testTheKeyboardsOwnChangeIsNotAHostChangeEvenWhenTheProxyReportsItLate() {
        var tracker = HostChangeTracker()
        tracker.reset(before: "", after: "")
        // The keyboard inserts; a stale notification comes first (same context), then the real one.
        tracker.ownChange(now: 0)
        XCTAssertFalse(tracker.observe(before: "", after: "", now: 0.05), "nothing changed yet")
        XCTAssertFalse(tracker.observe(before: "你好", after: "", now: 0.1), "this is our insert")
        XCTAssertFalse(tracker.observe(before: "你好", after: "", now: 0.12), "the same context twice is no change")
        // Now the person moves the caret.
        XCTAssertTrue(tracker.observe(before: "你", after: "好", now: 2))
    }

    func testAChangeWithoutAnOwnChangeBeforeItIsTheHosts() {
        var tracker = HostChangeTracker()
        XCTAssertFalse(tracker.observe(before: "abc", after: "", now: 0), "the first look only records")
        XCTAssertTrue(tracker.observe(before: "ab", after: "c", now: 1))
        XCTAssertTrue(tracker.observe(before: "", after: "abc", now: 2))
    }

    func testAnOwnChangeThatNeverGetsItsNotificationStopsMaskingAfterAWhile() {
        var tracker = HostChangeTracker()
        tracker.reset(before: "abc", after: "")
        tracker.ownChange(now: 0)     // an insert the host swallowed: no notification ever comes
        XCTAssertTrue(tracker.observe(before: "ab", after: "c", now: HostChangeTracker.patience + 1), "the person's move is not hidden for ever")
    }

    func testTwoQuickInsertsAreBothOurs() {
        var tracker = HostChangeTracker()
        tracker.reset(before: "", after: "")
        tracker.ownChange(now: 0)
        tracker.ownChange(now: 0.05)
        XCTAssertFalse(tracker.observe(before: "a", after: "", now: 0.1))
        XCTAssertFalse(tracker.observe(before: "ab", after: "", now: 0.15))
        XCTAssertTrue(tracker.observe(before: "a", after: "b", now: 0.2), "a third change has no insert behind it")
    }
}
