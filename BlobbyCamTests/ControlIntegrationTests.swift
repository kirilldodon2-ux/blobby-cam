import AppKit
import Darwin
import XCTest
@testable import BlobbyCam

@MainActor
final class ControlIntegrationTests: XCTestCase {
    func testTerminalLaunchDefaultsToLiveButGUIOnlyDoesNot() {
        XCTAssertTrue(AppDelegate.shouldStartLive(terminalMode: true, arguments: []))
        XCTAssertTrue(AppDelegate.shouldStartLive(terminalMode: false, arguments: ["--blobbycam-live-preview"]))
        XCTAssertTrue(AppDelegate.shouldStartLive(terminalMode: false, arguments: []))
    }

    func testXCTestHostDetectionRecognizesTheCurrentTestProcess() {
        let processInfo = ProcessInfo.processInfo
        XCTAssertTrue(AppDelegate.isRunningUnderXCTest(
            arguments: processInfo.arguments,
            environment: processInfo.environment
        ))
        XCTAssertTrue(AppDelegate.isRunningUnderXCTest(
            arguments: [],
            environment: ["XCTestConfigurationFilePath": "/tmp/BlobbyCamTests.xctestconfiguration"]
        ))
        XCTAssertFalse(AppDelegate.isRunningUnderXCTest(arguments: [], environment: [:]))
    }

    func testPTYArrowAndEnterReachAppStateThroughProductionTerminalIO() async throws {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        XCTAssertEqual(openpty(&masterFD, &slaveFD, nil, nil, nil), 0)
        defer {
            if masterFD >= 0 { Darwin.close(masterFD) }
            if slaveFD >= 0 { Darwin.close(slaveFD) }
        }

        var originalAttributes = termios()
        XCTAssertEqual(tcgetattr(slaveFD, &originalAttributes), 0)

        let outputDrain = PTYOutputDrain(fileDescriptor: masterFD)
        outputDrain.start()
        defer { outputDrain.stop() }

        let state = AppState()
        let terminalIO = DarwinTerminalSessionIO(inputFD: slaveFD, outputFD: slaveFD)
        let controller = makeController(
            state: state,
            session: TerminalSession(io: terminalIO)
        )
        defer { controller.stop() }

        try controller.start()

        var rawAttributes = termios()
        XCTAssertEqual(tcgetattr(slaveFD, &rawAttributes), 0)
        let rawMinimum = withUnsafeBytes(of: rawAttributes.c_cc) { $0[Int(VMIN)] }
        XCTAssertEqual(rawMinimum, 1, "poll supplies the timeout while raw reads wait for at least one byte")
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(controller.isRunning, "an idle TTY must not be mistaken for EOF")

        writePTY(masterFD, bytes: [0x1B, 0x5B, 0x42]) // Down selects SHOW ALL.
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(controller.model.selectedHomeIndex, 1, "The production read loop must deliver arrow keys to the menu model")

        let showAllChanged = expectation(description: "Enter toggles SHOW ALL through the key callback")
        let showAllSubscription = state.$showAll.dropFirst().sink { isShown in
            if !isShown { showAllChanged.fulfill() }
        }
        writePTY(masterFD, bytes: [0x0D])
        await fulfillment(of: [showAllChanged], timeout: 2)
        withExtendedLifetime(showAllSubscription) {}
        XCTAssertFalse(state.showAll)

        writePTY(masterFD, bytes: [0x1B, 0x5B, 0x41]) // Up returns to LIVE.
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(controller.model.selectedHomeIndex, 0)

        let liveChanged = expectation(description: "Enter toggles LIVE through the key callback")
        let liveSubscription = state.$isLive.dropFirst().sink { isLive in
            if isLive { liveChanged.fulfill() }
        }
        writePTY(masterFD, bytes: [0x0D])
        await fulfillment(of: [liveChanged], timeout: 2)
        withExtendedLifetime(liveSubscription) {}
        XCTAssertTrue(state.isLive)

        controller.stop()
        var restoredAttributes = termios()
        XCTAssertEqual(tcgetattr(slaveFD, &restoredAttributes), 0)
        let terminalFlags = tcflag_t(ICANON | ECHO | ISIG)
        XCTAssertEqual(
            restoredAttributes.c_lflag & terminalFlags,
            originalAttributes.c_lflag & terminalFlags,
            "Stopping the input session restores canonical input, echo, and signal handling"
        )
        let originalMinimum = withUnsafeBytes(of: originalAttributes.c_cc) { $0[Int(VMIN)] }
        let restoredMinimum = withUnsafeBytes(of: restoredAttributes.c_cc) { $0[Int(VMIN)] }
        XCTAssertEqual(restoredMinimum, originalMinimum, "Stopping also restores the original minimum-byte setting")
    }

