// SPDX-License-Identifier: GPL-3.0-or-later
import Darwin
import OCRime
import XCTest
@testable import OCRime

/// The lifecycle rules behind several keyboard processes (one per host app), overlapping controllers and
/// processes that get killed: the user dictionary is open only while a session is, under a cross-process
/// lock; a stale controller cannot finalise a new one's engine; what was learned is on disk right after the
/// commit.
final class RimeLifecycleTests: XCTestCase {
    private var sharedDirectory: String {
        get throws {
            guard let path = ProcessInfo.processInfo.environment["OC_RIME_SHARED"], !path.isEmpty else {
                throw XCTSkip("OC_RIME_SHARED is not set")
            }
            return path
        }
    }

    private func makeConfiguration(userData: URL) throws -> RimeServiceConfiguration {
        RimeServiceConfiguration(sharedDataDirectory: try sharedDirectory, userDataDirectory: userData.path)
    }

    private func temporaryUserDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oc-life-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Paths of the files this process has open (`F_GETPATH` of every descriptor).
    private func openPaths() -> [String] {
        var result: [String] = []
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for descriptor in 0..<2048 where fcntl(Int32(descriptor), F_GETPATH, &buffer) != -1 {
            result.append(String(cString: buffer))
        }
        return result
    }

    private func userdbFiles(open directory: URL) -> [String] {
        let marker = directory.lastPathComponent
        return openPaths().filter { $0.contains(marker) && $0.contains(".userdb") }
    }

