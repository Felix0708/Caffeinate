import Foundation
import IOKit.pwr_mgt
import IOKit.ps

public enum AwakeMode: String, CaseIterable, Identifiable {
    case display = "Display (화면 켜짐 유지)"
    case system = "System Only (시스템만 유지)"

    public var id: String { rawValue }

    var assertionType: CFString {
        switch self {
        case .display:
            return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        case .system:
            return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        }
    }
}

public final class PowerManager {
    public static let shared = PowerManager()

    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive: Bool = false
    private(set) var currentMode: AwakeMode = .display

    private init() {}

    deinit {
        deactivate()
    }

    @discardableResult
    public func activate(mode: AwakeMode = .display, reason: String = "Caffeine active") -> Bool {
        if isActive {
            deactivate()
        }

        var newID: IOPMAssertionID = 0
        let cfReason = reason as CFString
        let result = IOPMAssertionCreateWithName(
            mode.assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            cfReason,
            &newID
        )

        if result == kIOReturnSuccess {
            assertionID = newID
            isActive = true
            currentMode = mode
            return true
        } else {
            assertionID = 0
            isActive = false
            return false
        }
    }

    public func deactivate() {
        guard isActive, assertionID != 0 else {
            isActive = false
            assertionID = 0
            return
        }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    // MARK: - Battery & Power Information

    public static func isACPowerConnected() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return true // 데스크탑 맥 등 배터리가 없는 경우 기본 true
        }

        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                if state == kIOPSACPowerValue as String {
                    return true
                } else if state == kIOPSBatteryPowerValue as String {
                    return false
                }
            }
        }
        return true
    }

    public static func currentBatteryPercentage() -> Int? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let max = desc[kIOPSMaxCapacityKey as String] as? Int,
               max > 0 {
                return Int((Double(cur) / Double(max)) * 100.0)
            }
        }
        return nil
    }

    // MARK: - Process Existence

    public static func isProcessRunning(pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}
