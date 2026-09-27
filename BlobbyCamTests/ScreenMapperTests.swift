import AppKit
import CoreGraphics
import ImageIO
import XCTest
@testable import BlobbyCam

final class ScreenMapperTests: XCTestCase {
    func testNormalizedRectMapsToRawSourcePixelsForUpOrientation() throws {
        let pixels = try XCTUnwrap(ScreenMapper.sourcePixelRect(
            fromOrientedNormalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.25, height: 0.4),
            sourcePixelSize: CGSize(width: 640, height: 480),
            orientation: .up
        ))

        assertRect(pixels, equals: CGRect(x: 64, y: 96, width: 160, height: 192))
    }

    func testPortraitOrientationMapsOrientedCropBackToSourceBuffer() throws {
        let pixels = try XCTUnwrap(ScreenMapper.sourcePixelRect(
            fromOrientedNormalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            sourcePixelSize: CGSize(width: 480, height: 640),
            orientation: .right
        ))

        assertRect(pixels, equals: CGRect(x: 192, y: 64, width: 192, height: 192))
    }

    func testMirroredExifOrientationsMapBackToTheirSourceQuadrants() throws {
        let rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let size = CGSize(width: 480, height: 640)

        let leftMirrored = try XCTUnwrap(ScreenMapper.sourcePixelRect(
            fromOrientedNormalizedRect: rect,
            sourcePixelSize: size,
            orientation: .leftMirrored
        ))
        let rightMirrored = try XCTUnwrap(ScreenMapper.sourcePixelRect(
            fromOrientedNormalizedRect: rect,
            sourcePixelSize: size,
            orientation: .rightMirrored
        ))

        assertRect(leftMirrored, equals: CGRect(x: 192, y: 384, width: 192, height: 192))
        assertRect(rightMirrored, equals: CGRect(x: 96, y: 64, width: 192, height: 192))
    }

    func testInvalidOrDisjointSourceGeometryIsRejected() {
        XCTAssertNil(ScreenMapper.sourcePixelRect(
            fromOrientedNormalizedRect: CGRect(x: .nan, y: 0, width: 0.2, height: 0.2),
            sourcePixelSize: CGSize(width: 640, height: 480),
            orientation: .up
        ))
        XCTAssertNil(ScreenMapper.sourcePixelRect(
            fromOrientedNormalizedRect: CGRect(x: 2, y: 2, width: 0.2, height: 0.2),
            sourcePixelSize: CGSize(width: 640, height: 480),
            orientation: .up
        ))
    }

    func testMirrorDifferenceIsAppliedOnceToScreenPlacement() throws {
        let screen = screen(identifier: "primary", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let sourceLeft = CGRect(x: 0.05, y: 0.45, width: 0.1, height: 0.1)
        let unmirrored = try XCTUnwrap(ScreenMapper.panelPlacement(
            for: sourceLeft,
            panelSize: CGSize(width: 100, height: 80),
            on: screen,
            sourceIsMirrored: false,
            requestedMirror: false
        ))
        let appMirrored = try XCTUnwrap(ScreenMapper.panelPlacement(
            for: sourceLeft,
            panelSize: CGSize(width: 100, height: 80),
            on: screen,
            sourceIsMirrored: false,
            requestedMirror: true
        ))
        let sourceAlreadyMirrored = try XCTUnwrap(ScreenMapper.panelPlacement(
            for: sourceLeft,
            panelSize: CGSize(width: 100, height: 80),
            on: screen,
            sourceIsMirrored: true,
            requestedMirror: true
        ))

        XCTAssertLessThan(unmirrored.frame.midX, screen.visibleFrame.midX)
        XCTAssertGreaterThan(appMirrored.frame.midX, screen.visibleFrame.midX)
        XCTAssertEqual(sourceAlreadyMirrored.frame, unmirrored.frame)
    }

    func testDefaultSelfieMirrorDisplaysAnatomicalLeftEyeOnLeftAndKeepsSemanticIDs() throws {
        let screen = screen(identifier: "primary", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        // Vision's anatomical left-eye landmark is on the image's right in the unmirrored feed.
        let detections: [FeatureID: CGRect] = [
            .leftEye: CGRect(x: 0.70, y: 0.45, width: 0.08, height: 0.08),
            .rightEye: CGRect(x: 0.22, y: 0.45, width: 0.08, height: 0.08)
        ]

        XCTAssertTrue(MirrorPolicy.selfieOrientationByDefault)
        let leftEyePanel = try XCTUnwrap(ScreenMapper.panelPlacement(
            for: try XCTUnwrap(detections[.leftEye]),
            panelSize: CGSize(width: 100, height: 80),
            on: screen,
            sourceIsMirrored: false,
            requestedMirror: MirrorPolicy.selfieOrientationByDefault
        ))
        let rightEyePanel = try XCTUnwrap(ScreenMapper.panelPlacement(
            for: try XCTUnwrap(detections[.rightEye]),
            panelSize: CGSize(width: 100, height: 80),
            on: screen,
            sourceIsMirrored: false,
            requestedMirror: MirrorPolicy.selfieOrientationByDefault
        ))

        XCTAssertLessThan(leftEyePanel.frame.midX, screen.visibleFrame.midX)
        XCTAssertGreaterThan(rightEyePanel.frame.midX, screen.visibleFrame.midX)
        XCTAssertEqual(FeatureID.leftEye.windowTitle, "LEFT EYE")
        XCTAssertEqual(FeatureID.rightEye.windowTitle, "RIGHT EYE")
    }

    func testRetinaScaleKeepsAppKitPointGeometryAndReportsBackingScale() throws {
        let oneX = screen(identifier: "one-x", visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900), scale: 1)
        let twoX = screen(identifier: "two-x", visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900), scale: 2)
        let detection = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)

        let placement1x = try XCTUnwrap(ScreenMapper.panelPlacement(
            for: detection,
            panelSize: CGSize(width: 100, height: 80),
            on: oneX,
            sourceIsMirrored: false,
            requestedMirror: false
        ))
        let placement2x = try XCTUnwrap(ScreenMapper.panelPlacement(
            for: detection,
            panelSize: CGSize(width: 100, height: 80),
            on: twoX,
            sourceIsMirrored: false,
            requestedMirror: false
        ))

        XCTAssertEqual(placement1x.frame, placement2x.frame)
        XCTAssertEqual(placement1x.backingScaleFactor, 1)
        XCTAssertEqual(placement2x.backingScaleFactor, 2)
    }

    func testNegativeExternalOriginAndPanelEdgesRemainVisible() throws {
        let external = screen(
            identifier: "external",
            frame: CGRect(x: -1600, y: -100, width: 1600, height: 900),
            visibleFrame: CGRect(x: -1600, y: -100, width: 1600, height: 860)
        )
        let leftDetection = CGRect(x: 0, y: 0, width: 0.05, height: 0.05)
        let placement = try XCTUnwrap(ScreenMapper.panelPlacement(
            for: leftDetection,
            panelSize: CGSize(width: 300, height: 200),
            on: external,
            sourceIsMirrored: false,
            requestedMirror: false
        ))

        XCTAssertEqual(placement.displayIdentifier, "external")
        XCTAssertEqual(placement.frame.minX, external.visibleFrame.minX)
        XCTAssertEqual(placement.frame.minY, external.visibleFrame.minY)
        XCTAssertTrue(external.visibleFrame.contains(placement.frame))
    }

    func testOversizedPanelIsReducedToVisibleFrameAndScreenSelectionUsesMenuThenPrimary() throws {
        let primary = screen(identifier: "primary", visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), primary: true)
        let external = screen(identifier: "external", frame: CGRect(x: -1600, y: 0, width: 1600, height: 900), visibleFrame: CGRect(x: -1600, y: 0, width: 1600, height: 860))
        let screens = [primary, external]

        XCTAssertEqual(ScreenMapper.selectedScreen(
            from: screens,
            menuWindowFrame: CGRect(x: -900, y: 100, width: 400, height: 300)
        )?.displayIdentifier, "external")
        XCTAssertEqual(ScreenMapper.selectedScreen(from: screens, menuWindowFrame: nil)?.displayIdentifier, "primary")

        let placement = try XCTUnwrap(ScreenMapper.panelPlacement(
            for: CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1),
            panelSize: CGSize(width: 2000, height: 1000),
            on: external,
            sourceIsMirrored: false,
            requestedMirror: false
        ))
        XCTAssertEqual(placement.frame.size, external.visibleFrame.size)
    }

    private func screen(
        identifier: String,
        frame: CGRect? = nil,
        visibleFrame: CGRect,
        scale: CGFloat = 1,
        primary: Bool = false
    ) -> ScreenGeometry {
        ScreenGeometry(
            displayIdentifier: identifier,
            frame: frame ?? visibleFrame,
            visibleFrame: visibleFrame,
            backingScaleFactor: scale,
            isPrimary: primary
        )
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
