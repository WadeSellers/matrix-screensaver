import Foundation
import Metal
import MetalKit
import simd

public final class BloomPipeline {
    public let device: MTLDevice

    private let extractPipeline: MTLRenderPipelineState
    private let blurHPipeline: MTLRenderPipelineState
    private let blurVPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState

    private var bloomA: MTLTexture?
    private var bloomB: MTLTexture?
    private var bloomSize: CGSize = .zero

    public init?(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat) {
        self.device = device

        guard
            let vertexFn = library.makeFunction(name: "vertex_fullscreen"),
            let extractFn = library.makeFunction(name: "fragment_bloom_extract"),
            let blurHFn = library.makeFunction(name: "fragment_bloom_blur_h"),
            let blurVFn = library.makeFunction(name: "fragment_bloom_blur_v"),
            let compositeFn = library.makeFunction(name: "fragment_bloom_composite")
        else { return nil }

        func make(_ frag: MTLFunction, _ format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = vertexFn
            d.fragmentFunction = frag
            d.colorAttachments[0].pixelFormat = format
            return try device.makeRenderPipelineState(descriptor: d)
        }

        do {
            self.extractPipeline = try make(extractFn, pixelFormat)
            self.blurHPipeline = try make(blurHFn, pixelFormat)
            self.blurVPipeline = try make(blurVFn, pixelFormat)
            self.compositePipeline = try make(compositeFn, pixelFormat)
        } catch {
            return nil
        }
    }

    public func resize(to fullSize: CGSize) {
        let halfSize = CGSize(
            width: max(2, floor(fullSize.width / 2)),
            height: max(2, floor(fullSize.height / 2))
        )
        if halfSize == bloomSize { return }
        bloomSize = halfSize

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: Int(halfSize.width),
            height: Int(halfSize.height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        bloomA = device.makeTexture(descriptor: descriptor)
        bloomB = device.makeTexture(descriptor: descriptor)
    }

    public func encode(
        commandBuffer: MTLCommandBuffer,
        sceneTexture: MTLTexture,
        target: MTLTexture,
        loadAction: MTLLoadAction = .dontCare
    ) {
        guard let bloomA, let bloomB else { return }

        // 1. Extract: scene → bloomA (half-res, only pixels above threshold).
        encodeFullscreen(
            commandBuffer: commandBuffer,
            pipeline: extractPipeline,
            destination: bloomA
        ) { encoder in
            encoder.setFragmentTexture(sceneTexture, index: 0)
        }

        // 2. Horizontal blur: bloomA → bloomB.
        var blurUniforms = blurUniforms(forSize: bloomSize)
        encodeFullscreen(
            commandBuffer: commandBuffer,
            pipeline: blurHPipeline,
            destination: bloomB
        ) { encoder in
            encoder.setFragmentBytes(
                &blurUniforms,
                length: MemoryLayout<BlurUniforms>.stride,
                index: 0
            )
            encoder.setFragmentTexture(bloomA, index: 0)
        }

        // 3. Vertical blur: bloomB → bloomA.
        encodeFullscreen(
            commandBuffer: commandBuffer,
            pipeline: blurVPipeline,
            destination: bloomA
        ) { encoder in
            encoder.setFragmentBytes(
                &blurUniforms,
                length: MemoryLayout<BlurUniforms>.stride,
                index: 0
            )
            encoder.setFragmentTexture(bloomB, index: 0)
        }

        // 4. Composite: scene + bloom → target (drawable).
        encodeFullscreen(
            commandBuffer: commandBuffer,
            pipeline: compositePipeline,
            destination: target,
            loadAction: loadAction
        ) { encoder in
            encoder.setFragmentTexture(sceneTexture, index: 0)
            encoder.setFragmentTexture(bloomA, index: 1)
        }
    }

    private func blurUniforms(forSize size: CGSize) -> BlurUniforms {
        BlurUniforms(
            texelSize: SIMD2<Float>(
                Float(1.0 / max(size.width, 1)),
                Float(1.0 / max(size.height, 1))
            ),
            pad: SIMD2<Float>(0, 0)
        )
    }

    private func encodeFullscreen(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLRenderPipelineState,
        destination: MTLTexture,
        loadAction: MTLLoadAction = .dontCare,
        configure: (MTLRenderCommandEncoder) -> Void
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = loadAction
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }
        encoder.setRenderPipelineState(pipeline)
        configure(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

private struct BlurUniforms {
    var texelSize: SIMD2<Float>
    var pad: SIMD2<Float>
}
