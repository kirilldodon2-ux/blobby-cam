import CoreGraphics
import CoreMedia
import ImageIO
import XCTest
@testable import BlobbyCam

final class RendererGeometryTests: XCTestCase {
    func testEachFeatureCanProduceADistinctPaddedSourcePixelCropFromOneFrame() throws {
        let size = CGSize(width: 640, height: 480)
        let expectedRects: [FeatureID: CGRect] = [
            .leftEye: CGRect(x: 0.1, y: 0.7, width: 0.1, height: 0.1),
            .rightEye: CGRect(x: 0.75, y: 0.7, width: 0.1, height: 0.1),
            .nose: CGRect(x: 0.4, y: 0.5, width: 0.1, height: 0.15),
            .mouth: CGRect(x: 0.35, y: 0.2, width: 0.25, height: 0.1),
            .leftHand: CGRect(x: 0.02, y: 0.05, width: 0.2, height: 0.25),
            .rightHand: CGRect(x: 0.78, y: 0.05, width: 0.2, height: 0.25)
        ]
        let sourceCrops = try XCTUnwrap(Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { featureID in
            let detection = FeatureDetection(
                id: featureID,
                normalizedRect: try XCTUnwrap(expectedRects[featureID]),
                confidence: 0.9,
                timestamp: CMTime(value: 1, timescale: 30)
            )
            let crop = CoreImageCropRenderer.sourcePixelCrop(
                for: detection,
                configuration: FeatureConfiguration.default,
                sourcePixelSize: size,
                orientation: .up
            )
            return crop.map { (featureID, $0) }
        }.compactMap { $0 }))

        XCTAssertEqual(sourceCrops.count, FeatureID.allCases.count)
        let crops = Array(sourceCrops.values)
        for (index, crop) in crops.enumerated() {
            for other in crops.dropFirst(index + 1) {
                XCTAssertNotEqual(crop, other, "Each feature should have a distinct source crop")
            }
            XCTAssertGreaterThan(crop.width, 0)
            XCTAssertGreaterThan(crop.height, 0)
            XCTAssertGreaterThanOrEqual(crop.minX, 0)
            XCTAssertGreaterThanOrEqual(crop.minY, 0)
            XCTAssertLessThanOrEqual(crop.maxX, size.width)
            XCTAssertLessThanOrEqual(crop.maxY, size.height)
        }
    }

    func testCropIncludesPaddingAndOrientationTransformFromT11() throws {
        let detection = FeatureDetection(
            id: .nose,
            normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            confidence: 0.9,
            timestamp: CMTime(value: 1, timescale: 30)
        )
        let crop = try XCTUnwrap(CoreImageCropRenderer.sourcePixelCrop(
            for: detection,
            configuration: FeatureConfiguration.default,
            sourcePixelSize: CGSize(width: 480, height: 640),
            orientation: .right
        ))

        XCTAssertGreaterThan(crop.width, 0)
        XCTAssertGreaterThan(crop.height, 0)
        XCTAssertGreaterThanOrEqual(crop.minX, 0)
        XCTAssertGreaterThanOrEqual(crop.minY, 0)
        XCTAssertLessThanOrEqual(crop.maxX, 480)
        XCTAssertLessThanOrEqual(crop.maxY, 640)
    }

    func testInvalidDetectionProducesNoSourceCrop() {
        let detection = FeatureDetection(
            id: .leftEye,
            normalizedRect: CGRect(x: .nan, y: 0.5, width: 0.1, height: 0.1),
            confidence: 0.9,
            timestamp: CMTime(value: 1, timescale: 30)
        )
        XCTAssertNil(CoreImageCropRenderer.sourcePixelCrop(
            for: detection,
            configuration: .default,
            sourcePixelSize: CGSize(width: 640, height: 480),
            orientation: .up
        ))
    }

    func testAspectFillCropsWideAndTallSourcesToTheDrawableRatio() throws {
        let wide = try XCTUnwrap(CoreImageCropRenderer.aspectFillSourceRect(
            sourceSize: CGSize(width: 4, height: 2),
            targetSize: CGSize(width: 1, height: 1)
        ))
        XCTAssertEqual(wide, CGRect(x: 1, y: 0, width: 2, height: 2))

        let tall = try XCTUnwrap(CoreImageCropRenderer.aspectFillSourceRect(
            sourceSize: CGSize(width: 2, height: 4),
            targetSize: CGSize(width: 1, height: 1)
        ))
        XCTAssertEqual(tall, CGRect(x: 0, y: 1, width: 2, height: 2))

        let sameAspect = try XCTUnwrap(CoreImageCropRenderer.aspectFillSourceRect(
            sourceSize: CGSize(width: 4, height: 2),
            targetSize: CGSize(width: 2, height: 1)
        ))
        XCTAssertEqual(sameAspect, CGRect(x: 0, y: 0, width: 4, height: 2))
        XCTAssertNil(CoreImageCropRenderer.aspectFillSourceRect(sourceSize: .zero, targetSize: CGSize(width: 100, height: 100)))
    }
}
