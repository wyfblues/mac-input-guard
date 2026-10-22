import Foundation
import Darwin

enum AppIdentity {
    static let bundleID = "org.macinputguard.app"
    static let keychainService = "org.macinputguard.password-verifier"
    static let urlScheme = "macinputguard"
    static let compatibilityRevision = 1
}

enum AppPaths {
    static func directory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/MacInputGuard", isDirectory: true)
    }
    static let dataDirectory = directory(home: FileManager.default.homeDirectoryForCurrentUser)
    static let statusFile = dataDirectory.appendingPathComponent("status.json")
    static let approvalFile = dataDirectory.appendingPathComponent("compatibility.json")

    static func prepare(directory: URL = dataDirectory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}

enum AppInstanceLock {
    private static var descriptor: Int32 = -1
    static func acquire() -> Bool {
        let path = AppPaths.dataDirectory.appendingPathComponent("instance.lock").path
        descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return false }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            Darwin.close(descriptor); descriptor = -1
            return false
        }
        return true
    }
}
