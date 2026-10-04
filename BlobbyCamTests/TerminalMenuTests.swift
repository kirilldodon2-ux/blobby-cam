import CoreGraphics
import XCTest
@testable import BlobbyCam

final class TerminalMenuTests: XCTestCase {
    func testHomeNavigationClampsAndOpensTheSelectedFeaturesWindowList() {
        var model = TerminalMenuModel()
        let snapshot = makeSnapshot()

        XCTAssertNil(model.handle(.up, snapshot: snapshot))
        XCTAssertEqual(model.selectedHomeIndex, 0)

        for featureID in FeatureID.allCases {
            let expectedIndex = TerminalMenuModel.firstFeatureIndex + (FeatureID.allCases.firstIndex(of: featureID) ?? 0)
            while model.selectedHomeIndex < expectedIndex {
                XCTAssertNil(model.handle(.down, snapshot: snapshot))
            }
            XCTAssertNil(model.handle(.enter, snapshot: snapshot))
            XCTAssertEqual(model.selectedFeature, featureID)
            XCTAssertTrue(model.isShowingWindowList)
            XCTAssertNil(model.handle(.escape, snapshot: snapshot))
            XCTAssertFalse(model.isShowingFeatureDetails)
            XCTAssertEqual(model.selectedHomeIndex, expectedIndex)
        }

        for _ in 0..<TerminalMenuModel.homeItemCount {
            _ = model.handle(.down, snapshot: snapshot)
        }
        XCTAssertEqual(model.selectedHomeIndex, TerminalMenuModel.homeItemCount - 1)
        XCTAssertNil(model.handle(.down, snapshot: snapshot))
        XCTAssertEqual(model.selectedHomeIndex, TerminalMenuModel.homeItemCount - 1)
    }

    func testEveryGlobalActionHasAKeyboardPath() {
        XCTAssertEqual(action(atHomeIndex: 0, key: .enter), .toggleLive)
        XCTAssertEqual(action(atHomeIndex: 1, key: .right), .toggleAll)
        XCTAssertEqual(action(atHomeIndex: 2, key: .left), .toggleFollow)
        XCTAssertEqual(action(atHomeIndex: 3, key: .enter), .toggleMirror)
        XCTAssertEqual(action(atHomeIndex: 4, key: .left), .adjustSmoothing(-1))
        XCTAssertEqual(action(atHomeIndex: 4, key: .right), .adjustSmoothing(1))
        XCTAssertEqual(action(atHomeIndex: 5, key: .enter), .toggleAutoCropScale)
        XCTAssertEqual(action(atHomeIndex: 6, key: .enter), .toggleAllUIBars)
        XCTAssertEqual(action(atHomeIndex: 7, key: .enter), .toggleSyphon)
        XCTAssertEqual(action(atHomeIndex: 8, key: .enter), .resetAll)
        XCTAssertEqual(action(atHomeIndex: 15, key: .right), .toggleGoofyUI)
        XCTAssertEqual(action(atHomeIndex: 16, key: .enter), .quit)
        for (offset, featureID) in FeatureID.allCases.enumerated() {
            XCTAssertEqual(action(atHomeIndex: TerminalMenuModel.firstFeatureIndex + offset, key: .left), .toggleFeature(featureID))
            XCTAssertEqual(action(atHomeIndex: TerminalMenuModel.firstFeatureIndex + offset, key: .right), .toggleFeature(featureID))
        }

        var model = TerminalMenuModel()
        XCTAssertEqual(model.handle(.quit), .quit)
        XCTAssertNil(model.handle(.escape), "Escape at the top level leaves the selection in place")
    }

    @MainActor
    func testAutoCropScaleDefaultsOffAndResetTurnsItOff() {
        let state = AppState()
        XCTAssertFalse(state.autoCropScale)
        state.setAutoCropScale(true)
        XCTAssertTrue(state.autoCropScale)
        state.reset()
        XCTAssertFalse(state.autoCropScale)
    }

