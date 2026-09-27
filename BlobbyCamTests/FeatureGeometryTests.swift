import CoreGraphics
import CoreMedia
import XCTest
@testable import BlobbyCam

final class FeatureGeometryTests: XCTestCase {
    func testPaddingExpandsEveryEdgeAndClampsAtImageBounds() throws {
        let feature = detection(CGRect(x: 0.05, y: 0.72, width: 0.2, height: 0.16))
        let crop = try XCTUnwrap(FeatureGeometry.cropRect(for: feature, configuration: configuration(padding: 0.25)))

        assertRect(crop, equals: CGRect(x: 0, y: 0.68, width: 0.3, height: 0.24))
        assertInBounds(crop)
    }

    func testZeroAndTinyFeaturePaddingPreservePositiveDimensions() throws {
        let feature = detection(CGRect(x: 0.4, y: 0.4, width: 0.0000001, height: 0.0000002))
        let unpadded = try XCTUnwrap(FeatureGeometry.cropRect(for: feature, configuration: configuration(padding: 0)))
        let padded = try XCTUnwrap(FeatureGeometry.cropRect(for: feature, configuration: configuration(padding: 0.25)))

        XCTAssertGreaterThan(unpadded.width, 0)
        XCTAssertGreaterThan(unpadded.height, 0)
        XCTAssertGreaterThan(padded.width, unpadded.width)
        XCTAssertGreaterThan(padded.height, unpadded.height)
        assertInBounds(padded)
    }

    func testExtremeFinitePaddingSafelyCoversImageAndInvalidPaddingIsRejected() throws {
        let feature = detection(CGRect(x: 0.4, y: 0.3, width: 0.1, height: 0.2))
        let fullImage = try XCTUnwrap(FeatureGeometry.cropRect(
            for: feature,
            configuration: configuration(padding: .greatestFiniteMagnitude)
        ))
        XCTAssertEqual(fullImage, FeatureGeometry.imageBounds)
        XCTAssertNil(FeatureGeometry.cropRect(for: feature, configuration: configuration(padding: -0.1)))
        XCTAssertNil(FeatureGeometry.cropRect(for: feature, configuration: configuration(padding: .nan)))
        XCTAssertNil(FeatureGeometry.cropRect(for: feature, configuration: configuration(padding: .infinity)))
    }

    func testCropZoomAndPanAreIndependentAndClampedToSourceBounds() throws {
        let feature = detection(CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1))
        let zoomed = try XCTUnwrap(FeatureGeometry.cropRect(
            for: feature,
            configuration: configuration(padding: 0.25, zoom: 2, offsetX: 0.1, offsetY: -0.1)
        ))
        assertRect(zoomed, equals: CGRect(x: 0.5125, y: 0.3125, width: 0.075, height: 0.075))

        let pannedToEdge = try XCTUnwrap(FeatureGeometry.cropRect(
            for: feature,
            configuration: configuration(padding: 0.25, zoom: 1, offsetX: 1, offsetY: 1)
        ))
        XCTAssertEqual(pannedToEdge.maxX, 1, accuracy: 0.000001)
        XCTAssertEqual(pannedToEdge.maxY, 1, accuracy: 0.000001)
        assertInBounds(pannedToEdge)

        let zoomedOut = try XCTUnwrap(FeatureGeometry.cropRect(
            for: feature,
            configuration: configuration(padding: 0.25, zoom: 0.25)
        ))
        assertInBounds(zoomedOut)
        XCTAssertGreaterThan(zoomedOut.width, 0.5)
        XCTAssertGreaterThan(zoomedOut.height, 0.5)

        XCTAssertNil(FeatureGeometry.cropRect(
            for: feature,
            configuration: configuration(padding: 0.25, zoom: .nan)
        ))
    }

    func testInvalidOrOutOfImageDetectionProducesNoCrop() {
        let invalidRects = [
            CGRect(x: 0.2, y: 0.2, width: 0, height: 0.2),
            CGRect(x: .nan, y: 0.2, width: 0.1, height: 0.2),
            CGRect(x: 0.2, y: 0.2, width: .infinity, height: 0.2),
            CGRect(x: 2, y: 2, width: 0.2, height: 0.2)
        ]
        for rect in invalidRects {
            XCTAssertNil(FeatureGeometry.cropRect(for: detection(rect), configuration: configuration(padding: 0.25)))
        }

        XCTAssertNil(FeatureGeometry.cropRect(
            for: detection(CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1), confidence: .nan),
            configuration: configuration(padding: 0.25)
        ))
        XCTAssertNil(FeatureGeometry.cropRect(
            for: detection(CGRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1), confidence: 1.1),
            configuration: configuration(padding: 0.25)
        ))
    }

    func testPartiallyOutOfImageDetectionIsClippedBeforePadding() throws {
        let feature = detection(CGRect(x: -0.1, y: 0.3, width: 0.2, height: 0.2))
        let crop = try XCTUnwrap(FeatureGeometry.cropRect(for: feature, configuration: configuration(padding: 0)))

        assertRect(crop, equals: CGRect(x: 0, y: 0.3, width: 0.1, height: 0.2))
        assertInBounds(crop)
    }

    private func detection(_ rect: CGRect, confidence: Float = 0.8) -> FeatureDetection {
        FeatureDetection(
            id: .nose,
            normalizedRect: rect,
            confidence: confidence,
            timestamp: CMTime(value: 1, timescale: 30)
        )
    }

    private func configuration(
        padding: CGFloat,
        zoom: CGFloat = 1,
        offsetX: CGFloat = 0,
        offsetY: CGFloat = 0
    ) -> FeatureConfiguration {
        FeatureConfiguration(
            isEnabled: true,
            windowScale: 1,
            cropPadding: padding,
            detectionThreshold: 0.55,
            cropZoom: zoom,
            cropOffsetX: offsetX,
            cropOffsetY: offsetY
        )
    }

    private func assertInBounds(_ rect: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite, file: file, line: line)
        XCTAssertGreaterThan(rect.width, 0, file: file, line: line)
        XCTAssertGreaterThan(rect.height, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minX, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minY, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxX, 1, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxY, 1, file: file, line: line)
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