    func testTypedGlobalActionsUpdateTheSharedAppState() {
        let state = AppState()
        var goofyToggleCount = 0
        var sizeReset: FeatureID?
        let controller = makeController(
            state: state,
            onToggleGoofyUI: { goofyToggleCount += 1 },
            onResetFeatureSize: { sizeReset = $0 }
        )

        controller.dispatch(.toggleLive)
        controller.dispatch(.toggleAll)
        controller.dispatch(.toggleFollow)
        controller.dispatch(.toggleMirror)
        controller.dispatch(.adjustSmoothing(1))
        controller.dispatch(.toggleFreeze(.nose))
        controller.dispatch(.toggleFeature(.leftEye))
        controller.dispatch(.toggleGoofyUI)
        controller.dispatch(.resetFeatureSize(.leftEye))

        XCTAssertTrue(state.isLive)
        XCTAssertFalse(state.showAll)
        XCTAssertTrue(state.follow)
        XCTAssertNotEqual(state.mirror, MirrorPolicy.selfieOrientationByDefault)
        XCTAssertEqual(state.smoothing, 0.05, accuracy: 0.0001)
        XCTAssertTrue(state.features[.nose]?.isFrozen == true)
        XCTAssertFalse(state.features[.leftEye]?.isEnabled ?? true)
        XCTAssertEqual(goofyToggleCount, 1)
        XCTAssertEqual(sizeReset, .leftEye)

        controller.dispatch(.resetAll)
        XCTAssertFalse(state.isLive)
        XCTAssertTrue(state.showAll)
        XCTAssertFalse(state.follow)
        XCTAssertEqual(state.smoothing, AppState.defaultSmoothing)
        XCTAssertFalse(state.features[.nose]?.isFrozen ?? true)
        XCTAssertTrue(state.features[.leftEye]?.isEnabled ?? false)
    }

    func testQuitActionRequestsApplicationTermination() {
        let state = AppState()
        var quitCount = 0
        let controller = makeController(state: state, onQuit: { quitCount += 1 })

        controller.handle(.quit)

        XCTAssertEqual(quitCount, 1)
    }

    func testKeyboardActionsAdjustFeaturePlacementAndCropIndependently() {
        let state = AppState()
        state.setWindowSize(CGSize(width: 360, height: 270), for: .nose)
        let controller = makeController(state: state)

        controller.dispatch(.adjustFeature(.nose, .windowX, 1))
        controller.dispatch(.adjustFeature(.nose, .windowY, -1))
        controller.dispatch(.adjustFeature(.nose, .cropZoom, 1))
        controller.dispatch(.adjustFeature(.nose, .panX, 1))
        controller.dispatch(.adjustFeature(.nose, .panY, -1))
        controller.dispatch(.adjustFeature(.nose, .padding, 1))
        controller.dispatch(.adjustFeature(.nose, .detection, 1))

        let adjusted = try! XCTUnwrap(state.features[.nose])
        XCTAssertEqual(adjusted.windowOffsetX, 10)
        XCTAssertEqual(adjusted.windowOffsetY, -10)
        XCTAssertEqual(adjusted.cropZoom, 1.25)
        XCTAssertEqual(adjusted.cropOffsetX, 0.05, accuracy: 0.0001)
        XCTAssertEqual(adjusted.cropOffsetY, -0.05, accuracy: 0.0001)
        XCTAssertEqual(adjusted.cropPadding, 0.30, accuracy: 0.0001)
        XCTAssertEqual(adjusted.detectionThreshold, 0.60, accuracy: 0.0001)
        XCTAssertEqual(adjusted.windowSizeOverride, CGSize(width: 360, height: 270))

        controller.dispatch(.resetFeatureSize(.nose))
        let reset = try! XCTUnwrap(state.features[.nose])
        XCTAssertNil(reset.windowSizeOverride)
        XCTAssertEqual(reset.cropZoom, adjusted.cropZoom, "Resetting panel size must preserve independent crop framing")
        XCTAssertEqual(reset.cropOffsetX, adjusted.cropOffsetX)
        XCTAssertEqual(reset.cropOffsetY, adjusted.cropOffsetY)
    }

