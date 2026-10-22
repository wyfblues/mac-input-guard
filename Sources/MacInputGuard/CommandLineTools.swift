import AppKit
import Foundation
import Darwin

enum CommandLineTools {
    private static func output(_ row: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { exit(1) }
        print(line)
    }
    private static func process(_ pid: Int, parent: Int? = nil) -> Bool {
        guard pid > 0, kill(Int32(pid), 0) == 0 else { return false }
        let command = Process(); let pipe = Pipe()
        command.executableURL = URL(fileURLWithPath: "/bin/ps")
        command.arguments = ["-p", String(pid), "-o", "ppid=,comm="]
        command.standardOutput = pipe; command.standardError = FileHandle.nullDevice
        do { try command.run() } catch { return false }
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        command.waitUntilExit()
        let parts = text.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard command.terminationStatus == 0, parts.count == 2,
              URL(fileURLWithPath: String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)).lastPathComponent == "MacInputGuard"
            else { return false }
        return parent == nil || Int(parts[0]) == parent
    }
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--diagnostics") {
            output(["bundle_id": AppIdentity.bundleID, "data_directory": AppPaths.dataDirectory.path,
                "keychain_service": AppIdentity.keychainService,
                "architecture": CompatibilityApproval.currentArchitecture,
                "accessibility_allowed": AXIsProcessTrusted(),
                "compatibility_approved": CompatibilityApproval.load()?.isCurrent == true,
                "background_only_on_login": true])
            exit(0)
        }
        if args.contains("--status") {
            guard let data = try? Data(contentsOf: AppPaths.statusFile),
                  var row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = row["pid"] as? Int, process(pid) else {
                output(["mode": "not-running", "physical_blocking": false]); exit(0)
            }
            if row["physical_blocking"] as? Bool == true {
                let fresh = Date().timeIntervalSince1970 - (row["updated_at"] as? Double ?? 0) <= 3
                let worker = row["input_worker_pid"] as? Int ?? 0
                if !fresh || !process(worker, parent: pid) {
                    row["mode"] = "input-health-unconfirmed"
                    row["physical_blocking"] = false; row["input_filter_ready"] = false
                }
            }
            output(row); exit(0)
        }
        if args.contains("--disable-login") {
            do {
                if LoginSettings.isConfigured { try LoginSettings.setEnabled(false) }
                output(["login_enabled": false]); exit(0)
            } catch { fputs("Unable to disable login item; use the app's login setting first.\n", stderr); exit(1) }
        }
    }
}
