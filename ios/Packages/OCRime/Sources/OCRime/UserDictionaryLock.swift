// SPDX-License-Identifier: GPL-3.0-or-later
import Darwin
import Foundation

/// A cross-process advisory lock (`flock`) next to the user dictionary. iOS runs one keyboard process per
/// host app, so two processes can reach for the same LevelDB. librime reacts to a failed open by
/// scheduling a repair that may rename the database, so the dictionary is never opened without this lock:
/// whoever cannot take it within a moment runs without the user dictionary.
///
/// `flock` belongs to the open file, so it is released by `release()`, by closing and by the death of the
/// process (a killed keyboard never leaves a stale lock).
final class UserDictionaryLock {
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    /// Tries to take the lock, retrying every 20 ms until `timeout` has passed. `nil` means somebody else holds it.
    static func acquire(path: String, timeout: TimeInterval = 0.3) -> UserDictionaryLock? {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return UserDictionaryLock(descriptor: descriptor) }
            if Date() >= deadline { break }
            usleep(20_000)
        }
        close(descriptor)
        return nil
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}
