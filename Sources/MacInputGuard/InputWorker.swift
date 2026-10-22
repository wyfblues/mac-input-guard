import AppKit
import ApplicationServices
import Foundation

struct InputLease: Codable {
    var until: Double
    var unlockPID: Int32
    var unlockRect: [Double]?
}

// This child owns the event tap. No passwords, key text or event locations are
// logged. Losing the parent, its heartbeat, or event-tap health releases input.
final class InputWorker {
    static let eventMask: CGEventMask = {
        let types: [CGEventType] = [.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,
            .mouseMoved,.leftMouseDragged,.rightMouseDragged,.keyDown,.keyUp,.flagsChanged,
            .scrollWheel,.otherMouseDown,.otherMouseUp,.otherMouseDragged]
        return types.reduce(CGEventMask(PhysicalInputPolicy.gestureEventMask)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
    }()
    let lock = NSLock()
    var lease = InputLease(until: 0, unlockPID: 0, unlockRect: nil)
    var tap: CFMachPort?
    var blocked = 0
    var passed = 0
    var blockedScroll = 0
    var passedScroll = 0
    var blockedGestures = 0
    var passedGestures = 0
    var lastAttempt = 0.0
    var loopTick = ProcessInfo.processInfo.systemUptime
    var hardDeadline: Double = .infinity

    func snapshot() -> InputLease { lock.lock(); defer { lock.unlock() }; return lease }
    func emit(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
    }
    func run() -> Never {
        guard AXIsProcessTrusted(), getppid() > 1 else { emit(["event":"permission-required"]); exit(2) }
        if let index = CommandLine.arguments.firstIndex(of: "--bounded"),
           CommandLine.arguments.indices.contains(index + 1),
           let seconds = Double(CommandLine.arguments[index + 1]), seconds > 0, seconds <= 15 {
            hardDeadline = ProcessInfo.processInfo.systemUptime + seconds
        }
        // A startup heartbeat must arrive promptly. The independent watchdog
        // thread exits this child even if its event run loop stops responding.
        lease.until = ProcessInfo.processInfo.systemUptime + 1.5
        DispatchQueue.global(qos: .userInteractive).async {
            while true {
                self.lock.lock(); let lastTick = self.loopTick; self.lock.unlock()
                let now = ProcessInfo.processInfo.systemUptime
                if now >= min(self.snapshot().until, self.hardDeadline) || now - lastTick > 1.5 {
                    self.emit(["event":"lease-expired"]); exit(0)
                }
                Thread.sleep(forTimeInterval:0.1)
            }
        }
        DispatchQueue.global(qos: .userInteractive).async {
            var buffer = Data()
            while true {
                let data = FileHandle.standardInput.availableData
                if data.isEmpty { exit(0) }
                buffer.append(data)
                if buffer.count > 8192 { exit(3) }
                while let end = buffer.firstIndex(of:10) {
                    let line = buffer.prefix(upTo:end); buffer.removeSubrange(...end)
                    guard var value = try? JSONDecoder().decode(InputLease.self,from:line) else { exit(3) }
                    value.until = min(value.until, ProcessInfo.processInfo.systemUptime + 2)
                    self.lock.lock(); self.lease = value; self.lock.unlock()
                }
            }
        }
        let callback: CGEventTapCallBack = { _,type,event,context in
            let worker = Unmanaged<InputWorker>.fromOpaque(context!).takeUnretainedValue()
            return worker.filter(type,event)
        }
        guard let created = CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,
            options:.defaultTap,eventsOfInterest:Self.eventMask,callback:callback,
            userInfo:Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil,created,0) else {
            emit(["event":"tap-unavailable"]); exit(2)
        }
        tap = created
        CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
        var lastHeartbeat = 0.0
        let loopTimer = Timer(timeInterval:0.2,repeats:true) { _ in
            self.lock.lock(); self.loopTick = ProcessInfo.processInfo.systemUptime; self.lock.unlock()
            if ProcessInfo.processInfo.systemUptime - lastHeartbeat >= 0.5 {
                lastHeartbeat = ProcessInfo.processInfo.systemUptime
                self.emit(["event":"heartbeat", "blocked_scroll":self.blockedScroll,
                    "passed_scroll":self.passedScroll, "blocked_gestures":self.blockedGestures,
                    "passed_gestures":self.passedGestures])
            }
        }
        RunLoop.main.add(loopTimer,forMode:.common)
        emit(["event":"ready", "pid":getpid()])
        CFRunLoopRun()
        CGEvent.tapEnable(tap:created,enable:false); CFMachPortInvalidate(created)
        emit(["event":"stopped", "blocked":blocked,"passed":passed]); exit(0)
    }
    func filter(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap:tap,enable:false) }
            emit(["event":"tap-disabled"]); CFRunLoopStop(CFRunLoopGetMain())
            return Unmanaged.passUnretained(event)
        }
        let now = ProcessInfo.processInfo.systemUptime
        let state = snapshot()
        let physical = PhysicalInputPolicy.isPhysical(sourcePID:event.getIntegerValueField(.eventSourceUnixProcessID),
            sourceState:event.getIntegerValueField(.eventSourceStateID))
        if physical && now < min(state.until, hardDeadline) {
            var localUnlock = false
            if let rect = state.unlockRect, rect.count == 4,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == state.unlockPID {
                let frame = CGRect(x:rect[0],y:rect[1],width:rect[2],height:rect[3])
                switch type {
                case .mouseMoved: localUnlock = true
                case .leftMouseDown,.leftMouseUp,.leftMouseDragged:
                    localUnlock = frame.contains(event.location)
                case .keyDown,.keyUp,.flagsChanged:
                    let forbidden: CGEventFlags = [.maskCommand,.maskControl,.maskAlternate,.maskSecondaryFn]
                    localUnlock = event.flags.intersection(forbidden).isEmpty
                default: break
                }
            }
            if !localUnlock {
                blocked += 1
                if type == .scrollWheel { blockedScroll += 1 }
                if PhysicalInputPolicy.gestureEventTypes.contains(type.rawValue) { blockedGestures += 1 }
                if [.keyDown,.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(type), now - lastAttempt >= 1 {
                    lastAttempt = now; emit(["event":"physical-attempt"])
                }
                return nil
            }
        }
        passed += 1
        if type == .scrollWheel { passedScroll += 1 }
        if PhysicalInputPolicy.gestureEventTypes.contains(type.rawValue) { passedGestures += 1 }
        return Unmanaged.passUnretained(event)
    }
}

