import AppKit
import CoreGraphics
import ApplicationServices
import Foundation

var preview = CommandLine.arguments.contains("--preview")
let protectOnLaunch = CommandLine.arguments.contains("--protect")
var backgroundOnLaunch = CommandLine.arguments.contains("--background")
let stateFile = AppPaths.statusFile

func desktopAvailable() -> Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
          session[kCGSessionOnConsoleKey as String] as? Bool == true,
          session[kCGSessionLoginDoneKey as String] as? Bool == true,
          session["CGSSessionScreenIsLocked"] as? Bool != true else { return false }
    let display = CGMainDisplayID()
    return CGDisplayIsActive(display) != 0 && CGDisplayIsAsleep(display) == 0
}

final class PrivacyDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = PasswordStore()
    var record: PasswordRecord?
    var setupWindow: NSWindow?
    var unlockWindow: NSWindow?
    let inputController = PhysicalInputController()
    var statusItem: NSStatusItem?
    var passwords: [NSSecureTextField] = []
    var hints: [NSTextField] = []
    var buttons: [NSButton] = []
    var gate = AttemptGate()
    var protecting = false
    var busy = false
    var failureCooldown: Timer?
    var observers: [NSObjectProtocol] = []
    var launched = false
    var requestedProtection = false
    var requestedPreview = false
    var passwordWindow: NSWindow?
    var editFields: [NSSecureTextField] = []
    var editButtons: [NSButton] = []
    var editHint: NSTextField?
    var editingRecovery = false
    var editBusy = false
    var editGate = AttemptGate()
    var editTimer: Timer?
    let globalShortcut = GlobalProtectionShortcut()
    var shortcutError: Int32 = 0
    var credentialLoadError: String?
    var authorizingCredential = false
    var lastMode = "starting"
    var inputMonitor: Timer?
    var reviewWindow: NSWindow?
    var reviewChecks: [NSButton] = []
    var previewStartedAt: Double?
    var previewWasReady = false
    var lastCompletedPreview: Date?
    var validationVerified: Bool { CompatibilityApproval.load()?.isCurrent == true }
    func writeStatus(_ mode: String) {
        lastMode = mode
        statusItem?.button?.title = protecting && inputController.isReady ? "◉" : "○"
        let value: [String:Any] = ["mode":mode,"pid":getpid(),"updated_at":Date().timeIntervalSince1970,
            "shortcut":GlobalProtectionShortcut.displayName,"shortcut_registered":globalShortcut.isRegistered,
            "shortcut_error":shortcutError,"background_launch":backgroundOnLaunch,
            "protection_kind":"physical-input-only","overlay":false,"screen_count":0,
            "strict_input_restrictions":false,"physical_blocking":protecting && inputController.isReady,
            "input_filter_ready":inputController.isReady,"input_worker_pid":inputController.process?.processIdentifier ?? 0,
            "input_counts":inputController.inputCounts,
            "accessibility_allowed":AXIsProcessTrusted(),"validation_verified":validationVerified]
        if let data = try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) {
            try? data.write(to:stateFile,options:.atomic)
            try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:stateFile.path)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        backgroundOnLaunch = backgroundOnLaunch || LoginSettings.wasLaunchedAtLogin
        NSApp.setActivationPolicy(backgroundOnLaunch ? .accessory : .regular)
        let menu = NSMenu()
        let item = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "测试 12 秒", action: #selector(demonstrate), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出亮屏隐私保护", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        installInputObservers()
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem?.button?.title = "○"
        let statusMenu = NSMenu()
        statusMenu.addItem(withTitle:"亮屏输入保护",action:#selector(openControls),keyEquivalent:"")
        statusMenu.addItem(withTitle:"退出",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"")
        statusItem?.menu = statusMenu
        inputController.unlockContext = { [weak self] in self?.passwordWindow ?? self?.unlockWindow }
        inputController.onEvent = { [weak self] event in self?.handleInputEvent(event) }
        if requestedPreview { preview = true }
        if preview { launched = true; beginInputProtection(); return }
        shortcutError = globalShortcut.start { [weak self] in self?.activateProtectionShortcut() }
        loadCredential()
        launched = true
        if backgroundOnLaunch {
            // Login startup only registers the shortcut. It must never show a
            // window, activate the app, or cover the desktop automatically.
            writeStatus(credentialLoadError != nil ? "credential-unavailable-background" :
                (record == nil ? "setup-required-background" : "ready-background"))
        }
        else if let error = credentialLoadError { showSetup(error: error) }
        else if (protectOnLaunch || requestedProtection) && record != nil { beginInputProtection() }
        else { showSetup() }
    }

    @objc func openControls() {
        if protecting { showUnlock() }
        else { showSetup(error:credentialLoadError) }
    }
    func installInputObservers() {
        for name in [NSWorkspace.willSleepNotification,NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                guard let self, self.protecting else { return }
                self.endInputProtection(); self.writeStatus("suspended")
            })
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == AppIdentity.urlScheme && $0.host == "preview" }) {
            if !launched { requestedPreview = true }
            else { demonstrate() }
            return
        }
        guard urls.contains(where: { $0.scheme == AppIdentity.urlScheme && $0.host == "protect" }) else { return }
        if !launched { requestedProtection = true; return }
        activateProtectionShortcut()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if authorizingCredential {
            setupWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return false
        }
        if let editor = passwordWindow { editor.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else if protecting { showUnlock() }
        else {
            if credentialLoadError != nil { loadCredential() }
            if setupWindow == nil { showSetup(error: credentialLoadError) }
            setupWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if editBusy || (protecting && !preview) { NSSound.beep(); return .terminateCancel }
        writeStatus("stopped"); return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        inputController.stop()
        globalShortcut.stop()
        writeStatus("stopped")
    }

    func label(_ text: String, size: CGFloat = 15, color: NSColor = .labelColor) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: text)
        view.font = NSFont.systemFont(ofSize: size); view.textColor = color
        view.alignment = .center; return view
    }
    func secure(_ placeholder: String) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.placeholderString = placeholder; field.font = .systemFont(ofSize: 17)
        field.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return field
    }
    func button(_ text: String, action: Selector) -> NSButton {
        let view = NSButton(title: text, target: self, action: action)
        view.bezelStyle = .rounded; view.controlSize = .large; return view
    }
    func stack(_ views: [NSView], in parent: NSView, width: CGFloat = 320) {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: parent.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: width)])
        for view in views where view is NSTextField {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    func showSetup(error: String? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        setupWindow?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: record == nil ? 250 : 430),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = credentialLoadError != nil ? "授权钥匙串" :
            (record == nil ? "设置保护密码" : "亮屏保护")
        window.isReleasedWhenClosed = false
        let content = window.contentView!
        if let error {
            passwords = []; hints = []; buttons = []
            let message = authorizingCredential ? "请在系统弹窗中完成钥匙串授权" :
                (credentialLoadError == nil ? error : "需要授权读取已保存的保护密码")
            var views: [NSView] = [label(message, size: 14)]
            if credentialLoadError != nil {
                let authorize = button("授权钥匙串", action: #selector(authorizeCredential))
                authorize.isEnabled = !authorizingCredential
                views.append(authorize)
            }
            views.append(button("退出", action: #selector(quitReady)))
            stack(views, in: content)
            writeStatus(credentialLoadError != nil ? "credential-unavailable" : "input-not-ready")
        } else if record == nil {
            let first = secure("密码（至少 3 个字符）")
            let second = secure("确认密码")
            passwords = [first, second]
            let hint = label("", size: 13)
            hint.isHidden = true
            hints = [hint]
            let save = button("保存", action: #selector(savePassword))
            buttons = [save]
            stack([first, second, hint, save], in: content)
            writeStatus("setup-required")
        } else {
            passwords = []; hints = []; buttons = []
            let protectButton = button(validationVerified ? "开启保护" : "请先完成兼容性检查", action: #selector(protect))
            protectButton.isEnabled = validationVerified && AXIsProcessTrusted()
            let change = smallButton("修改密码", action: #selector(changePassword))
            let forgot = smallButton("忘记密码", action: #selector(forgotPassword))
            let actions = NSStackView(views: [change, forgot])
            actions.orientation = .horizontal; actions.spacing = 24
            buttons = [protectButton, change, forgot]
            let shortcutHint = label(globalShortcut.isRegistered ? GlobalProtectionShortcut.displayName : "快捷键暂不可用", size: 13, color: .secondaryLabelColor)
            let test = smallButton("测试 12 秒",action:#selector(demonstrate))
            let permissionHint = label(AXIsProcessTrusted() ? "只拦实体键鼠，桌面保持可见" : "需要在系统设置中允许辅助功能",size:13,color:.secondaryLabelColor)
            let review = smallButton("兼容性检查", action: #selector(showCompatibilityReview))
            let testActions = NSStackView(views: [test, review])
            testActions.orientation = .horizontal; testActions.spacing = 24
            let permission = smallButton("辅助功能设置", action: #selector(openAccessibilitySettings))
            let refresh = smallButton("刷新状态", action: #selector(refreshControls))
            let permissionActions = NSStackView(views: [permission, refresh])
            permissionActions.orientation = .horizontal; permissionActions.spacing = 24
            let login = NSButton(checkboxWithTitle: "登录后在后台待命", target: self, action: #selector(toggleLogin(_:)))
            login.state = LoginSettings.isEnabled ? .on : .off
            stack([protectButton, shortcutHint, permissionHint, actions, testActions, permissionActions, login], in: content)
            writeStatus("ready")
        }
        setupWindow = window
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if let field = passwords.first { window.makeFirstResponder(field) }
    }
    @objc func quitReady() { if !protecting { NSApp.terminate(nil) } }

    func smallButton(_ text: String, action: Selector) -> NSButton {
        let result = button(text, action: action)
        result.isBordered = false
        result.font = .systemFont(ofSize: 13)
        return result
    }

    @objc func changePassword() { showPasswordEditor(recovery: false) }
    @objc func forgotPassword() { showPasswordEditor(recovery: true) }

    func loadCredential() {
        do { record = try store.load(allowInteraction: false); credentialLoadError = nil }
        catch { credentialLoadError = error.localizedDescription }
    }

    @objc func authorizeCredential() {
        guard !protecting, !authorizingCredential else { return }
        authorizingCredential = true
        showSetup(error: credentialLoadError)
        writeStatus("authorizing-keychain")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try self.store.load() }
            DispatchQueue.main.async {
                self.authorizingCredential = false
                switch result {
                case .success(let record): self.record = record; self.credentialLoadError = nil
                case .failure(let error): self.credentialLoadError = error.localizedDescription
                }
                self.showSetup(error: self.credentialLoadError)
            }
        }
    }

    func activateProtectionShortcut() {
        guard desktopAvailable() else { return }
        if authorizingCredential { setupWindow?.makeKeyAndOrderFront(nil); return }
        if protecting { showUnlock(); return }
        if let editor = passwordWindow { editor.makeKeyAndOrderFront(nil); return }
        if credentialLoadError != nil { loadCredential() }
        if let error = credentialLoadError { showSetup(error: error); return }
        if record != nil { preview = false; beginInputProtection() }
        else {
            if setupWindow == nil { showSetup() }
            setupWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showPasswordEditor(recovery: Bool) {
        guard !preview, record != nil, !busy else { return }
        if let editor = passwordWindow { editor.makeKeyAndOrderFront(nil); return }
        editingRecovery = recovery
        let editor = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 310),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        editor.title = recovery ? "重置保护密码" : "修改保护密码"
        editor.isReleasedWhenClosed = false; editor.delegate = self
        let credential = secure(recovery ? "当前 Mac 账户的登录密码" : "当前保护密码")
        let password = secure("新保护密码（至少 3 个字符）")
        let confirmation = secure("确认新密码")
        confirmation.target = self; confirmation.action = #selector(submitPasswordEdit)
        editFields = [credential, password, confirmation]
        let hint = label("", size: 13)
        hint.isHidden = true; editHint = hint
        let save = button(recovery ? "验证并重置" : "保存", action: #selector(submitPasswordEdit))
        let cancel = smallButton("取消", action: #selector(cancelPasswordEdit))
        editButtons = [save, cancel]
        let actions = NSStackView(views: [cancel, save]); actions.orientation = .horizontal; actions.spacing = 18
        stack([credential, password, confirmation, hint, actions], in: editor.contentView!)
        passwordWindow = editor
        setBusy(true)
        writeStatus(protecting ? "protected-password-recovery" : "editing-password")
        editor.center(); editor.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true); editor.makeFirstResponder(credential)
        updateEditCooldown()
    }

    func setEditHint(_ message: String) {
        editHint?.stringValue = message; editHint?.isHidden = message.isEmpty
    }
    func setEditBusy(_ value: Bool) {
        editBusy = value
        for field in editFields { field.isEnabled = !value }
        for button in editButtons { button.isEnabled = !value }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !editBusy || editTimer != nil }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window === passwordWindow { finishPasswordEditor() }
            if window === unlockWindow { unlockWindow = nil }
        }
    }
    @objc func cancelPasswordEdit() {
        guard !editBusy || editTimer != nil else { return }
        passwordWindow?.close()
    }
    func finishPasswordEditor() {
        for field in editFields { field.stringValue = "" }
        if let editor = passwordWindow { editor.parent?.removeChildWindow(editor) }
        passwordWindow = nil; editFields = []; editButtons = []; editHint = nil
        editTimer?.invalidate(); editTimer = nil
        editBusy = false; setBusy(false)
        writeStatus(protecting ? "protected-input" : "ready")
        if protecting { showUnlock() }
        else { setupWindow?.makeKeyAndOrderFront(nil) }
    }

    func updateEditCooldown() {
        editTimer?.invalidate(); editTimer = nil
        let wait = editGate.wait(now: Date().timeIntervalSince1970)
        guard wait > 0 else { return }
        setEditBusy(true)
        // Cancellation remains available during cooldown; closing never clears it.
        editButtons.last?.isEnabled = true
        setEditHint("请等待 \(wait) 秒")
        editTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            let seconds = self.editGate.wait(now: Date().timeIntervalSince1970)
            if seconds > 0 { self.setEditHint("请等待 \(seconds) 秒") }
            else {
                timer.invalidate(); self.editTimer = nil
                self.setEditBusy(false); self.setEditHint("")
            }
        }
    }

    @objc func submitPasswordEdit() {
        guard !editBusy, editFields.count == 3,
              editGate.wait(now: Date().timeIntervalSince1970) == 0 else { return }
        let credential = editFields[0].stringValue
        let password = editFields[1].stringValue
        guard !credential.isEmpty else {
            setEditHint(editingRecovery ? "请输入 Mac 登录密码" : "请输入当前保护密码"); return
        }
        guard password.count >= 3 else { setEditHint("至少 3 个字符"); return }
        guard password == editFields[2].stringValue else { setEditHint("两次新密码不一致"); return }
        let recovery = editingRecovery
        for field in editFields { field.stringValue = "" }
        setEditBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> PasswordRecord in
                if recovery {
                    return try self.store.resetPassword(macLoginPassword: credential, newPassword: password)
                }
                return try self.store.changePassword(currentPassword: credential, newPassword: password)
            }
            DispatchQueue.main.async {
                self.setEditBusy(false)
                switch result {
                case .success(let record):
                    self.record = record; self.gate.reset(); self.editGate.reset()
                    self.passwordWindow?.close()
                    if self.protecting { self.endInputProtection() }
                    self.showSetup()
                case .failure(let error):
                    if let failure = error as? PrivacyError {
                        switch failure {
                        case .wrongPassword, .systemVerificationFailed:
                            self.editGate.failed(now: Date().timeIntervalSince1970)
                        default: break
                        }
                    }
                    self.setEditHint(error.localizedDescription)
                    self.updateEditCooldown()
                }
            }
        }
    }

    func setHint(_ message: String) {
        for hint in hints { hint.stringValue = message; hint.isHidden = message.isEmpty }
    }

    @objc func savePassword() {
        guard !busy, passwords.count == 2, record == nil else { return }
        let password = passwords[0].stringValue
        guard password.count >= 3 else { setHint("至少 3 个字符"); return }
        guard password == passwords[1].stringValue else { setHint("两次密码不一致"); return }
        setBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> PasswordRecord in
                let record = try PasswordRecord.create(password)
                try self.store.saveNew(record)
                return record
            }
            DispatchQueue.main.async {
                self.setBusy(false)
                for field in self.passwords { field.stringValue = "" }
                switch result {
                case .success(let record): self.record = record; self.showSetup()
                case .failure(let error): self.setHint(error.localizedDescription)
                }
            }
        }
    }

    @objc func demonstrate() {
        guard !protecting, passwordWindow == nil, !authorizingCredential else { return }
        preview = true; beginInputProtection()
    }
    @objc func protect() { preview = false; if record != nil { beginInputProtection() } }
    func beginInputProtection() {
        guard !protecting, passwordWindow == nil, desktopAvailable(), preview || record != nil else { return }
        guard preview || validationVerified else { showSetup(error:"尚未完成验证，未开启保护"); return }
        guard AXIsProcessTrusted() else { showSetup(error:"请在系统设置中允许辅助功能后再试"); return }
        protecting = true
        setupWindow?.orderOut(nil)
        reviewWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        do {
            previewStartedAt = preview ? ProcessInfo.processInfo.systemUptime : nil
            previewWasReady = false
            try inputController.start(boundedSeconds:preview ? 12 : nil); writeStatus("input-starting")
            let timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in
                guard let self else { return }
                if !desktopAvailable() { self.endInputProtection(); self.writeStatus("suspended") }
                else { self.writeStatus(self.lastMode) }
            }
            inputMonitor = timer; RunLoop.main.add(timer,forMode:.common)
        }
        catch { endInputProtection(); writeStatus("input-start-failed") }
    }
    func handleInputEvent(_ event: String) {
        guard protecting else { return }
        switch event {
        case "ready":
            previewWasReady = preview
            writeStatus(preview ? "input-preview" : "protected-input")
        case "physical-attempt": showUnlock()
        case "released", "tap-disabled", "permission-required", "tap-unavailable", "lease-expired", "stopped":
            let wasPreview = preview
            if wasPreview, PreviewCompletion.accepts(startedAt: previewStartedAt,
                wasReady: previewWasReady, event: event, now: ProcessInfo.processInfo.systemUptime) {
                lastCompletedPreview = Date()
            }
            endInputProtection(); writeStatus(wasPreview ? "preview-finished" : "protection-stopped")
        default: break
        }
    }
    func showUnlock() {
        guard protecting, desktopAvailable() else { return }
        if let editor = passwordWindow {
            editor.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); return
        }
        if let window = unlockWindow {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); return
        }
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:360,height:230),
            styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = preview ? "输入保护测试 · 12 秒" : "解除输入保护"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.canJoinAllApplications]
        window.delegate = self
        let password = secure(preview ? "测试输入（无需密码）" : "保护密码")
        password.target = self; password.action = #selector(unlock(_:))
        let hint = label("",size:13); hint.isHidden = true
        let unlock = button(preview ? "结束测试" : "解锁",action:#selector(unlock(_:)))
        passwords = [password]; hints = [hint]; buttons = [unlock]
        var views: [NSView] = [password,hint,unlock]
        if !preview { views.append(smallButton("忘记密码",action:#selector(forgotPassword))) }
        stack(views,in:window.contentView!,width:280)
        unlockWindow = window
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true); window.makeFirstResponder(password)
        setBusy(busy)
    }

    func setBusy(_ value: Bool) {
        busy = value
        for button in buttons { button.isEnabled = !value }
        for password in passwords { password.isEnabled = !value }
    }

    @objc func unlock(_ sender: Any?) {
        if preview { endInputProtection(); writeStatus("preview-finished"); return }
        guard protecting, !busy, let record, let field = passwords.first else { return }
        let now = Date().timeIntervalSince1970
        guard gate.wait(now: now) == 0 else { return }
        // The current unlock window has one password field. NSButton defaults
        // to tag -1, so its tag cannot identify that field.
        let password = field.stringValue
        for field in passwords { field.stringValue = "" }
        setBusy(true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try record.matches(password) }
            DispatchQueue.main.async {
                switch result {
                case .success(true): self.gate.reset(); self.endInputProtection(); self.showSetup()
                case .success(false):
                    self.gate.failed(now: Date().timeIntervalSince1970)
                    self.setHint("密码不正确")
                    self.startCooldownIfNeeded()
                case .failure:
                    // A verification error does not release physical input.
                    self.setHint("暂时无法验证，请重试")
                    self.setBusy(false)
                }
            }
        }
    }
    func startCooldownIfNeeded() {
        if gate.wait(now: Date().timeIntervalSince1970) == 0 {
            setBusy(false); return
        }
        failureCooldown?.invalidate()
        failureCooldown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            let seconds = self.gate.wait(now: Date().timeIntervalSince1970)
            if seconds > 0 { self.setHint("请等待 \(seconds) 秒") }
            else {
                timer.invalidate(); self.failureCooldown = nil
                self.setHint("")
                self.setBusy(false)
            }
        }
    }
    func endInputProtection() {
        protecting = false; busy = false
        inputMonitor?.invalidate(); inputMonitor = nil
        inputController.stop()
        failureCooldown?.invalidate(); failureCooldown = nil
        for field in passwords { field.stringValue = "" }
        unlockWindow?.orderOut(nil); unlockWindow?.close(); unlockWindow = nil
        passwords = []; hints = []; buttons = []
        preview = false; previewStartedAt = nil; previewWasReady = false
        writeStatus("ready-background")
    }

}

signal(SIGPIPE,SIG_IGN)
CommandLineTools.runIfRequested()
if CommandLine.arguments.contains("--input-worker") { InputWorker().run() }
do { try AppPaths.prepare() } catch { fputs("Unable to prepare local application data.\n", stderr); exit(1) }
guard AppInstanceLock.acquire() else { exit(0) }
let application = NSApplication.shared
let delegate = PrivacyDelegate()
application.delegate = delegate
application.run()
