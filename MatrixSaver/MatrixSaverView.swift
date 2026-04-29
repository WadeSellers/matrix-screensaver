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
        setupMatrixView()
        registerLifecycleObservers()
    }

    public required init?(coder: NSCoder) {
        let defaults = ScreenSaverDefaults(forModuleWithName: Self.moduleName)
        self.settings = defaults.map(MatrixSettings.init(loadedFrom:)) ?? .defaults
        super.init(coder: coder)
        setupMatrixView()
        registerLifecycleObservers()
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
        // Sonoma+ stopped reliably calling stopAnimation() before tearing the
        // screensaver down; this distributed notification is the actual signal.
        // The block API retains the observer; we don't need to keep a handle.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screensaver.willstop"),
            object: nil,
            queue: .main
        ) { _ in
            exit(0)
        }
    }
}
