import Cocoa
import ScreenSaver
import Metal
import MatrixCore

@objc(MatrixSaverView)
public final class MatrixSaverView: ScreenSaverView {
    private static let moduleName = "com.wadesellers.MatrixSaver"

    private var matrixView: MatrixView?
    private var configSheet: ConfigSheet?
    private var settings: MatrixSettings

    public override init?(frame: NSRect, isPreview: Bool) {
        let defaults = ScreenSaverDefaults(forModuleWithName: Self.moduleName)
        self.settings = defaults.map(MatrixSettings.init(loadedFrom:)) ?? .defaults
        super.init(frame: frame, isPreview: isPreview)
        // Renderer setup is deferred to viewDidMoveToWindow so we can
        // inspect the actual window state and skip phantom instances —
        // see the comment on viewDidMoveToWindow.
        registerLifecycleObservers()
    }

    public required init?(coder: NSCoder) {
        let defaults = ScreenSaverDefaults(forModuleWithName: Self.moduleName)
        self.settings = defaults.map(MatrixSettings.init(loadedFrom:)) ?? .defaults
        super.init(coder: coder)
        registerLifecycleObservers()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard matrixView == nil, let win = window else { return }

        // Ghost-instance detection (Tahoe 26.3-aware version).
        //
        // legacyScreenSaver on Sequoia/Tahoe creates 2-3 ScreenSaverView
        // instances per activation. The init? frame is the same for all of
        // them (matches some NSScreen size), so we can't filter by init
        // frame alone. The phantoms reveal themselves only after they're
        // mounted in a window: the framework gives the phantom a 0x0 window
        // or a window whose .screen is nil. macOS then picks one of the
        // sibling windows as the visible one for the screen — sometimes the
        // real one, sometimes a phantom. When it picks a phantom we see a
        // black screen even though our renderer is humming on a hidden one.
        //
        // The fix: defer the expensive setup (Metal device, glyph atlas,
        // renderer, command queue) until we get viewDidMoveToWindow with a
        // legitimate window, and skip it entirely for the phantoms. Yields
        // the visible-window slot to the real instance.
        let f = win.frame
        let isPhantom = f.size.width < 1 || f.size.height < 1 || win.screen == nil
        if isPhantom { return }

        setupMatrixView()
    }

    public override var animationTimeInterval: TimeInterval {
        get { 1.0 / 60.0 }
        set { /* Metal drives itself via MTKView's display link */ }
    }

    public override func animateOneFrame() {
        // Intentionally empty: MTKView pushes frames itself.
    }

    public override func startAnimation() {
        super.startAnimation()
        matrixView?.isPaused = false
    }

    public override func stopAnimation() {
        matrixView?.isPaused = true
        super.stopAnimation()
    }

    public override var hasConfigureSheet: Bool { true }

    public override var configureSheet: NSWindow? {
        let defaults = ScreenSaverDefaults(forModuleWithName: Self.moduleName)
        let sheet = ConfigSheet(saverView: self, current: settings, defaults: defaults)
        self.configSheet = sheet
        return sheet.window
    }

    /// Applies a settings change to the live renderer without persisting.
    /// Called by the config sheet on every control change so the user sees
    /// immediate feedback.
    func applyLiveSettings(_ mutate: (inout MatrixSettings) -> Void) {
        mutate(&settings)
        matrixView?.renderer?.settings = settings
    }

    /// Persists the current settings to ScreenSaverDefaults.
    func persistSettings(_ defaults: UserDefaults?) {
        guard let defaults else { return }
        settings.save(to: defaults)
        defaults.synchronize()
    }

    private func setupMatrixView() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let view = MatrixView(frame: bounds, device: device)
        view.autoresizingMask = [.width, .height]
        view.renderer?.settings = settings
        addSubview(view)
        matrixView = view
    }

    private func registerLifecycleObservers() {
        // willstop is the canonical "screensaver is being torn down" signal.
        // We pause our renderer immediately (so we don't push frames into a
        // drawable that's about to be invalidated) and then exit the process
        // after a 2-second delay.
        //
        // The 2-second delay is critical and was hard-won by Aerial's
        // maintainer (see github.com/JohnCoates/Aerial/issues/1396):
        //   - Immediate exit(0) makes legacyScreenSaver relaunch us when the
        //     user re-triggers the screensaver, producing the every-other-
        //     activation-black symptom.
        //   - Skipping exit(0) entirely lets ScreenSaverView instances
        //     accumulate across activations / sleep cycles.
        //   - 2.0s is long enough that the framework finishes its own
        //     teardown before we exit, but short enough that the user
        //     doesn't notice the lingering process.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screensaver.willstop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.matrixView?.isPaused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                exit(0)
            }
        }

        // System sleep — also exit(0). Without this, ScreenSaverView
        // instances stack across each sleep/wake cycle and contribute to the
        // ghost-instance pile-up. Aerial does the same.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            exit(0)
        }
    }
}
