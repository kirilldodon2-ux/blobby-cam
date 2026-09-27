import CoreGraphics
import CoreMedia
import XCTest
@testable import BlobbyCam

final class TrackingSmootherTests: XCTestCase {
    func testShowThresholdRequiresValidGeometryAndConfidence() {
        var smoother = TrackingSmoother()
        let configs = defaultConfigurations()

        let lowConfidence = smoother.process(
            snapshot(milliseconds: 0, detections: [.nose: detection(.nose, rect: rect(0.2), confidence: 0.54, time: 0)]),
            configurations: configs
        )
        assertHidden(lowConfidence[.nose])

        let invalidGeometry = FeatureDetection(
            id: .nose,
            normalizedRect: CGRect(x: .nan, y: 0.2, width: 0.2, height: 0.2),
            confidence: 0.9,
            timestamp: time(10)
        )
        let invalid = smoother.process(
            snapshot(milliseconds: 10, detections: [.nose: invalidGeometry]),
            configurations: configs
        )
        assertHidden(invalid[.nose])
        XCTAssertNil(invalid[.nose]?.detection)
    }

    func testSingleFrameMissHoldsGeometryAndReacquisitionSmoothsIt() throws {
        var smoother = TrackingSmoother()
        let configs = defaultConfigurations()
        _ = smoother.process(
            snapshot(milliseconds: 0, detections: [.nose: detection(.nose, rect: rect(0.2), time: 0)]),
            configurations: configs
        )

        let missed = smoother.process(snapshot(milliseconds: 100, detections: [:]), configurations: configs)
        let graceState = try XCTUnwrap(missed[.nose])
        if case .grace(let lastSeen) = graceState.lifecycle {
            XCTAssertEqual(lastSeen, time(0))
        } else {
            XCTFail("Expected a grace state after a frame miss")
        }
        XCTAssertEqual(graceState.detection?.normalizedRect, rect(0.2))
        XCTAssertEqual(graceState.fadeOpacity, 1)

        let reacquired = smoother.process(
            snapshot(milliseconds: 150, detections: [.nose: detection(
                .nose,
                rect: CGRect(x: 0.6, y: 0.5, width: 0.4, height: 0.3),
                confidence: 0.45,
                time: 150
            )]),
            configurations: configs,
            smoothing: 0.7
        )
        let visibleState = try XCTUnwrap(reacquired[.nose])
        if case .visible = visibleState.lifecycle {} else {
            XCTFail("A detection above the hold threshold should reacquire the feature")
        }
        XCTAssertEqual(visibleState.detection?.normalizedRect.minX ?? -1, 0.32, accuracy: 0.000001)
        XCTAssertEqual(visibleState.detection?.normalizedRect.width ?? -1, 0.26, accuracy: 0.000001)
        XCTAssertEqual(visibleState.detection?.timestamp, time(150))
    }

    func testGraceThenHideFadeThenHiddenUsesFrameTime() throws {
        var smoother = TrackingSmoother()
        let configs = defaultConfigurations()
        _ = smoother.process(
            snapshot(milliseconds: 0, detections: [.leftHand: detection(.leftHand, rect: rect(0.25), time: 0)]),
            configurations: configs
        )

        let duringGrace = smoother.process(snapshot(milliseconds: 250, detections: [:]), configurations: configs)[.leftHand]
        let grace = try XCTUnwrap(duringGrace)
        XCTAssertEqual(grace.fadeOpacity, 1)
        if case .grace = grace.lifecycle {} else { XCTFail("Expected grace at 250 ms") }

        let fading = try XCTUnwrap(smoother.process(snapshot(milliseconds: 310, detections: [:]), configurations: configs)[.leftHand])
        XCTAssertTrue(fading.isFading)
        XCTAssertEqual(fading.fadeOpacity, 0.5, accuracy: 0.000001)
        XCTAssertEqual(fading.detection?.normalizedRect, rect(0.25))

        let hidden = smoother.process(snapshot(milliseconds: 380, detections: [:]), configurations: configs)[.leftHand]
        assertHidden(hidden)
    }

    func testStaleSnapshotCannotMoveFeatureBackward() throws {
        var smoother = TrackingSmoother()
        let configs = defaultConfigurations()
        _ = smoother.process(
            snapshot(milliseconds: 1000, detections: [.mouth: detection(.mouth, rect: rect(0.2), time: 1000)]),
            configurations: configs
        )

        let stale = smoother.process(
            snapshot(milliseconds: 900, detections: [.mouth: detection(.mouth, rect: rect(0.8), time: 900)]),
            configurations: configs
        )
        let state = try XCTUnwrap(stale[.mouth])
        XCTAssertEqual(state.detection?.normalizedRect, rect(0.2))
        XCTAssertEqual(state.detection?.timestamp, time(1000))
    }

