// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import OCCore

/// Builds data shaped like a real `embedded.mobileprovision`: a CMS envelope
/// (binary bytes) around a clear XML property list.
func sampleProfile(
    groups: [String]?,
    team: String = "ABCDE12345",
    expires: String = "2026-12-01T10:00:00Z"
) -> Data {
    var entitlements = "<key>application-identifier</key><string>\(team).io.github.ninmiao.orangecell</string>"
    entitlements += "<key>get-task-allow</key><true/>"
    if let groups {
        entitlements += "<key>com.apple.security.application-groups</key><array>"
        entitlements += groups.map { "<string>\($0)</string>" }.joined()
        entitlements += "</array>"
    }
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>Name</key><string>iOS Team Provisioning Profile: io.github.ninmiao.orangecell</string>
    <key>UUID</key><string>00000000-1111-2222-3333-444444444444</string>
    <key>TeamIdentifier</key><array><string>\(team)</string></array>
    <key>CreationDate</key><date>2026-11-24T10:00:00Z</date>
    <key>ExpirationDate</key><date>\(expires)</date>
    <key>Entitlements</key><dict>\(entitlements)</dict>
    </dict></plist>
    """
    var data = Data([0x30, 0x82, 0x0A, 0x01, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0, 0x80, 0x00, 0xFF])
    data.append(Data(xml.utf8))
    data.append(Data([0x00, 0xFF, 0x30, 0x82, 0x01, 0x22, 0x3C, 0x3F]))
    return data
}

func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

final class ProvisioningProfileTests: XCTestCase {
    func testExtractsPlistFromCmsEnvelope() throws {
        let profile = try ProvisioningProfile.parse(sampleProfile(groups: ["group.io.github.ninmiao.orangecell"]))
        XCTAssertEqual(profile.teamIdentifier, "ABCDE12345")
        XCTAssertEqual(profile.applicationIdentifier, "ABCDE12345.io.github.ninmiao.orangecell")
        XCTAssertEqual(profile.applicationGroups, ["group.io.github.ninmiao.orangecell"])
        XCTAssertEqual(profile.getTaskAllow, true)
        XCTAssertEqual(profile.uuid, "00000000-1111-2222-3333-444444444444")
        XCTAssertEqual(profile.creationDate, date("2026-11-24T10:00:00Z"))
        XCTAssertEqual(profile.expirationDate, date("2026-12-01T10:00:00Z"))
    }

    func testRejectsDataWithoutPropertyList() {
        XCTAssertThrowsError(try ProvisioningProfile.parse(Data([0x30, 0x82, 0x01, 0x02]))) { error in
            XCTAssertEqual(error as? ProvisioningProfile.ParseError, .noPropertyList)
        }
        XCTAssertThrowsError(try ProvisioningProfile.parse(Data())) { error in
            XCTAssertEqual(error as? ProvisioningProfile.ParseError, .noPropertyList)
        }
    }

    func testRejectsBrokenPropertyList() {
        let broken = Data("xx<?xml version=\"1.0\"?><plist><dict><key>a</key></plist>yy".utf8)
        XCTAssertThrowsError(try ProvisioningProfile.parse(broken)) { error in
            XCTAssertEqual(error as? ProvisioningProfile.ParseError, .malformed)
        }
    }

    func testPlainXmlPlistWithoutEnvelopeIsAccepted() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Name</key><string>bare</string></dict></plist>
        """
        let profile = try ProvisioningProfile.parse(Data(xml.utf8))
        XCTAssertEqual(profile.name, "bare")
        XCTAssertTrue(profile.applicationGroups.isEmpty)
        XCTAssertNil(profile.expirationDate)
    }

    // MARK: expiry

    func testExpiryParsing() throws {
        let profile = try ProvisioningProfile.parse(sampleProfile(groups: nil, expires: "2026-12-01T10:00:00Z"))
        XCTAssertEqual(profile.daysRemaining(now: date("2026-11-28T10:00:00Z")), 3)
        XCTAssertEqual(profile.daysRemaining(now: date("2026-11-28T11:00:00Z")), 2)
        XCTAssertEqual(profile.secondsRemaining(now: date("2026-12-01T09:00:00Z")), 3_600)
        XCTAssertFalse(profile.isExpiring(within: 2, now: date("2026-11-28T10:00:00Z")))
        XCTAssertTrue(profile.isExpiring(within: 2, now: date("2026-11-30T10:00:00Z")))
    }

    func testExpiredProfile() throws {
        let profile = try ProvisioningProfile.parse(sampleProfile(groups: nil, expires: "2026-12-01T10:00:00Z"))
        let later = date("2026-12-03T10:00:00Z")
        XCTAssertEqual(profile.daysRemaining(now: later), 0)
        XCTAssertEqual(try XCTUnwrap(profile.secondsRemaining(now: later)), -172_800, accuracy: 0.5)
        XCTAssertTrue(profile.isExpiring(now: later))
    }

    func testUnknownExpiryIsNotReportedAsExpiring() {
        let profile = ProvisioningProfile()
        XCTAssertNil(profile.daysRemaining())
        XCTAssertFalse(profile.isExpiring())
    }
}

