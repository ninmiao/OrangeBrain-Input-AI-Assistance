// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(Security)
import Security
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Where API keys live. Two backends exist because a free-account sideload may
/// not get a Keychain access group shared by the app and the keyboard
/// (docs/IOS_PLAN.md section 4.6); the diagnostics screen shows which one works.
public protocol SecretStore {
    var backendName: String { get }
    func set(_ value: Data, account: String) throws
    func get(account: String) throws -> Data?
    func remove(account: String) throws
}

public struct SecretStoreError: Error, Equatable, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public init(code: Int32, message: String) {
        self.code = code
        self.message = message
    }
    public var description: String { "\(message) (\(code))" }
}

#if canImport(CryptoKit)
/// AES-GCM files in a directory (normally `<app group>/secrets`). The key sits
/// next to the files; both are protected by iOS data protection and excluded
/// from backups, so only this app and its keyboard sandbox can read them.
///
/// Failure rules (they protect every stored key from being lost):
/// * the key file is created only when it does not exist, with an exclusive create
///   (temp file + hard link), so two processes racing on first use end up with the
///   same key;
/// * a key file that exists but cannot be read (transient failure before first unlock,
///   wrong size) is an error, never "no key": it is not overwritten;
/// * the account name is bound into the AES-GCM authenticated data, so a secret file
///   copied under another account does not decrypt.
public final class EncryptedFileSecretStore: SecretStore {
    public let backendName = "encrypted-file"
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var keyURL: URL { directory.appendingPathComponent(".store.key") }

