// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import OCCore

/// The live user dictionary is private to the keyboard; a dictionary an M1 build left in the
/// App Group moves there once.
final class UserDictionaryTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oc-userdb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeUserdb(at directory: URL, name: String, content: String) throws {
        let db = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: db, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: db.appendingPathComponent("CURRENT"))
        try Data("log".utf8).write(to: db.appendingPathComponent("000003.log"))
    }

    func testLegacyDictionaryMovesWhenThePrivateFolderHasNone() throws {
        let group = try temporaryDirectory().appendingPathComponent("rime-user")
        let privateUser = try temporaryDirectory().appendingPathComponent("rime-user")
        try makeUserdb(at: group, name: "orangecell_wanxiang.userdb", content: "MANIFEST-000002")
        let result = UserDictionaryMigration.migrate(from: group, to: privateUser)
        XCTAssertEqual(result, .moved(["orangecell_wanxiang.userdb"]))
        XCTAssertEqual(try String(contentsOf: privateUser.appendingPathComponent("orangecell_wanxiang.userdb/CURRENT"), encoding: .utf8), "MANIFEST-000002")
        XCTAssertFalse(FileManager.default.fileExists(atPath: group.appendingPathComponent("orangecell_wanxiang.userdb").path), "the legacy copy must be gone")
        // Once is enough.
        XCTAssertEqual(UserDictionaryMigration.migrate(from: group, to: privateUser), .notNeeded)
    }

    func testNothingMovesWhenThePrivateFolderAlreadyHasADictionary() throws {
        let group = try temporaryDirectory().appendingPathComponent("rime-user")
        let privateUser = try temporaryDirectory().appendingPathComponent("rime-user")
        try makeUserdb(at: group, name: "orangecell_wanxiang.userdb", content: "legacy")
        try makeUserdb(at: privateUser, name: "orangecell_wanxiang.userdb", content: "private")
        XCTAssertEqual(UserDictionaryMigration.migrate(from: group, to: privateUser), .notNeeded)
        XCTAssertEqual(try String(contentsOf: privateUser.appendingPathComponent("orangecell_wanxiang.userdb/CURRENT"), encoding: .utf8), "private")
        XCTAssertTrue(FileManager.default.fileExists(atPath: group.appendingPathComponent("orangecell_wanxiang.userdb").path))
    }

    func testNothingToMoveWithoutALegacyDictionary() throws {
        let group = try temporaryDirectory().appendingPathComponent("rime-user")
        let privateUser = try temporaryDirectory().appendingPathComponent("rime-user")
        XCTAssertEqual(UserDictionaryMigration.migrate(from: group, to: privateUser), .notNeeded)
    }

    func testKeyboardDirectoriesDoNotDependOnFullAccess() throws {
        let privateUser = try temporaryDirectory().appendingPathComponent("rime-user")
        let context = AppGroupContext(profile: nil, resolution: .init(identifier: nil, source: .missing), containerURL: nil)
        let withoutAccess = RimeDataLocator.keyboardDirectories(context: context, hasFullAccess: false, privateUser: privateUser)
        let withAccess = RimeDataLocator.keyboardDirectories(context: context, hasFullAccess: true, privateUser: privateUser)
        XCTAssertEqual(withoutAccess?.user, privateUser)
        XCTAssertEqual(withAccess?.user, privateUser)
        XCTAssertNil(withoutAccess?.staging)
    }

    func testInstallationFileGetsTheSyncDirectoryOnce() throws {
        let user = try temporaryDirectory()
        let sync = try temporaryDirectory().appendingPathComponent("rime-sync")
        XCTAssertTrue(RimeInstallation.prepare(userDirectory: user, syncDirectory: sync))
        let text = try String(contentsOf: user.appendingPathComponent("installation.yaml"), encoding: .utf8)
        XCTAssertTrue(text.contains("installation_id: \"orangecell-ios\""))
        XCTAssertTrue(text.contains("sync_dir: \"\(sync.path)\""))
        XCTAssertFalse(RimeInstallation.prepare(userDirectory: user, syncDirectory: sync), "unchanged: nothing to write")
        // Without Full Access the export is switched off again.
        XCTAssertTrue(RimeInstallation.prepare(userDirectory: user, syncDirectory: nil))
        XCTAssertFalse(try String(contentsOf: user.appendingPathComponent("installation.yaml"), encoding: .utf8).contains("sync_dir"))
    }
}
