import AppKit
import CoreMedia
import CoreVideo
import XCTest
@testable import BlobbyCam

@MainActor
final class FeatureWindowManagerTests: XCTestCase {
    func testChromeTogglePreservesPanelIdentityVideoSizeAndPosition() throws {
        let manager = FeatureWindowManager()
        let state = AppState()
        let id = try XCTUnwrap(state.windowIDs(for: .mouth).first)
        let panel = manager.panel(for: id)
        manager.move(.mouth, to: NSPoint(x: 100, y: 140))
        manager.resize(.mouth, to: NSSize(width: 340, height: 210))
        let identity = ObjectIdentifier(panel)
        let origin = panel.frame.origin
        let size = panel.contentView?.frame.size
        for _ in 0..<5 {
            state.setUIBarHidden(true, for: id)
            manager.applyWindowChrome(configurations: state.configurationsByWindowID)
            XCTAssertTrue(panel.hidesUIBar)
            XCTAssertFalse(panel.styleMask.contains(.titled))
            XCTAssertTrue(panel.styleMask.contains(.resizable))
            XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
            XCTAssertTrue(panel.isMovableByWindowBackground)
            XCTAssertFalse(panel.canBecomeKey)
            XCTAssertEqual(panel.contentView?.frame.size, size)
            XCTAssertEqual(panel.frame.origin, origin)
            XCTAssertFalse(manager.panel(for: .nose).hidesUIBar)
            state.setUIBarHidden(false, for: id)
            manager.applyWindowChrome(configurations: state.configurationsByWindowID)
            XCTAssertTrue(panel.styleMask.contains(.titled))
            XCTAssertNotNil(panel.standardWindowButton(.closeButton))
            XCTAssertEqual(panel.contentView?.frame.size, size)
            XCTAssertEqual(panel.frame.origin, origin)
            XCTAssertEqual(ObjectIdentifier(manager.panel(for: id)), identity)
        }
    }

    func testGlobalChromeSettingAllowsIndependentCopyOverrideAndReset() throws {
        let state = AppState()
        XCTAssertFalse(state.allUIBarsHidden)
        state.setWindowCount(3, for: .mouth)
        let mouthIDs = state.windowIDs(for: .mouth)
        state.setAllUIBarsHidden(true)
        XCTAssertTrue(state.allUIBarsHidden)
        state.setUIBarHidden(false, for: mouthIDs[1])
        XCTAssertFalse(state.allUIBarsHidden)
        XCTAssertEqual(state.configuration(for: mouthIDs[0])?.hidesUIBar, true)
        XCTAssertEqual(state.configuration(for: mouthIDs[1])?.hidesUIBar, false)
        state.setWindowCount(4, for: .mouth)
        let newID = try XCTUnwrap(state.windowIDs(for: .mouth).last)
        XCTAssertEqual(state.configuration(for: newID)?.hidesUIBar, true)
        state.reset()
        XCTAssertTrue(state.configurationsByWindowID.values.allSatisfy { !$0.hidesUIBar })
    }

    func testCreatesSixDistinctPersistentPanels() {
        let manager = FeatureWindowManager()

        XCTAssertEqual(manager.panels.count, FeatureID.allCases.count)
        let identities = FeatureID.allCases.map { ObjectIdentifier(manager.panel(for: $0)) }
        XCTAssertEqual(Set(identities).count, FeatureID.allCases.count)

        for featureID in FeatureID.allCases {
            let panel = manager.panel(for: featureID)
            XCTAssertEqual(panel.featureID, featureID)
            XCTAssertEqual(panel.title, featureID.windowTitle)
            XCTAssertFalse(panel.isVisible)
            XCTAssertEqual(panel.styleMask, [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel])
            XCTAssertEqual(panel.contentMinSize, NSSize(width: 80, height: 60))
            XCTAssertEqual(panel.contentMaxSize, NSSize(width: 960, height: 720))
            XCTAssertNotNil(panel.standardWindowButton(.closeButton))
            XCTAssertNotNil(panel.standardWindowButton(.miniaturizeButton))
            XCTAssertNotNil(panel.standardWindowButton(.zoomButton))
            XCTAssertEqual(panel.appearance?.name, .darkAqua)
            XCTAssertEqual(panel.titleVisibility, .visible)
            XCTAssertFalse(panel.titlebarAppearsTransparent)
            XCTAssertEqual(panel.level, .floating)
            XCTAssertTrue(panel.isFloatingPanel)
            XCTAssertTrue(panel.isMovable)
            XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
            XCTAssertFalse(panel.canBecomeKey)
            XCTAssertFalse(panel.canBecomeMain)
            XCTAssertFalse(panel.ignoresMouseEvents)
            XCTAssertTrue(panel.isOpaque)
            XCTAssertEqual(panel.backgroundColor, .black)
            XCTAssertFalse(panel.hidesOnDeactivate)
            XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
            XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
            XCTAssertEqual(panel.contentView?.frame.size, FeatureWindowManager.defaultPanelSize)
            XCTAssertTrue(panel.contentView?.autoresizingMask.contains(.width) == true)
            XCTAssertTrue(panel.contentView?.autoresizingMask.contains(.height) == true)
        }
    }

