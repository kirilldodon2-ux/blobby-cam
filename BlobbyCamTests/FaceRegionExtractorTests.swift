import CoreGraphics
import CoreMedia
import XCTest
@testable import BlobbyCam

final class FaceRegionExtractorTests: XCTestCase {
    func testExtractsFourOffCenterFaceRegionsInFullImageCoordinates() {
        let timestamp = CMTime(value: 90, timescale: 30)
        let detections = FaceRegionExtractor.extract(
            faceBoundingBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5),
            confidence: 0.87,
            timestamp: timestamp,
            visionLeftEye: [CGPoint(x: 0.1, y: 0.7), CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.15, y: 0.9)],
            visionRightEye: [CGPoint(x: 0.7, y: 0.7), CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.75, y: 0.9)],
            nose: [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.6, y: 0.5)],
            outerLips: [CGPoint(x: 0.35, y: 0.15), CGPoint(x: 0.65, y: 0.25)],
            innerLips: nil
        )

        XCTAssertEqual(detections.count, 4)
        let byID = Dictionary(uniqueKeysWithValues: detections.map { ($0.id, $0) })
        XCTAssertEqual(Set(byID.keys), Set([.leftEye, .rightEye, .nose, .mouth]))
        assertRect(byID[.leftEye]?.normalizedRect, equals: CGRect(x: 0.48, y: 0.65, width: 0.04, height: 0.1))
        assertRect(byID[.rightEye]?.normalizedRect, equals: CGRect(x: 0.24, y: 0.65, width: 0.04, height: 0.1))
        assertRect(byID[.nose]?.normalizedRect, equals: CGRect(x: 0.36, y: 0.5, width: 0.08, height: 0.05))
        assertRect(byID[.mouth]?.normalizedRect, equals: CGRect(x: 0.34, y: 0.375, width: 0.12, height: 0.05))
        for detection in detections {
            XCTAssertEqual(detection.confidence, 0.87)
            XCTAssertEqual(detection.timestamp, timestamp)
            XCTAssertGreaterThanOrEqual(detection.normalizedRect.minX, 0)
            XCTAssertGreaterThanOrEqual(detection.normalizedRect.minY, 0)
            XCTAssertLessThanOrEqual(detection.normalizedRect.maxX, 1)
            XCTAssertLessThanOrEqual(detection.normalizedRect.maxY, 1)
        }
    }

    func testMissingAndDegenerateLandmarksProduceNoDetection() {
        let detections = FaceRegionExtractor.extract(
            faceBoundingBox: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
            confidence: 0.9,
            timestamp: CMTime(value: 1, timescale: 30),
            visionLeftEye: nil,
            visionRightEye: [CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.4, y: 0.5)],
            nose: [CGPoint(x: .nan, y: 0.5), CGPoint(x: 0.5, y: 0.6)],
            outerLips: nil,
            innerLips: nil
        )

        XCTAssertTrue(detections.isEmpty)
    }

    func testMouthFallsBackToInnerLipsAndRegionsClipToImageBounds() {
        let detections = FaceRegionExtractor.extract(
            faceBoundingBox: CGRect(x: 0.8, y: 0.7, width: 0.4, height: 0.4),
            confidence: 0.6,
            timestamp: .zero,
            visionLeftEye: nil,
            visionRightEye: nil,
            nose: nil,
            outerLips: nil,
            innerLips: [CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.75, y: 0.75)]
        )

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections[0].id, .mouth)
        assertRect(detections[0].normalizedRect, equals: CGRect(x: 0.9, y: 0.8, width: 0.1, height: 0.2))
    }

    func testExpressionsMoveFaceCropsWithoutChangingTheirMagnification() throws {
        let face = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.6)
        func detect(eyeTop: CGFloat, mouthBottom: CGFloat) -> [FeatureID: FeatureDetection] {
            let results = FaceRegionExtractor.extract(
                faceBoundingBox: face,
                confidence: 0.9,
                timestamp: .zero,
                visionLeftEye: nil,
                visionRightEye: [CGPoint(x: 0.2, y: 0.7), CGPoint(x: 0.4, y: eyeTop)],
                nose: nil,
                outerLips: [CGPoint(x: 0.3, y: mouthBottom), CGPoint(x: 0.7, y: 0.35)],
                innerLips: nil
            )
            return Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        }
        let neutral = detect(eyeTop: 0.8, mouthBottom: 0.25)
        let expressive = detect(eyeTop: 0.72, mouthBottom: 0.05)
        for id in [FeatureID.leftEye, .mouth] {
            let first = try XCTUnwrap(neutral[id])
            let second = try XCTUnwrap(expressive[id])
            XCTAssertNotEqual(first.normalizedRect.height, second.normalizedRect.height)
            XCTAssertEqual(first.cropReferenceSize, second.cropReferenceSize)
            let firstCrop = try XCTUnwrap(FeatureGeometry.cropRect(for: first, configuration: .default))
            let secondCrop = try XCTUnwrap(FeatureGeometry.cropRect(for: second, configuration: .default))
            XCTAssertEqual(firstCrop.width, secondCrop.width, accuracy: 0.000001)
            XCTAssertEqual(firstCrop.height, secondCrop.height, accuracy: 0.000001)
            let firstAuto = try XCTUnwrap(FeatureGeometry.cropRect(for: first, configuration: .default, autoScale: true))
            let secondAuto = try XCTUnwrap(FeatureGeometry.cropRect(for: second, configuration: .default, autoScale: true))
            XCTAssertNotEqual(firstAuto.height, secondAuto.height)
        }
    }

    private func assertRect(
        _ actual: CGRect?,
        equals expected: CGRect,
        accuracy: CGFloat = 0.000001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected a region rectangle", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }
}
