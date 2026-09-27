import AppKit
import XCTest
@testable import BlobbyCam

@MainActor
final class FeatureWindowManagerTests: XCTestCase {
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
}
