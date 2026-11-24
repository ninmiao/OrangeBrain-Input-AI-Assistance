// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import OCCore

final class KeyStorageTests: XCTestCase {
    func testChoosesBackendFromKeyboardProbes() {
        let none = KeyStorageSelfTest.chooseBackend(keyboardProbes: [])
        XCTAssertEqual(none, "none")

        let fileOnly = KeyStorageSelfTest.chooseBackend(keyboardProbes: [
            KeyStorageProbe(backend: "keychain-shared", crossProcessReadOK: false, detail: "-34018"),
            KeyStorageProbe(backend: "keychain-default", crossProcessReadOK: false),
            KeyStorageProbe(backend: "encrypted-file", crossProcessReadOK: true),
        ])
        XCTAssertEqual(fileOnly, "encrypted-file")

        let shared = KeyStorageSelfTest.chooseBackend(keyboardProbes: [
            KeyStorageProbe(backend: "keychain-shared", crossProcessReadOK: true),
            KeyStorageProbe(backend: "encrypted-file", crossProcessReadOK: true),
        ])
        XCTAssertEqual(shared, "keychain-shared")

        // The default keychain group is private to one process, so it never counts.
        let defaultOnly = KeyStorageSelfTest.chooseBackend(keyboardProbes: [
            KeyStorageProbe(backend: "keychain-default", crossProcessReadOK: true),
        ])
        XCTAssertEqual(defaultOnly, "none")
    }

    #if canImport(CryptoKit)
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oc-keys-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testEncryptedFileStoreRoundTrip() throws {
        let directory = try temporaryDirectory()
        let store = EncryptedFileSecretStore(directory: directory)
        XCTAssertNil(try store.get(account: "openai"))

        let secret = Data("sk-test-not-a-real-key".utf8)
        try store.set(secret, account: "openai")
        XCTAssertEqual(try store.get(account: "openai"), secret)

        // A second instance over the same directory (the keyboard process) sees it.
        let other = EncryptedFileSecretStore(directory: directory)
        XCTAssertEqual(try other.get(account: "openai"), secret)
        XCTAssertNil(try other.get(account: "gemini"))

        try store.set(Data("changed".utf8), account: "openai")
        XCTAssertEqual(try other.get(account: "openai"), Data("changed".utf8))

        try store.remove(account: "openai")
        XCTAssertNil(try other.get(account: "openai"))
    }

    func testFilesOnDiskDoNotContainThePlaintext() throws {
        let directory = try temporaryDirectory()
        let store = EncryptedFileSecretStore(directory: directory)
        let secret = "sk-plaintext-marker-1234567890"
        try store.set(Data(secret.utf8), account: "marker")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.isEmpty)
        for name in names {
            let bytes = try Data(contentsOf: directory.appendingPathComponent(name))
            XCTAssertNil(bytes.range(of: Data(secret.utf8)), "\(name) leaks the secret")
            XCTAssertFalse(name.contains("marker"), "file names must not reveal accounts")
        }
    }

    func testTamperedFileIsRejected() throws {
        let directory = try temporaryDirectory()
        let store = EncryptedFileSecretStore(directory: directory)
        try store.set(Data("value".utf8), account: "a")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".secret") }
        let target = directory.appendingPathComponent(try XCTUnwrap(files.first))
        var bytes = try Data(contentsOf: target)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: target)
        XCTAssertThrowsError(try store.get(account: "a"))
    }

    private final class ErrorBox {
        private let lock = NSLock()
        private var messages: [String] = []
        func add(_ error: Error) { lock.lock(); messages.append(String(describing: error)); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return messages }
    }

    /// First use from many writers at once (app and keyboard racing): exactly one key
    /// survives and every writer can read all secrets.
    func testConcurrentFirstUseCreatesOneKey() throws {
        let directory = try temporaryDirectory()
        let count = 16
        let stores = (0..<count).map { _ in EncryptedFileSecretStore(directory: directory) }
        let errors = ErrorBox()
        DispatchQueue.concurrentPerform(iterations: count) { index in
            do {
                try stores[index].set(Data("value-\(index)".utf8), account: "account-\(index)")
            } catch {
                errors.add(error)
            }
        }
        XCTAssertEqual(errors.all, [])
        let reader = EncryptedFileSecretStore(directory: directory)
        for index in 0..<count {
            XCTAssertEqual(try reader.get(account: "account-\(index)"), Data("value-\(index)".utf8))
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".store.key.") }
        XCTAssertEqual(leftovers, [], "temporary key files must be cleaned up")
    }

    func testUnreadableKeyFileIsAnErrorAndNeverReplaced() throws {
        let directory = try temporaryDirectory()
        let store = EncryptedFileSecretStore(directory: directory)
        try store.set(Data("first".utf8), account: "a")
        let keyURL = directory.appendingPathComponent(".store.key")
        let original = try Data(contentsOf: keyURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: keyURL.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path) }

        XCTAssertThrowsError(try store.set(Data("second".utf8), account: "b"))
        XCTAssertThrowsError(try store.get(account: "a"))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        XCTAssertEqual(try Data(contentsOf: keyURL), original, "the key must not have been overwritten")
        XCTAssertEqual(try store.get(account: "a"), Data("first".utf8))
    }

    func testWrongSizedKeyFileIsRejectedNotReplaced() throws {
        let directory = try temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keyURL = directory.appendingPathComponent(".store.key")
        try Data([1, 2, 3]).write(to: keyURL)
        let store = EncryptedFileSecretStore(directory: directory)
        XCTAssertThrowsError(try store.set(Data("x".utf8), account: "a"))
        XCTAssertEqual(try Data(contentsOf: keyURL), Data([1, 2, 3]))
    }

    func testSecretFileCopiedToAnotherAccountDoesNotDecrypt() throws {
        let directory = try temporaryDirectory()
        let store = EncryptedFileSecretStore(directory: directory)
        try store.set(Data("alpha-secret".utf8), account: "alpha")
        try store.set(Data("beta-secret".utf8), account: "beta")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".secret") }.sorted()
        XCTAssertEqual(files.count, 2)
        // Put the first file's bytes into the second file: only the first file's owner may still decrypt.
        let firstBytes = try Data(contentsOf: directory.appendingPathComponent(files[0]))
        try firstBytes.write(to: directory.appendingPathComponent(files[1]))
        let alpha = try? store.get(account: "alpha")
        let beta = try? store.get(account: "beta")
        let readable = [alpha, beta].compactMap { $0 ?? nil }
        XCTAssertEqual(readable.count, 1, "the account name is part of the authenticated data")
    }

    func testRemoveIsQuietForMissingFilesAndRemovesRealOnes() throws {
        let directory = try temporaryDirectory()
        let store = EncryptedFileSecretStore(directory: directory)
        XCTAssertNoThrow(try store.remove(account: "never-written"))
        try store.set(Data("x".utf8), account: "a")
        try store.remove(account: "a")
        XCTAssertNil(try store.get(account: "a"))
    }

    func testSelfTestSampleThroughEncryptedStore() throws {
        let directory = try temporaryDirectory()
        let writer = EncryptedFileSecretStore(directory: directory)
        try writer.set(KeyStorageSelfTest.sampleValue, account: KeyStorageSelfTest.sampleAccount)
        let reader = EncryptedFileSecretStore(directory: directory)
        XCTAssertEqual(try reader.get(account: KeyStorageSelfTest.sampleAccount), KeyStorageSelfTest.sampleValue)
    }
    #endif
}

