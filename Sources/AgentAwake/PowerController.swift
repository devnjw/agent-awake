import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import AgentAwakeCore

struct PowerSnapshot {
    var source: PowerSource = .unknown
    var battery: Int?
    var lidClosed: Bool?
    var thermal = ProcessInfo.processInfo.thermalState.rawValue

    static func read() -> PowerSnapshot {
        var result = PowerSnapshot()
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            if let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
                result.source = source == kIOPSACPowerValue ? .ac : (source == kIOPSBatteryPowerValue ? .battery : .unknown)
            }
            if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
                for source in sources {
                    guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                          description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                          let current = description[kIOPSCurrentCapacityKey] as? Int,
                          let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                    result.battery = min(100, max(0, current * 100 / maximum))
                }
            }
        }
        result.lidClosed = rootBool("AppleClamshellState")
        return result
    }
}

func rootBool(_ key: String) -> Bool? {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return nil }
    defer { IOObjectRelease(root) }
    return IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
}

enum PowerError: LocalizedError {
    case system(String, kern_return_t)
    case unsupported
    var errorDescription: String? {
        switch self {
        case .system(let operation, let code): return "\(operation) failed (IOKit \(String(format: "0x%08x", UInt32(bitPattern: code))))"
        case .unsupported: return "Lid control isn't available on this Mac."
        }
    }
}

// Private IOKit selector, defined in Apple's IOPMLibDefs.h. This is intentionally
// isolated: it is not a supported public API and must be rechecked on OS updates.
// Unlike pmset disablesleep, it does not persist a system-wide preference.
final class PowerController {
    static func emergencyRelease() throws {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { throw PowerError.unsupported }
        defer { IOObjectRelease(root) }
        var connection: io_connect_t = 0
        let code = IOServiceOpen(root, mach_task_self_, 0, &connection)
        guard code == KERN_SUCCESS else { throw PowerError.system("Recovery connection", code) }
        defer { IOServiceClose(connection) }
        var value: UInt64 = 0
        let result = IOConnectCallScalarMethod(connection, 12, &value, 1, nil, nil)
        if result != KERN_SUCCESS { throw PowerError.system("Sleep restoration", result) }
    }
    private var connection: io_connect_t = 0
    private var idleAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private(set) var lidControlAccepted = false
    private var restoreNeeded = false
    private var baselineDisabled = false
    var assertionHeld: Bool { idleAssertion != 0 && systemAssertion != 0 }

    func acquire() throws {
        guard PowerSnapshot.read().source == .ac else { throw PowerError.unsupported }
        guard rootBool("AppleClamshellState") != nil else { throw PowerError.unsupported }
        if connection == 0 {
            let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
            guard root != 0 else { throw PowerError.unsupported }
            defer { IOObjectRelease(root) }
            try check(IOServiceOpen(root, mach_task_self_, 0, &connection), "Power service connection")
            baselineDisabled = rootBool("AppleClamshellCausesSleep") == false
        }
        do {
            if idleAssertion == 0 {
                try check(IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn), "AgentAwake · plugged-in agent session" as CFString,
                    &idleAssertion), "Idle sleep assertion")
            }
            if systemAssertion == 0 {
                try check(IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn), "AgentAwake · AC power only" as CFString,
                    &systemAssertion), "System sleep assertion")
            }
            // Reapply while armed: powerd can reevaluate this shared flag on display changes.
            restoreNeeded = true
            try setLidDisabled(true)
            lidControlAccepted = true
        } catch {
            try? release()
            throw error
        }
    }

    func release() throws {
        var failure: Error?
        if restoreNeeded {
            do {
                // Preserve an external-display mode that was present before our session.
                // On battery always release our request.
                try setLidDisabled(baselineDisabled && PowerSnapshot.read().source == .ac)
                restoreNeeded = false
                lidControlAccepted = false
            } catch { failure = error }
        }
        if idleAssertion != 0 { IOPMAssertionRelease(idleAssertion); idleAssertion = 0 }
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion); systemAssertion = 0 }
        if !restoreNeeded && connection != 0 { IOServiceClose(connection); connection = 0 }
        if let failure { throw failure }
    }

    private func setLidDisabled(_ disabled: Bool) throws {
        var argument: UInt64 = disabled ? 1 : 0
        try check(IOConnectCallScalarMethod(connection, 12, &argument, 1, nil, nil), "Lid control")
    }
    private func check(_ code: kern_return_t, _ operation: String) throws {
        if code != KERN_SUCCESS { throw PowerError.system(operation, code) }
    }
    deinit { try? release() }
}