    private func userdbDirectories(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.contains(".userdb") }
    }

    /// Types nihao and picks the candidate at `index`; returns what was committed.
    @discardableResult
    private func learn(_ service: RimeService, index: Int = 2) -> String? {
        let typed = service.typeSync("nihao")
        XCTAssertGreaterThan(typed.candidates.count, index)
        return service.selectSync(candidateAt: index).commit
    }

    private func firstCandidate(_ service: RimeService) -> String? {
        let first = service.typeSync("nihao").candidates.first?.text
        _ = service.clearSync()
        return first
    }

    // MARK: R1 (a): the user dictionary closes when the session does

    func testTheUserDictionaryIsClosedWhenTheKeyboardIsHidden() throws {
        let user = temporaryUserDirectory()
        let service = RimeService(configuration: try makeConfiguration(userData: user))
        XCTAssertNil(service.startSync())
        XCTAssertEqual(service.userDictionaryMode, .learning)
        learn(service)
        let whileOpen = userdbFiles(open: user)
        ocInfo("r1.openUserdbFiles.visible=\(whileOpen.count)")
        XCTAssertFalse(whileOpen.isEmpty, "the user dictionary should be open while the session lives")

        service.deactivateSync()
        let afterHide = userdbFiles(open: user)
        ocInfo("r1.openUserdbFiles.hidden=\(afterHide.count)")
        XCTAssertTrue(afterHide.isEmpty, "hiding the keyboard must close the user dictionary, still open: \(afterHide)")
        XCTAssertEqual(service.userDictionaryMode, .off)

        // Shown again: the learned phrase is there.
        XCTAssertNil(service.startSync())
        XCTAssertEqual(firstCandidate(service), "拟好")
        service.stopSync()
    }

    // MARK: R1 (b): contention never reaches librime's recovery

    func testWhenAnotherProcessHoldsTheLockThisOneRunsWithoutTheUserDictionary() throws {
        let user = temporaryUserDirectory()
        let configuration = try makeConfiguration(userData: user)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        // The other keyboard process: holds the lock for the whole test.
        let other = try XCTUnwrap(UserDictionaryLock.acquire(path: configuration.userDictionaryLockPath, timeout: 0.1))

        let service = RimeService(configuration: configuration)
        let started = Date()
        XCTAssertNil(service.startSync(), "the engine must start without the user dictionary")
        ocInfo("r1.contended.startSeconds=\(String(format: "%.2f", Date().timeIntervalSince(started)))")
        XCTAssertEqual(service.userDictionaryMode, .busy)
        XCTAssertEqual(firstCandidate(service), "你好", "typing works without the user dictionary")
        learn(service)
        XCTAssertTrue(userdbFiles(open: user).isEmpty, "the user dictionary must not be opened without the lock")
        service.deactivateSync()
        XCTAssertTrue(userdbDirectories(in: user).isEmpty, "nothing may have been created or renamed: \(userdbDirectories(in: user))")

        // The other process lets go: this one learns again, and the phrase it picked while it was busy is not there.
        other.release()
        XCTAssertNil(service.startSync())
        XCTAssertEqual(service.userDictionaryMode, .learning)
        XCTAssertEqual(firstCandidate(service), "你好")
        learn(service)
        service.deactivateSync()
        XCTAssertFalse(userdbDirectories(in: user).isEmpty)
        XCTAssertTrue(userdbDirectories(in: user).allSatisfy { !$0.hasSuffix(".old") })
        XCTAssertNil(service.startSync())
        XCTAssertEqual(firstCandidate(service), "拟好")
        service.stopSync()
    }

    // MARK: R2: an old controller cannot finalise the engine of a new one

    func testAnOldServiceGoingAwayDoesNotTouchTheEngineOfANewOne() throws {
        let previousDelay = RimeRuntime.idleFinalizeDelay
        RimeRuntime.idleFinalizeDelay = 0.3
        addTeardownBlock { RimeRuntime.idleFinalizeDelay = previousDelay }
        let configuration = try makeConfiguration(userData: temporaryUserDirectory())

        var old: RimeService? = RimeService(configuration: configuration)
        XCTAssertNil(old?.startSync())
        let new = RimeService(configuration: configuration)   // B exists before A is released
        XCTAssertNil(new.startSync())
        old?.deactivateSync()
        old = nil
        // Well past the idle delay and the time A's release needs on the Rime queue.
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(firstCandidate(new), "你好", "the new service must keep typing after the old one is gone")
        XCTAssertTrue(new.isRunning)

        // Once the last service lets go and the delay passed, the runtime finalises the engine by itself.
        new.deactivateSync()
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertFalse(RimeRuntime.shared.queue.sync { RimeRuntime.shared.isRunning }, "the idle engine should have been finalised")
        // ... and the next use starts it again.
        XCTAssertEqual(firstCandidate(new), "你好")
        new.stopSync()
    }

    // MARK: R3: learning survives a kill right after the commit

    func testWhatWasLearnedIsOnDiskRightAfterTheCommit() throws {
        let user = temporaryUserDirectory()
        let service = RimeService(configuration: try makeConfiguration(userData: user))
        XCTAssertNil(service.startSync())
        learn(service)
        // The process "dies" here: copy the dictionary files as they are (the session is still open, nothing
        // was closed or flushed by a shutdown) and let a fresh process-like service read the copy.
        let survivor = temporaryUserDirectory()
        try FileManager.default.createDirectory(at: survivor, withIntermediateDirectories: true)
        for name in userdbDirectories(in: user) {
            try FileManager.default.copyItem(at: user.appendingPathComponent(name), to: survivor.appendingPathComponent(name))
        }
        XCTAssertFalse(userdbDirectories(in: survivor).isEmpty)
        service.stopSync()

        let restarted = RimeService(configuration: try makeConfiguration(userData: survivor))
        XCTAssertNil(restarted.startSync())
        XCTAssertEqual(firstCandidate(restarted), "拟好", "the phrase learned just before the kill is missing from the copy")
        restarted.stopSync()
    }

    /// The first candidates of a few inputs, to choose phrases the end-to-end learning test can use.
    func testObserveCandidatesForTheEndToEndPhrases() throws {
        let service = RimeService(configuration: try makeConfiguration(userData: temporaryUserDirectory()))
        XCTAssertNil(service.startSync())
        for input in ["shijie", "zhongguo", "mingtian", "xiexie", "women"] {
            let update = service.typeSync(input)
            ocInfo("candidates.\(input)=\(update.candidates.prefix(6).map(\.text).joined(separator: "|"))")
            _ = service.clearSync()
        }
        // Does one choice move a phrase of a sentence list to the top? (the end-to-end test relies on it)
        for (input, index) in [("woyaochihuoguo", 1), ("shijie", 1), ("zhongguo", 1)] {
            for round in 1...2 {
                _ = service.typeSync(input)
                let picked = service.selectSync(candidateAt: index).commit ?? "?"
                let after = service.typeSync(input).candidates.prefix(4).map(\.text).joined(separator: "|")
                _ = service.clearSync()
                ocInfo("learned.\(input).round\(round).picked=\(picked) order=\(after)")
            }
        }
        service.stopSync()
    }
}
