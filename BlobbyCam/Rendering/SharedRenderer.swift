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
        let crops: [WindowInstanceID: FeatureCrop]
        let opacities: [WindowInstanceID: CGFloat]
    }

    let device: MTLDevice
    private let cropRenderer: CoreImageCropRenderer
    private let syphonOutput: SyphonOutput
    private var syphonConfigurations: [WindowInstanceID: FeatureConfiguration] = [:]
    private var renderState: RenderState?
    private var latestTimestamp: CMTime?
    private var renderViews: [WindowInstanceID: WeakRenderView] = [:]

    /// Returns nil when the system has no Metal device or command queue.
    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let cropRenderer = CoreImageCropRenderer(device: device) else { return nil }
        self.device = device
        self.cropRenderer = cropRenderer
        syphonOutput = SyphonOutput(renderer: cropRenderer)
    }

    var syphonEnabled: Bool { syphonOutput.isEnabled }
    var syphonStreamCount: Int { syphonOutput.streamCount }

    func configureSyphon(enabled: Bool, configurations: [WindowInstanceID: FeatureConfiguration]) {
        guard syphonOutput.isEnabled != enabled || syphonConfigurations != configurations else { return }
        syphonConfigurations = configurations
        syphonOutput.configure(enabled: enabled, configurations: configurations)
        publishSyphon()
    }

    private func publishSyphon() {
        guard syphonOutput.isEnabled else { return }
        let crops = renderState?.crops ?? [:]
        syphonOutput.publish(images: crops.mapValues(\.image), frames: crops.mapValues(\.frame), opacities: renderState?.opacities ?? [:])
    }

    func stopSyphon() { syphonOutput.stop() }

    func makeRenderView(for featureID: FeatureID) -> FeatureRenderView {
        // Compatibility entry point for the original single-window-per-feature path.
        makeRenderView(for: WindowInstanceID(featureID: featureID, serial: 1))
    }

    func makeRenderView(for windowID: WindowInstanceID) -> FeatureRenderView {
        let view = FeatureRenderView(windowID: windowID, renderer: self, device: device)
        renderViews[windowID] = WeakRenderView(view)
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
        let instanceConfigurations = Dictionary(uniqueKeysWithValues: configurations.map { featureID, configuration in
            (WindowInstanceID(featureID: featureID, serial: 1), configuration)
        })
        let instanceStates = Dictionary(uniqueKeysWithValues: featureStates.map { featureID, state in
            (WindowInstanceID(featureID: featureID, serial: 1), state)
        })
        update(
            frame: frame,
            featureStates: instanceStates,
            configurations: instanceConfigurations,
            requestedMirror: requestedMirror,
            autoCropScale: autoCropScale
        )
    }

    /// Compatibility path for instance configurations paired with one shared feature state.
    /// Runtime copy handling uses the per-instance overload below.
    func update(
        frame: CameraFrame,
        featureStates: [FeatureID: SmoothedFeatureState],
        configurations: [WindowInstanceID: FeatureConfiguration],
        requestedMirror: Bool,
        autoCropScale: Bool = false
    ) {
        let instanceStates = Dictionary(uniqueKeysWithValues: configurations.keys.map { id in
            (id, featureStates[id.featureID] ?? Self.hiddenState)
        })
        update(
            frame: frame,
            featureStates: instanceStates,
            configurations: configurations,
            requestedMirror: requestedMirror,
            autoCropScale: autoCropScale
        )
    }

    /// Builds one lazy crop graph for each configured window instance while sharing a single
    /// CIImage wrapper and the same feature detection across all copies of that feature.
    func update(
        frame: CameraFrame,
        featureStates: [WindowInstanceID: SmoothedFeatureState],
        configurations: [WindowInstanceID: FeatureConfiguration],
        requestedMirror: Bool,
        autoCropScale: Bool = false
    ) {
        guard frame.timestamp.isValid else { return }
        if let latestTimestamp, CMTimeCompare(frame.timestamp, latestTimestamp) < 0 { return }
        latestTimestamp = frame.timestamp
        let sourceImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let pixelSize = CGSize(width: CVPixelBufferGetWidth(frame.pixelBuffer), height: CVPixelBufferGetHeight(frame.pixelBuffer))
        var crops: [WindowInstanceID: FeatureCrop] = [:]
        var opacities: [WindowInstanceID: CGFloat] = [:]

        for (windowID, configuration) in configurations {
            guard configuration.isEnabled else { continue }
            if configuration.isFrozen, let previous = renderState?.crops[windowID] {
                crops[windowID] = previous
                opacities[windowID] = 1
                continue
            }
            guard
                  let state = featureStates[windowID], state.fadeOpacity > 0,
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
            crops[windowID] = FeatureCrop(frame: frame, image: featureImage)
            opacities[windowID] = state.fadeOpacity
        }

        renderState = RenderState(crops: crops, opacities: opacities)
        publishSyphon()
        discardReleasedViews()
        for (windowID, weakView) in renderViews {
            guard let view = weakView.value else { continue }
            view.alphaValue = Double(opacities[windowID] ?? 0)
            view.setNeedsDisplay(view.bounds)
        }
    }

    func clear() {
        renderState = nil
        latestTimestamp = nil
        publishSyphon()
        discardReleasedViews()
        for weakView in renderViews.values {
            guard let view = weakView.value else { continue }
            view.alphaValue = 0
            view.setNeedsDisplay(view.bounds)
        }
    }

    func retainFrozen(configurations: [FeatureID: FeatureConfiguration]) {
        // Compatibility entry point for the original single-window-per-feature path.
        let instanceConfigurations = Dictionary(uniqueKeysWithValues: configurations.map { featureID, configuration in
            (WindowInstanceID(featureID: featureID, serial: 1), configuration)
        })
        retainFrozen(configurations: instanceConfigurations)
    }

    func retainFrozen(configurations: [WindowInstanceID: FeatureConfiguration]) {
        latestTimestamp = nil
        let retained = renderState?.crops.filter { id, _ in
            configurations[id]?.isEnabled == true && configurations[id]?.isFrozen == true
        } ?? [:]
        renderState = RenderState(
            crops: retained,
            opacities: Dictionary(uniqueKeysWithValues: retained.keys.map { ($0, CGFloat(1)) })
        )
        publishSyphon()
        for (windowID, weakView) in renderViews {
            guard let view = weakView.value else { continue }
            view.alphaValue = retained[windowID] == nil ? 0 : 1
            view.setNeedsDisplay(view.bounds)
        }
    }

    func hasFrame(for featureID: FeatureID) -> Bool {
        hasFrame(for: WindowInstanceID(featureID: featureID, serial: 1))
    }

    func hasFrame(for windowID: WindowInstanceID) -> Bool {
        renderState?.crops[windowID] != nil
    }

    func renderedTimestamp(for featureID: FeatureID) -> CMTime? {
        renderedTimestamp(for: WindowInstanceID(featureID: featureID, serial: 1))
    }

    func renderedTimestamp(for windowID: WindowInstanceID) -> CMTime? {
        renderState?.crops[windowID]?.frame.timestamp
    }

    func draw(_ featureID: FeatureID, in view: MTKView) {
        draw(WindowInstanceID(featureID: featureID, serial: 1), in: view)
    }

    private static let hiddenState = SmoothedFeatureState(
        detection: nil,
        lifecycle: .hidden,
        fadeOpacity: 0
    )

    func draw(_ windowID: WindowInstanceID, in view: MTKView) {
        guard let state = renderState,
              let crop = state.crops[windowID]
        else {
            clearDrawable(in: view)
            return
        }
        cropRenderer.draw(crop.image, retaining: crop.frame, in: view)
    }

    private func discardReleasedViews() {
        renderViews = renderViews.filter { $0.value.value != nil }
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