    private func fileURL(for account: String) -> URL {
        let digest = SHA256.hash(data: Data(account.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".secret")
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    /// `nil` only when the file does not exist; anything else that goes wrong throws.
    private func readKey() throws -> SymmetricKey? {
        guard FileManager.default.fileExists(atPath: keyURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: keyURL)
        } catch {
            throw SecretStoreError(code: -4, message: "key file unreadable: " + String(describing: error))
        }
        guard data.count == 32 else {
            throw SecretStoreError(code: -3, message: "key file has the wrong size")
        }
        return SymmetricKey(data: data)
    }

    private func createKeyExclusively() throws -> SymmetricKey {
        try prepareDirectory()
        let key = SymmetricKey(size: .bits256)
        let temporary = directory.appendingPathComponent(".store.key." + UUID().uuidString)
        try write(key.withUnsafeBytes { Data($0) }, to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        if link(temporary.path, keyURL.path) == 0 { return key }
        let failure = errno
        if failure == EEXIST {
            // Another process created the key first: use theirs.
            guard let existing = try readKey() else {
                throw SecretStoreError(code: Int32(failure), message: "key vanished after a create race")
            }
            return existing
        }
        throw SecretStoreError(code: Int32(failure), message: "could not create the key file")
    }

    private func loadKey(create: Bool) throws -> SymmetricKey? {
        if let key = try readKey() { return key }
        guard create else { return nil }
        return try createKeyExclusively()
    }

    public func set(_ value: Data, account: String) throws {
        guard let key = try loadKey(create: true) else {
            throw SecretStoreError(code: -1, message: "no key")
        }
        let sealed = try AES.GCM.seal(value, using: key, authenticating: Data(account.utf8))
        guard let combined = sealed.combined else {
            throw SecretStoreError(code: -2, message: "seal failed")
        }
        try write(combined, to: fileURL(for: account))
    }

    public func get(account: String) throws -> Data? {
        let url = fileURL(for: account)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let key = try loadKey(create: false) else {
            throw SecretStoreError(code: -5, message: "secret exists but the key file is missing")
        }
        let box = try AES.GCM.SealedBox(combined: try Data(contentsOf: url))
        return try AES.GCM.open(box, using: key, authenticating: Data(account.utf8))
    }

    public func remove(account: String) throws {
        let url = fileURL(for: account)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
#endif

#if canImport(Security)
/// Generic-password items. With `accessGroup == nil` the item lands in the
/// process's default group (private to that process); with an explicit group
/// the app and the keyboard can share it when both are entitled to it.
public final class KeychainSecretStore: SecretStore {
    public let backendName: String
    private let service: String
    private let accessGroup: String?

    public init(service: String = "io.github.ninmiao.orangecell.keys", accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
        self.backendName = accessGroup == nil ? "keychain-default" : "keychain-shared"
    }

    private func query(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func set(_ value: Data, account: String) throws {
        var base = query(account: account)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            base[kSecValueData as String] = value
            base[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(base as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw SecretStoreError(code: status, message: "keychain set")
        }
    }

    public func get(account: String) throws -> Data? {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecretStoreError(code: status, message: "keychain get")
        }
        return item as? Data
    }

    public func remove(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError(code: status, message: "keychain remove")
        }
    }

    /// The access group the system picked for this process (`<TEAMID>.<bundle id>`),
    /// found by adding a throw-away item and reading its group attribute.
    public static func discoverDefaultAccessGroup() -> String? {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "oc.group-probe",
            kSecAttrAccount as String: "oc.group-probe",
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(probe as CFDictionary, &result)
        if status == errSecItemNotFound {
            var add = probe
            add[kSecValueData as String] = Data("probe".utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, &result)
        }
        guard status == errSecSuccess, let attributes = result as? [String: Any] else { return nil }
        return attributes[kSecAttrAccessGroup as String] as? String
    }
}
#endif

/// Outcome of one backend in the start-up self-test. The app writes a known
/// sample value; the keyboard reads it back, which proves cross-process sharing.
public struct KeyStorageProbe: Codable, Equatable, Sendable {
    public var backend: String
    public var accessGroup: String?
    public var wroteOK: Bool?
    public var readBackOK: Bool?
    public var crossProcessReadOK: Bool?
    public var detail: String

    public init(
        backend: String,
        accessGroup: String? = nil,
        wroteOK: Bool? = nil,
        readBackOK: Bool? = nil,
        crossProcessReadOK: Bool? = nil,
        detail: String = ""
    ) {
        self.backend = backend
        self.accessGroup = accessGroup
        self.wroteOK = wroteOK
        self.readBackOK = readBackOK
        self.crossProcessReadOK = crossProcessReadOK
        self.detail = detail
    }
}

public enum KeyStorageSelfTest {
    /// Not a secret: a fixed marker the app stores and the keyboard looks for.
    public static let sampleAccount = "selftest.shared"
    public static let sampleValue = Data("oc-keystore-selftest-v1".utf8)
    public static let sharedKeychainSuffix = "io.github.ninmiao.orangecell.shared"

    /// Backends worth testing in this process, in order of preference.
    public static func stores(context: AppGroupContext) -> [any SecretStore] {
        var stores: [any SecretStore] = []
        #if canImport(Security)
        if let team = context.profile?.teamIdentifier {
            stores.append(KeychainSecretStore(accessGroup: team + "." + sharedKeychainSuffix))
        }
        stores.append(KeychainSecretStore(accessGroup: nil))
        #endif
        #if canImport(CryptoKit)
        if let directory = context.sharedDirectory("secrets") {
            stores.append(EncryptedFileSecretStore(directory: directory))
        }
        #endif
        return stores
    }

    /// `discover` asks the system for the process's default group, which adds a throw-away
    /// Keychain item; only the app's explicit self-test does that, never the keyboard.
    private static func group(of store: any SecretStore, context: AppGroupContext, discover: Bool) -> String? {
        #if canImport(Security)
        if store.backendName == "keychain-shared", let team = context.profile?.teamIdentifier {
            return team + "." + sharedKeychainSuffix
        }
        if store.backendName == "keychain-default", discover { return KeychainSecretStore.discoverDefaultAccessGroup() }
        #endif
        return nil
    }

    /// App side: write the sample into every backend and read it back in the same process.
    public static func writeAndVerifyLocally(context: AppGroupContext) -> [KeyStorageProbe] {
        stores(context: context).map { store in
            var probe = KeyStorageProbe(backend: store.backendName, accessGroup: group(of: store, context: context, discover: true))
            do {
                try store.set(sampleValue, account: sampleAccount)
                probe.wroteOK = true
                probe.readBackOK = (try store.get(account: sampleAccount)) == sampleValue
            } catch {
                probe.wroteOK = probe.wroteOK ?? false
                probe.detail = String(describing: error)
            }
            return probe
        }
    }

    /// Keyboard side: read the sample the app wrote, without writing anything.
    public static func readAcrossProcesses(context: AppGroupContext) -> [KeyStorageProbe] {
        stores(context: context).map { store in
            var probe = KeyStorageProbe(backend: store.backendName, accessGroup: group(of: store, context: context, discover: false))
            do {
                let value = try store.get(account: sampleAccount)
                probe.crossProcessReadOK = value == sampleValue
                if value == nil { probe.detail = "sample not found" }
            } catch {
                probe.crossProcessReadOK = false
                probe.detail = String(describing: error)
            }
            return probe
        }
    }

    /// The backend the app should use, given what the keyboard managed to read.
    public static func chooseBackend(keyboardProbes: [KeyStorageProbe]) -> String {
        if keyboardProbes.contains(where: { $0.backend == "keychain-shared" && $0.crossProcessReadOK == true }) {
            return "keychain-shared"
        }
        if keyboardProbes.contains(where: { $0.backend == "encrypted-file" && $0.crossProcessReadOK == true }) {
            return "encrypted-file"
        }
        return "none"
    }
}
