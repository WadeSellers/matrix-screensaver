import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

public final class MatrixRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let glyphAtlas: GlyphAtlas

    private var grid: GridLayout = GridLayout(drawableSize: CGSize(width: 1, height: 1))
    private var columnBuffer: MTLBuffer?
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
              let fragmentFn = library.makeFunction(name: "fragment_columns") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.pipelineState = pipeline
        super.init()

        // Seed with a default grid so columnBuffer is non-nil before the first
        // drawableSizeWillChange callback. Without this, the first draw() can
        // create an MTLRenderCommandEncoder and bail before endEncoding(),
        // which Metal aborts on.
        rebuildColumnBuffer()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        grid = GridLayout(drawableSize: size)
        rebuildColumnBuffer()
    }

    private func rebuildColumnBuffer() {
        let count = grid.columnCount
        guard count > 0 else { return }
        var states: [ColumnState] = []
        states.reserveCapacity(count)
        for col in 0..<count {
            let speed = Float.random(in: 8...22)
            let head = Float.random(in: -20...0)
            let seed = UInt32(col) &* 2654435761
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

    public func draw(in view: MTKView) {
        // Self-heal grid sizing: drawableSizeWillChange only fires when the
        // size *changes*, so a view created at its final size never triggers
        // it. Sync from view.drawableSize on every frame; the work is cheap
        // when the size already matches.
        let actualSize = view.drawableSize
        if actualSize.width > 0, actualSize.height > 0,
           abs(grid.viewportSize.width - actualSize.width) > 0.5
            || abs(grid.viewportSize.height - actualSize.height) > 0.5 {
            grid = GridLayout(drawableSize: actualSize)
            rebuildColumnBuffer()
        }

        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastFrameTime, 0.1))
        lastFrameTime = now

        advance(deltaTime: dt)

        // Order matters: validate everything that doesn't allocate Metal
        // resources first. Creating an encoder and then bailing without
        // endEncoding() causes Metal to abort the process.
        guard let columnBuffer,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = commandQueue.makeCommandBuffer() else {
            return
        }
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
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

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<GridUniforms>.stride,
            index: 0
        )
        encoder.setFragmentBuffer(columnBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(glyphAtlas.texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private func advance(deltaTime: Float) {
        guard let columnBuffer else { return }
        let count = grid.columnCount
        // Conservative ceiling: per-column trailLength is up to 20 (set in
        // shader as 12 + seed % 9). Reset once head clears the longest
        // possible trail.
        let maxTrailLength: Float = 20
        let states = columnBuffer.contents().bindMemory(
            to: ColumnState.self,
            capacity: count
        )
        for i in 0..<count {
            states[i].frameCounter &+= 1
            states[i].headRow += states[i].speed * deltaTime
            if states[i].headRow > Float(grid.rowCount) + maxTrailLength {
                states[i].headRow = -Float.random(in: 0...12)
                states[i].speed = Float.random(in: 8...22)
                // New seed on each cycle so trail length, stammer flag, and
                // glyph pattern all differ between this column's reincarnations.
                states[i].seed = UInt32.random(in: 1...UInt32.max)
            }
        }
    }
}
