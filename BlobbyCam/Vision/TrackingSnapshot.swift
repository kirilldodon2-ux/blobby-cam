import CoreGraphics
import CoreMedia

struct FeatureDetection {
    let id: FeatureID
    /// Normalized full-image coordinates, before crop padding.
    let normalizedRect: CGRect
    /// Optional face-relative field of view. Its center follows `normalizedRect`, while its
    /// dimensions stay independent of an eye blink or a mouth opening.
    let cropReferenceSize: CGSize?
    let confidence: Float
    let timestamp: CMTime

    init(
        id: FeatureID,
        normalizedRect: CGRect,
        confidence: Float,
        timestamp: CMTime,
        cropReferenceSize: CGSize? = nil
    ) {
        self.id = id
        self.normalizedRect = normalizedRect
        self.cropReferenceSize = cropReferenceSize
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

struct TrackingSnapshot {
    let timestamp: CMTime
    let detections: [FeatureID: FeatureDetection]
}
