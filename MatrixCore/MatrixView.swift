import MetalKit

public final class MatrixView: MTKView {
    public private(set) var renderer: MatrixRenderer?

    public override init(frame: CGRect, device: MTLDevice?) {
        let resolvedDevice = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frame, device: resolvedDevice)
        configureDefaults()
    }

    public required init(coder: NSCoder) {
        super.init(coder: coder)
        configureDefaults()
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
    }
}
