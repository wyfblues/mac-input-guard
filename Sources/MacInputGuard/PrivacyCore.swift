import Foundation
import Security
import CommonCrypto
import OpenDirectory
import Darwin

enum PrivacyError: Error, LocalizedError {
    case random(OSStatus), keychain(OSStatus), invalidRecord, derivation
    case wrongPassword, systemVerificationFailed, passwordMissing, passwordTooShort, storageBusy
    var errorDescription: String? {
        switch self {
        case .random: return "无法生成安全随机数。"
        case .keychain(let status): return "无法访问本机钥匙串（\(status)），未开启保护。"
        case .invalidRecord: return "密码校验记录损坏，不能验证密码。"
        case .derivation: return "密码校验失败，请稍后再试。"
        case .wrongPassword: return "当前保护密码不正确"
        case .systemVerificationFailed: return "Mac 登录密码不正确或暂时无法验证"
        case .passwordMissing: return "没有可修改的保护密码"
        case .passwordTooShort: return "至少 3 个字符"
        case .storageBusy: return "暂时无法更新密码，请稍后重试"
        }
    }
}

protocol LoginPasswordVerifying {
    func verify(_ password: String) -> Bool
}

struct MacLoginPasswordVerifier: LoginPasswordVerifying {
    private func currentAccount() throws -> ODRecord {
        // Only the currently signed-in local account. Never accepts an arbitrary
        // username or changes the macOS account's credentials.
        let node = try ODNode(session: ODSession.default(), name: "/Local/Default")
        return try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
    }
    func accountAvailable() -> Bool { (try? currentAccount()) != nil }
    func verify(_ password: String) -> Bool {
        guard !password.isEmpty else { return false }
        do {
            try currentAccount().verifyPassword(password)
            return true
        } catch {
            // Directory/authentication errors never grant recovery access.
            return false
        }
    }
}

struct PasswordRecord: Codable {
    let version: Int
    let rounds: UInt32
    let salt: Data
    let verifier: Data

    static func derive(_ password: String, salt: Data, rounds: UInt32) throws -> Data {
        let bytes = Array(password.utf8)
        var output = [UInt8](repeating: 0, count: 32)
        let result = bytes.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), bytes.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &output, output.count)
            }
        }
        guard result == kCCSuccess else { throw PrivacyError.derivation }
        return Data(output)
    }

    static func create(_ password: String) throws -> PasswordRecord {
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else { throw PrivacyError.random(status) }
        return PasswordRecord(version: 1, rounds: 600_000, salt: salt,
            verifier: try derive(password, salt: salt, rounds: 600_000))
    }

    func matches(_ password: String) throws -> Bool {
        guard version == 1, rounds == 600_000, salt.count == 32, verifier.count == 32
            else { throw PrivacyError.invalidRecord }
        let candidate = try Self.derive(password, salt: salt, rounds: rounds)
        var difference: UInt8 = 0
        for (a, b) in zip(candidate, verifier) { difference |= a ^ b }
        return difference == 0
    }
}

struct PasswordStore {
    private static let interactionLock = NSRecursiveLock()
    let service: String
    let lockDirectory: URL
    init(service: String = AppIdentity.keychainService, lockDirectory: URL = AppPaths.dataDirectory) {
        self.service = service; self.lockDirectory = lockDirectory
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: NSUserName(),
         kSecAttrSynchronizable as String: false]
    }
    func load(allowInteraction: Bool = true) throws -> PasswordRecord? {
        Self.interactionLock.lock()
        defer { Self.interactionLock.unlock() }
        // Existing items live in the legacy login Keychain. Its ACL UI does
        // not honor only the modern SecItem UI hint. This switch is process-
        // local, serialized, and restored after reading; it never changes ACLs.
        var previousInteraction: DarwinBoolean = true
        let interactionStatus = SecKeychainGetUserInteractionAllowed(&previousInteraction)
        guard interactionStatus == errSecSuccess else { throw PrivacyError.keychain(interactionStatus) }
        let changeStatus = SecKeychainSetUserInteractionAllowed(allowInteraction)
        guard changeStatus == errSecSuccess else { throw PrivacyError.keychain(changeStatus) }
        defer { SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }
        var search = query
        // Legacy generic-password items also need this flag: background launch
        // must return an authorization error instead of waiting for hidden UI.
        if !allowInteraction {
            search[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PrivacyError.keychain(status) }
        guard let data = item as? Data,
              let record = try? JSONDecoder().decode(PasswordRecord.self, from: data)
            else { throw PrivacyError.invalidRecord }
        guard record.version == 1, record.rounds == 600_000,
              record.salt.count == 32, record.verifier.count == 32
            else { throw PrivacyError.invalidRecord }
        return record
    }
    func saveNew(_ record: PasswordRecord) throws {
        try withUpdateLock { try insert(record) }
    }
    private func insert(_ record: PasswordRecord) throws {
        var item = query
        item[kSecValueData as String] = try JSONEncoder().encode(record)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrLabel as String] = "Mac Input Guard — Password verifier"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw PrivacyError.keychain(status) }
    }

    private func withUpdateLock<T>(_ operation: () throws -> T) throws -> T {
        try AppPaths.prepare(directory: lockDirectory)
        let path = lockDirectory.appendingPathComponent("password-update.lock").path
        let file = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard file >= 0 else { throw PrivacyError.storageBusy }
        defer { Darwin.close(file) }
        guard flock(file, LOCK_EX) == 0 else { throw PrivacyError.storageBusy }
        defer { flock(file, LOCK_UN) }
        return try operation()
    }

    private func replace(_ record: PasswordRecord) throws {
        // Atomic update: a failed write leaves the previous Keychain item intact.
        let update = [kSecValueData as String: try JSONEncoder().encode(record)]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecSuccess else { throw PrivacyError.keychain(status) }
    }

    func changePassword(currentPassword: String, newPassword: String) throws -> PasswordRecord {
        guard newPassword.count >= 3 else { throw PrivacyError.passwordTooShort }
        return try withUpdateLock {
            guard let current = try load() else { throw PrivacyError.passwordMissing }
            guard try current.matches(currentPassword) else { throw PrivacyError.wrongPassword }
            let replacement = try PasswordRecord.create(newPassword)
            try replace(replacement)
            return replacement
        }
    }

    func resetPassword(macLoginPassword: String, newPassword: String,
                       verifier: LoginPasswordVerifying = MacLoginPasswordVerifier()) throws -> PasswordRecord {
        guard newPassword.count >= 3 else { throw PrivacyError.passwordTooShort }
        guard verifier.verify(macLoginPassword) else { throw PrivacyError.systemVerificationFailed }
        return try withUpdateLock {
            guard try load() != nil else { throw PrivacyError.passwordMissing }
            let replacement = try PasswordRecord.create(newPassword)
            try replace(replacement)
            return replacement
        }
    }
}

struct AttemptGate {
    private(set) var failures = 0
    private(set) var blockedUntil: TimeInterval = 0
    func wait(now: TimeInterval) -> Int { max(0, Int(ceil(blockedUntil - now))) }
    mutating func failed(now: TimeInterval) {
        failures += 1
        if failures % 5 == 0 {
            blockedUntil = now + min(300, 30 * pow(2, Double(failures / 5 - 1)))
        }
    }
    mutating func reset() { failures = 0; blockedUntil = 0 }
}
