import CoreGraphics
import XCTest
@testable import BlobbyCam

final class TerminalMenuTests: XCTestCase {
    func testHomeNavigationClampsAndReachesEveryFeature() {
        var model = TerminalMenuModel()

        XCTAssertNil(model.handle(.up))
        XCTAssertEqual(model.selectedHomeIndex, 0)

        for featureID in FeatureID.allCases {
            let expectedIndex = TerminalMenuModel.firstFeatureIndex + (FeatureID.allCases.firstIndex(of: featureID) ?? 0)
            while model.selectedHomeIndex < expectedIndex {
                XCTAssertNil(model.handle(.down))
            }
            XCTAssertNil(model.handle(.enter))
            XCTAssertEqual(model.selectedFeature, featureID)
            XCTAssertNil(model.handle(.escape))
            XCTAssertFalse(model.isShowingFeatureDetails)
            XCTAssertEqual(model.selectedHomeIndex, expectedIndex)
        }

        for _ in 0..<TerminalMenuModel.homeItemCount {
            _ = model.handle(.down)
        }
        XCTAssertEqual(model.selectedHomeIndex, TerminalMenuModel.homeItemCount - 1)
        XCTAssertNil(model.handle(.down))
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
        XCTAssertEqual(action(atHomeIndex: 6, key: .enter), .resetAll)
        XCTAssertEqual(action(atHomeIndex: 13, key: .right), .toggleGoofyUI)
        XCTAssertEqual(action(atHomeIndex: 14, key: .enter), .quit)
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

    func testCompactTerminalKeepsSelectedFeatureRowVisibleWithoutOverflow() {
        var model = TerminalMenuModel()
        for _ in 0..<9 { _ = model.handle(.down) } // NOSE
        let frame = TerminalMenuRenderer().render(model: model, snapshot: makeSnapshot(), width: 40, height: 12)
        let lines = frame.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 12)
        XCTAssertTrue(lines.allSatisfy { stripANSI($0).count <= 40 })
        XCTAssertTrue(stripANSI(frame).contains("> NOSE"))
    }

    func testLoadingScreenUsesKitArtAndRealCameraState() {
        let renderer = TerminalMenuRenderer()
        let frame = renderer.renderLoading(cameraStatus: "ASKING PERMISSION", width: 64, height: 23)
        XCTAssertTrue(frame.contains("hello from dodon.one!"))
        XCTAssertTrue(frame.contains("CAMERA: ASKING PERMISSION"))
        XCTAssertFalse(frame.contains("30%"))
        XCTAssertTrue(frame.components(separatedBy: "\n").allSatisfy { stripANSI($0).count <= 64 })
    }

    func testEveryFeatureActionAndFieldIsReachable() {
        for featureID in FeatureID.allCases {
            var model = makeModel(onFeature: featureID)
            XCTAssertEqual(model.selectedFeatureField, .enabled)
            XCTAssertEqual(model.handle(.enter), .toggleFeature(featureID))
            XCTAssertEqual(model.handle(.right), .toggleFeature(featureID))

            XCTAssertNil(model.handle(.down))
            XCTAssertEqual(model.selectedFeatureField, .freeze)
            XCTAssertEqual(model.handle(.enter), .toggleFreeze(featureID))
            XCTAssertEqual(model.handle(.left), .toggleFreeze(featureID))

            XCTAssertNil(model.handle(.down))
            XCTAssertEqual(model.selectedFeatureField, .sizeReset)
            XCTAssertEqual(model.handle(.enter), .resetFeatureSize(featureID))
            XCTAssertNil(model.handle(.left), "The size row resets with Enter")

            let expectedFields: [TerminalFeatureField] = [
                .windowX, .windowY, .cropZoom, .panX, .panY, .padding, .detection
            ]
            for field in expectedFields {
                XCTAssertNil(model.handle(.down))
                XCTAssertEqual(model.selectedFeatureField, field)
                XCTAssertEqual(model.handle(.left), .adjustFeature(featureID, field, -1))
                XCTAssertEqual(model.handle(.right), .adjustFeature(featureID, field, 1))
            }

            XCTAssertNil(model.handle(.down))
            XCTAssertEqual(model.selectedFeatureField, .detection)
            XCTAssertNil(model.handle(.down))
            XCTAssertEqual(model.handle(.quit), .quit)
            XCTAssertNil(model.handle(.escape))
            XCTAssertFalse(model.isShowingFeatureDetails)
        }
    }

    func testFeatureDetailNavigationClampsAtBothEnds() {
        var model = makeModel(onFeature: .nose)
        XCTAssertNil(model.handle(.up))
        XCTAssertEqual(model.selectedFeatureField, .enabled)

        for _ in 0..<TerminalFeatureField.allCases.count {
            _ = model.handle(.down)
        }
        XCTAssertEqual(model.selectedFeatureField, .detection)
        XCTAssertNil(model.handle(.down))
        XCTAssertEqual(model.selectedFeatureField, .detection)
    }

