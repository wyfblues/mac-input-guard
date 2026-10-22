import Foundation
@main struct InputPolicyTests {
    static func main() {
        func blocked(_ pid: Int64, _ state: Int64, now: Double = 5, until: Double = 10, unlock: Bool = false) -> Bool {
            PhysicalInputPolicy.shouldBlock(sourcePID: pid, sourceState: state, now: now,
                leaseUntil: until, localUnlockInput: unlock)
        }
        precondition(blocked(0, 0) && blocked(0, 1))
        precondition(!blocked(123, 0) && !blocked(123, 1) && !blocked(123, -1))
        precondition(!blocked(0, -1) && !blocked(0, 2))
        precondition(!blocked(0, 1, now: 10) && !blocked(0, 1, now: 11))
        precondition(!blocked(0, 1, unlock: true))
        for raw: UInt32 in [18,19,20,29,30,31,32] {
            precondition(PhysicalInputPolicy.gestureEventMask & (UInt64(1) << raw) != 0)
        }
        for raw: UInt32 in [0,10,14,22,63] {
            precondition(PhysicalInputPolicy.gestureEventMask & (UInt64(1) << raw) == 0)
        }
        print("PASS: physical signatures, synthetic sources, unknown sources, expired lease, unlock exception")
    }
}
