import Foundation

// Measured session-tap signatures on this Mac. Event metadata is not an
// authentication boundary; this prevents casual physical input only.
struct PhysicalInputPolicy {
    // AppKit gesture event values also appear as raw session-tap events, but
    // are absent from CGEventType's public case list. This Mac's physical
    // Space-switching gestures were observed as type 29 with PID 0/state 1.
    static let gestureEventTypes: Set<UInt32> = [18, 19, 20, 29, 30, 31, 32]
    static let gestureEventMask: UInt64 = gestureEventTypes.reduce(0) { $0 | (UInt64(1) << $1) }

    static func isPhysical(sourcePID: Int64, sourceState: Int64) -> Bool {
        sourcePID == 0 && (sourceState == 0 || sourceState == 1)
    }
    static func shouldBlock(sourcePID: Int64, sourceState: Int64,
                            now: TimeInterval, leaseUntil: TimeInterval,
                            localUnlockInput: Bool = false) -> Bool {
        now < leaseUntil && !localUnlockInput && isPhysical(sourcePID: sourcePID, sourceState: sourceState)
    }
}