final class DiagnosticsTests: XCTestCase {
    func testReportRoundTripsThroughJson() throws {
        let report = DiagnosticsReport(
            role: "keyboard",
            generatedAt: date("2026-11-24T10:00:00Z"),
            bundleIdentifier: "io.github.ninmiao.orangecell.keyboard",
            appVersion: "0.1.0 (1)",
            fullAccess: false,
            groupNominal: AppGroupLocator.nominalGroup,
            groupResolved: AppGroupLocator.nominalGroup + ".ABCDE12345",
            groupSource: AppGroupLocator.Source.profileSuffixed.rawValue,
            containerPath: "/tmp/x",
            containerWritable: true,
            probeWritten: true,
            peerProbe: nil,
            profileName: "profile",
            teamIdentifier: "ABCDE12345",
            profileGroups: [AppGroupLocator.nominalGroup + ".ABCDE12345"],
            profileExpires: date("2026-12-01T10:00:00Z"),
            profileDaysRemaining: 6,
            keyStorage: [KeyStorageProbe(backend: "encrypted-file", crossProcessReadOK: true)],
            footprintMB: 12.3,
            rimeVersion: "1.17.0",
            rimeModules: ["lua", "octagram"],
            ocCoreOK: true,
            notes: ["n"]
        )
        let text = DiagnosticsCollector.json(report)
        let decoded = try DiagnosticsFiles.decoder().decode(DiagnosticsReport.self, from: Data(text.utf8))
        XCTAssertEqual(decoded, report)
    }

    func testProbeWithoutContainerIsNil() {
        let context = AppGroupContext(
            profile: nil,
            resolution: AppGroupLocator.Resolution(identifier: nil, source: .missing),
            containerURL: nil
        )
        XCTAssertNil(AppGroupProbe.write(role: "app", context: context, bundleIdentifier: "x"))
        XCTAssertNil(AppGroupProbe.read(role: "keyboard", context: context))
    }

    func testProbeWrittenByOneRoleIsReadByTheOther() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("oc-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let context = AppGroupContext(
            profile: nil,
            resolution: AppGroupLocator.Resolution(identifier: "group.test", source: .nominalNoProfile),
            containerURL: base
        )
        let written = try XCTUnwrap(AppGroupProbe.write(role: "app", context: context, bundleIdentifier: "io.test.app"))
        let read = try XCTUnwrap(AppGroupProbe.read(role: "app", context: context))
        XCTAssertEqual(read.nonce, written.nonce)
        XCTAssertEqual(read.groupIdentifier, "group.test")
        XCTAssertNil(AppGroupProbe.read(role: "keyboard", context: context))
    }

    func testMemoryProbeReportsPlausibleValueOnApplePlatforms() {
        #if canImport(Darwin)
        let megabytes = MemoryProbe.physFootprintMB()
        XCTAssertNotNil(megabytes)
        XCTAssertGreaterThan(megabytes ?? 0, 1)
        #else
        XCTAssertNil(MemoryProbe.physFootprintMB())
        #endif
    }
}