    func testShowHideMoveAndResizeKeepPanelIdentity() {
        let manager = FeatureWindowManager()
        let original = manager.panel(for: .leftEye)
        let identity = ObjectIdentifier(original)

        for _ in 0..<3 {
            manager.show(.leftEye)
            XCTAssertTrue(original.isVisible)
            manager.hide(.leftEye)
            XCTAssertFalse(original.isVisible)
        }

        manager.move(.leftEye, to: NSPoint(x: 90, y: 120))
        manager.resize(.leftEye, to: NSSize(width: 320, height: 210))

        XCTAssertEqual(original.frame.origin, NSPoint(x: 90, y: 120))
        XCTAssertEqual(original.contentView?.frame.size, NSSize(width: 320, height: 210))
        XCTAssertEqual(ObjectIdentifier(manager.panel(for: .leftEye)), identity)
    }

    func testRedCloseTurnsFeatureOffAndReusesTheSamePanelOnEnable() {
        let manager = FeatureWindowManager()
        let state = AppState()
        manager.onUserClose = { id in state.setFeatureEnabled(false, for: id) }
        let nose = manager.panel(for: .nose)
        let identity = ObjectIdentifier(nose)
        manager.show(.nose)
        XCTAssertTrue(nose.isVisible)
        XCTAssertFalse(nose.windowShouldClose(nose))
        XCTAssertFalse(nose.isVisible)
        XCTAssertFalse(state.features[.nose]?.isEnabled ?? true)
        XCTAssertTrue(state.features[.mouth]?.isEnabled == true)
        state.setFeatureEnabled(true, for: .nose)
        manager.show(.nose)
        XCTAssertTrue(nose.isVisible)
        XCTAssertEqual(ObjectIdentifier(manager.panel(for: .nose)), identity)
    }

