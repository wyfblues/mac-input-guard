import Foundation

struct PreviewCompletion {
    static func accepts(startedAt: Double?, wasReady: Bool, event: String, now: Double) -> Bool {
        guard let start = startedAt, wasReady,
              ["released", "lease-expired", "stopped"].contains(event) else { return false }
        return (11.8...15.5).contains(now - start)
    }
}

// This is a local owner's compatibility attestation, not a security boundary
// or an assertion that a model has independently verified every checked item.
struct CompatibilityApproval: Codable {
    static let items: [(key: String, title: String)] = [
        ("physicalInput", "实体键盘和鼠标在测试中被拦住"),
        ("physicalScroll", "实体触控板两指滚动被拦住"),
        ("physicalGestures", "三／四指切换桌面被拦住（如设备支持）"),
        ("unlockDialog", "解锁测试小窗可以输入，结束按钮可以点击"),
        ("automationInput", "常用 AI 工具仍能输入和点击"),
        ("automationScroll", "常用 AI 工具仍能滚动页面"),
        ("automationDesktop", "常用 AI 工具仍能切换应用、打开文件和验证页面"),
        ("automaticRelease", "完整 12 秒结束后，实体键鼠自动恢复")
    ]
    let revision: Int
    let systemVersion: String
    let architecture: String
    let reviewedAt: Date
    let completedPreviewAt: Date
    let confirmedItems: Set<String>

    static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    var isCurrent: Bool {
        revision == AppIdentity.compatibilityRevision &&
        systemVersion == ProcessInfo.processInfo.operatingSystemVersionString &&
        architecture == Self.currentArchitecture &&
        reviewedAt >= completedPreviewAt &&
        reviewedAt.timeIntervalSince(completedPreviewAt) < 86_400 &&
        confirmedItems == Set(Self.items.map(\.key))
    }
    static func load(from file: URL = AppPaths.approvalFile) -> Self? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save(to file: URL = AppPaths.approvalFile) throws {
        try AppPaths.prepare(directory: file.deletingLastPathComponent())
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
