import AppKit
import CoreMedia
import CoreVideo
import ImageIO
import XCTest
@testable import BlobbyCam

@MainActor
final class IntegrationStateTests: XCTestCase {
    func testAllFeaturesUsePersistentPanelsAndStateHidesOnlyRequestedPanels() throws {
        let manager = FeatureWindowManager()
        let identities = Dictionary(uniqueKeysWithValues: FeatureID.allCases.map {
            ($0, ObjectIdentifier(manager.panel(for: $0)))
        })
        let configurations = defaultConfigurations()
        let frame = try makeFrame(timestamp: 1)
        let snapshot = makeSnapshot(timestamp: frame.timestamp, detectedFeatures: FeatureID.allCases)

        apply(manager, frame: frame, snapshot: snapshot, configurations: configurations)

        for id in FeatureID.allCases {
            XCTAssertTrue(manager.panel(for: id).isVisible, "Expected \(id) to be visible")
        }

        var oneDisabled = configurations
        oneDisabled[.leftEye]?.isEnabled = false
        apply(manager, frame: frame, snapshot: snapshot, configurations: oneDisabled)
        XCTAssertFalse(manager.panel(for: .leftEye).isVisible)
        for id in FeatureID.allCases where id != .leftEye {
            XCTAssertTrue(manager.panel(for: id).isVisible, "Disabling leftEye must not hide \(id)")
        }

        apply(manager, frame: frame, snapshot: snapshot, configurations: oneDisabled, showAll: false)
        XCTAssertTrue(FeatureID.allCases.allSatisfy { !manager.panel(for: $0).isVisible })
        apply(manager, frame: frame, snapshot: snapshot, configurations: oneDisabled)
        XCTAssertTrue(FeatureID.allCases.filter { $0 != .leftEye }.allSatisfy { manager.panel(for: $0).isVisible })

        apply(manager, frame: frame, snapshot: snapshot, configurations: oneDisabled, isLive: false)
        XCTAssertTrue(FeatureID.allCases.allSatisfy { !manager.panel(for: $0).isVisible })
        for id in FeatureID.allCases {
            XCTAssertEqual(ObjectIdentifier(manager.panel(for: id)), identities[id])
        }
    }

