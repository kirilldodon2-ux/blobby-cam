import CoreGraphics
import CoreMedia
import Vision

struct FaceRegionExtractor {
    func extract(from observation: VNFaceObservation, timestamp: CMTime) -> [FeatureDetection] {
        guard let landmarks = observation.landmarks else { return [] }
        return Self.extract(
            faceBoundingBox: observation.boundingBox,
            confidence: observation.confidence,
            timestamp: timestamp,
            visionLeftEye: points(in: landmarks.leftEye),
            visionRightEye: points(in: landmarks.rightEye),
            nose: points(in: landmarks.nose),
            outerLips: points(in: landmarks.outerLips),
            innerLips: points(in: landmarks.innerLips)
        )
    }

    /// Converts landmark points normalized to a face box into normalized full-image rectangles.
    /// Vision does not attach point confidence to face landmarks, so every region uses the
    /// containing face observation's confidence. If `outerLips` is absent, `innerLips` is used.
    static func extract(
        faceBoundingBox: CGRect,
        confidence: Float,
        timestamp: CMTime,
        visionLeftEye: [CGPoint]?,
        visionRightEye: [CGPoint]?,
        nose: [CGPoint]?,
        outerLips: [CGPoint]?,
        innerLips: [CGPoint]?
    ) -> [FeatureDetection] {
        guard isFinite(faceBoundingBox),
              faceBoundingBox.width > 0,
              faceBoundingBox.height > 0,
              confidence.isFinite
        else { return [] }

        // The live selfie review showed Vision's eye names opposite the intended display
        // labels. Normalize this once so panel titles and future per-eye controls stay aligned.
        let regions: [(FeatureID, [CGPoint]?)] = [
            (.leftEye, visionRightEye),
            (.rightEye, visionLeftEye),
            (.nose, nose),
            (.mouth, outerLips ?? innerLips)
        ]

        return regions.compactMap { id, points in
            guard let points,
                  let rect = imageRect(for: points, inside: faceBoundingBox)
            else { return nil }
            let fieldOfView: CGSize
            switch id {
            case .leftEye, .rightEye:
                fieldOfView = CGSize(width: faceBoundingBox.width * 0.28, height: faceBoundingBox.height * 0.14)
            case .nose:
                fieldOfView = CGSize(width: faceBoundingBox.width * 0.28, height: faceBoundingBox.height * 0.25)
            case .mouth:
                fieldOfView = CGSize(width: faceBoundingBox.width * 0.50, height: faceBoundingBox.height * 0.25)
            case .leftHand, .rightHand:
                return nil
            }
            return FeatureDetection(
                id: id,
                normalizedRect: rect,
                confidence: confidence,
                timestamp: timestamp,
                cropReferenceSize: fieldOfView
            )
        }
    }

    private func points(in region: VNFaceLandmarkRegion2D?) -> [CGPoint]? {
        region?.normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
    }

    private static func imageRect(for points: [CGPoint], inside face: CGRect) -> CGRect? {
        guard !points.isEmpty,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else { return nil }

        let imagePoints = points.map { point in
            CGPoint(
                x: face.minX + point.x * face.width,
                y: face.minY + point.y * face.height
            )
        }
        let minX = imagePoints.map(\.x).min() ?? 0
        let maxX = imagePoints.map(\.x).max() ?? 0
        let minY = imagePoints.map(\.y).min() ?? 0
        let maxY = imagePoints.map(\.y).max() ?? 0
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

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
    }
}
