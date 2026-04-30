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
        settings: MatrixSettings,
        viewportSize: CGSize,
        loadAction: MTLLoadAction = .dontCare
    ) {
        guard let bloomA, let bloomB else { return }

        // If bloom is disabled, skip the bloom passes and use a black bloom
        // texture in the composite. (We still use the composite shader so
        // CRT effects can apply uniformly.)
        if settings.bloomEnabled {
            encodeFullscreen(
                commandBuffer: commandBuffer,
                pipeline: extractPipeline,
                destination: bloomA
            ) { encoder in
                encoder.setFragmentTexture(sceneTexture, index: 0)
            }

            var blurU = blurUniforms(forSize: bloomSize)
            encodeFullscreen(
                commandBuffer: commandBuffer,
                pipeline: blurHPipeline,
                destination: bloomB
            ) { encoder in
                encoder.setFragmentBytes(
                    &blurU,
                    length: MemoryLayout<BlurUniforms>.stride,
                    index: 0
                )
                encoder.setFragmentTexture(bloomA, index: 0)
            }

            encodeFullscreen(
                commandBuffer: commandBuffer,
                pipeline: blurVPipeline,
                destination: bloomA
            ) { encoder in
                encoder.setFragmentBytes(
                    &blurU,
                    length: MemoryLayout<BlurUniforms>.stride,
                    index: 0
                )
                encoder.setFragmentTexture(bloomB, index: 0)
            }
        } else {
            // Clear bloomA to black so the composite gets nothing from it.
            let clearPass = MTLRenderPassDescriptor()
            clearPass.colorAttachments[0].texture = bloomA
            clearPass.colorAttachments[0].loadAction = .clear
            clearPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            clearPass.colorAttachments[0].storeAction = .store
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: clearPass) {
                enc.endEncoding()
            }
        }

        var compU = CompositeUniforms(
            // Cranked up from the original "subtle" values so the
            // difference between on/off is obviously visible — the user
            // shouldn't have to squint to confirm a toggle worked.
            //   bloomStrength:   0.85 → 1.20 (head halos visibly bigger)
            //   scanlineDarken:  0.30 → 0.45 (scanlines clearly visible)
            //   vignetteAmount:  0.55 → 0.70 (corner falloff prominent)
            bloomStrength: settings.bloomEnabled ? 1.20 : 0,
            crtEnabled: settings.crtEnabled ? 1 : 0,
            scanlineDarken: 0.45,
            vignetteAmount: 0.70,
            viewportSize: SIMD2<Float>(
                Float(viewportSize.width),
                Float(viewportSize.height)
            ),
            pad: SIMD2<Float>(0, 0)
        )

        encodeFullscreen(
            commandBuffer: commandBuffer,
            pipeline: compositePipeline,
            destination: target,
            loadAction: loadAction
        ) { encoder in
            encoder.setFragmentBytes(
                &compU,
                length: MemoryLayout<CompositeUniforms>.stride,
                index: 0
            )
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

private struct CompositeUniforms {
    var bloomStrength: Float
    var crtEnabled: Float
    var scanlineDarken: Float
    var vignetteAmount: Float
    var viewportSize: SIMD2<Float>
    var pad: SIMD2<Float>
}
