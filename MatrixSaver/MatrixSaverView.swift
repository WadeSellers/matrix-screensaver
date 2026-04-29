import Cocoa
import ScreenSaver
import Metal
import MatrixCore

@objc(MatrixSaverView)
public final class MatrixSaverView: ScreenSaverView {
    private var matrixView: MatrixView?

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setupMatrixView()
        registerLifecycleObservers()
    }

    public required init?(coder: NSCoder) {
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

    private func setupMatrixView() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let view = MatrixView(frame: bounds, device: device)
        view.autoresizingMask = [.width, .height]
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
