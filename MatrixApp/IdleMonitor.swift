import Foundation
import IOKit

/// Polls the system HID idle time once per second and fires a callback
/// when the configured threshold is crossed. The callback is invoked
/// once per "idle event" — i.e. once when the user crosses idle, then
/// not again until they're active and go idle again.
///
/// Uses IOKit's `HIDIdleTime` property on `IOHIDSystem`, which is the
/// canonical macOS idle source (input-server time since the last
/// keyboard, mouse, or trackpad event). Doesn't require any
/// permissions.
@MainActor
final class IdleMonitor {
    /// Seconds of inactivity required before firing.
    var thresholdSeconds: TimeInterval

    /// Called on the main thread when the threshold is first crossed.
    /// Won't fire again until the user is active, then idle again.
    var onIdle: (() -> Void)?

    /// Whether the monitor is enabled. When false the timer is fully
    /// stopped — no polling, no main-thread work — to avoid stutter
    /// against an active render loop.
    var isEnabled: Bool = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    private var pollTimer: Timer?
    private var hasFiredForCurrentIdlePeriod: Bool = false

    init(thresholdSeconds: TimeInterval = 5 * 60) {
        self.thresholdSeconds = thresholdSeconds
    }

    func start() {
        stop()
        let timer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Common run loop mode so it fires even during interactive UI tracking.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Reset edge-trigger state — call when the user has dismissed the
    /// screensaver (we're no longer in the "fired" state).
    func resetEdgeTrigger() {
        hasFiredForCurrentIdlePeriod = false
    }

    private func tick() {
        let idle = IdleMonitor.systemIdleSeconds()

        if idle >= thresholdSeconds {
            if !hasFiredForCurrentIdlePeriod {
                hasFiredForCurrentIdlePeriod = true
                onIdle?()
            }
        } else {
            // User became active — clear the edge-trigger so next idle
            // period can fire again.
            hasFiredForCurrentIdlePeriod = false
        }
    }

    /// System-wide idle time (seconds since last HID input event).
    /// Returns 0 if the IOHIDSystem service can't be queried.
    static func systemIdleSeconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        let matchResult = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        )
        guard matchResult == KERN_SUCCESS, iterator != 0 else { return 0 }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let nanos = dict["HIDIdleTime"] as? UInt64 else {
            return 0
        }
        return TimeInterval(nanos) / 1_000_000_000
    }
}
