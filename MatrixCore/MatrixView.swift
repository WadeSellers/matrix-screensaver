import AppKit
import MetalKit

public final class MatrixView: MTKView {
    public private(set) var renderer: MatrixRenderer?

    // nonisolated(unsafe) so deinit can read these to remove observers.
    // We only mutate from main-actor contexts (init / observer callbacks).
    private nonisolated(unsafe) var thermalObserver: NSObjectProtocol?
    private nonisolated(unsafe) var willSleepObserver: NSObjectProtocol?
    private nonisolated(unsafe) var didWakeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var powerSourceObserver: NSObjectProtocol?

    public override init(frame: CGRect, device: MTLDevice?) {
        let resolvedDevice = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frame, device: resolvedDevice)
        configureDefaults()
        registerLifecycleObservers()
    }

    public required init(coder: NSCoder) {
        super.init(coder: coder)
        configureDefaults()
        registerLifecycleObservers()
    }

    deinit {
        removeObservers()
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        // Stop pushing frames when we're not on screen.
        isPaused = (newWindow == nil)
    }

    private func configureDefaults() {
        colorPixelFormat = .bgra8Unorm_srgb
        preferredFramesPerSecond = 60
        isPaused = false
        enableSetNeedsDisplay = false
        framebufferOnly = false
        clearColor = MTLClearColorMake(0, 0, 0, 1)

        if let device {
            let r = MatrixRenderer(device: device)
            self.renderer = r
            self.delegate = r
        }

        applyPowerProfile()
    }

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default

        thermalObserver = center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyPowerProfile()
        }

        // NSWorkspace notifications for system sleep/wake. Pause the render
        // loop so we don't burn battery while the system is asleep, and so
        // we don't push stale frames into the drawable cycle.
        let ws = NSWorkspace.shared.notificationCenter
        willSleepObserver = ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isPaused = true
        }
        didWakeObserver = ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isPaused = (self?.window == nil)
            self?.applyPowerProfile()
        }

        // IOKit doesn't ship a Notification.Name for power-source changes that
        // surfaces nicely in Swift. Re-checking on thermal-state change covers
        // most plug/unplug events; for the rest we re-check on wake.
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        if let thermalObserver { center.removeObserver(thermalObserver) }

        let ws = NSWorkspace.shared.notificationCenter
        if let willSleepObserver { ws.removeObserver(willSleepObserver) }
        if let didWakeObserver { ws.removeObserver(didWakeObserver) }
        if let powerSourceObserver { ws.removeObserver(powerSourceObserver) }
    }

    private func applyPowerProfile() {
        let tier = PowerProfile.currentTier()
        preferredFramesPerSecond = PowerProfile.framesPerSecond(for: tier)
    }
}