    func testRenderViewCanBeReplacedWithoutReplacingPanel() throws {
        let manager = FeatureWindowManager()
        let panel = manager.panel(for: .mouth)
        let identity = ObjectIdentifier(panel)
        let renderView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))

        manager.installRenderView(renderView, for: .mouth)

        XCTAssertTrue(try XCTUnwrap(panel.contentView) === renderView)
        XCTAssertEqual(ObjectIdentifier(manager.panel(for: .mouth)), identity)
    }

    func testCopyCloseRemovesOnlyThatPanelAndRenumbersSurvivors() {
        let manager = FeatureWindowManager()
        let state = AppState()
        state.setWindowCount(3, for: .mouth)
        manager.reconcileWindowIDs(state.windowIDsByFeature)

        let ids = state.windowIDs(for: .mouth)
        let first = manager.panel(for: ids[0])
        let middle = manager.panel(for: ids[1])
        let last = manager.panel(for: ids[2])
        let middleIdentity = ObjectIdentifier(middle)
        let lastIdentity = ObjectIdentifier(last)
        let lastFrame = CGRect(x: 620, y: 420, width: 240, height: 180)
        last.setFrame(lastFrame, display: false)
        manager.onUserClose = { id in state.closeWindowInstance(id) }

        XCTAssertFalse(middle.windowShouldClose(middle))
        manager.reconcileWindowIDs(state.windowIDsByFeature)

        XCTAssertNil(manager.panelsByWindowID[ids[1]])
        XCTAssertTrue(manager.panelsByWindowID[ids[0]] === first)
        XCTAssertEqual(ObjectIdentifier(manager.panel(for: ids[2])), lastIdentity)
        XCTAssertEqual(last.frame, lastFrame)
        XCTAssertEqual(first.title, "MOUTH 1")
        XCTAssertEqual(last.title, "MOUTH 2")
        XCTAssertEqual(state.windowIDs(for: .mouth), [ids[0], ids[2]])
        XCTAssertEqual(manager.panels.count, FeatureID.allCases.count)
        XCTAssertEqual(ObjectIdentifier(middle), middleIdentity)
    }

    func testLastCopyCloseTurnsOffAndRetainsItsPanel() {
        let manager = FeatureWindowManager()
        let state = AppState()
        let id = state.windowIDs(for: .mouth)[0]
        let panel = manager.panel(for: id)
        let identity = ObjectIdentifier(panel)
        manager.onUserClose = { id in state.closeWindowInstance(id) }

        XCTAssertFalse(panel.windowShouldClose(panel))
        manager.reconcileWindowIDs(state.windowIDsByFeature)

        XCTAssertEqual(state.windowIDs(for: .mouth), [id])
        XCTAssertFalse(state.configuration(for: id)?.isEnabled ?? true)
        XCTAssertEqual(ObjectIdentifier(manager.panel(for: id)), identity)
        XCTAssertFalse(panel.isVisible)
    }

    func testTwentyMouthCopiesKeepIDsSharedRendererAndIndependentNativeSizesAfterMiddleClose() throws {
        let manager = FeatureWindowManager()
        let state = AppState()
        let renderer = try XCTUnwrap(SharedRenderer())
        manager.installRenderer(renderer)
        state.setWindowCount(20, for: .mouth)
        manager.reconcileWindowIDs(state.windowIDsByFeature)

        let originalPanelIdentities = FeatureID.allCases.map { ObjectIdentifier(manager.panel(for: $0)) }
        let ids = state.windowIDs(for: .mouth)
        XCTAssertEqual(ids.count, 20)
        XCTAssertEqual(manager.panelsByWindowID.count, FeatureID.allCases.count + 19)
        for (index, id) in ids.enumerated() {
            let panel = manager.panel(for: id)
            XCTAssertEqual(panel.title, "MOUTH \(index + 1)")
            XCTAssertEqual((panel.contentView as? FeatureRenderView)?.windowID, id)
            manager.resize(id, to: NSSize(
                width: CGFloat(140 + index * 3),
                height: CGFloat(100 + index * 2)
            ))
        }

        let firstSize = manager.panel(for: ids[0]).contentView?.frame.size
        let thirdSize = manager.panel(for: ids[2]).contentView?.frame.size
        XCTAssertNotEqual(firstSize, thirdSize)
        let firstIdentity = ObjectIdentifier(manager.panel(for: ids[0]))
        let thirdIdentity = ObjectIdentifier(manager.panel(for: ids[2]))
        let twentiethIdentity = ObjectIdentifier(manager.panel(for: ids[19]))
        let middle = manager.panel(for: ids[9])
        manager.onUserClose = { id in
            state.closeWindowInstance(id)
        }

        XCTAssertFalse(middle.windowShouldClose(middle))
        // Reconcile only after AppKit's close callback has returned, as the app does.
        manager.reconcileWindowIDs(state.windowIDsByFeature)
        drainMainRunLoop()

        let survivors = state.windowIDs(for: .mouth)
        XCTAssertEqual(survivors.count, 19)
        XCTAssertFalse(survivors.contains(ids[9]))
        XCTAssertEqual(ObjectIdentifier(manager.panel(for: ids[0])), firstIdentity)
        XCTAssertEqual(ObjectIdentifier(manager.panel(for: ids[2])), thirdIdentity)
        XCTAssertEqual(ObjectIdentifier(manager.panel(for: ids[19])), twentiethIdentity)
        XCTAssertEqual(middle.title, "MOUTH 10")
        XCTAssertEqual(manager.panel(for: ids[10]).title, "MOUTH 10")
        XCTAssertEqual(manager.panel(for: ids[0]).contentView?.frame.size, firstSize)
        XCTAssertEqual(manager.panel(for: ids[2]).contentView?.frame.size, thirdSize)
        XCTAssertEqual(FeatureID.allCases.map { ObjectIdentifier(manager.panel(for: $0)) }, originalPanelIdentities)
    }

    func testRemovedExtraPanelIsHiddenAndReusedForANewID() throws {
        let manager = FeatureWindowManager()
        let state = AppState()
        manager.installRenderer(try XCTUnwrap(SharedRenderer()))
        let originals = FeatureID.allCases.map { ObjectIdentifier(manager.panel(for: $0)) }
        state.setWindowCount(2, for: .mouth)
        manager.reconcileWindowIDs(state.windowIDsByFeature)
        let extraID = state.windowIDs(for: .mouth)[1]
        let extra = manager.panel(for: extraID)
        manager.show(extraID)
        XCTAssertTrue(extra.isVisible)
        state.setWindowCount(1, for: .mouth)
        manager.reconcileWindowIDs(state.windowIDsByFeature)

        XCTAssertNil(manager.panelsByWindowID[extraID])
        XCTAssertFalse(extra.isVisible)
        XCTAssertEqual(manager.reusablePanelsByFeature[.mouth]?.count, 1)
        XCTAssertEqual(FeatureID.allCases.map { ObjectIdentifier(manager.panel(for: $0)) }, originals)

        state.setWindowCount(2, for: .mouth)
        manager.reconcileWindowIDs(state.windowIDsByFeature)
        let replacementID = state.windowIDs(for: .mouth)[1]
        XCTAssertNotEqual(replacementID, extraID)
        XCTAssertTrue(manager.panel(for: replacementID) === extra)
        XCTAssertEqual(extra.windowID, replacementID)
        XCTAssertEqual((extra.contentView as? FeatureRenderView)?.windowID, replacementID)
        XCTAssertTrue(manager.reusablePanelsByFeature[.mouth]?.isEmpty ?? true)
    }

    func testAutoFollowOffKeepsManuallyPlacedCopiesWhenAnotherCopySpawns() throws {
        let manager = FeatureWindowManager()
        let state = AppState()
        state.setWindowCount(2, for: .mouth)
        manager.reconcileWindowIDs(state.windowIDsByFeature)
        let firstID = try XCTUnwrap(state.windowIDs(for: .mouth).first)
        let secondID = state.windowIDs(for: .mouth)[1]
        let time1 = CMTime(value: 1, timescale: 30)
        let frame1 = try makeFrame(time1)
        let detection1 = FeatureDetection(
            id: .mouth,
            normalizedRect: CGRect(x: 0.38, y: 0.24, width: 0.16, height: 0.12),
            confidence: 0.95,
            timestamp: time1
        )
        apply(manager, frame: frame1, detection: detection1, state: state)

        let firstPanel = manager.panel(for: firstID)
        let secondPanel = manager.panel(for: secondID)
        firstPanel.setFrameOrigin(NSPoint(x: 60, y: 70))
        secondPanel.setFrameOrigin(NSPoint(x: 620, y: 410))
        let firstFrame = firstPanel.frame
        let secondFrame = secondPanel.frame

        state.setWindowCount(3, for: .mouth)
        manager.reconcileWindowIDs(state.windowIDsByFeature)
        let time2 = CMTime(value: 2, timescale: 30)
        let frame2 = try makeFrame(time2)
        let detection2 = FeatureDetection(
            id: .mouth,
            normalizedRect: CGRect(x: 0.55, y: 0.28, width: 0.16, height: 0.12),
            confidence: 0.95,
            timestamp: time2
        )
        apply(manager, frame: frame2, detection: detection2, state: state)

        XCTAssertEqual(firstPanel.frame, firstFrame)
        XCTAssertEqual(secondPanel.frame, secondFrame)
        let spawnedID = try XCTUnwrap(state.windowIDs(for: .mouth).last)
        let spawned = manager.panel(for: spawnedID)
        XCTAssertFalse(spawned.frame.intersects(firstPanel.frame))
        XCTAssertFalse(spawned.frame.intersects(secondPanel.frame))
    }

    private func apply(
        _ manager: FeatureWindowManager,
        frame: CameraFrame,
        detection: FeatureDetection,
        state: AppState
    ) {
        let snapshot = TrackingSnapshot(timestamp: frame.timestamp, detections: [.mouth: detection])
        manager.apply(
            snapshot: snapshot,
            frame: frame,
            windowIDsByFeature: state.windowIDsByFeature,
            configurations: state.configurationsByWindowID,
            isLive: true,
            showAll: true,
            follow: false,
            smoothing: 0,
            mirror: false,
            screens: [ScreenGeometry(
                displayIdentifier: "primary",
                frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                backingScaleFactor: 2,
                isPrimary: true
            )],
            menuWindowFrame: nil
        )
    }

    private func makeFrame(_ timestamp: CMTime) throws -> CameraFrame {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer),
            kCVReturnSuccess
        )
        return CameraFrame(
            pixelBuffer: try XCTUnwrap(pixelBuffer),
            timestamp: timestamp,
            orientation: .up,
            isMirrored: false
        )
    }

    private func drainMainRunLoop() {
        autoreleasepool {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }
}
