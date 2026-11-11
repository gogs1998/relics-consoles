import CoreKit
import MetalKit
import SwiftUI

enum ScreenMode: String, CaseIterable, Identifiable, Sendable {
    case auto, sharp, integer, scanlines, lcd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .sharp: "Sharp"
        case .integer: "Pixel-perfect"
        case .scanlines: "Scanlines"
        case .lcd: "LCD"
        }
    }

    var symbol: String {
        switch self {
        case .auto: "wand.and.stars"
        case .sharp: "square.grid.3x3.fill"
        case .integer: "square.grid.4x3.fill"
        case .scanlines: "line.3.horizontal"
        case .lcd: "rectangle.split.3x3"
        }
    }
}

/// Where the game goes inside a box, for a given mode.
enum ScreenFit {
    /// Returns the game rect (centred in `box`) and whether it ended up integer-scaled.
    static func rect(video: CGSize, in box: CGSize, mode: ScreenMode, pixelAspect: Double = 1,
                     displayScale: CGFloat) -> (size: CGSize, integer: Bool) {
        guard video.width > 0, video.height > 0, box.width > 0, box.height > 0 else { return (.zero, false) }
        let vw = video.width * pixelAspect
        let vh = video.height
        let fit = min(box.width / vw, box.height / vh)
        // Integer multiples in *device pixels*, so 1x on a 3x display is 3 device pixels.
        let devFit = fit * displayScale
        let devInt = floor(devFit)
        let intScale = devInt / displayScale
        let integerOK = devInt >= 1 && pixelAspect == 1
        let useInteger: Bool
        switch mode {
        case .integer: useInteger = integerOK
        case .auto: useInteger = integerOK && intScale / fit >= 0.85
        default: useInteger = false
        }
        let s = useInteger ? intScale : fit
        return (CGSize(width: (vw * s).rounded(.down), height: (vh * s).rounded(.down)), useInteger)
    }
}

/// The game screen: an MTKView that uploads the newest frame and draws one quad.
struct GameScreen: UIViewRepresentable {
    let frames: FrameExchange
    var mode: ScreenMode
    var integer: Bool
    /// Show only this part of the frame (one of a multi-screen system's screens); nil = all of it.
    var crop: ScreenRegion?

    func makeCoordinator() -> Renderer { Renderer(frames: frames) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        view.isOpaque = true
        view.framebufferOnly = true
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Game screen"
        context.coordinator.update(mode: mode, integer: integer, crop: crop)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(mode: mode, integer: integer, crop: crop)
    }

    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        let device: MTLDevice?
        private let queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var texture: MTLTexture?
        private let frames: FrameExchange
        private var lastSequence: UInt64 = .max
        private var shaderMode: Int32 = 0
        private var crop: ScreenRegion?

        init(frames: FrameExchange) {
            self.frames = frames
            device = MTLCreateSystemDefaultDevice()
            queue = device?.makeCommandQueue()
            super.init()
            if let device, let library = device.makeDefaultLibrary() {
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = library.makeFunction(name: "screen_vertex")
                desc.fragmentFunction = library.makeFunction(name: "screen_fragment")
                desc.colorAttachments[0].pixelFormat = .bgra8Unorm
                pipeline = try? device.makeRenderPipelineState(descriptor: desc)
            }
        }

        func update(mode: ScreenMode, integer: Bool, crop newCrop: ScreenRegion?) {
            if newCrop != crop {
                crop = newCrop
                lastSequence = .max   // re-upload the current frame with the new crop
            }
            switch mode {
            case .scanlines: shaderMode = 2
            case .lcd: shaderMode = 3
            default: shaderMode = integer ? 1 : 0
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let device, let queue, let pipeline else { return }
            var tex = texture
            let crop = crop
            lastSequence = frames.withFrame(newerThan: lastSequence) { framePixels, frameW, frameH in
                var pixels = framePixels, w = frameW, h = frameH
                if let crop, crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0,
                   crop.x + crop.width <= frameW, crop.y + crop.height <= frameH {
                    pixels = framePixels + crop.y * frameW + crop.x
                    w = crop.width
                    h = crop.height
                }
                if tex == nil || tex!.width != w || tex!.height != h {
                    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h,
                                                                     mipmapped: false)
                    d.usage = .shaderRead
                    d.storageMode = .shared
                    tex = device.makeTexture(descriptor: d)
                }
                tex?.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixels,
                             bytesPerRow: frameW * 4)
            }
            texture = tex
            guard let texture, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let buffer = queue.makeCommandBuffer(),
                  let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            var params = Params(texSize: SIMD2(Float(texture.width), Float(texture.height)),
                                outSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                                mode: shaderMode)
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentTexture(texture, index: 0)
            enc.setFragmentBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }

    struct Params {
        var texSize: SIMD2<Float>
        var outSize: SIMD2<Float>
        var mode: Int32
    }
}
