import XCTest
@testable import BlobbyCam

final class ContractTests: XCTestCase {
    @MainActor
    func testEveryFeatureHasOneDefaultConfiguration() throws {
        let state = AppState()

        XCTAssertEqual(FeatureID.allCases.count, 6)
        XCTAssertEqual(Set(state.features.keys), Set(FeatureID.allCases))
        XCTAssertEqual(state.features.count, FeatureID.allCases.count)
        XCTAssertFalse(state.isLive)
        XCTAssertTrue(state.showAll)
        XCTAssertFalse(state.follow)
        XCTAssertEqual(state.smoothing, 0)
        XCTAssertTrue(state.mirror)

        for id in FeatureID.allCases {
            let configuration = try XCTUnwrap(state.features[id])
            XCTAssertTrue(configuration.isEnabled)
            XCTAssertFalse(configuration.isFrozen)
            XCTAssertEqual(configuration.windowScale, 1.0)
            XCTAssertNil(configuration.windowSizeOverride)
            XCTAssertEqual(configuration.cropPadding, 0.25)
            XCTAssertEqual(configuration.detectionThreshold, 0.55)
            XCTAssertEqual(configuration.cropZoom, id == .leftEye || id == .rightEye ? 0.5 : 1)
            XCTAssertEqual(configuration.cropOffsetX, 0)
            XCTAssertEqual(configuration.cropOffsetY, 0)
            XCTAssertEqual(configuration.windowOffsetX, 0)
            XCTAssertEqual(configuration.windowOffsetY, 0)
        }
    }

    @MainActor
    func testScaleAndDetectionThresholdAreClampedAtActionBoundary() {
        let state = AppState()

        state.setWindowScale(-10, for: .leftEye)
        XCTAssertEqual(state.features[.leftEye]?.windowScale, 0.25)

        state.setWindowScale(10, for: .rightEye)
        XCTAssertEqual(state.features[.rightEye]?.windowScale, 4)

        state.setWindowScale(.nan, for: .nose)
        XCTAssertEqual(state.features[.nose]?.windowScale, 1)

        state.setWindowSize(CGSize(width: 310, height: 225), for: .leftEye)
        XCTAssertEqual(state.features[.leftEye]?.windowSizeOverride, CGSize(width: 310, height: 225))
        state.setWindowScale(2, for: .leftEye)
        XCTAssertNil(state.features[.leftEye]?.windowSizeOverride)

        state.setDetectionThreshold(-1, for: .mouth)
        XCTAssertEqual(state.features[.mouth]?.detectionThreshold, 0)

        state.setDetectionThreshold(2, for: .leftHand)
        XCTAssertEqual(state.features[.leftHand]?.detectionThreshold, 1)

        state.setDetectionThreshold(.nan, for: .rightHand)
        XCTAssertEqual(state.features[.rightHand]?.detectionThreshold, FeatureConfiguration.default.detectionThreshold)

        state.setCropZoom(.infinity, for: .leftEye)
        XCTAssertEqual(state.features[.leftEye]?.cropZoom, FeatureConfiguration.cropZoomRange.upperBound)
        state.setCropZoom(.nan, for: .rightEye)
        XCTAssertEqual(state.features[.rightEye]?.cropZoom, 0.5)
        state.setCropOffsetX(-3, for: .nose)
        XCTAssertEqual(state.features[.nose]?.cropOffsetX, -1)
        state.setCropOffsetY(.infinity, for: .mouth)
        XCTAssertEqual(state.features[.mouth]?.cropOffsetY, 1)
        state.setWindowOffsetX(-10_000, for: .leftHand)
        XCTAssertEqual(state.features[.leftHand]?.windowOffsetX, FeatureConfiguration.windowOffsetRange.lowerBound)
        state.setWindowOffsetY(.nan, for: .rightHand)
        XCTAssertEqual(state.features[.rightHand]?.windowOffsetY, 0)
    }

    @MainActor
    func testStateActionsAndResetRestoreDefaults() {
        let state = AppState()
        state.setLive(true)
        state.setShowAll(false)
        state.setFollow(true)
        state.setSmoothing(0.7)
        state.setMirror(true)
        state.setFeatureEnabled(false, for: .leftEye)
        state.setCropPadding(0.4, for: .leftEye)

        XCTAssertTrue(state.isLive)
        XCTAssertFalse(state.showAll)
        XCTAssertTrue(state.follow)
        XCTAssertEqual(state.smoothing, 0.7)
        XCTAssertTrue(state.mirror)
        XCTAssertFalse(state.features[.leftEye]?.isEnabled ?? true)
        XCTAssertEqual(state.features[.leftEye]?.cropPadding, 0.4)

        state.reset()

        XCTAssertFalse(state.isLive)
        XCTAssertTrue(state.showAll)
        XCTAssertFalse(state.follow)
        XCTAssertEqual(state.smoothing, AppState.defaultSmoothing)
        XCTAssertTrue(state.mirror)
        var expectedEye = FeatureConfiguration.default
        expectedEye.cropZoom = 0.5
        XCTAssertEqual(state.features[.leftEye], expectedEye)
    }

    @MainActor
    func testDisablingFeatureClearsFreezeAndPreservesOtherFeature() {
        let state = AppState()
        state.setFeatureFrozen(true, for: .nose)
        state.setFeatureFrozen(true, for: .leftEye)
        XCTAssertTrue(state.features[.nose]?.isFrozen == true)
        state.setFeatureEnabled(false, for: .nose)
        XCTAssertFalse(state.features[.nose]?.isFrozen ?? true)
        XCTAssertTrue(state.features[.leftEye]?.isFrozen == true)
        state.setFeatureEnabled(true, for: .nose)
        XCTAssertFalse(state.features[.nose]?.isFrozen ?? true)
    }
}
