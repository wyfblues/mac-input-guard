import Foundation

@main struct PortabilityTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-input-guard-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let otherHome = root.appendingPathComponent("a different user")
        let directory = AppPaths.directory(home: otherHome)
        precondition(directory.path.hasPrefix(otherHome.path))
        precondition(!directory.path.contains(".codex"))
        let file = directory.appendingPathComponent("compatibility.json")
        precondition(CompatibilityApproval.load(from: file) == nil)
        let now = Date()
        let keys = Set(CompatibilityApproval.items.map(\.key))
        func report(revision: Int = AppIdentity.compatibilityRevision,
                    system: String = ProcessInfo.processInfo.operatingSystemVersionString,
                    architecture: String = CompatibilityApproval.currentArchitecture,
                    items: Set<String>? = nil, elapsed: Double = 1) -> CompatibilityApproval {
            CompatibilityApproval(revision: revision, systemVersion: system, architecture: architecture,
                reviewedAt: now, completedPreviewAt: now.addingTimeInterval(-elapsed),
                confirmedItems: items ?? keys)
        }
        precondition(report().isCurrent)
        precondition(!report(revision: -1).isCurrent)
        precondition(!report(system: "different operating system").isCurrent)
        precondition(!report(architecture: "different architecture").isCurrent)
        precondition(!report(items: []).isCurrent)
        precondition(!report(items: keys.union(["unknown"])).isCurrent)
        precondition(!report(elapsed: -1).isCurrent)
        precondition(!report(elapsed: 86_400).isCurrent)
        try report().save(to: file)
        precondition(CompatibilityApproval.load(from: file)?.isCurrent == true)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        precondition(permissions?.intValue == 0o600)
        try Data("invalid".utf8).write(to: file)
        precondition(CompatibilityApproval.load(from: file) == nil)
        precondition(!PreviewCompletion.accepts(startedAt: nil, wasReady: true, event: "released", now: 12))
        precondition(!PreviewCompletion.accepts(startedAt: 0, wasReady: false, event: "released", now: 12))
        precondition(!PreviewCompletion.accepts(startedAt: 0, wasReady: true, event: "released", now: 5))
        precondition(!PreviewCompletion.accepts(startedAt: 0, wasReady: true, event: "tap-disabled", now: 12))
        precondition(!PreviewCompletion.accepts(startedAt: 0, wasReady: true, event: "released", now: 20))
        precondition(PreviewCompletion.accepts(startedAt: 0, wasReady: true, event: "released", now: 12))
        print("PASS: portable paths, missing/malformed/stale approval rejection, file permissions, bounded-preview completion gate")
    }
}