    func testKeyboardNavigationReachesControlsAndCameraStatusRendersInFrame() {
        let state = AppState()
        let controller = makeController(state: state)

        controller.handle(.down)
        controller.handle(.enter)
        XCTAssertFalse(state.showAll)

        controller.handle(.down)
        controller.handle(.down)
        controller.handle(.down)
        controller.handle(.down)
        controller.handle(.down)
        controller.handle(.down)
        controller.handle(.enter)
        XCTAssertEqual(controller.model.selectedFeature, .leftEye)

        state.setCameraStatus(.denied)
        let snapshot = TerminalMenuSnapshot(
            appState: state,
            goofyUIVisible: false,
            windowSizes: Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { ($0, CGSize(width: 240, height: 180)) })
        )
        let frame = TerminalMenuRenderer().render(model: controller.model, snapshot: snapshot)
        let lines = frame.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 24)
        XCTAssertTrue(lines.allSatisfy { stripANSI($0).count == 80 })
        XCTAssertTrue(frame.contains("ACCESS DENIED"))
    }

    func testCameraFailureStatusLabelsStayVisibleAndPrintable() {
        let statuses: [CameraStatus] = [
            .interrupted,
            .restricted,
            .unavailable,
            .error("camera runtime failure")
        ]

        for status in statuses {
            let state = AppState()
            state.setCameraStatus(status)
            let snapshot = TerminalMenuSnapshot(
                appState: state,
                goofyUIVisible: false,
                windowSizes: [:]
            )
            let frame = TerminalMenuRenderer().render(model: TerminalMenuModel(), snapshot: snapshot)
            XCTAssertTrue(frame.contains(status.terminalLabel))
            let printableFrame = frame.replacingOccurrences(
                of: #"\x1B\[[0-?]*[ -/]*[@-~]"#,
                with: "",
                options: .regularExpression
            )
            XCTAssertTrue(printableFrame.unicodeScalars.allSatisfy {
                $0 == "\n" || $0.value >= 0x20
            }, "status frames may use Unicode art but must not contain stray C0 controls")

            var detailModel = TerminalMenuModel()
            for _ in 0..<TerminalMenuModel.firstFeatureIndex { _ = detailModel.handle(.down) }
            _ = detailModel.handle(.enter)
            let detailFrame = TerminalMenuRenderer().render(model: detailModel, snapshot: snapshot)
            let detailLines = detailFrame.components(separatedBy: "\n")
            XCTAssertEqual(detailLines.count, 24)
            XCTAssertTrue(detailLines.allSatisfy { stripANSI($0).count == 80 })
            XCTAssertTrue(detailFrame.contains(status.terminalLabel))
        }
    }

    private func makeController(
        state: AppState,
        session: TerminalSession = TerminalSession(io: InertTerminalIO()),
        onToggleGoofyUI: @escaping () -> Void = {},
        onResetFeatureSize: @escaping (FeatureID) -> Void = { _ in },
        onQuit: @escaping () -> Void = {}
    ) -> TerminalMenuController {
        TerminalMenuController(
            appState: state,
            session: session,
            windowSizes: { [:] },
            goofyUIVisible: { false },
            onToggleGoofyUI: onToggleGoofyUI,
            onResetFeatureSize: onResetFeatureSize,
            onQuit: onQuit,
            onSessionFailure: { _ in }
        )
    }

    private func writePTY(_ fileDescriptor: Int32, bytes: [UInt8]) {
        bytes.withUnsafeBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            XCTAssertEqual(Darwin.write(fileDescriptor, address, buffer.count), buffer.count)
        }
    }

    private func stripANSI(_ string: String) -> String {
        let expression = try! NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*m")
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.stringByReplacingMatches(in: string, range: range, withTemplate: "")
    }
}

private final class PTYOutputDrain {
    private let fileDescriptor: Int32
    private let queue = DispatchQueue(label: "com.blobbycam.tests.pty-output-drain")
    private let stopSignal = DispatchSemaphore(value: 0)
    private let finished = DispatchGroup()

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    func start() {
        finished.enter()
        queue.async {
            defer { self.finished.leave() }
            while self.stopSignal.wait(timeout: .now()) == .timedOut {
                var descriptor = pollfd(fd: self.fileDescriptor, events: Int16(POLLIN), revents: 0)
                guard Darwin.poll(&descriptor, 1, 25) > 0,
                      descriptor.revents & Int16(POLLIN) != 0
                else { continue }

                var buffer = [UInt8](repeating: 0, count: 4_096)
                _ = buffer.withUnsafeMutableBytes { bytes -> Int in
                    guard let address = bytes.baseAddress else { return 0 }
                    return Darwin.read(self.fileDescriptor, address, bytes.count)
                }
            }
        }
    }

    func stop() {
        stopSignal.signal()
        finished.wait()
    }
}

private final class InertTerminalIO: TerminalSessionIO {
    var isTTY: Bool { false }
    func enterRawMode() throws {}
    func restoreTerminalMode() throws {}
    func read(timeout: TimeInterval) throws -> TerminalReadResult { .timedOut }
    func write(_ text: String) throws {}
}
