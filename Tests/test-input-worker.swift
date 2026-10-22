import AppKit
import Foundation

// These event objects are passed only to the filter function, never posted.
@main struct InputWorkerTests {
    static func main() {
        let worker = InputWorker()
        let event = CGEvent(source:nil)!
        event.setIntegerValueField(.eventSourceUnixProcessID,value:0)
        event.setIntegerValueField(.eventSourceStateID,value:1)
        worker.lease = InputLease(until:ProcessInfo.processInfo.systemUptime + 30,
            unlockPID:0,unlockRect:nil)
        for raw: UInt32 in [18,19,20,22,29,30,31,32] {
            let type = CGEventType(rawValue:raw)!
            precondition(InputWorker.eventMask & (CGEventMask(1) << raw) != 0)
            precondition(worker.filter(type,event) == nil, "Physical scroll or gesture passed")
            event.setIntegerValueField(.eventSourceUnixProcessID,value:123)
            precondition(worker.filter(type,event) != nil, "Automation source blocked")
            event.setIntegerValueField(.eventSourceUnixProcessID,value:0)
        }
        precondition(worker.blockedScroll == 1 && worker.blockedGestures == 7)
        precondition(worker.passedScroll == 1 && worker.passedGestures == 7)
        worker.lease.until = 0
        precondition(worker.filter(.scrollWheel,event) != nil)
        precondition(worker.filter(CGEventType(rawValue:29)!,event) != nil)
        worker.lease.until = ProcessInfo.processInfo.systemUptime + 30
        worker.hardDeadline = 0
        precondition(worker.filter(.scrollWheel,event) != nil)
        precondition(worker.filter(CGEventType(rawValue:30)!,event) != nil)
        precondition(InputWorker.eventMask & (CGEventMask(1) << 14) == 0)
        print("PASS: actual worker blocks physical wheel and gestures, passes automation and expired trials")
    }
}