    func testFaceCropReferenceSurvivesSmoothing() throws {
        var smoother = TrackingSmoother()
        let configs = defaultConfigurations()
        let first = FeatureDetection(
            id: .mouth,
            normalizedRect: rect(0.2),
            confidence: 0.9,
            timestamp: time(0),
            cropReferenceSize: CGSize(width: 0.2, height: 0.1)
        )
        let second = FeatureDetection(
            id: .mouth,
            normalizedRect: rect(0.3),
            confidence: 0.9,
            timestamp: time(100),
            cropReferenceSize: CGSize(width: 0.4, height: 0.2)
        )
        _ = smoother.process(snapshot(milliseconds: 0, detections: [.mouth: first]), configurations: configs)
        let result = smoother.process(snapshot(milliseconds: 100, detections: [.mouth: second]), configurations: configs, smoothing: 0.7)
        let size = try XCTUnwrap(result[.mouth]?.detection?.cropReferenceSize)
        XCTAssertEqual(size.width, 0.26, accuracy: 0.000001)
        XCTAssertEqual(size.height, 0.13, accuracy: 0.000001)
    }

    func testZeroSmoothingMovesCropAnchorToCurrentLandmarks() throws {
        var smoother = TrackingSmoother()
        let configs = defaultConfigurations()
        _ = smoother.process(
            snapshot(milliseconds: 0, detections: [.leftEye: detection(.leftEye, rect: rect(0.2), time: 0)]),
            configurations: configs,
            smoothing: 0
        )
        let moved = smoother.process(
            snapshot(milliseconds: 100, detections: [.leftEye: detection(.leftEye, rect: rect(0.6), time: 100)]),
            configurations: configs,
            smoothing: 0
        )
        XCTAssertEqual(try XCTUnwrap(moved[.leftEye]?.detection).normalizedRect, rect(0.6))
    }

    func testMaximumSmoothingStillTracksMotion() throws {
        var smoother = TrackingSmoother()
        let configs = defaultConfigurations()
        _ = smoother.process(
            snapshot(milliseconds: 0, detections: [.nose: detection(.nose, rect: rect(0.2), time: 0)]),
            configurations: configs,
            smoothing: 1
        )
        let moved = smoother.process(
            snapshot(milliseconds: 100, detections: [.nose: detection(.nose, rect: rect(0.6), time: 100)]),
            configurations: configs,
            smoothing: 1
        )
        XCTAssertGreaterThan(try XCTUnwrap(moved[.nose]?.detection).normalizedRect.minX, 0.2)
    }

    func testFeatureOffAndResetClearHeldStateAndTimestampHistory() throws {
        var smoother = TrackingSmoother()
        var configs = defaultConfigurations()
        _ = smoother.process(
            snapshot(milliseconds: 100, detections: [.rightEye: detection(.rightEye, rect: rect(0.3), time: 100)]),
            configurations: configs
        )
        configs[.rightEye]?.isEnabled = false
        let disabled = smoother.process(snapshot(milliseconds: 110, detections: [:]), configurations: configs)
        assertHidden(disabled[.rightEye])
        XCTAssertNil(disabled[.rightEye]?.detection)

        configs[.rightEye]?.isEnabled = true
        _ = smoother.process(
            snapshot(milliseconds: 120, detections: [.rightEye: detection(.rightEye, rect: rect(0.6), time: 120)]),
            configurations: configs
        )
        smoother.reset()
        let resetState = smoother.process(
            snapshot(milliseconds: 10, detections: [.rightEye: detection(.rightEye, rect: rect(0.7), time: 10)]),
            configurations: configs
        )
        XCTAssertEqual(resetState[.rightEye]?.detection?.normalizedRect, rect(0.7))
        XCTAssertEqual(resetState[.rightEye]?.detection?.timestamp, time(10))
    }

    private func defaultConfigurations() -> [FeatureID: FeatureConfiguration] {
        Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { ($0, FeatureConfiguration.default) })
    }

    private func snapshot(milliseconds: Int64, detections: [FeatureID: FeatureDetection]) -> TrackingSnapshot {
        TrackingSnapshot(timestamp: time(milliseconds), detections: detections)
    }

    private func detection(
        _ id: FeatureID,
        rect: CGRect,
        confidence: Float = 0.9,
        time milliseconds: Int64
    ) -> FeatureDetection {
        FeatureDetection(id: id, normalizedRect: rect, confidence: confidence, timestamp: time(milliseconds))
    }

    private func rect(_ minX: CGFloat) -> CGRect {
        CGRect(x: minX, y: 0.3, width: 0.2, height: 0.2)
    }

    private func time(_ milliseconds: Int64) -> CMTime {
        CMTime(value: milliseconds, timescale: 1000)
    }

    private func assertHidden(_ state: SmoothedFeatureState?, file: StaticString = #filePath, line: UInt = #line) {
        guard let state else {
            XCTFail("Expected an output state for every feature", file: file, line: line)
            return
        }
        if case .hidden = state.lifecycle {} else {
            XCTFail("Expected a hidden feature", file: file, line: line)
        }
        XCTAssertNil(state.detection, file: file, line: line)
        XCTAssertEqual(state.fadeOpacity, 0, file: file, line: line)
    }
}
