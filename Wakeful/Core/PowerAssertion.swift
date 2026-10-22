import IOKit.pwr_mgt

/// Wraps IOKit power assertions, the same mechanism `caffeinate` uses.
@MainActor
final class PowerAssertion {
    private var idleAssertion: IOPMAssertionID?
    private var idleAssertionPreventsDisplaySleep = false
    private var systemAssertion: IOPMAssertionID?

    var isHeld: Bool { idleAssertion != nil }

    /// - Parameters:
    ///   - preventDisplaySleep: keep the screen on too, not just the system.
    ///   - preventLidSleep: also hold `PreventSystemSleep`, which macOS honours with the lid closed
    ///     while the Mac is on power (it is ignored on battery).
    @discardableResult
    func acquire(preventDisplaySleep: Bool, preventLidSleep: Bool, reason: String) -> Bool {
        if idleAssertion == nil || idleAssertionPreventsDisplaySleep != preventDisplaySleep {
            release(&idleAssertion)
            let type = preventDisplaySleep
                ? kIOPMAssertionTypePreventUserIdleDisplaySleep
                : kIOPMAssertionTypePreventUserIdleSystemSleep
            idleAssertion = create(type, reason: reason)
            idleAssertionPreventsDisplaySleep = preventDisplaySleep
        }

        if preventLidSleep, systemAssertion == nil {
            systemAssertion = create(kIOPMAssertionTypePreventSystemSleep, reason: reason)
        } else if !preventLidSleep {
            release(&systemAssertion)
        }
        return idleAssertion != nil
    }

    func release() {
        release(&idleAssertion)
        release(&systemAssertion)
    }

    private func create(_ type: String, reason: String) -> IOPMAssertionID? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    private func release(_ id: inout IOPMAssertionID?) {
        if let current = id { IOPMAssertionRelease(current) }
        id = nil
    }
}
