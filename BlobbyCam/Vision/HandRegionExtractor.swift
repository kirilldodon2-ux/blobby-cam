import CoreGraphics
import CoreMedia
import Vision

struct HandJointSample {
    let location: CGPoint
    let confidence: Float
}

struct HandRegionExtractor {
    /// Weak Vision joints frequently jump outside the palm and make the crop include unrelated
    /// background. Keep a valid wrist and only use joints with enough confidence for the bounds.
    static let minimumCropJointConfidence: Float = 0.35

    func extract(from observation: VNHumanHandPoseObservation, timestamp: CMTime) -> FeatureDetection? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        let wrist = points[.wrist].map { HandJointSample(location: $0.location, confidence: $0.confidence) }
        let additionalJoints = points.compactMap { joint, point in
            joint == .wrist ? nil : HandJointSample(location: point.location, confidence: point.confidence)
        }
        return Self.extract(
            chirality: observation.chirality,
            wrist: wrist,
            additionalJoints: additionalJoints,
            timestamp: timestamp
        )
    }

    /// Uses Vision chirality directly and never infers left/right from x position.
    /// The wrist and at least two other finite joints above the crop-confidence floor are
    /// required. The rectangle bounds those reliable joints, and confidence is their
    /// unweighted arithmetic mean.
    static func extract(
        chirality: VNChirality,
        wrist: HandJointSample?,
        additionalJoints: [HandJointSample],
        timestamp: CMTime
    ) -> FeatureDetection? {
        let featureID: FeatureID
        switch chirality {
        case .left:
            featureID = .leftHand
        case .right:
            featureID = .rightHand
        case .unknown:
            return nil
        @unknown default:
            return nil
        }

        guard let wrist, isReliable(wrist) else { return nil }
        let joints = [wrist] + additionalJoints.filter(isReliable)
        guard joints.count >= 3,
              let rect = imageRect(for: joints)
        else { return nil }

        let confidence = joints.reduce(Float.zero) { $0 + $1.confidence } / Float(joints.count)
        guard confidence.isFinite else { return nil }
        return FeatureDetection(
            id: featureID,
            normalizedRect: rect,
            confidence: confidence,
            timestamp: timestamp
        )
    }

    private static func isReliable(_ sample: HandJointSample) -> Bool {
        sample.location.x.isFinite && sample.location.y.isFinite
            && sample.confidence.isFinite && sample.confidence >= minimumCropJointConfidence
    }

    private static func imageRect(for joints: [HandJointSample]) -> CGRect? {
        guard !joints.isEmpty else { return nil }
        let minX = joints.map { $0.location.x }.min() ?? 0
        let maxX = joints.map { $0.location.x }.max() ?? 0
        let minY = joints.map { $0.location.y }.min() ?? 0
        let maxY = joints.map { $0.location.y }.max() ?? 0
        guard maxX > minX, maxY > minY else { return nil }

        let imageBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .intersection(imageBounds)
        guard !rect.isNull, !rect.isEmpty,
              rect.minX.isFinite, rect.minY.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite
        else { return nil }
        return rect
    }
}
