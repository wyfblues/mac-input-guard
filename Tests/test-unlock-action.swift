import AppKit
import Foundation

// Exercise the actual delegate and target/action path, suppressing windows and
// personal status output. The harness never loads the owner's Keychain record.
final class UnlockHarness: PrivacyDelegate {
    var completed = false
    override func showSetup(error: String? = nil) { }
    override func writeStatus(_ mode: String) { lastMode = mode }
    override func endInputProtection() { super.endInputProtection(); completed = true }
}

@main struct UnlockActionTests {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        preview = false
        let record = try PasswordRecord.create("test-only-password")
        func harness(_ password: String) -> (UnlockHarness, NSSecureTextField, NSButton) {
            let delegate = UnlockHarness()
            delegate.record = record; delegate.protecting = true
            let field = delegate.secure("test")
            field.stringValue = password
            field.target = delegate; field.action = #selector(PrivacyDelegate.unlock(_:))
            let button = delegate.button("test",action:#selector(PrivacyDelegate.unlock(_:)))
            delegate.passwords = [field]; delegate.buttons = [button]
            delegate.hints = [delegate.label("",size:13)]
            return (delegate,field,button)
        }
        func waitUntil(_ predicate: () -> Bool) {
            let end = Date().addingTimeInterval(5)
            while !predicate() && Date() < end { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
            precondition(predicate(), "Unlock target/action did not finish")
        }
        if CommandLine.arguments.contains("--reproduce-old-button-bug") {
            let (delegate,field,button) = harness("test-only-password")
            precondition(button.tag == -1 && field.tag == 0)
            precondition(NSApp.sendAction(button.action!,to:button.target,from:button))
            precondition(!delegate.busy && delegate.protecting && !delegate.completed && !field.stringValue.isEmpty)
            print("REPRODUCED: default NSButton tag -1 silently rejects unlock before password verification")
            return
        }
        for source in ["button","return","button-with-custom-tag"] {
            let (delegate,field,button) = harness("test-only-password")
            if source == "button-with-custom-tag" { button.tag = 99 }
            let sender: NSControl = source == "return" ? field : button
            precondition(NSApp.sendAction(sender.action!,to:sender.target,from:sender))
            precondition(delegate.busy && field.stringValue.isEmpty)
            waitUntil { delegate.completed }
            precondition(!delegate.protecting)
        }
        let (delegate,field,button) = harness("incorrect-test-only-password")
        precondition(button.tag == -1)
        precondition(NSApp.sendAction(button.action!,to:button.target,from:button))
        waitUntil { !delegate.busy }
        precondition(delegate.protecting && !delegate.completed && field.stringValue.isEmpty)
        precondition(button.isEnabled && delegate.gate.failures == 1)
        print("PASS: default mouse button, Return, unrelated button tag, wrong-password preservation")
    }
}
