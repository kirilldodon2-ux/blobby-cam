import AppKit
import MetalKit

@MainActor
final class FeatureRenderView: MTKView, MTKViewDelegate {
    let windowID: WindowInstanceID
    var featureID: FeatureID { windowID.featureID }
    private weak var renderer: SharedRenderer?

    override var isOpaque: Bool { false }

    init(featureID: FeatureID, renderer: SharedRenderer, device: MTLDevice) {
        self.windowID = WindowInstanceID(featureID: featureID, serial: 1)
        self.renderer = renderer
        super.init(frame: .zero, device: device)

        configureView()
    }

    init(windowID: WindowInstanceID, renderer: SharedRenderer, device: MTLDevice) {
        self.windowID = windowID
        self.renderer = renderer
        super.init(frame: .zero, device: device)

        configureView()
    }

    private func configureView() {
        delegate = self
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        enableSetNeedsDisplay = true
        isPaused = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        autoResizeDrawable = true
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        alphaValue = 0
    }

    func draw(in view: MTKView) {
        renderer?.draw(windowID, in: view)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Core Image fits each crop into the updated drawable size on the next invalidation.
    }

    required init(coder: NSCoder) {
        fatalError("FeatureRenderView does not support coder initialization")
    }
}
