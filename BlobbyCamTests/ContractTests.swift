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

    @MainActor
    func testWindowCopiesCloneFirstConfigurationAndThenEditIndependently() throws {
        let state = AppState()
        let firstID = try XCTUnwrap(state.windowIDs(for: .mouth).first)
        XCTAssertEqual(firstID.serial, 1)

        state.setWindowSize(CGSize(width: 420, height: 280), for: firstID)
        state.setCropZoom(2.25, for: firstID)
        state.setCropOffsetX(0.2, for: firstID)
        state.setDetectionThreshold(0.8, for: firstID)

        state.setWindowCount(3, for: .mouth)
        let ids = state.windowIDs(for: .mouth)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(ids.map(\.serial), [1, 2, 3])
        XCTAssertEqual(state.configuration(for: ids[1]), state.configuration(for: firstID))
        XCTAssertEqual(state.configuration(for: ids[2]), state.configuration(for: firstID))

        state.setCropZoom(4, for: ids[1])
        state.setFeatureEnabled(false, for: ids[1])
        XCTAssertEqual(state.configuration(for: firstID)?.cropZoom, 2.25)
        XCTAssertTrue(state.configuration(for: firstID)?.isEnabled == true)
        XCTAssertFalse(state.configuration(for: ids[1])?.isEnabled ?? true)

        state.setWindowCount(4, for: .mouth)
        let fourthID = try XCTUnwrap(state.windowIDs(for: .mouth).last)
        XCTAssertEqual(state.configuration(for: fourthID), state.configuration(for: firstID),
                       "New instances clone the current first configuration, not another copy's edits")
        XCTAssertTrue(state.configuration(for: fourthID)?.isEnabled == true,
                      "A disabled secondary instance does not change the first instance inherited by new copies")
    }

    @MainActor
    func testWindowCountShrinksFromEndAndUsesFreshMonotonicIDsWhenExpanded() throws {
        let state = AppState()
        state.setWindowCount(4, for: .nose)
        let originalIDs = state.windowIDs(for: .nose)
        state.setWindowSize(CGSize(width: 500, height: 330), for: originalIDs[1])

        state.setWindowCount(2, for: .nose)
        XCTAssertEqual(state.windowIDs(for: .nose), Array(originalIDs.prefix(2)))
        XCTAssertNil(state.configuration(for: originalIDs[2]))
        XCTAssertNil(state.configuration(for: originalIDs[3]))
        XCTAssertEqual(state.configuration(for: originalIDs[1])?.windowSizeOverride, CGSize(width: 500, height: 330))

        state.setWindowCount(3, for: .nose)
        let expandedIDs = state.windowIDs(for: .nose)
        XCTAssertEqual(expandedIDs.count, 3)
        XCTAssertEqual(expandedIDs[2].serial, 5)
        XCTAssertNotEqual(expandedIDs[2], originalIDs[2])

        state.setWindowCount(99, for: .nose)
        XCTAssertEqual(state.windowCount(for: .nose), AppState.maximumWindowCount)
        state.setWindowCount(0, for: .nose)
        XCTAssertEqual(state.windowCount(for: .nose), 1)
        XCTAssertEqual(state.windowIDs(for: .nose).first, originalIDs.first)
    }

    @MainActor
    func testTwentyMouthsInheritCurrentCropAndKeepIndependentSizes() throws {
        let state = AppState()
        let firstID = try XCTUnwrap(state.windowIDs(for: .mouth).first)
        state.setWindowSize(CGSize(width: 360, height: 240), for: firstID)
        state.setCropZoom(1.75, for: firstID)

        state.setWindowCount(20, for: .mouth)
        let ids = state.windowIDs(for: .mouth)
        XCTAssertEqual(ids.count, 20)
        XCTAssertEqual(Set(ids).count, 20)
        XCTAssertTrue(ids.allSatisfy { state.configuration(for: $0)?.cropZoom == 1.75 })
        XCTAssertTrue(ids.allSatisfy {
            state.configuration(for: $0)?.windowSizeOverride == CGSize(width: 360, height: 240)
        })

        state.setWindowSize(CGSize(width: 500, height: 300), for: ids[10])
        XCTAssertEqual(state.configuration(for: ids[10])?.windowSizeOverride, CGSize(width: 500, height: 300))
        XCTAssertEqual(state.configuration(for: ids[9])?.windowSizeOverride, CGSize(width: 360, height: 240))
        XCTAssertEqual(state.configuration(for: ids[11])?.windowSizeOverride, CGSize(width: 360, height: 240))
    }

    @MainActor
    func testClosingSpecificWindowAndFinalWindowKeepsPanelIdentity() throws {
        let state = AppState()
        state.setWindowCount(3, for: .leftEye)
        let initialIDs = state.windowIDs(for: .leftEye)
        state.setFeatureFrozen(true, for: initialIDs[1])

        XCTAssertTrue(state.closeWindowInstance(initialIDs[1]))
        XCTAssertEqual(state.windowIDs(for: .leftEye), [initialIDs[0], initialIDs[2]])
        XCTAssertNil(state.configuration(for: initialIDs[1]))
        XCTAssertEqual(state.windowCount(for: .leftEye), 2)

        state.setWindowCount(1, for: .leftEye)
        let retainedID = try XCTUnwrap(state.windowIDs(for: .leftEye).first)
        state.setFeatureFrozen(true, for: retainedID)
        XCTAssertTrue(state.closeWindowInstance(retainedID))
        XCTAssertEqual(state.windowIDs(for: .leftEye), [retainedID])
        XCTAssertFalse(state.configuration(for: retainedID)?.isEnabled ?? true)
        XCTAssertFalse(state.configuration(for: retainedID)?.isFrozen ?? true)

        state.setFeatureEnabled(true, for: .leftEye)
        XCTAssertEqual(state.windowIDs(for: .leftEye), [retainedID])
        XCTAssertTrue(state.configuration(for: retainedID)?.isEnabled == true)
    }

    @MainActor
    func testFeatureLevelEnableControlsAllCopiesAndResetRetainsFirstIdentity() throws {
        let state = AppState()
        state.setWindowCount(3, for: .rightHand)
        let ids = state.windowIDs(for: .rightHand)
        state.setFeatureEnabled(false, for: .rightHand)
        XCTAssertTrue(ids.allSatisfy { state.configuration(for: $0)?.isEnabled == false })

        state.setFeatureEnabled(true, for: .rightHand)
        XCTAssertTrue(ids.allSatisfy { state.configuration(for: $0)?.isEnabled == true })
        state.setCropZoom(3, for: ids[1])
        state.reset()

        XCTAssertEqual(state.windowIDs(for: .rightHand), [ids[0]])
        XCTAssertEqual(state.features[.rightHand], FeatureConfiguration.default)
        state.setWindowCount(2, for: .rightHand)
        XCTAssertEqual(state.windowIDs(for: .rightHand).last?.serial, 4,
                       "Reset must not make retired serials available for reuse")
    }
}