    func testCompactTerminalKeepsSelectedFeatureRowAndNavigationHintsVisible() {
        var model = TerminalMenuModel()
        for _ in 0..<(TerminalMenuModel.firstFeatureIndex + 2) { _ = model.handle(.down) } // NOSE
        let frame = TerminalMenuRenderer().render(model: model, snapshot: makeSnapshot(), width: 40, height: 12)
        let lines = frame.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 12)
        XCTAssertTrue(lines.allSatisfy { stripANSI($0).count <= 40 })
        XCTAssertTrue(stripANSI(frame).contains("> NOSE"))
        XCTAssertTrue(frame.contains("ENTER: WINDOWS"))
    }

    func testLoadingScreenUsesKitArtAndRealCameraState() {
        let renderer = TerminalMenuRenderer()
        let frame = renderer.renderLoading(cameraStatus: "ASKING PERMISSION", width: 64, height: 23)
        XCTAssertTrue(frame.contains("hello from dodon.one!"))
        XCTAssertTrue(frame.contains("CAMERA: ASKING PERMISSION"))
        XCTAssertFalse(frame.contains("30%"))
        XCTAssertTrue(frame.components(separatedBy: "\n").allSatisfy { stripANSI($0).count <= 64 })
    }

    func testInstanceListCountNavigationAndStableSelectionWhenOrdinalsChange() {
        let ids = (1...4).map { WindowInstanceID(featureID: .nose, serial: UInt64($0)) }
        let threeCopies = makeSnapshot(counts: [.nose: 3])
        var model = makeModel(onFeature: .nose, snapshot: threeCopies, selectWindow: false)
        XCTAssertTrue(model.isShowingWindowList)
        XCTAssertNil(model.selectedWindowInstanceID)
        XCTAssertEqual(model.handle(.left, snapshot: threeCopies), .adjustWindowCount(.nose, -1))
        XCTAssertEqual(model.handle(.right, snapshot: threeCopies), .adjustWindowCount(.nose, 1))

        _ = model.handle(.down, snapshot: threeCopies)
        XCTAssertEqual(model.selectedWindowInstanceID, ids[0])
        _ = model.handle(.down, snapshot: threeCopies)
        XCTAssertEqual(model.selectedWindowInstanceID, ids[1])
        _ = model.handle(.down, snapshot: threeCopies)
        XCTAssertEqual(model.selectedWindowInstanceID, ids[2])
        XCTAssertNil(model.handle(.enter, snapshot: threeCopies))
        XCTAssertTrue(model.isShowingFeatureDetails)

        let afterMiddleClose = makeSnapshot(instanceIDs: [.nose: [ids[0], ids[2]]])
        model.reconcile(with: afterMiddleClose)
        XCTAssertEqual(model.selectedWindowInstanceID, ids[2], "The selected instance ID survives another copy being removed")
        let renamedFrame = TerminalMenuRenderer().render(model: model, snapshot: afterMiddleClose)
        XCTAssertTrue(renamedFrame.contains("FEATURE / NOSE 2"), "The title follows the current ordinal while the selected ID stays stable")

        let afterSelectedClose = makeSnapshot(instanceIDs: [.nose: [ids[0]]])
        model.reconcile(with: afterSelectedClose)
        XCTAssertEqual(model.selectedWindowInstanceID, ids[0], "A removed selection falls back to a surviving neighbor")
        XCTAssertNil(model.handle(.escape, snapshot: afterSelectedClose))
        XCTAssertTrue(model.isShowingWindowList)
        XCTAssertEqual(model.selectedWindowInstanceID, ids[0])
        XCTAssertNil(model.handle(.escape, snapshot: afterSelectedClose))
        XCTAssertFalse(model.isShowingWindowList)
    }

    func testEveryInstanceControlHasAKeyboardActionPath() {
        let snapshot = makeSnapshot()
        let windowID = try! XCTUnwrap(snapshot.windowIDs(for: .nose).first)
        var model = makeModel(onFeature: .nose, snapshot: snapshot)

        XCTAssertEqual(model.handle(.enter, snapshot: snapshot), .toggleWindowEnabled(windowID))
        XCTAssertEqual(model.handle(.right, snapshot: snapshot), .toggleWindowEnabled(windowID))
        _ = model.handle(.down, snapshot: snapshot)
        XCTAssertEqual(model.selectedFeatureField, .freeze)
        XCTAssertEqual(model.handle(.enter, snapshot: snapshot), .toggleWindowFreeze(windowID))
        _ = model.handle(.down, snapshot: snapshot)
        XCTAssertEqual(model.selectedFeatureField, .hideUIBar)
        XCTAssertEqual(model.handle(.enter, snapshot: snapshot), .adjustWindow(windowID, .hideUIBar, 1))
        XCTAssertEqual(model.handle(.left, snapshot: snapshot), .adjustWindow(windowID, .hideUIBar, -1))
        _ = model.handle(.down, snapshot: snapshot)
        XCTAssertEqual(model.selectedFeatureField, .sizeReset)
        XCTAssertEqual(model.handle(.enter, snapshot: snapshot), .resetWindowSize(windowID))
        XCTAssertNil(model.handle(.left, snapshot: snapshot), "The size row resets with Enter")

        for field in [TerminalFeatureField.windowX, .windowY, .cropZoom, .panX, .panY, .padding, .detection] {
            _ = model.handle(.down, snapshot: snapshot)
            XCTAssertEqual(model.selectedFeatureField, field)
            XCTAssertEqual(model.handle(.left, snapshot: snapshot), .adjustWindow(windowID, field, -1))
            XCTAssertEqual(model.handle(.right, snapshot: snapshot), .adjustWindow(windowID, field, 1))
        }
    }

    func testWindowListFits80By24WithEightCopiesAndHintsVisible() {
        let snapshot = makeSnapshot(counts: [.mouth: 8])
        let model = makeModel(onFeature: .mouth, snapshot: snapshot, selectWindow: false)
        let frame = TerminalMenuRenderer().render(model: model, snapshot: snapshot, width: 80, height: 24)
        let lines = frame.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 24)
        XCTAssertTrue(lines.allSatisfy { stripANSI($0).count == 80 })
        XCTAssertTrue(frame.contains("WINDOWS / MOUTH"))
        XCTAssertTrue(frame.contains("MOUTH 8"))
        XCTAssertTrue(frame.contains("←/→ WINDOWS"))
        XCTAssertTrue(frame.contains("ENTER: SETTINGS"))
        XCTAssertTrue(frame.contains("ESC: BACK"))
    }

    func testHomeFrameFitsStandardTerminalWithGuideAndAllFeatures() {
        let snapshot = makeSnapshot()
        let frame = TerminalMenuRenderer().render(model: TerminalMenuModel(), snapshot: snapshot, width: 80, height: 24)
        let lines = frame.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 24)
        XCTAssertTrue(lines.allSatisfy { stripANSI($0).count == 80 })
        XCTAssertTrue(frame.contains("┌"))
        XCTAssertTrue(frame.contains("└"))
        XCTAssertTrue(frame.contains("D O D O N . O N E"))
        XCTAssertFalse(frame.contains("BRAND ART: TBD"))
        XCTAssertTrue(stripANSI(frame).contains("LIVE"))
        XCTAssertTrue(frame.contains("HIDE ALL"))
        XCTAssertTrue(frame.contains("AUTO FOLLOW"))
        XCTAssertTrue(frame.contains("MIRROR"))
        XCTAssertTrue(frame.contains("SMOOTHING"))
        XCTAssertTrue(frame.contains("AUTO CROP SCALE"))
        XCTAssertTrue(frame.contains("ENTER: WINDOWS"))
        XCTAssertTrue(frame.contains("SYPHON OUTPUT"))
        XCTAssertTrue(frame.contains("RESET ALL"))
        XCTAssertTrue(frame.contains("SHOW GOOFY UI"))
        XCTAssertTrue(frame.contains("QUIT"))
        XCTAssertTrue(frame.contains("CAMERA: IDLE"))
        XCTAssertTrue(stripANSI(frame).contains("dodon.one"))
        XCTAssertFalse(frame.contains("30%"))
        for featureID in FeatureID.allCases {
            XCTAssertTrue(frame.contains(featureID.windowTitle))
        }
        XCTAssertTrue(frame.contains("↑/↓ SELECT"))
        XCTAssertTrue(frame.contains("←/→ CHANGE"))
    }

    func testFeatureFrameShowsAllSettingsAndCurrentInstanceValues() {
        let snapshot = makeSnapshot()
        var model = makeModel(onFeature: .leftEye, snapshot: snapshot)
        let frame = TerminalMenuRenderer().render(model: model, snapshot: snapshot)
        let lines = frame.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 24)
        XCTAssertTrue(lines.allSatisfy { stripANSI($0).count == 80 })
        XCTAssertTrue(frame.contains("FEATURE / LEFT EYE"))
        XCTAssertTrue(frame.contains("CAMERA: IDLE"))
        XCTAssertTrue(stripANSI(frame).contains("dodon.one"))
        XCTAssertFalse(frame.contains("30%"))
        for label in ["ENABLED", "FREEZE FRAME", "WINDOW SIZE", "WINDOW X", "WINDOW Y", "CROP ZOOM", "PAN X", "PAN Y", "CROP PADDING", "DETECTION"] {
            XCTAssertTrue(frame.contains(label), "Missing setting row: \(label)")
        }
        XCTAssertTrue(frame.contains("300x200 PT"))
        XCTAssertTrue(frame.contains("+25 PT"))
        XCTAssertTrue(frame.contains("-15 PT"))
        XCTAssertTrue(frame.contains("1.50X"))
        XCTAssertTrue(frame.contains("+0.10"))
        XCTAssertTrue(frame.contains("-0.20"))
        XCTAssertTrue(frame.contains("35%"))
        XCTAssertTrue(frame.contains("0.65"))

        XCTAssertNil(model.handle(.escape, snapshot: snapshot))
        XCTAssertTrue(model.isShowingWindowList)
        XCTAssertNil(model.handle(.escape, snapshot: snapshot))
        XCTAssertFalse(model.isShowingFeatureDetails)
        XCTAssertEqual(model.selectedHomeIndex, TerminalMenuModel.firstFeatureIndex)
    }

    func testSelectedAndActiveRowsStayPinkWithASeparateSelectionMarker() {
        let snapshot = makeSnapshot()
        var model = TerminalMenuModel()
        let renderer = TerminalMenuRenderer()
        let pink = "\u{001B}[38;2;255;112;184m"

        var lines = renderer.render(model: model, snapshot: snapshot).components(separatedBy: "\n")
        XCTAssertTrue(lines[3].contains("\u{001B}[38;2;255;92;146m"), "Active LIVE uses rainbow colors")
        XCTAssertTrue(stripANSI(lines[3]).hasPrefix("│> LIVE"), "The marker identifies selection")

        _ = model.handle(.down)
        lines = renderer.render(model: model, snapshot: snapshot).components(separatedBy: "\n")
        XCTAssertTrue(lines[3].contains("\u{001B}[38;2;255;92;146m"), "Active LIVE remains rainbow after selection moves")
        XCTAssertFalse(stripANSI(lines[3]).hasPrefix("│>"), "LIVE is no longer selected")
        XCTAssertTrue(lines[4].contains(pink), "The selected SHOW/HIDE ALL row is pink")
        XCTAssertTrue(stripANSI(lines[4]).hasPrefix("│> HIDE ALL"), "Selection marker remains visible")

        var featureModel = makeModel(onFeature: .leftEye, snapshot: snapshot)
        let featureLines = renderer.render(model: featureModel, snapshot: snapshot).components(separatedBy: "\n")
        XCTAssertTrue(featureLines[5].contains(pink), "The active instance toggle is pink")
        _ = featureModel.handle(.down, snapshot: snapshot)
        let movedFeatureLines = renderer.render(model: featureModel, snapshot: snapshot).components(separatedBy: "\n")
        XCTAssertTrue(movedFeatureLines[5].contains(pink), "The active instance stays pink after selection moves")
        XCTAssertFalse(stripANSI(movedFeatureLines[5]).hasPrefix("│>"))
        XCTAssertTrue(stripANSI(movedFeatureLines[6]).hasPrefix("│> FREEZE FRAME"))
    }

    func testCameraStatesAreRenderedFromSnapshotWithoutFakeProgress() {
        let renderer = TerminalMenuRenderer()
        for status in ["IDLE", "STARTING", "LIVE", "DENIED", "ERROR"] {
            let snapshot = makeSnapshot(cameraStatus: status)
            let frame = renderer.render(model: TerminalMenuModel(), snapshot: snapshot)
            XCTAssertTrue(frame.contains("CAMERA: \(status)"), "Missing camera state: \(status)")
            XCTAssertFalse(frame.contains("30%"))
            XCTAssertFalse(frame.contains("installing..."))
        }
    }

    func testEachFeatureDetailUsesItsFeatureTitleAndCurrentCameraState() {
        let renderer = TerminalMenuRenderer()
        for featureID in FeatureID.allCases {
            let model = makeModel(onFeature: featureID, snapshot: makeSnapshot())
            let frame = renderer.render(model: model, snapshot: makeSnapshot(cameraStatus: "STARTING"))
            let lines = frame.components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 24)
            XCTAssertTrue(lines.allSatisfy { stripANSI($0).count == 80 })
            XCTAssertTrue(frame.contains("FEATURE / \(featureID.windowTitle)"))
            XCTAssertTrue(frame.contains("CAMERA: STARTING"))
            XCTAssertTrue(frame.contains("ENABLED"))
            XCTAssertTrue(frame.contains("WINDOW SIZE"))
            XCTAssertTrue(frame.contains("DETECTION"))
            XCTAssertTrue(stripANSI(frame).contains("dodon.one"))
        }
    }

    func testGoofyVisibilityAndFeatureStatesComeFromEachSnapshot() {
        let hidden = makeSnapshot(goofyUIVisible: false)
        let shown = makeSnapshot(goofyUIVisible: true)
        let renderer = TerminalMenuRenderer()

        XCTAssertTrue(renderer.render(model: TerminalMenuModel(), snapshot: hidden).contains("SHOW GOOFY UI"))
        XCTAssertTrue(renderer.render(model: TerminalMenuModel(), snapshot: shown).contains("HIDE GOOFY UI"))

        let model = makeModel(onFeature: .rightHand, snapshot: hidden)
        XCTAssertTrue(renderer.render(model: model, snapshot: hidden).contains("ENABLED"))
        XCTAssertTrue(renderer.render(model: model, snapshot: hidden).contains("ON"))
        let offSnapshot = makeSnapshot(enabled: false)
        let offModel = makeModel(onFeature: .rightHand, snapshot: offSnapshot)
        XCTAssertTrue(renderer.render(model: offModel, snapshot: offSnapshot).contains("OFF"))
    }

    @MainActor
    func testControllerDispatchesPerInstanceSettingsAndPreservesTheOtherCopy() {
        let state = AppState()
        state.setWindowCount(2, for: .mouth)
        let ids = state.windowIDs(for: .mouth)
        let first = ids[0]
        let second = ids[1]
        let controller = makeController(state: state)

        let mouthIndex = TerminalMenuModel.firstFeatureIndex + (FeatureID.allCases.firstIndex(of: .mouth) ?? 0)
        for _ in 0..<mouthIndex { controller.handle(.down) }
        controller.handle(.enter)
        controller.handle(.right) // add a third window from the selected count row
        XCTAssertEqual(state.windowCount(for: .mouth), 3)
        controller.handle(.down)
        controller.handle(.down)
        controller.handle(.enter)
        XCTAssertEqual(controller.model.selectedWindowInstanceID, second)

        controller.handle(.right) // second copy ON -> OFF
        controller.handle(.right) // OFF -> ON
        controller.handle(.down) // FREEZE FRAME
        controller.handle(.enter)
        controller.dispatch(.adjustWindow(second, .windowX, 1))
        controller.dispatch(.adjustWindow(second, .windowY, -1))
        controller.dispatch(.adjustWindow(second, .cropZoom, 1))
        controller.dispatch(.adjustWindow(second, .panX, 1))
        controller.dispatch(.adjustWindow(second, .panY, -1))
        controller.dispatch(.adjustWindow(second, .padding, 1))
        controller.dispatch(.adjustWindow(second, .detection, 1))
        state.setWindowSize(CGSize(width: 360, height: 270), for: second)
        controller.dispatch(.resetWindowSize(second))

        let firstConfiguration = try! XCTUnwrap(state.configuration(for: first))
        let secondConfiguration = try! XCTUnwrap(state.configuration(for: second))
        XCTAssertTrue(secondConfiguration.isEnabled)
        XCTAssertTrue(secondConfiguration.isFrozen)
        XCTAssertEqual(secondConfiguration.windowOffsetX, 10)
        XCTAssertEqual(secondConfiguration.windowOffsetY, -10)
        XCTAssertEqual(secondConfiguration.cropZoom, 1.25)
        XCTAssertEqual(secondConfiguration.cropOffsetX, 0.05, accuracy: 0.0001)
        XCTAssertEqual(secondConfiguration.cropOffsetY, -0.05, accuracy: 0.0001)
        XCTAssertEqual(secondConfiguration.cropPadding, 0.30, accuracy: 0.0001)
        XCTAssertEqual(secondConfiguration.detectionThreshold, 0.60, accuracy: 0.0001)
        XCTAssertNil(secondConfiguration.windowSizeOverride)
        XCTAssertEqual(firstConfiguration.windowOffsetX, 0)
        XCTAssertEqual(firstConfiguration.windowOffsetY, 0)
        XCTAssertFalse(firstConfiguration.isFrozen)

        controller.handle(.escape)
        XCTAssertTrue(controller.model.isShowingWindowList)
        XCTAssertEqual(controller.model.selectedWindowInstanceID, second)
    }

    func testDeepSettingsAlsoFit80By24AndKeepHintsVisible() {
        let snapshot = makeSnapshot(counts: [.mouth: 8])
        let model = makeModel(onFeature: .mouth, snapshot: snapshot)
        let frame = TerminalMenuRenderer().render(model: model, snapshot: snapshot, width: 80, height: 24)
        let lines = frame.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 24)
        XCTAssertTrue(lines.allSatisfy { stripANSI($0).count == 80 })
        XCTAssertTrue(frame.contains("FEATURE / MOUTH"))
        XCTAssertTrue(frame.contains("ENABLED"))
        XCTAssertTrue(frame.contains("FREEZE FRAME"))
        XCTAssertTrue(frame.contains("DETECTION"))
        XCTAssertTrue(frame.contains("ENTER ACTIVATE"))
        XCTAssertTrue(frame.contains("ESC: BACK"))
    }

    private func action(atHomeIndex index: Int, key: TerminalKey) -> TerminalMenuAction? {
        var model = TerminalMenuModel()
        let snapshot = makeSnapshot()
        for _ in 0..<index { _ = model.handle(.down, snapshot: snapshot) }
        return model.handle(key, snapshot: snapshot)
    }

    private func makeModel(
        onFeature featureID: FeatureID,
        snapshot: TerminalMenuSnapshot,
        selectWindow: Bool = true
    ) -> TerminalMenuModel {
        var model = TerminalMenuModel()
        let index = TerminalMenuModel.firstFeatureIndex + (FeatureID.allCases.firstIndex(of: featureID) ?? 0)
        for _ in 0..<index { _ = model.handle(.down, snapshot: snapshot) }
        _ = model.handle(.enter, snapshot: snapshot)
        if selectWindow {
            _ = model.handle(.down, snapshot: snapshot)
            _ = model.handle(.enter, snapshot: snapshot)
        }
        return model
    }

    private func makeSnapshot(
        goofyUIVisible: Bool = false,
        enabled: Bool = true,
        cameraStatus: String = "IDLE",
        counts: [FeatureID: Int] = [:],
        instanceIDs: [FeatureID: [WindowInstanceID]] = [:]
    ) -> TerminalMenuSnapshot {
        let features = Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { featureID -> (FeatureID, TerminalFeatureSnapshot) in
            var configuration = FeatureConfiguration.default
            configuration.isEnabled = enabled
            if featureID == .leftEye {
                configuration.windowOffsetX = 25
                configuration.windowOffsetY = -15
                configuration.cropZoom = 1.5
                configuration.cropOffsetX = 0.1
                configuration.cropOffsetY = -0.2
                configuration.cropPadding = 0.35
                configuration.detectionThreshold = 0.65
            }
            let size = featureID == .leftEye ? CGSize(width: 300, height: 200) : CGSize(width: 240, height: 180)
            return (featureID, TerminalFeatureSnapshot(configuration: configuration, windowSize: size))
        })
        var resolvedIDs = instanceIDs
        for featureID in FeatureID.allCases where resolvedIDs[featureID] == nil {
            let count = counts[featureID] ?? 1
            resolvedIDs[featureID] = (1...max(1, count)).map {
                WindowInstanceID(featureID: featureID, serial: UInt64($0))
            }
        }
        return TerminalMenuSnapshot(
            isLive: true,
            showAll: true,
            follow: false,
            mirror: true,
            smoothing: 0.3,
            cameraStatus: cameraStatus,
            goofyUIVisible: goofyUIVisible,
            features: features,
            windowIDsByFeature: resolvedIDs
        )
    }

    private func stripANSI(_ string: String) -> String {
        let expression = try! NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*m")
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.stringByReplacingMatches(in: string, range: range, withTemplate: "")
    }

    @MainActor
    private func makeController(state: AppState) -> TerminalMenuController {
        TerminalMenuController(
            appState: state,
            session: TerminalSession(io: InertTerminalIO()),
            windowSizes: { [:] },
            goofyUIVisible: { false },
            onToggleGoofyUI: {},
            onResetFeatureSize: { _ in },
            onQuit: {},
            onSessionFailure: { _ in }
        )
    }
}

private final class InertTerminalIO: TerminalSessionIO {
    var isTTY: Bool { false }
    func enterRawMode() throws {}
    func restoreTerminalMode() throws {}
    func read(timeout: TimeInterval) throws -> TerminalReadResult { .timedOut }
    func write(_ text: String) throws {}
}
