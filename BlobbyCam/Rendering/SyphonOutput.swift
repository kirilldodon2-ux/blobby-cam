import AppKit
import CoreImage
import Metal
import Syphon

/// Optional output of existing feature crops. Camera, Vision, and local windows remain the owners
/// of their current work; this adapter owns only named Syphon servers and reusable output textures.
@MainActor
final class SyphonOutput {
    private struct Stream {
        let server: SyphonMetalServer
        var texture: MTLTexture?
    }

    private let renderer: CoreImageCropRenderer
    private var streams: [WindowInstanceID: Stream] = [:]
    private var configurations: [WindowInstanceID: FeatureConfiguration] = [:]
    private let inFlight = DispatchSemaphore(value: 2)
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private(set) var isEnabled = false
    private var refreshTimer: Timer?
    private var lastInputAt = Date.distantPast
    private var latestImages: [WindowInstanceID: CIImage] = [:]
    private var latestFrames: [WindowInstanceID: CameraFrame] = [:]
    private var latestOpacities: [WindowInstanceID: CGFloat] = [:]
    var streamCount: Int { streams.count }

    func serverDescription(for id: WindowInstanceID) -> [String: Any]? {
        streams[id]?.server.serverDescription.mapValues { $0 as Any }
    }

    init(renderer: CoreImageCropRenderer) { self.renderer = renderer }

    static func streamName(for id: WindowInstanceID) -> String {
        // Stable serials keep an existing receiver attached when a middle copy is removed.
        "Blobby / \(id.featureID.windowTitle) / \(id.serial)"
    }

    static func outputSize(for configuration: FeatureConfiguration) -> CGSize {
        let size = configuration.windowSizeOverride ?? CGSize(
            width: 240 * configuration.windowScale,
            height: 180 * configuration.windowScale
        )
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return CGSize(width: 480, height: 360)
        }
        let scale = min(2, 1024 / max(size.width, size.height))
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    func configure(enabled: Bool, configurations: [WindowInstanceID: FeatureConfiguration]) {
        isEnabled = enabled
        self.configurations = configurations
        let desired = enabled ? Set(configurations.filter { $0.value.isEnabled }.keys) : []
        for id in Array(streams.keys) where !desired.contains(id) {
            streams.removeValue(forKey: id)?.server.stop()
        }
        for id in desired where streams[id] == nil {
            let server = SyphonMetalServer(name: Self.streamName(for: id), device: renderer.device, options: nil)
            streams[id] = Stream(server: server)
        }
        if enabled, refreshTimer == nil {
            // A client can attach after LIVE stops or a feature freezes. Re-publish the held
            // frame while idle; ordinary live updates publish at the camera cadence.
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, Date().timeIntervalSince(self.lastInputAt) >= 0.1 else { return }
                    self.renderLatest()
                }
            }
        } else if !enabled {
            refreshTimer?.invalidate()
            refreshTimer = nil
            latestImages.removeAll()
            latestFrames.removeAll()
            latestOpacities.removeAll()
        }
    }

    /// Skip rather than queue frames if the GPU is behind. Disconnected streams allocate no texture.
    func publish(images: [WindowInstanceID: CIImage], frames: [WindowInstanceID: CameraFrame], opacities: [WindowInstanceID: CGFloat]) {
        guard isEnabled else { return }
        lastInputAt = Date()
        latestImages = images
        latestFrames = frames
        latestOpacities = opacities
        renderLatest()
    }

    private func renderLatest() {
        guard isEnabled, streams.values.contains(where: { $0.server.hasClients }),
              inFlight.wait(timeout: .now()) == .success else { return }
        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        for id in Array(streams.keys) {
            guard var stream = streams[id], stream.server.hasClients,
                  let configuration = configurations[id] else { continue }
            let size = Self.outputSize(for: configuration)
            let width = Int(size.width), height = Int(size.height)
            if stream.texture?.width != width || stream.texture?.height != height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
                descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
                descriptor.storageMode = .private
                stream.texture = renderer.device.makeTexture(descriptor: descriptor)
                streams[id] = stream
            }
            guard let texture = stream.texture else { continue }
            let bounds = CGRect(origin: .zero, size: size)
            var output = CIImage(color: .clear).cropped(to: bounds)
            if let image = latestImages[id],
               let crop = CoreImageCropRenderer.aspectFillSourceRect(sourceSize: image.extent.size, targetSize: size) {
                output = image.clampedToExtent()
                    .transformed(by: CGAffineTransform(translationX: -image.extent.minX - crop.minX, y: -image.extent.minY - crop.minY))
                    .transformed(by: CGAffineTransform(scaleX: size.width / crop.width, y: size.height / crop.height))
                    .cropped(to: bounds)
                    .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: latestOpacities[id] ?? 1)])
            }
            renderer.context.render(output, to: texture, commandBuffer: commandBuffer, bounds: bounds, colorSpace: colorSpace)
            // Core Image's Metal render target and Syphon's published texture use Metal orientation.
            stream.server.publishFrameTexture(texture, on: commandBuffer, imageRegion: bounds, flipped: false)
        }
        let lifetime = SyphonFrameLifetime(frames: Array(latestFrames.values))
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { [lifetime, semaphore] _ in
            withExtendedLifetime(lifetime) {}
            semaphore.signal()
        }
        commandBuffer.commit()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        latestImages.removeAll()
        latestFrames.removeAll()
        latestOpacities.removeAll()
        for stream in streams.values { stream.server.stop() }
        streams.removeAll()
        configurations.removeAll()
        isEnabled = false
    }
}

private final class SyphonFrameLifetime: @unchecked Sendable {
    let frames: [CameraFrame]
    init(frames: [CameraFrame]) { self.frames = frames }
}
