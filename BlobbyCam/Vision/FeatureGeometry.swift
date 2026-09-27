import CoreGraphics

enum FeatureGeometry {
    static let imageBounds = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Expands the normalized feature rectangle by `cropPadding`, applies independent zoom and
    /// full-image-coordinate pan, then clamps the resulting field of view to the camera image.
    /// Orientation and mirroring are applied later by the mapper/renderer.
    static func cropRect(
        for detection: FeatureDetection,
        configuration: FeatureConfiguration,
        autoScale: Bool = false
    ) -> CGRect? {
        let rect = detection.normalizedRect
        let padding = configuration.cropPadding
        let zoom = configuration.cropZoom
        let offsetX = configuration.cropOffsetX
        let offsetY = configuration.cropOffsetY
        guard rect.minX.isFinite, rect.minY.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0,
              detection.confidence.isFinite,
              (0...1).contains(detection.confidence),
              padding.isFinite, padding >= 0,
              zoom.isFinite, FeatureConfiguration.cropZoomRange.contains(zoom),
              offsetX.isFinite, (-1...1).contains(offsetX),
              offsetY.isFinite, (-1...1).contains(offsetY)
        else { return nil }

        let clippedRect = rect.intersection(imageBounds)
        guard !clippedRect.isNull, !clippedRect.isEmpty,
              clippedRect.minX.isFinite, clippedRect.minY.isFinite,
              clippedRect.maxX.isFinite, clippedRect.maxY.isFinite
        else { return nil }

        if !autoScale, let referenceSize = detection.cropReferenceSize {
            guard referenceSize.width.isFinite, referenceSize.height.isFinite,
                  referenceSize.width > 0, referenceSize.height > 0
            else { return nil }
            // Facial expressions change landmark bounds but should not change magnification.
            // Pan and zoom remain user controlled; the landmark center still tracks motion.
            let width = min(imageBounds.width, referenceSize.width * (1 + 2 * padding) / zoom)
            let height = min(imageBounds.height, referenceSize.height * (1 + 2 * padding) / zoom)
            guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
            let centerX = clippedRect.midX + offsetX
            let centerY = clippedRect.midY + offsetY
            return CGRect(
                x: min(max(centerX - width / 2, imageBounds.minX), imageBounds.maxX - width),
                y: min(max(centerY - height / 2, imageBounds.minY), imageBounds.maxY - height),
                width: width,
                height: height
            )
        }

        let horizontalPadding = clippedRect.width * padding
        let verticalPadding = clippedRect.height * padding
        let paddedMinX = clippedRect.minX - min(horizontalPadding, clippedRect.minX)
        let paddedMaxX = clippedRect.maxX + min(horizontalPadding, imageBounds.maxX - clippedRect.maxX)
        let paddedMinY = clippedRect.minY - min(verticalPadding, clippedRect.minY)
        let paddedMaxY = clippedRect.maxY + min(verticalPadding, imageBounds.maxY - clippedRect.maxY)
        let width = min(imageBounds.width, (paddedMaxX - paddedMinX) / zoom)
        let height = min(imageBounds.height, (paddedMaxY - paddedMinY) / zoom)
        let centerX = (paddedMinX + paddedMaxX) / 2 + offsetX
        let centerY = (paddedMinY + paddedMaxY) / 2 + offsetY
        let minX = min(max(centerX - width / 2, imageBounds.minX), imageBounds.maxX - width)
        let maxX = minX + width
        let minY = min(max(centerY - height / 2, imageBounds.minY), imageBounds.maxY - height)
        let maxY = minY + height
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite,
              maxX > minX, maxY > minY
        else { return nil }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
