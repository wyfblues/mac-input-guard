import Foundation
import Security

private struct TestLoginVerifier: LoginPasswordVerifying {
    let accepts: Bool
    func verify(_ password: String) -> Bool { accepts }
}

@main struct CoreTests {
    static func main() throws {
        // Published PBKDF2-HMAC-SHA256 vector; independent of our random-record path.
        let vector = try PasswordRecord.derive("password", salt: Data("salt".utf8), rounds: 1)
        precondition(vector.map { String(format: "%02x", $0) }.joined() ==
            "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        let password = "Test-only密碼-ForVerification"
        let first = try PasswordRecord.create(password)
        let second = try PasswordRecord.create(password)
        precondition(first.salt != second.salt)
        let correct = try first.matches(password)
        let incorrect = try first.matches(password + "x")
        precondition(correct && !incorrect)
        let restored = try JSONDecoder().decode(PasswordRecord.self, from: JSONEncoder().encode(first))
        let restoredCorrect = try restored.matches(password)
        precondition(restoredCorrect)
        let invalid = PasswordRecord(version: 1, rounds: 0, salt: first.salt, verifier: first.verifier)
        do { _ = try invalid.matches(password); fatalError("Invalid KDF settings were accepted") }
        catch PrivacyError.invalidRecord { }
        var gate = AttemptGate()
        for _ in 0..<5 { gate.failed(now: 100) }
        precondition(gate.wait(now: 100) == 30)
        precondition(gate.wait(now: 131) == 0)
        for _ in 0..<5 { gate.failed(now: 131) }
        precondition(gate.wait(now: 131) == 60)
        gate.reset(); precondition(gate.failures == 0 && gate.wait(now: 100) == 0)
        // Isolated test item only. Never reads or changes the real password item.
        let service = "org.macinputguard.test." + UUID().uuidString
        let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("mac-input-guard-core-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: testDirectory) }
        let store = PasswordStore(service: service, lockDirectory: testDirectory)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: NSUserName()]
        defer { SecItemDelete(query as CFDictionary) }
        let missing = try store.load(); precondition(missing == nil)
        try store.saveNew(first)
        let stored = try store.load()
        let storedCorrect = try stored?.matches(password)
        precondition(storedCorrect == true)
        let silentRead = try store.load(allowInteraction: false)
        let silentReadCorrect = try silentRead?.matches(password)
        precondition(silentReadCorrect == true)
        do { try store.saveNew(second); fatalError("Password was overwritten") }
        catch PrivacyError.keychain(let status) { precondition(status == errSecDuplicateItem) }

        // Failed authentication must preserve the existing credential.
        do { _ = try store.changePassword(currentPassword: "incorrect", newPassword: "abc"); fatalError("Wrong old password was accepted") }
        catch PrivacyError.wrongPassword { }
        let unchangedAfterWrong = try store.load()!.matches(password)
        precondition(unchangedAfterWrong)
        do { _ = try store.changePassword(currentPassword: password, newPassword: "ab"); fatalError("Short password was accepted") }
        catch PrivacyError.passwordTooShort { }
        let unchangedAfterShort = try store.load()!.matches(password)
        precondition(unchangedAfterShort)
        _ = try store.changePassword(currentPassword: password, newPassword: "abc")
        let changed = try store.load()!
        let acceptsChanged = try changed.matches("abc")
        let rejectsPrevious = try !changed.matches(password)
        precondition(acceptsChanged && rejectsPrevious && changed.salt != first.salt)

        do {
            _ = try store.resetPassword(macLoginPassword: "test-only-proof", newPassword: "xyz",
                                        verifier: TestLoginVerifier(accepts: false))
            fatalError("Failed Mac authentication reset a password")
        } catch PrivacyError.systemVerificationFailed { }
        let unchangedAfterRecoveryFailure = try store.load()!.matches("abc")
        precondition(unchangedAfterRecoveryFailure)
        _ = try store.resetPassword(macLoginPassword: "test-only-proof", newPassword: "xyz",
                                    verifier: TestLoginVerifier(accepts: true))
        let reset = try store.load()!
        let acceptsReset = try reset.matches("xyz")
        let rejectsChanged = try !reset.matches("abc")
        precondition(acceptsReset && rejectsChanged && reset.salt != changed.salt)
        // Reads local account metadata only; never attempts a real login password.
        precondition(MacLoginPasswordVerifier().accountAvailable())
        print("PASS: crypto, Keychain, cooldown, authenticated change, failed-change preservation, recovery rejection/success, local account lookup")
    }
}
