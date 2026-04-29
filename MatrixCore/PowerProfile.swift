import Foundation
import IOKit.ps

/// Resolves a target framerate from the current thermal + battery state.
/// Critical for the fanless M2 Air: sustained 60fps GPU work at 5K can hit
/// thermal throttling within minutes; better to drop to 30fps preemptively.
public enum PowerProfile {
    public enum Tier {
        case nominal   // 60fps, full bloom
        case balanced  // 30fps, full bloom (battery or .fair thermal)
        case low       // 20fps, bloom may be disabled (.serious / .critical)
    }

    public static func currentTier() -> Tier {
        let thermal = ProcessInfo.processInfo.thermalState
        switch thermal {
        case .serious, .critical:
            return .low
        case .fair:
            return .balanced
        case .nominal:
            break
        @unknown default:
            break
        }
        return isOnBattery() ? .balanced : .nominal
    }

    public static func framesPerSecond(for tier: Tier) -> Int {
        switch tier {
        case .nominal:  return 60
        case .balanced: return 30
        case .low:      return 20
        }
    }

    public static func bloomEnabled(for tier: Tier) -> Bool {
        tier != .low
    }

    /// IOKit power-source check. Returns true on battery, false on AC.
    private static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }
        guard let rawList = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()
            as? [CFTypeRef] else {
            return false
        }
        for source in rawList {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if let state = info[kIOPSPowerSourceStateKey] as? String {
                if state == kIOPSACPowerValue { return false }
                if state == kIOPSBatteryPowerValue { return true }
            }
        }
        return false
    }
}
