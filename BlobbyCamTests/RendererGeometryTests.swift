import CoreImage
import Metal
import Syphon
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

@MainActor
final class SyphonOutputTests: XCTestCase {
    func testStreamLifecycleKeepsStableIdentityWhenCopiesAreRemoved() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let output = SyphonOutput(renderer: try XCTUnwrap(CoreImageCropRenderer(device: device)))
        defer { output.stop() }
        let ids = (1...20).map { WindowInstanceID(featureID: .mouth, serial: UInt64($0)) }
        var configurations = Dictionary(uniqueKeysWithValues: ids.map { ($0, FeatureConfiguration.default) })
        output.configure(enabled: false, configurations: configurations)
        XCTAssertEqual(output.streamCount, 0)
        output.configure(enabled: true, configurations: configurations)
        XCTAssertEqual(output.streamCount, 20)
        let description = try XCTUnwrap(output.serverDescription(for: ids[19]))
        configurations.removeValue(forKey: ids[3])
        configurations[ids[4]]?.isEnabled = false
        output.configure(enabled: true, configurations: configurations)
        XCTAssertEqual(output.streamCount, 18)
        XCTAssertEqual(output.serverDescription(for: ids[19])?[SyphonServerDescriptionUUIDKey] as? String,
                       description[SyphonServerDescriptionUUIDKey] as? String)
        output.configure(enabled: false, configurations: configurations)
        XCTAssertEqual(output.streamCount, 0)
    }

    func testHeldFrameReachesLateMetalClientAndMissingCropClearsOutput() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try XCTUnwrap(CoreImageCropRenderer(device: device))
        let output = SyphonOutput(renderer: renderer)
        defer { output.stop() }
        let id = WindowInstanceID(featureID: .mouth, serial: 900)
        var configuration = FeatureConfiguration.default
        configuration.windowSizeOverride = CGSize(width: 32, height: 32)
        output.configure(enabled: true, configurations: [id: configuration])
        let bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: bounds)
        output.publish(images: [id: image], frames: [:], opacities: [id: 1])
        let client = SyphonMetalClient(serverDescription: try XCTUnwrap(output.serverDescription(for: id)),
                                      device: device, options: nil, newFrameHandler: nil)
        defer { client.stop() }
        XCTAssertTrue(client.isValid)
        var texture: MTLTexture?
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if client.hasNewFrame { texture = client.newFrameImage(); break }
        }
        let received = try XCTUnwrap(texture, "An idle sender must deliver the held frame to a late client")
        XCTAssertEqual(received.width, 64)
        XCTAssertEqual(received.height, 64)
        func pixel(_ texture: MTLTexture) throws -> [UInt8] {
            let ci = try XCTUnwrap(CIImage(mtlTexture: texture, options: nil))
            var bytes = [UInt8](repeating: 0, count: 4)
            renderer.context.render(ci, toBitmap: &bytes, rowBytes: 4,
                                    bounds: CGRect(x: 20, y: 20, width: 1, height: 1),
                                    format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return bytes
        }
        let red = try pixel(received)
        XCTAssertGreaterThan(red[0], 240)
        XCTAssertLessThan(red[1], 10)
        XCTAssertEqual(red[3], 255)
        output.publish(images: [:], frames: [:], opacities: [:])
        var cleared = false
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if client.hasNewFrame, let frame = client.newFrameImage(), try pixel(frame)[3] == 0 {
                cleared = true; break
            }
        }
        XCTAssertTrue(cleared, "Lost detection must clear the stream instead of retaining stale pixels")
    }

    func testOutputSizeBoundsExtremeWindowDimensions() {
        var configuration = FeatureConfiguration.default
        configuration.windowSizeOverride = CGSize(width: 8000, height: 4000)
        XCTAssertEqual(SyphonOutput.outputSize(for: configuration), CGSize(width: 1024, height: 512))
    }
}
