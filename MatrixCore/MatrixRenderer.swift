import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

/// Must exactly mirror the `ColorUniforms` struct in Shaders.metal.
/// Each SIMD4<Float> is 16 bytes, matching Metal's float4 alignment.
private struct ColorUniforms {
    var headColor:      SIMD4<Float>
    var nearTrailColor: SIMD4<Float>
    var midTrailColor:  SIMD4<Float>
    var farTrailColor:  SIMD4<Float>

    init(theme: MatrixTheme) {
        headColor      = theme.headColor
        nearTrailColor = theme.nearTrailColor
        midTrailColor  = theme.midTrailColor
        farTrailColor  = theme.farTrailColor
    }
}

public final class MatrixRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let columnPipeline: MTLRenderPipelineState
    private let glyphAtlas: GlyphAtlas
    private let bloomPipeline: BloomPipeline

    public var settings: MatrixSettings = .defaults

    private var grid: GridLayout = GridLayout(drawableSize: CGSize(width: 1, height: 1))
    private var columnBuffer: MTLBuffer?
    private var sceneTexture: MTLTexture?
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()

    public init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        guard let atlas = GlyphAtlas(device: device) else { return nil }
        self.device = device
        self.commandQueue = queue
        self.glyphAtlas = atlas

        let bundle = Bundle(for: MatrixRenderer.self)
        guard let library = try? device.makeDefaultLibrary(bundle: bundle),
              let vertexFn = library.makeFunction(name: "vertex_fullscreen"),
              let columnFn = library.makeFunction(name: "fragment_columns") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = columnFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb

        guard let columnPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.columnPipeline = columnPipeline

        guard let bloom = BloomPipeline(
            device: device,
            library: library,
            pixelFormat: .bgra8Unorm_srgb
        ) else { return nil }
        self.bloomPipeline = bloom

        super.init()

        // Seed with a default grid so columnBuffer is non-nil before the first
        // drawableSizeWillChange callback. Without this, the first draw() can
        // create an MTLRenderCommandEncoder and bail before endEncoding(),
        // which Metal aborts on.
        rebuildColumnBuffer()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        applyDrawableSize(size)
    }

    // MTKView delegate path — used by SaverTest. Just defers to the shared
    // implementation below.
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        renderFrame(into: drawable, drawableSize: view.drawableSize)
    }

    /// Render one frame into the given drawable. Both the MTKView delegate
    /// (SaverTest) and the layer-hosting path (MatrixSaver) call this.
    public func renderFrame(into drawable: CAMetalDrawable, drawableSize: CGSize) {
        // Self-heal grid sizing — cheap when sizes already match.
        if drawableSize.width > 0, drawableSize.height > 0,
           abs(grid.viewportSize.width - drawableSize.width) > 0.5
            || abs(grid.viewportSize.height - drawableSize.height) > 0.5 {
            applyDrawableSize(drawableSize)
        }

        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastFrameTime, 0.1))
        lastFrameTime = now

        advance(deltaTime: dt)

        guard let columnBuffer,
              let sceneTexture,
              let buffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // ---- Pass 1: render columns to sceneTexture ----
        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = sceneTexture
        scenePass.colorAttachments[0].loadAction = .clear
        scenePass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        scenePass.colorAttachments[0].storeAction = .store

        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: scenePass) else {
            return
        }

        var uniforms = GridUniforms(
            columnCount: UInt32(grid.columnCount),
            rowCount: UInt32(grid.rowCount),
            cellSize: Float(grid.cellSize),
            aspectFix: 1.0,
            viewportSize: SIMD2<Float>(
                Float(grid.viewportSize.width),
                Float(grid.viewportSize.height)
            ),
            glyphCount: UInt32(glyphAtlas.glyphCount),
            cellsPerRow: UInt32(glyphAtlas.cellsPerRow)
        )

        var colorUniforms = ColorUniforms(theme: settings.theme)

        encoder.setRenderPipelineState(columnPipeline)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<GridUniforms>.stride,
            index: 0
        )
        encoder.setFragmentBuffer(columnBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(
            &colorUniforms,
            length: MemoryLayout<ColorUniforms>.stride,
            index: 2
        )
        encoder.setFragmentTexture(glyphAtlas.texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        // ---- Pass 2-5: bloom + composite to drawable ----
        bloomPipeline.encode(
            commandBuffer: buffer,
            sceneTexture: sceneTexture,
            target: drawable.texture,
            settings: settings,
            viewportSize: drawableSize
        )

        buffer.present(drawable)
        buffer.commit()
    }

    private func applyDrawableSize(_ size: CGSize) {
        grid = GridLayout(drawableSize: size)
        rebuildColumnBuffer()
        ensureSceneTexture(size: size)
        bloomPipeline.resize(to: size)
    }

    private func ensureSceneTexture(size: CGSize) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: max(1, Int(size.width)),
            height: max(1, Int(size.height)),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        sceneTexture = device.makeTexture(descriptor: descriptor)
    }

    private func rebuildColumnBuffer() {
        let count = grid.columnCount
        guard count > 0 else { return }
        var states: [ColumnState] = []
        states.reserveCapacity(count)
        for col in 0..<count {
            let speed = Float.random(in: 8...22)
            let head = Float.random(in: -20...0)
            let seed = UInt32.random(in: 1...UInt32.max)
            _ = col
            states.append(ColumnState(
                headRow: head,
                speed: speed,
                frameCounter: 0,
                seed: seed
            ))
        }
        let length = MemoryLayout<ColumnState>.stride * count
        columnBuffer = device.makeBuffer(
            bytes: states,
            length: length,
            options: .storageModeShared
        )
    }

    private func advance(deltaTime: Float) {
        guard let columnBuffer else { return }
        let count = grid.columnCount
        let maxTrailLength: Float = 20
        let states = columnBuffer.contents().bindMemory(
            to: ColumnState.self,
            capacity: count
        )
        let speedScale = settings.speedMultiplier
        for i in 0..<count {
            states[i].frameCounter &+= 1
            states[i].headRow += states[i].speed * deltaTime * speedScale
            if states[i].headRow > Float(grid.rowCount) + maxTrailLength {
                states[i].headRow = -Float.random(in: 0...12)
                states[i].speed = Float.random(in: 8...22)
                states[i].seed = UInt32.random(in: 1...UInt32.max)
            }
        }
    }
}