    func testSixCoincidentFeatureTargetsAreLaidOutWithoutWindowOverlap() throws {
        let manager = FeatureWindowManager()
        let frame = try makeFrame(timestamp: 1)
        let sharedRect = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        var detections: [FeatureID: FeatureDetection] = [:]
        for featureID in FeatureID.allCases {
            detections[featureID] = FeatureDetection(
                id: featureID,
                normalizedRect: sharedRect,
                confidence: 0.9,
                timestamp: frame.timestamp
            )
        }
        apply(
            manager,
            frame: frame,
            snapshot: TrackingSnapshot(timestamp: frame.timestamp, detections: detections),
            configurations: defaultConfigurations(),
            menuWindowFrame: CGRect(x: 320, y: 280, width: 360, height: 240)
        )

        let visibleFrames = FeatureID.allCases.map { featureID -> CGRect in
            let panel = manager.panel(for: featureID)
            XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(manager.panel(for: featureID).featureID == featureID)
            return panel.frame
        }
        let menuFrame = CGRect(x: 320, y: 280, width: 360, height: 240)
        for (index, frame) in visibleFrames.enumerated() {
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1_000, height: 800).contains(frame))
            XCTAssertFalse(frame.intersects(menuFrame))
            for other in visibleFrames.dropFirst(index + 1) {
                XCTAssertFalse(frame.intersects(other), "Feature panels must never overlap")
            }
        }
    }

    func testFaceLayoutCentersNoseAndMouthUnderMirroredEyeRow() throws {
        let manager = FeatureWindowManager()
        let frame = try makeFrame(timestamp: 1)
        let detections: [FeatureID: CGRect] = [
            // Anatomical left eye is on the right in an unmirrored camera image.
            .leftEye: CGRect(x: 0.70, y: 0.62, width: 0.08, height: 0.08),
            .rightEye: CGRect(x: 0.22, y: 0.60, width: 0.08, height: 0.08),
            .nose: CGRect(x: 0.44, y: 0.42, width: 0.12, height: 0.12),
            .mouth: CGRect(x: 0.43, y: 0.25, width: 0.14, height: 0.10)
        ]
        var featureDetections: [FeatureID: FeatureDetection] = [:]
        for (id, rect) in detections {
            featureDetections[id] = FeatureDetection(
                id: id,
                normalizedRect: rect,
                confidence: 0.95,
                timestamp: frame.timestamp
            )
        }
        apply(
            manager,
            frame: frame,
            snapshot: TrackingSnapshot(timestamp: frame.timestamp, detections: featureDetections),
            configurations: defaultConfigurations(),
            mirror: true,
            visibleFrame: CGRect(x: 0, y: 50, width: 1_000, height: 750)
        )

        let leftEye = manager.panel(for: .leftEye).frame
        let rightEye = manager.panel(for: .rightEye).frame
        let nose = manager.panel(for: .nose).frame
        let mouth = manager.panel(for: .mouth).frame

        XCTAssertLessThan(leftEye.midX, rightEye.midX)
        XCTAssertGreaterThan(leftEye.minY, nose.maxY, "eye=\(leftEye), nose=\(nose)")
        XCTAssertGreaterThan(nose.minY, mouth.maxY, "nose=\(nose), mouth=\(mouth)")
        XCTAssertEqual(nose.midX, (leftEye.midX + rightEye.midX) / 2, accuracy: 1)
        XCTAssertEqual(mouth.midX, nose.midX, accuracy: 1)
        XCTAssertFalse(leftEye.intersects(rightEye))
        XCTAssertFalse(leftEye.intersects(nose))
        XCTAssertFalse(rightEye.intersects(nose))
        XCTAssertFalse(nose.intersects(mouth))
    }

    func testBriefMissHoldsGeometryAndOlderSnapshotCannotMovePanelBack() throws {
        let manager = FeatureWindowManager()
        let configurations = defaultConfigurations()
        let firstFrame = try makeFrame(timestamp: 1_000, timescale: 1_000)
        let firstSnapshot = makeSnapshot(
            timestamp: firstFrame.timestamp,
            detectedFeatures: [.nose],
            noseRect: CGRect(x: 0.25, y: 0.35, width: 0.1, height: 0.12)
        )
        apply(manager, frame: firstFrame, snapshot: firstSnapshot, configurations: configurations)
        manager.move(.nose, to: CGPoint(x: 80, y: 90))
        let originalFrame = manager.panel(for: .nose).frame

        let missFrame = try makeFrame(timestamp: 1_100, timescale: 1_000)
        apply(
            manager,
            frame: missFrame,
            snapshot: makeSnapshot(timestamp: missFrame.timestamp, detectedFeatures: []),
            configurations: configurations
        )
        XCTAssertTrue(manager.panel(for: .nose).isVisible)
        XCTAssertEqual(manager.panel(for: .nose).frame, originalFrame)

        let newerMissFrame = try makeFrame(timestamp: 1_310, timescale: 1_000)
        apply(
            manager,
            frame: newerMissFrame,
            snapshot: makeSnapshot(timestamp: newerMissFrame.timestamp, detectedFeatures: []),
            configurations: configurations
        )
        XCTAssertTrue(manager.panel(for: .nose).isVisible, "The feature should fade before it hides")

        let staleFrame = try makeFrame(timestamp: 1_200, timescale: 1_000)
        let staleSnapshot = makeSnapshot(
            timestamp: staleFrame.timestamp,
            detectedFeatures: [.nose],
            noseRect: CGRect(x: 0.75, y: 0.72, width: 0.1, height: 0.12)
        )
        apply(manager, frame: staleFrame, snapshot: staleSnapshot, configurations: configurations)
        XCTAssertEqual(manager.panel(for: .nose).frame, originalFrame)

        let expiredFrame = try makeFrame(timestamp: 1_380, timescale: 1_000)
        apply(
            manager,
            frame: expiredFrame,
            snapshot: makeSnapshot(timestamp: expiredFrame.timestamp, detectedFeatures: []),
            configurations: configurations
        )
        XCTAssertFalse(manager.panel(for: .nose).isVisible)

        let reacquiredFrame = try makeFrame(timestamp: 1_500, timescale: 1_000)
        apply(
            manager,
            frame: reacquiredFrame,
            snapshot: makeSnapshot(
                timestamp: reacquiredFrame.timestamp,
                detectedFeatures: [.nose],
                noseRect: CGRect(x: 0.75, y: 0.72, width: 0.1, height: 0.12)
            ),
            configurations: configurations
        )
        XCTAssertTrue(manager.panel(for: .nose).isVisible)
        XCTAssertEqual(manager.panel(for: .nose).frame, originalFrame,
                       "A reappearing detection must not reset a manually placed static panel")
    }

    func testFollowCanPausePositionWhileConfigurationChangesResizeExistingPanel() throws {
        let manager = FeatureWindowManager()
        var configurations = defaultConfigurations()
        let firstFrame = try makeFrame(timestamp: 1)
        let firstSnapshot = makeSnapshot(
            timestamp: firstFrame.timestamp,
            detectedFeatures: [.mouth],
            mouthRect: CGRect(x: 0.2, y: 0.25, width: 0.12, height: 0.1)
        )
        apply(manager, frame: firstFrame, snapshot: firstSnapshot, configurations: configurations)
        let panel = manager.panel(for: .mouth)
        let panelIdentity = ObjectIdentifier(panel)
        let firstOrigin = panel.frame.origin

        let movedFrame = try makeFrame(timestamp: 2)
        let movedSnapshot = makeSnapshot(
            timestamp: movedFrame.timestamp,
            detectedFeatures: [.mouth],
            mouthRect: CGRect(x: 0.7, y: 0.65, width: 0.12, height: 0.1)
        )
        apply(manager, frame: movedFrame, snapshot: movedSnapshot, configurations: configurations, follow: false)
        XCTAssertEqual(panel.frame.origin, firstOrigin)

        configurations[.mouth]?.windowScale = 1.5
        apply(manager, frame: movedFrame, snapshot: movedSnapshot, configurations: configurations, follow: false)
        XCTAssertEqual(panel.contentView?.frame.size, NSSize(width: 360, height: 270))
        XCTAssertGreaterThan(panel.frame.height, 270, "The native titlebar is outside the live-content area")
        XCTAssertEqual(panel.frame.origin, firstOrigin)
        XCTAssertEqual(ObjectIdentifier(manager.panel(for: .mouth)), panelIdentity)

        apply(manager, frame: movedFrame, snapshot: movedSnapshot, configurations: configurations, follow: true)
        XCTAssertNotEqual(panel.frame.origin, firstOrigin)
    }

    func testStaticModePreservesNativePanelFramesWhileCropsContinueTracking() throws {
        let manager = FeatureWindowManager()
        let configurations = defaultConfigurations()
        let firstFrame = try makeFrame(timestamp: 1)
        let firstSnapshot = makeSnapshot(timestamp: firstFrame.timestamp, detectedFeatures: FeatureID.allCases)
        apply(manager, frame: firstFrame, snapshot: firstSnapshot, configurations: configurations)

        let initialFrames = Dictionary(uniqueKeysWithValues: FeatureID.allCases.map {
            ($0, manager.panel(for: $0).frame)
        })
        let panel = manager.panel(for: .nose)
        manager.move(.nose, to: NSPoint(x: 25, y: 35))
        let draggedFrame = panel.frame
        XCTAssertNotEqual(draggedFrame, initialFrames[.nose])

        let nextFrame = try makeFrame(timestamp: 2)
        let nextSnapshot = makeSnapshot(
            timestamp: nextFrame.timestamp,
            detectedFeatures: FeatureID.allCases,
            noseRect: CGRect(x: 0.72, y: 0.68, width: 0.12, height: 0.12),
            mouthRect: CGRect(x: 0.68, y: 0.35, width: 0.12, height: 0.10)
        )
        apply(manager, frame: nextFrame, snapshot: nextSnapshot, configurations: configurations)

        XCTAssertEqual(panel.frame, draggedFrame, "Tracking and layout must leave a manually moved panel in place")
        for id in FeatureID.allCases where id != .nose {
            XCTAssertEqual(manager.panel(for: id).frame, initialFrames[id], "Static mode must hold \(id)'s native frame")
        }
    }

    func testCropControlsAndWindowOffsetsRemainIndependent() throws {
        let manager = FeatureWindowManager()
        var configurations = defaultConfigurations()
        let frame = try makeFrame(timestamp: 1)
        let snapshot = makeSnapshot(timestamp: frame.timestamp, detectedFeatures: [.leftEye])
        apply(manager, frame: frame, snapshot: snapshot, configurations: configurations)

        let panel = manager.panel(for: .leftEye)
        let originalSize = panel.frame.size
        let originalOrigin = panel.frame.origin
        configurations[.leftEye]?.cropZoom = 2
        configurations[.leftEye]?.cropOffsetX = 0.04
        configurations[.leftEye]?.cropOffsetY = -0.03
        apply(manager, frame: frame, snapshot: snapshot, configurations: configurations)

        XCTAssertEqual(panel.frame.size, originalSize, "Crop framing must not resize the native window")
        XCTAssertEqual(panel.frame.origin, originalOrigin, "Crop framing must not reposition the native window")

        let movedFrame = try makeFrame(timestamp: 2)
        let movedSnapshot = makeSnapshot(timestamp: movedFrame.timestamp, detectedFeatures: [.leftEye])
        configurations[.leftEye]?.windowOffsetX = 80
        configurations[.leftEye]?.windowOffsetY = -35
        apply(manager, frame: movedFrame, snapshot: movedSnapshot, configurations: configurations)

        XCTAssertEqual(panel.frame.origin.x, originalOrigin.x + 80, accuracy: 0.01)
        XCTAssertEqual(panel.frame.origin.y, originalOrigin.y - 35, accuracy: 0.01)
        XCTAssertEqual(panel.frame.size, originalSize)
    }

    func testFreezingOneCropRetainsItsFrameThroughDetectionLossWhileOthersStayLive() throws {
        let manager = FeatureWindowManager()
        let renderer = try XCTUnwrap(SharedRenderer())
        manager.installRenderer(renderer)
        var configurations = defaultConfigurations()
        let firstFrame = try makeFrame(timestamp: 1)
        apply(
            manager,
            frame: firstFrame,
            snapshot: makeSnapshot(timestamp: firstFrame.timestamp, detectedFeatures: [.nose, .mouth]),
            configurations: configurations
        )
        let nosePanel = manager.panel(for: .nose)
        let noseFrame = nosePanel.frame
        XCTAssertEqual(renderer.renderedTimestamp(for: .nose), firstFrame.timestamp)

        configurations[.nose]?.isFrozen = true
        let nextFrame = try makeFrame(timestamp: 20)
        apply(
            manager,
            frame: nextFrame,
            snapshot: makeSnapshot(timestamp: nextFrame.timestamp, detectedFeatures: [.mouth]),
            configurations: configurations
        )
        XCTAssertEqual(renderer.renderedTimestamp(for: .nose), firstFrame.timestamp)
        XCTAssertEqual(renderer.renderedTimestamp(for: .mouth), nextFrame.timestamp)
        XCTAssertEqual(nosePanel.frame, noseFrame)
        XCTAssertTrue(nosePanel.isVisible)

        apply(
            manager,
            frame: nextFrame,
            snapshot: makeSnapshot(timestamp: nextFrame.timestamp, detectedFeatures: []),
            configurations: configurations,
            isLive: false
        )
        XCTAssertTrue(nosePanel.isVisible, "FREEZE keeps its last frame when LIVE stops")
        XCTAssertFalse(manager.panel(for: .mouth).isVisible)
        XCTAssertEqual(renderer.renderedTimestamp(for: .nose), firstFrame.timestamp)

        configurations[.nose]?.isFrozen = false
        let resumedFrame = try makeFrame(timestamp: 21)
        apply(
            manager,
            frame: resumedFrame,
            snapshot: makeSnapshot(timestamp: resumedFrame.timestamp, detectedFeatures: [.nose, .mouth]),
            configurations: configurations
        )
        XCTAssertEqual(renderer.renderedTimestamp(for: .nose), resumedFrame.timestamp)
    }

    func testNativeDragResizePersistsAcrossFramesAndScalePresetCanReplaceIt() throws {
        let manager = FeatureWindowManager()
        let state = AppState()
        manager.onUserResize = { featureID, size in
            state.setWindowSize(size, for: featureID)
        }
        let firstFrame = try makeFrame(timestamp: 1)
        let firstSnapshot = makeSnapshot(timestamp: firstFrame.timestamp, detectedFeatures: [.leftEye])
        apply(manager, frame: firstFrame, snapshot: firstSnapshot, configurations: state.features)

        let panel = manager.panel(for: .leftEye)
        let identity = ObjectIdentifier(panel)
        let draggedSize = NSSize(width: 320, height: 255)
        panel.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
        panel.setContentSize(draggedSize)
        let draggedOrigin = panel.frame.origin
        apply(manager, frame: firstFrame, snapshot: firstSnapshot, configurations: state.features)
        XCTAssertEqual(panel.contentView?.frame.size, draggedSize)
        XCTAssertEqual(panel.frame.origin, draggedOrigin)

        panel.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: panel))
        XCTAssertEqual(state.features[.leftEye]?.windowSizeOverride, draggedSize)
        let nextFrame = try makeFrame(timestamp: 2)
        let nextSnapshot = makeSnapshot(timestamp: nextFrame.timestamp, detectedFeatures: [.leftEye])
        apply(manager, frame: nextFrame, snapshot: nextSnapshot, configurations: state.features)
        XCTAssertEqual(panel.contentView?.frame.size, draggedSize)
        XCTAssertEqual(ObjectIdentifier(panel), identity)

        state.setWindowScale(1.5, for: .leftEye)
        apply(manager, frame: nextFrame, snapshot: nextSnapshot, configurations: state.features)
        XCTAssertNil(state.features[.leftEye]?.windowSizeOverride)
        XCTAssertEqual(panel.contentView?.frame.size, NSSize(width: 360, height: 270))
    }

    func testFrozenWindowCopyRetainsItsOwnFrameWhileAnotherCopyAdvances() throws {
        let renderer = try XCTUnwrap(SharedRenderer())
        let first = WindowInstanceID(featureID: .mouth, serial: 1)
        let second = WindowInstanceID(featureID: .mouth, serial: 2)
        let firstFrame = try makeFrame(timestamp: 1)
        let secondFrame = try makeFrame(timestamp: 2)
        let firstDetection = FeatureDetection(
            id: .mouth,
            normalizedRect: CGRect(x: 0.2, y: 0.25, width: 0.2, height: 0.1),
            confidence: 0.95,
            timestamp: firstFrame.timestamp
        )
        let nextDetection = FeatureDetection(
            id: .mouth,
            normalizedRect: CGRect(x: 0.6, y: 0.25, width: 0.2, height: 0.1),
            confidence: 0.95,
            timestamp: secondFrame.timestamp
        )
        let firstStates = [
            FeatureID.mouth: SmoothedFeatureState(
                detection: firstDetection,
                lifecycle: .visible,
                fadeOpacity: 1
            )
        ]

        renderer.update(
            frame: firstFrame,
            featureStates: firstStates,
            configurations: [first: .default, second: .default],
            requestedMirror: false
        )

        var secondConfiguration = FeatureConfiguration.default
        secondConfiguration.cropOffsetX = 0.25
        var frozenFirstConfiguration = FeatureConfiguration.default
        frozenFirstConfiguration.isFrozen = true
        let nextStates = [
            FeatureID.mouth: SmoothedFeatureState(
                detection: nextDetection,
                lifecycle: .visible,
                fadeOpacity: 1
            )
        ]
        renderer.update(
            frame: secondFrame,
            featureStates: nextStates,
            configurations: [first: frozenFirstConfiguration, second: secondConfiguration],
            requestedMirror: false
        )

        XCTAssertEqual(renderer.renderedTimestamp(for: first), firstFrame.timestamp)
        XCTAssertEqual(renderer.renderedTimestamp(for: second), secondFrame.timestamp)

        let thirdFrame = try makeFrame(timestamp: 3)
        let noDetection = [
            FeatureID.mouth: SmoothedFeatureState(
                detection: nil,
                lifecycle: .hidden,
                fadeOpacity: 0
            )
        ]
        renderer.update(
            frame: thirdFrame,
            featureStates: noDetection,
            configurations: [first: frozenFirstConfiguration, second: secondConfiguration],
            requestedMirror: false
        )

        XCTAssertEqual(renderer.renderedTimestamp(for: first), firstFrame.timestamp)
        XCTAssertNil(renderer.renderedTimestamp(for: second))
        XCTAssertTrue(renderer.hasFrame(for: first))
        XCTAssertFalse(renderer.hasFrame(for: second))
    }

    private func apply(
        _ manager: FeatureWindowManager,
        frame: CameraFrame,
        snapshot: TrackingSnapshot,
        configurations: [FeatureID: FeatureConfiguration],
        isLive: Bool = true,
        showAll: Bool = true,
        follow: Bool = false,
        mirror: Bool = false,
        visibleFrame: CGRect = CGRect(x: 0, y: 0, width: 1_000, height: 800),
        menuWindowFrame: CGRect? = nil
    ) {
        manager.apply(
            snapshot: snapshot,
            frame: frame,
            configurations: configurations,
            isLive: isLive,
            showAll: showAll,
            follow: follow,
            smoothing: 1,
            mirror: mirror,
            screens: [ScreenGeometry(
                displayIdentifier: "primary",
                frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                visibleFrame: visibleFrame,
                backingScaleFactor: 2,
                isPrimary: true
            )],
            menuWindowFrame: menuWindowFrame
        )
    }

    private func defaultConfigurations() -> [FeatureID: FeatureConfiguration] {
        Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { ($0, .default) })
    }

    private func makeSnapshot(
        timestamp: CMTime,
        detectedFeatures: [FeatureID],
        noseRect: CGRect = CGRect(x: 0.42, y: 0.40, width: 0.12, height: 0.12),
        mouthRect: CGRect = CGRect(x: 0.42, y: 0.25, width: 0.12, height: 0.10)
    ) -> TrackingSnapshot {
        var detections: [FeatureID: FeatureDetection] = [:]
        for (index, id) in detectedFeatures.enumerated() {
            let rect: CGRect
            switch id {
            case .nose:
                rect = noseRect
            case .mouth:
                rect = mouthRect
            default:
                rect = CGRect(x: 0.08 + CGFloat(index) * 0.12, y: 0.45, width: 0.08, height: 0.08)
            }
            detections[id] = FeatureDetection(
                id: id,
                normalizedRect: rect,
                confidence: 0.95,
                timestamp: timestamp
            )
        }
        return TrackingSnapshot(timestamp: timestamp, detections: detections)
    }

    private func makeFrame(timestamp: Int64, timescale: Int32 = 30) throws -> CameraFrame {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                64,
                64,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            ),
            kCVReturnSuccess
        )
        return CameraFrame(
            pixelBuffer: try XCTUnwrap(pixelBuffer),
            timestamp: CMTime(value: timestamp, timescale: timescale),
            orientation: .up,
            isMirrored: false
        )
    }
}