final class AppGroupLocatorTests: XCTestCase {
    private let nominal = "group.io.github.ninmiao.orangecell"

    func testPlainGroupIsUsedAsIs() throws {
        let profile = try ProvisioningProfile.parse(sampleProfile(groups: [nominal]))
        let result = AppGroupLocator.resolve(profile: profile)
        XCTAssertEqual(result, AppGroupLocator.Resolution(identifier: nominal, source: .profileExact))
    }

    func testGroupWithTeamIdSuffix() throws {
        let profile = try ProvisioningProfile.parse(sampleProfile(groups: [nominal + ".ABCDE12345"]))
        let result = AppGroupLocator.resolve(profile: profile)
        XCTAssertEqual(result, AppGroupLocator.Resolution(identifier: nominal + ".ABCDE12345", source: .profileSuffixed))
    }

    func testMissingGroupMeansNoSharing() throws {
        let none = try ProvisioningProfile.parse(sampleProfile(groups: nil))
        XCTAssertEqual(AppGroupLocator.resolve(profile: none), AppGroupLocator.Resolution(identifier: nil, source: .missing))
        let other = try ProvisioningProfile.parse(sampleProfile(groups: ["group.com.example.other", "group.io.github.ninmiao.orangecellx"]))
        XCTAssertEqual(AppGroupLocator.resolve(profile: other), AppGroupLocator.Resolution(identifier: nil, source: .missing))
        let empty = try ProvisioningProfile.parse(sampleProfile(groups: []))
        XCTAssertNil(AppGroupLocator.resolve(profile: empty).identifier)
    }

    func testUnparsableProfileIsReportedAsSuch() {
        XCTAssertEqual(
            AppGroupLocator.resolve(load: .parseFailed("broken")),
            AppGroupLocator.Resolution(identifier: nominal, source: .profileParseFailed)
        )
        XCTAssertEqual(
            AppGroupLocator.resolve(load: .missing),
            AppGroupLocator.Resolution(identifier: nominal, source: .nominalNoProfile)
        )
    }

    #if canImport(Darwin)
    func testBundleWithGarbageProfileIsParseFailedNotMissing() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("oc-bundle-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let bundle = try XCTUnwrap(Bundle(url: base))
        XCTAssertEqual(ProvisioningProfile.loadResult(from: bundle), .missing)
        try Data([0x30, 0x82, 0x01, 0x02]).write(to: base.appendingPathComponent("embedded.mobileprovision"))
        guard case .parseFailed = ProvisioningProfile.loadResult(from: bundle) else {
            return XCTFail("a profile that cannot be parsed must not look like a missing one")
        }
        try sampleProfile(groups: [nominal]).write(to: base.appendingPathComponent("embedded.mobileprovision"))
        guard case .loaded(let profile) = ProvisioningProfile.loadResult(from: bundle) else {
            return XCTFail("a good profile must load")
        }
        XCTAssertEqual(profile.applicationGroups, [nominal])
    }
    #endif

    func testNoProfileFallsBackToNominalName() {
        XCTAssertEqual(
            AppGroupLocator.resolve(profile: nil),
            AppGroupLocator.Resolution(identifier: nominal, source: .nominalNoProfile)
        )
    }

    func testExactNameBeatsSuffixedNames() throws {
        let profile = try ProvisioningProfile.parse(sampleProfile(groups: [nominal + ".ZZZZZ99999", nominal]))
        XCTAssertEqual(AppGroupLocator.resolve(profile: profile).identifier, nominal)
    }

    func testTeamSuffixIsPreferredAmongSeveral() throws {
        let profile = try ProvisioningProfile.parse(
            sampleProfile(groups: [nominal + ".AAAAA00000", nominal + ".ABCDE12345"], team: "ABCDE12345")
        )
        XCTAssertEqual(AppGroupLocator.resolve(profile: profile).identifier, nominal + ".ABCDE12345")
    }

    func testBareDotSuffixIsNotAMatch() throws {
        let profile = try ProvisioningProfile.parse(sampleProfile(groups: [nominal + "."]))
        XCTAssertNil(AppGroupLocator.resolve(profile: profile).identifier)
    }

    func testUnrelatedGroupsAreIgnored() throws {
        let profile = try ProvisioningProfile.parse(sampleProfile(groups: ["group.com.example.other", nominal + ".ABCDE12345"]))
        XCTAssertEqual(AppGroupLocator.resolve(profile: profile).identifier, nominal + ".ABCDE12345")
    }
}