    func testHomeFrameFitsStandardTerminalWithGuideAndAllFeatures() {
        let snapshot = makeSnapshot()
        let model = TerminalMenuModel()
        let frame = TerminalMenuRenderer().render(model: model, snapshot: snapshot, width: 52, height: 23)
        let lines = frame.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 23)
        XCTAssertTrue(lines.allSatisfy { stripANSI($0).count == 52 })
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
        XCTAssertTrue(frame.contains("ENTER: WINDOW SETTINGS"))
        XCTAssertTrue(frame.contains("RESET ALL"))
        XCTAssertTrue(frame.contains("SHOW GOOFY UI"))
        XCTAssertTrue(frame.contains("QUIT"))
        XCTAssertTrue(frame.contains("CAMERA: IDLE"))
        XCTAssertTrue(stripANSI(frame).contains("dodon.one"))
        XCTAssertFalse(frame.contains("30%"), "The running menu does not show illustrative setup progress")
        for featureID in FeatureID.allCases {
            XCTAssertTrue(frame.contains(featureID.windowTitle))
        }
        XCTAssertTrue(frame.contains("↑/↓ SELECT"))
        XCTAssertTrue(frame.contains("←/→ CHANGE"))
    }

    func testFeatureFrameShowsAllSettingsAndCurrentSnapshotValues() {
        let snapshot = makeSnapshot()
        var model = makeModel(onFeature: .leftEye)
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

        XCTAssertNil(model.handle(.escape))
        XCTAssertFalse(model.isShowingFeatureDetails)
        XCTAssertEqual(model.selectedHomeIndex, TerminalMenuModel.firstFeatureIndex)
    }

    func testSelectedAndActiveRowsStayPinkWithASeparateSelectionMarker() {
        let snapshot = makeSnapshot()
        var model = TerminalMenuModel()
        let renderer = TerminalMenuRenderer()
        let pink = "\u{001B}[38;2;255;112;184m"

        var lines = renderer.render(model: model, snapshot: snapshot).components(separatedBy: "\n")
        XCTAssertTrue(lines[4].contains("\u{001B}[38;2;255;92;146m"), "Active LIVE uses rainbow colors")
        XCTAssertTrue(stripANSI(lines[4]).hasPrefix("│> LIVE"), "The marker identifies selection")

        _ = model.handle(.down)
        lines = renderer.render(model: model, snapshot: snapshot).components(separatedBy: "\n")
        XCTAssertTrue(lines[4].contains("\u{001B}[38;2;255;92;146m"), "Active LIVE remains rainbow after selection moves")
        XCTAssertFalse(stripANSI(lines[4]).hasPrefix("│>"), "LIVE is no longer selected")
        XCTAssertTrue(lines[5].contains(pink), "The selected SHOW/HIDE ALL row is pink")
        XCTAssertTrue(stripANSI(lines[5]).hasPrefix("│> HIDE ALL"), "Selection marker remains visible")

        var featureModel = makeModel(onFeature: .leftEye)
        let featureLines = renderer.render(model: featureModel, snapshot: snapshot).components(separatedBy: "\n")
        XCTAssertTrue(featureLines[5].contains(pink), "The active feature toggle is pink")
        _ = featureModel.handle(.down)
        let movedFeatureLines = renderer.render(model: featureModel, snapshot: snapshot).components(separatedBy: "\n")
        XCTAssertTrue(movedFeatureLines[5].contains(pink), "The active feature stays pink after selection moves")
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
            let model = makeModel(onFeature: featureID)
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

        var model = makeModel(onFeature: .rightHand)
        XCTAssertTrue(renderer.render(model: model, snapshot: hidden).contains("ENABLED"))
        XCTAssertTrue(renderer.render(model: model, snapshot: hidden).contains("ON"))
        XCTAssertNil(model.handle(.escape))
        model = makeModel(onFeature: .rightHand)
        XCTAssertTrue(renderer.render(model: model, snapshot: makeSnapshot(enabled: false)).contains("OFF"))
    }

    private func action(atHomeIndex index: Int, key: TerminalKey) -> TerminalMenuAction? {
        var model = TerminalMenuModel()
        for _ in 0..<index {
            _ = model.handle(.down)
        }
        return model.handle(key)
    }

    private func makeModel(onFeature featureID: FeatureID) -> TerminalMenuModel {
        var model = TerminalMenuModel()
        let index = TerminalMenuModel.firstFeatureIndex + (FeatureID.allCases.firstIndex(of: featureID) ?? 0)
        for _ in 0..<index {
            _ = model.handle(.down)
        }
        _ = model.handle(.enter)
        return model
    }

    private func makeSnapshot(
        goofyUIVisible: Bool = false,
        enabled: Bool = true,
        cameraStatus: String = "IDLE"
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
        return TerminalMenuSnapshot(
            isLive: true,
            showAll: true,
            follow: false,
            mirror: true,
            smoothing: 0.3,
            cameraStatus: cameraStatus,
            goofyUIVisible: goofyUIVisible,
            features: features
        )
    }

    private func stripANSI(_ string: String) -> String {
        let expression = try! NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*m")
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.stringByReplacingMatches(in: string, range: range, withTemplate: "")
    }
}
