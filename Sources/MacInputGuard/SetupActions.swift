import AppKit
import Foundation

extension PrivacyDelegate {
    @objc func openAccessibilitySettings() {
        guard !protecting else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func refreshControls() {
        guard !protecting else { return }
        loadCredential(); showSetup(error: credentialLoadError)
    }
    @objc func toggleLogin(_ sender: NSButton) {
        guard !protecting else { sender.state = LoginSettings.isEnabled ? .on : .off; return }
        do { try LoginSettings.setEnabled(sender.state == .on) }
        catch {
            let alert = NSAlert()
            alert.messageText = "无法更新登录启动设置"
            alert.informativeText = "请在系统设置的登录项中检查 MacInputGuard；保护状态没有改变。"
            alert.runModal()
        }
        sender.state = LoginSettings.isEnabled ? .on : .off
    }
    @objc func showCompatibilityReview() {
        guard !protecting, passwordWindow == nil, !authorizingCredential else { return }
        reviewWindow?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 570),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "本机兼容性检查"
        window.isReleasedWhenClosed = false
        reviewChecks = CompatibilityApproval.items.map { item in
            let check = NSButton(checkboxWithTitle: item.title, target: nil, action: nil)
            check.font = .systemFont(ofSize: 13)
            return check
        }
        let hint = label(lastCompletedPreview == nil ?
            "先完成一次完整的 12 秒测试，再按实际结果逐项确认。" :
            "仅勾选你实际确认的项目；AI 操作应与未保护时对照。", size: 13)
        let test = button("测试 12 秒", action: #selector(demonstrate))
        let save = button("保存本机检查结果", action: #selector(saveCompatibilityReview))
        save.isEnabled = lastCompletedPreview != nil && AXIsProcessTrusted()
        stack([hint, test] + reviewChecks + [save], in: window.contentView!, width: 510)
        reviewWindow = window
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func saveCompatibilityReview() {
        guard !protecting, AXIsProcessTrusted(), let completed = lastCompletedPreview,
              reviewChecks.count == CompatibilityApproval.items.count,
              reviewChecks.allSatisfy({ $0.state == .on }) else {
            NSSound.beep(); return
        }
        let approval = CompatibilityApproval(revision: AppIdentity.compatibilityRevision,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: CompatibilityApproval.currentArchitecture, reviewedAt: Date(),
            completedPreviewAt: completed, confirmedItems: Set(CompatibilityApproval.items.map(\.key)))
        guard approval.isCurrent else { NSSound.beep(); return }
        do {
            try approval.save()
            reviewWindow?.close(); reviewWindow = nil
            showSetup()
        } catch { showSetup(error: "无法保存本机检查结果，未开启保护") }
    }
}
