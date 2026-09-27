import CoreImage
import CoreMedia
import CoreVideo
import ImageIO
import Metal
import MetalKit

@MainActor
final class SharedRenderer {
    private struct FeatureCrop {
        let frame: CameraFrame
        let image: CIImage
    }

    private struct RenderState {
        let crops: [FeatureID: FeatureCrop]
        let opacities: [FeatureID: CGFloat]
    }

    let device: MTLDevice
    private let cropRenderer: CoreImageCropRenderer
    private var renderState: RenderState?
    private var latestTimestamp: CMTime?
    private var renderViews: [FeatureID: WeakRenderView] = [:]

    /// Returns nil when the system has no Metal device or command queue.
    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let cropRenderer = CoreImageCropRenderer(device: device) else { return nil }
        self.device = device
        self.cropRenderer = cropRenderer
    }

    func makeRenderView(for featureID: FeatureID) -> FeatureRenderView {
        let view = FeatureRenderView(featureID: featureID, renderer: self, device: device)
        renderViews[featureID] = WeakRenderView(view)
        return view
    }

    /// Stores one CIImage wrapper for the current CVPixelBuffer and builds lazy crop graphs that
    /// all refer to that same source. No per-feature pixel buffers or encoded images are created.
    func update(
        frame: CameraFrame,
        featureStates: [FeatureID: SmoothedFeatureState],
        configurations: [FeatureID: FeatureConfiguration],
        requestedMirror: Bool,
        autoCropScale: Bool = false
    ) {
        guard frame.timestamp.isValid else { return }
        if let latestTimestamp, CMTimeCompare(frame.timestamp, latestTimestamp) < 0 { return }
        latestTimestamp = frame.timestamp
        let sourceImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let pixelSize = CGSize(width: CVPixelBufferGetWidth(frame.pixelBuffer), height: CVPixelBufferGetHeight(frame.pixelBuffer))
        var crops: [FeatureID: FeatureCrop] = [:]
        var opacities: [FeatureID: CGFloat] = [:]

        for featureID in FeatureID.allCases {
            guard let configuration = configurations[featureID], configuration.isEnabled else { continue }
            if configuration.isFrozen, let previous = renderState?.crops[featureID] {
                crops[featureID] = previous
                opacities[featureID] = 1
                continue
            }
            guard
                  let state = featureStates[featureID], state.fadeOpacity > 0,
                  let detection = state.detection,
                  let pixelCrop = CoreImageCropRenderer.sourcePixelCrop(
                    for: detection,
                    configuration: configuration,
                    sourcePixelSize: pixelSize,
                    orientation: frame.orientation,
                    autoScale: autoCropScale
                  ),
                  let featureImage = cropRenderer.makeFeatureImage(
                    from: sourceImage,
                    pixelCrop: pixelCrop,
                    orientation: frame.orientation,
                    additionalMirror: ScreenMapper.requiresAdditionalMirror(
                        sourceIsMirrored: frame.isMirrored,
                        requestedMirror: requestedMirror
                    )
                  )
            else { continue }
            crops[featureID] = FeatureCrop(frame: frame, image: featureImage)
            opacities[featureID] = state.fadeOpacity
        }

        renderState = RenderState(crops: crops, opacities: opacities)
        for featureID in FeatureID.allCases {
            guard let view = renderViews[featureID]?.value else { continue }
            view.alphaValue = Double(opacities[featureID] ?? 0)
            view.setNeedsDisplay(view.bounds)
        }
    }

    func clear() {
        renderState = nil
        latestTimestamp = nil
        for weakView in renderViews.values {
            guard let view = weakView.value else { continue }
            view.alphaValue = 0
            view.setNeedsDisplay(view.bounds)
        }
    }

    func retainFrozen(configurations: [FeatureID: FeatureConfiguration]) {
        latestTimestamp = nil
        let retained = renderState?.crops.filter { id, _ in
            configurations[id]?.isEnabled == true && configurations[id]?.isFrozen == true
        } ?? [:]
        renderState = RenderState(
            crops: retained,
            opacities: Dictionary(uniqueKeysWithValues: retained.keys.map { ($0, CGFloat(1)) })
        )
        for (id, weakView) in renderViews {
            guard let view = weakView.value else { continue }
            view.alphaValue = retained[id] == nil ? 0 : 1
            view.setNeedsDisplay(view.bounds)
        }
    }

    func hasFrame(for featureID: FeatureID) -> Bool {
        renderState?.crops[featureID] != nil
    }

    func renderedTimestamp(for featureID: FeatureID) -> CMTime? {
        renderState?.crops[featureID]?.frame.timestamp
    }

    func draw(_ featureID: FeatureID, in view: MTKView) {
        guard let state = renderState,
              let crop = state.crops[featureID]
        else {
            clearDrawable(in: view)
            return
        }
        cropRenderer.draw(crop.image, retaining: crop.frame, in: view)
    }

    private func clearDrawable(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPass = view.currentRenderPassDescriptor,
              let commandBuffer = cropRenderer.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
        else { return }
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = view.clearColor
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

@MainActor
private final class WeakRenderView {
    weak var value: FeatureRenderView?
    init(_ value: FeatureRenderView) { self.value = value }
}
