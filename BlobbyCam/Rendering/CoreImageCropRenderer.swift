import CoreImage
import CoreVideo
import ImageIO
import Metal
import MetalKit

@MainActor
final class CoreImageCropRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let context: CIContext

    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        context = CIContext(mtlCommandQueue: commandQueue)
    }

    nonisolated static func sourcePixelCrop(
        for detection: FeatureDetection,
        configuration: FeatureConfiguration,
        sourcePixelSize: CGSize,
        orientation: CGImagePropertyOrientation,
        autoScale: Bool = false
    ) -> CGRect? {
        guard let paddedRect = FeatureGeometry.cropRect(for: detection, configuration: configuration, autoScale: autoScale) else {
            return nil
        }
        return ScreenMapper.sourcePixelRect(
            fromOrientedNormalizedRect: paddedRect,
            sourcePixelSize: sourcePixelSize,
            orientation: orientation
        )
    }

    /// Returns the centered part of `sourceSize` that has the target aspect ratio. Drawing this
    /// source rect into the full drawable uses aspect fill and cannot leave letterbox bars.
    nonisolated static func aspectFillSourceRect(sourceSize: CGSize, targetSize: CGSize) -> CGRect? {
        guard sourceSize.width.isFinite, sourceSize.height.isFinite,
              targetSize.width.isFinite, targetSize.height.isFinite,
              sourceSize.width > 0, sourceSize.height > 0,
              targetSize.width > 0, targetSize.height > 0
        else { return nil }

        let sourceAspect = sourceSize.width / sourceSize.height
        let targetAspect = targetSize.width / targetSize.height
        let size: CGSize
        if sourceAspect > targetAspect {
            size = CGSize(width: sourceSize.height * targetAspect, height: sourceSize.height)
        } else {
            size = CGSize(width: sourceSize.width, height: sourceSize.width / targetAspect)
        }
        return CGRect(
            x: (sourceSize.width - size.width) / 2,
            y: (sourceSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    func makeFeatureImage(
        from sourceImage: CIImage,
        pixelCrop: CGRect,
        orientation: CGImagePropertyOrientation,
        additionalMirror: Bool
    ) -> CIImage? {
        guard pixelCrop.minX.isFinite, pixelCrop.minY.isFinite,
              pixelCrop.width.isFinite, pixelCrop.height.isFinite,
              pixelCrop.width > 0, pixelCrop.height > 0
        else { return nil }

        let sourceExtent = sourceImage.extent
        let crop = pixelCrop.intersection(sourceExtent)
        guard !crop.isNull, !crop.isEmpty else { return nil }

        let cropped = sourceImage.cropped(to: crop)
        let rebased = cropped.transformed(by: CGAffineTransform(
            translationX: -cropped.extent.minX,
            y: -cropped.extent.minY
        ))
        var oriented = rebased.oriented(orientation)
        oriented = rebasedToOrigin(oriented)

        if additionalMirror {
            let extent = oriented.extent
            let flipped = oriented.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            let translated = flipped.transformed(by: CGAffineTransform(translationX: -flipped.extent.minX, y: -flipped.extent.minY))
            // A horizontal reflection can leave a negative X extent; shift it back to origin.
            oriented = translated.cropped(to: CGRect(origin: .zero, size: extent.size))
        }
        return oriented
    }

    func draw(_ image: CIImage, retaining frame: CameraFrame, in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        let texture = drawable.texture
        let targetBounds = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        guard let sourceCrop = Self.aspectFillSourceRect(sourceSize: image.extent.size, targetSize: targetBounds.size) else {
            return
        }
        let crop = CGRect(
            x: image.extent.midX - sourceCrop.width / 2,
            y: image.extent.midY - sourceCrop.height / 2,
            width: sourceCrop.width,
            height: sourceCrop.height
        )
        // Clamp edge samples before magnifying tiny eye crops. Sampling just outside a
        // fractional crop boundary otherwise reveals the panel's black backing as bars.
        let originAdjusted = image.clampedToExtent().transformed(by: CGAffineTransform(
            translationX: -crop.minX,
            y: -crop.minY
        ))
        let scaleX = targetBounds.width / sourceCrop.width
        let scaleY = targetBounds.height / sourceCrop.height
        let positioned = originAdjusted
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: targetBounds)

        guard let renderPass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = view.clearColor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        encoder.endEncoding()

        context.render(
            positioned,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: targetBounds,
            colorSpace: colorSpace
        )
        commandBuffer.present(drawable)
        // Core Image and Metal may still read the camera buffer after this method returns.
        let frameLifetime = CameraFrameLifetime(frame: frame)
        commandBuffer.addCompletedHandler { [frameLifetime] _ in
            withExtendedLifetime(frameLifetime.frame) {}
        }
        commandBuffer.commit()
    }

    private func rebasedToOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX,
            y: -image.extent.minY
        ))
    }
}

private struct CameraFrameLifetime: @unchecked Sendable {
    let frame: CameraFrame
}
