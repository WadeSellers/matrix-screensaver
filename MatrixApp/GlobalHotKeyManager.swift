import Carbon.HIToolbox
import Foundation
import os.log

private let log = OSLog(subsystem: "com.wadesellers.matrix", category: "hotkey")

/// Registers a global keyboard shortcut that fires from any app —
/// even fullscreen apps — without requiring Accessibility permission.
///
/// Why Carbon's `RegisterEventHotKey` and not
/// `NSEvent.addGlobalMonitorForEvents`? `RegisterEventHotKey` *captures*
/// the keystroke so the user doesn't accidentally type "M" into
/// whatever was frontmost when they triggered the shortcut. Global
/// `NSEvent` monitors are observe-only.
///
/// Why no Accessibility prompt? `RegisterEventHotKey` registers the
/// hotkey with WindowServer directly — same pathway Apple uses for
/// system shortcuts (Spotlight, Mission Control, Screenshots). The
/// system routes the event straight to our app, so we never need the
/// "control your computer" trust grant we deliberately retired.
@MainActor
final class GlobalHotKeyManager {
    /// Called on the main thread when the hotkey fires.
    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Default shortcut: ⌃⌥⌘M. Three modifiers + a letter is well
    /// outside any plausible accidental press; no system shortcut
    /// owns this combination; "M for Matrix" — easy to remember.
    static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_M)
    static let defaultModifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)
    /// Pre-formatted display string for Settings UI.
    static let defaultDisplayString = "⌃⌥⌘M"

    /// Register the default shortcut. Idempotent — re-registering
    /// unbinds the previous combination first.
    func register() {
        register(keyCode: Self.defaultKeyCode, modifiers: Self.defaultModifiers)
    }

    /// Register an arbitrary shortcut. `keyCode` is a Carbon virtual
    /// key code (e.g. `kVK_ANSI_M`); `modifiers` is the OR of Carbon
    /// modifier masks (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        // 'MTAX' — Matrix-specific 4-char signature so the event
        // handler can tell our hotkey apart from anyone else's that
        // might end up routed through the same target.
        let signature: OSType = 0x4D544158
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // Pass `self` through the userData void* so the C-function-pointer
        // callback (which can't capture context) can reach the instance.
        let userData = Unmanaged.passUnretained(self).toOpaque()

        // Install the event handler before registering the hotkey so
        // the very first keypress can't slip through in a race.
        var handler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                // Hop to main; the handler can be invoked from a
                // non-main thread.
                DispatchQueue.main.async {
                    manager.onPressed?()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handler
        )
        guard installStatus == noErr else {
            os_log("InstallEventHandler failed: %{public}d",
                   log: log, type: .error, installStatus)
            return
        }
        eventHandler = handler

        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard registerStatus == noErr else {
            os_log("RegisterEventHotKey failed: %{public}d (likely already in use by another app)",
                   log: log, type: .error, registerStatus)
            return
        }
        hotKeyRef = ref
        os_log("registered global hotkey %{public}@",
               log: log, type: .info, Self.defaultDisplayString)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