final class PhysicalInputController {
    var process: Process?
    var input: FileHandle?
    var pulse: Timer?
    private var boundedStop: Timer?
    private var lastHeartbeat = ProcessInfo.processInfo.systemUptime
    var isReady = false
    private(set) var inputCounts: [String:Int] = [:]
    var onEvent: ((String) -> Void)?
    var unlockContext: (() -> NSWindow?)?
    private var outputBuffer = Data()
    private var intentionalStop = false
    private var generation = UUID()

    func start(boundedSeconds: Double? = nil) throws {
        stop()
        inputCounts = [:]
        intentionalStop = false
        generation = UUID(); let current = generation
        let child = Process(); let stdin = Pipe(); let stdout = Pipe()
        child.executableURL = Bundle.main.executableURL
        child.arguments = ["--input-worker"]
        if let seconds = boundedSeconds { child.arguments! += ["--bounded", String(seconds)] }
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { guard self?.generation == current else { return }; self?.receive(data) }
        }
        child.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.process === child else { return }
                self.isReady = false
                self.pulse?.invalidate(); self.pulse = nil
                self.input = nil; self.process = nil
                if !self.intentionalStop { self.onEvent?("released") }
            }
        }
        process = child; input = stdin.fileHandleForWriting
        do { try child.run() } catch { process = nil; input = nil; throw error }
        lastHeartbeat = ProcessInfo.processInfo.systemUptime
        if let seconds = boundedSeconds {
            let deadlineTimer = Timer(timeInterval:seconds + 0.3,repeats:false) { [weak self] _ in
                guard let self else { return }
                self.stop(); self.onEvent?("released")
            }
            boundedStop = deadlineTimer; RunLoop.main.add(deadlineTimer,forMode:.common)
        }
        // The parent never waits synchronously for the child.
        sendLease()
        let timer = Timer(timeInterval:0.25,repeats:true) { [weak self] _ in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastHeartbeat > 2 {
                self.stop(); self.onEvent?("released")
            } else { self.sendLease() }
        }
        pulse = timer; RunLoop.main.add(timer,forMode:.common)
    }
    private func sendLease() {
        guard let input, process?.isRunning == true else { return }
        var rect: [Double]?
        if let window = unlockContext?(), window.isKeyWindow, window.isVisible, NSApp.isActive,
           window.isOnActiveSpace, window.occlusionState.contains(.visible),
           let screenHeight = NSScreen.screens.first?.frame.maxY {
            let frame = window.frame
            rect = [frame.minX,screenHeight - frame.maxY,frame.width,frame.height]
        }
        let value = InputLease(until:ProcessInfo.processInfo.systemUptime + 1.5,
            unlockPID:getpid(),unlockRect:rect)
        if let data = try? JSONEncoder().encode(value) {
            do { try input.write(contentsOf:data + Data([10])) }
            catch { stop(); onEvent?("released") }
        }
    }
    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        outputBuffer.append(data)
        while let end = outputBuffer.firstIndex(of:10) {
            let line = outputBuffer.prefix(upTo:end); outputBuffer.removeSubrange(...end)
            if let row = try? JSONSerialization.jsonObject(with:line) as? [String:Any], let event = row["event"] as? String {
                if event == "ready" || event == "heartbeat" { lastHeartbeat = ProcessInfo.processInfo.systemUptime }
                if event == "ready" { isReady = true }
                if event == "heartbeat" {
                    for key in ["blocked_scroll", "passed_scroll", "blocked_gestures", "passed_gestures"] {
                        if let value = row[key] as? Int { inputCounts[key] = value }
                    }
                    continue
                }
                onEvent?(event)
            }
        }
    }
    func stop() {
        generation = UUID()
        intentionalStop = true; isReady = false
        pulse?.invalidate(); pulse = nil
        boundedStop?.invalidate(); boundedStop = nil
        try? input?.close(); input = nil
        if let child = process, child.isRunning {
            child.terminate()
            DispatchQueue.global().asyncAfter(deadline:.now() + 0.3) {
                if child.isRunning { kill(child.processIdentifier,SIGKILL) }
            }
        }
        process = nil; outputBuffer.removeAll()
    }
    deinit { stop() }
}
