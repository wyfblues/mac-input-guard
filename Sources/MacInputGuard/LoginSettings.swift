import AppKit
import ServiceManagement
import Carbon

enum LoginSettings {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var isConfigured: Bool {
        SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    }
    static var wasLaunchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication,
              let data = event.paramDescriptor(forKeyword: keyAEPropData) else { return false }
        return data.enumCodeValue == keyAELaunchedAsLogInItem ||
            data.enumCodeValue == keyAELaunchedAsServiceItem
    }
    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}
