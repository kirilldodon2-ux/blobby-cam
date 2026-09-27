import CoreGraphics
import CoreMedia
import Vision
import XCTest
@testable import BlobbyCam

final class HandRegionExtractorTests: XCTestCase {
    func testGeometryAndConfidenceIgnoreLowConfidenceCropOutliers() throws {
        let timestamp = CMTime(value: 120, timescale: 30)
        let detection = try XCTUnwrap(HandRegionExtractor.extract(
            chirality: .left,
            wrist: sample(0.1, 0.2, confidence: 0.8),
            additionalJoints: [
                sample(0.3, 0.4, confidence: 0.4),
                sample(0.6, 0.5, confidence: 0.6),
                sample(0.98, 0.92, confidence: 0.1)
            ],
            timestamp: timestamp
        ))

        XCTAssertEqual(detection.id, .leftHand)
        assertRect(detection.normalizedRect, equals: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3))
        XCTAssertEqual(detection.confidence, 0.6, accuracy: 0.000001)
        XCTAssertEqual(detection.timestamp, timestamp)
    }

    func testChiralityDefinesIdentityIndependentOfHorizontalPosition() throws {
        let wrist = sample(0.8, 0.2, confidence: 0.9)
        let joints = [sample(0.6, 0.4, confidence: 0.8), sample(0.9, 0.6, confidence: 0.7)]

        let left = try XCTUnwrap(HandRegionExtractor.extract(
            chirality: .left,
            wrist: wrist,
            additionalJoints: joints,
            timestamp: .zero
        ))
        let right = try XCTUnwrap(HandRegionExtractor.extract(
            chirality: .right,
            wrist: wrist,
            additionalJoints: joints,
            timestamp: .zero
        ))

        XCTAssertEqual(left.id, .leftHand)
        XCTAssertEqual(right.id, .rightHand)
        XCTAssertEqual(left.normalizedRect, right.normalizedRect)
        XCTAssertNil(HandRegionExtractor.extract(
            chirality: .unknown,
            wrist: wrist,
            additionalJoints: joints,
            timestamp: .zero
        ))
    }

    func testMissingWristInsufficientJointsAndDegenerateBoundsAreRejected() {
        let wrist = sample(0.5, 0.5, confidence: 0.8)
        XCTAssertNil(HandRegionExtractor.extract(
            chirality: .right,
            wrist: nil,
            additionalJoints: [sample(0.4, 0.4, confidence: 0.9), sample(0.6, 0.6, confidence: 0.9)],
            timestamp: .zero
        ))
        XCTAssertNil(HandRegionExtractor.extract(
            chirality: .right,
            wrist: wrist,
            additionalJoints: [sample(0.6, 0.4, confidence: 0.9)],
            timestamp: .zero
        ))
        XCTAssertNil(HandRegionExtractor.extract(
            chirality: .right,
            wrist: wrist,
            additionalJoints: [sample(0.5, 0.4, confidence: 0.9), sample(0.5, 0.7, confidence: 0.9)],
            timestamp: .zero
        ))
    }

    func testInvalidJointsAreIgnoredAndOutputIsClippedToImageBounds() throws {
        let detection = try XCTUnwrap(HandRegionExtractor.extract(
            chirality: .right,
            wrist: sample(0.9, 0.85, confidence: 0.8),
            additionalJoints: [
                sample(1.2, 0.9, confidence: 0.6),
                sample(0.95, 1.1, confidence: 0.4),
                sample(.nan, 0.2, confidence: 1),
                sample(0.1, 0.2, confidence: 0)
            ],
            timestamp: .zero
        ))

        XCTAssertEqual(detection.id, .rightHand)
        assertRect(detection.normalizedRect, equals: CGRect(x: 0.9, y: 0.85, width: 0.1, height: 0.15))
        XCTAssertEqual(detection.confidence, 0.6, accuracy: 0.000001)
    }

    private func sample(_ x: CGFloat, _ y: CGFloat, confidence: Float) -> HandJointSample {
        HandJointSample(location: CGPoint(x: x, y: y), confidence: confidence)
    }

    private func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat = 0.000001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }
}
