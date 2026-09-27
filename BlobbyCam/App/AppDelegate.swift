import AppKit
import Combine
import CoreGraphics
import CoreMedia
import OSLog
import SwiftUI

private let blobbyLogger = Logger(subsystem: "com.blobbycam.BlobbyCam", category: "Runtime")

private func logEvent(_ message: String) {
    blobbyLogger.info("\(message, privacy: .public)")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let appState = AppState()
    private let windowManager = FeatureWindowManager()
    private var terminalMode: Bool
    private let terminalHostAtLaunch: NSRunningApplication?
    private var pendingTerminalFocusReturn = false
    private var terminalController: TerminalMenuController?
    private var menuWindow: NSWindow?
    private var renderer: SharedRenderer?
    private var visionTracker: VisionTracker?
    private var cameraCapture: CameraCapture?
    private var latestDelivery: AnalysisDelivery?
    private var subscriptions = Set<AnyCancellable>()
    private var loggedFirstVisionResult = false
    private var latchedCameraStatus: CameraStatus?

    init(terminalMode: Bool, terminalHostAtLaunch: NSRunningApplication? = nil) {
        self.terminalMode = terminalMode
        self.terminalHostAtLaunch = terminalHostAtLaunch
        super.init()
    }

    override init() {
        let processInfo = ProcessInfo.processInfo
        let isTestHost = Self.isRunningUnderXCTest(
            arguments: processInfo.arguments,
            environment: processInfo.environment
        )
        terminalMode = !isTestHost && DarwinTerminalSessionIO().isTTY
        terminalHostAtLaunch = nil
        super.init()
        logEvent("Blobby Cam lifecycle: AppDelegate initialized")
    }

    static func shouldStartLive(terminalMode: Bool, arguments: [String]) -> Bool {
        true
    }

    static func isRunningUnderXCTest(arguments: [String], environment: [String: String]) -> Bool {
        let environmentMarkers = [
            "XCTestConfigurationFilePath",
            "XCTestSessionIdentifier",
            "XCTestBundlePath"
        ]
        if environmentMarkers.contains(where: { environment[$0] != nil }) {
            return true
        }
        return arguments.contains { $0 == "-XCTest" || $0.hasPrefix("-XCTestConfigurationFilePath=") }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        logEvent("Blobby Cam lifecycle: applicationWillFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        guard !Self.isRunningUnderXCTest(arguments: arguments, environment: environment) else {
            logEvent("Blobby Cam lifecycle: XCTest host detected; suppressing camera and Terminal UI startup")
            return
        }
        logEvent("Blobby Cam lifecycle: applicationDidFinishLaunching, activationPolicy=\(NSApp.activationPolicy().rawValue), appActive=\(NSApp.isActive), frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
        NSApp.setActivationPolicy(terminalMode ? .accessory : .regular)
        windowManager.onUserResize = { [weak self] windowID, size in
            self?.appState.setWindowSize(size, for: windowID)
        }
        windowManager.onUserClose = { [weak self] windowID in
            guard let self else { return }
            self.appState.closeWindowInstance(windowID)
        }
        configureTracking()
        if Self.shouldStartLive(
            terminalMode: terminalMode,
            arguments: arguments
        ) {
            appState.setLive(true)
        }
        pendingTerminalFocusReturn = terminalMode
        bindState()

        if appState.isLive { cameraCapture?.start() }

        if terminalMode {
            startTerminalMenu()
        } else {
            createMenuWindow(show: true)
        }
        applyLatestDelivery()
        logEvent("Blobby Cam lifecycle: startup complete, windows=\(NSApp.windows.count), menuVisible=\(menuWindow?.isVisible == true), activationPolicy=\(NSApp.activationPolicy().rawValue)")
    }

    private func returnFocusToTerminalHost() {
        guard terminalMode, pendingTerminalFocusReturn else { return }
        pendingTerminalFocusReturn = false
        guard let terminalHostAtLaunch, !terminalHostAtLaunch.isTerminated else {
            logEvent("Blobby Cam terminal focus: no prior frontmost app was available")
            return
        }

        NSApp.yieldActivation(to: terminalHostAtLaunch)
        let activated = terminalHostAtLaunch.activate(options: [])
        logEvent("Blobby Cam terminal focus: yielded to \(terminalHostAtLaunch.bundleIdentifier ?? "unknown"), activationRequested=\(activated), appActive=\(NSApp.isActive), frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        logEvent("Blobby Cam lifecycle: applicationDidBecomeActive")
        guard !terminalMode else { return }
        menuWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminalController?.stop()
        cameraCapture?.stop()
        windowManager.resetPresentation()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !terminalMode && !Self.isRunningUnderXCTest(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard terminalMode, sender === menuWindow else { return true }
        sender.orderOut(nil)
        return false
    }

    private func startTerminalMenu() {
        let controller = TerminalMenuController(
            appState: appState,
            windowSizes: { [weak self] in self?.resolvedWindowSizes() ?? [:] },
            goofyUIVisible: { [weak self] in self?.menuWindow?.isVisible == true },
            onToggleGoofyUI: { [weak self] in self?.toggleGoofyUI() },
            onResetFeatureSize: { [weak self] featureID in
                guard let self else { return }
                guard let firstID = self.appState.windowIDs(for: featureID).first else { return }
                self.windowManager.resize(firstID, to: FeatureWindowManager.defaultPanelSize)
            },
            onQuit: { NSApp.terminate(nil) },
            onSessionFailure: { [weak self] error in self?.handleTerminalFailure(error) }
        )
        terminalController = controller
        do {
            try controller.start()
        } catch let error as TerminalSessionError {
            handleTerminalFailure(error)
        } catch {
            handleTerminalFailure(.ioFailure(String(describing: error)))
        }
    }

    private func handleTerminalFailure(_ error: TerminalSessionError) {
        logEvent("Blobby Cam Terminal: \(error.localizedDescription)")
        guard terminalMode else { return }
        pendingTerminalFocusReturn = false
        terminalController?.stop()
        terminalController = nil
        terminalMode = false
        NSApp.setActivationPolicy(.regular)
        createMenuWindow(show: true)
    }

    private func toggleGoofyUI() {
        if menuWindow?.isVisible == true {
            menuWindow?.orderOut(nil)
            return
        }
        createMenuWindow(show: true)
    }

    private func createMenuWindow(show: Bool) {
        if let menuWindow {
            if show { showMenuWindow(menuWindow) }
            return
        }
        let menuContentSize = NSSize(width: 360, height: 620)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: menuContentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Blobby Cam"
        window.contentMinSize = menuContentSize
        window.contentMaxSize = menuContentSize
        window.contentView = NSHostingView(rootView: BlobbyMenuView(appState: appState))
        window.center()
        window.delegate = self

        menuWindow = window
        if show { showMenuWindow(window) }
        logEvent("Blobby Cam lifecycle: menu shell constructed, visible=\(window.isVisible), frame=\(NSStringFromRect(window.frame))")
    }

    private func showMenuWindow(_ window: NSWindow) {
        if terminalMode {
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func resolvedWindowSizes() -> [FeatureID: CGSize] {
        Dictionary(uniqueKeysWithValues: FeatureID.allCases.compactMap { featureID in
            guard let configuration = appState.features[featureID] else { return nil }
            let boundedScale = configuration.windowScale.isFinite
                ? min(max(configuration.windowScale, 0.25), 4)
                : 1
            let size = configuration.windowSizeOverride ?? CGSize(
                width: FeatureWindowManager.defaultPanelSize.width * boundedScale,
                height: FeatureWindowManager.defaultPanelSize.height * boundedScale
            )
            return (featureID, size)
        })
    }

    private func configureTracking() {
        if let renderer = SharedRenderer() {
            self.renderer = renderer
            windowManager.installRenderer(renderer)
        } else {
            logEvent("Blobby Cam: Metal rendering is unavailable; tracking windows will remain transparent.")
        }

        let tracker = VisionTracker()
        visionTracker = tracker
        tracker.onFrameSnapshot = { [weak self] frame, snapshot in
            let delivery = AnalysisDelivery(frame: frame, snapshot: snapshot)
            Task { @MainActor [weak self, delivery] in
                self?.receive(delivery)
            }
        }
        tracker.onError = { message in
            logEvent("Blobby Cam Vision: \(message)")
        }

        cameraCapture = CameraCapture(onFrame: { [weak tracker] frame in
            tracker?.submit(frame)
        })
    }

    private func bindState() {
        appState.$isLive
            .dropFirst()
            .sink { [weak self] isLive in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if isLive {
                        self.latchedCameraStatus = nil
                        self.cameraCapture?.start()
                    } else {
                        self.cameraCapture?.stop()
                        self.latestDelivery = nil
                        self.windowManager.pausePresentation(
                            configurations: self.appState.configurationsByWindowID,
                            showAll: self.appState.showAll
                        )
                    }
                    self.applyLatestDelivery()
                }
            }
            .store(in: &subscriptions)

        appState.$showAll
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.applyLatestDelivery() } }
            .store(in: &subscriptions)
        appState.$follow
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.applyLatestDelivery() } }
            .store(in: &subscriptions)
        appState.$autoCropScale
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.applyLatestDelivery() } }
            .store(in: &subscriptions)
        appState.$smoothing
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.applyLatestDelivery() } }
            .store(in: &subscriptions)
        appState.$mirror
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.applyLatestDelivery() } }
            .store(in: &subscriptions)
        appState.$features
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.applyLatestDelivery() } }
            .store(in: &subscriptions)
        appState.$windowIDsByFeature
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.windowManager.reconcileWindowIDs(self.appState.windowIDsByFeature)
                    self.applyLatestDelivery()
                }
            }
            .store(in: &subscriptions)
        appState.$configurationsByWindowID
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.applyLatestDelivery() } }
            .store(in: &subscriptions)

        cameraCapture?.$state
            .sink { [weak self] state in
                Task { @MainActor [weak self] in self?.consumeCameraState(state) }
            }
            .store(in: &subscriptions)
    }

    private func consumeCameraState(_ state: CameraCaptureState) {
        logEvent("Blobby Cam camera state: \(String(describing: state))")
        switch state {
        case .stopped:
            appState.setCameraStatus(latchedCameraStatus ?? .idle)
            if !appState.isLive { returnFocusToTerminalHost() }
        case .requestingPermission:
            latchedCameraStatus = nil
            appState.setCameraStatus(.requestingPermission)
        case .starting:
            appState.setCameraStatus(.starting)
            returnFocusToTerminalHost()
        case .running:
            latchedCameraStatus = nil
            appState.setCameraStatus(.live)
            returnFocusToTerminalHost()
        case .stopping:
            appState.setCameraStatus(latchedCameraStatus ?? .stopping)
            if !appState.isLive { returnFocusToTerminalHost() }
        case .interrupted:
            latchedCameraStatus = .interrupted
            appState.setCameraStatus(.interrupted)
            returnFocusToTerminalHost()
            stopAfterCameraFailure()
        case let .failed(error):
            let status = cameraStatus(for: error)
            latchedCameraStatus = status
            appState.setCameraStatus(status)
            returnFocusToTerminalHost()
            stopAfterCameraFailure()
        }
    }

    private func cameraStatus(for error: CameraCaptureError) -> CameraStatus {
        switch error {
        case .permissionDenied: .denied
        case .permissionRestricted: .restricted
        case .noCameraAvailable: .unavailable
        case .permissionUndetermined: .error("PERMISSION NOT RESOLVED")
        default: .error(error.errorDescription ?? "UNKNOWN CAMERA ERROR")
        }
    }

    private func receive(_ delivery: AnalysisDelivery) {
        guard appState.isLive,
              CMTimeCompare(delivery.frame.timestamp, delivery.snapshot.timestamp) == 0
        else { return }
        if !loggedFirstVisionResult {
            loggedFirstVisionResult = true
            logEvent("Blobby Cam Vision: first coherent frame received, detections=\(delivery.snapshot.detections.keys.map(\.rawValue).sorted().joined(separator: ","))")
        }
        latestDelivery = delivery
        applyLatestDelivery()
    }

    private func applyLatestDelivery() {
        guard appState.isLive, let delivery = latestDelivery else {
            windowManager.pausePresentation(configurations: appState.configurationsByWindowID, showAll: appState.showAll)
            return
        }
        windowManager.apply(
            snapshot: delivery.snapshot,
            frame: delivery.frame,
            windowIDsByFeature: appState.windowIDsByFeature,
            configurations: appState.configurationsByWindowID,
            isLive: appState.isLive,
            showAll: appState.showAll,
            follow: appState.follow,
            smoothing: appState.smoothing,
            mirror: appState.mirror,
            screens: screenGeometries(),
            menuWindowFrame: menuWindow?.frame,
            autoCropScale: appState.autoCropScale
        )
    }

    private func stopAfterCameraFailure() {
        appState.setLive(false)
        cameraCapture?.stop()
        latestDelivery = nil
        windowManager.pausePresentation(configurations: appState.configurationsByWindowID, showAll: appState.showAll)
    }

    private func screenGeometries() -> [ScreenGeometry] {
        NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return ScreenGeometry(
                displayIdentifier: number?.stringValue ?? "screen-\(index)",
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                backingScaleFactor: screen.backingScaleFactor,
                isPrimary: number?.uint32Value == CGMainDisplayID()
            )
        }
    }
}

private struct AnalysisDelivery: @unchecked Sendable {
    let frame: CameraFrame
    let snapshot: TrackingSnapshot
}

@main
@MainActor
private enum BlobbyCamApplication {
    static func main() {
        logEvent("Blobby Cam lifecycle: explicit application bootstrap")
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        let isTestHost = AppDelegate.isRunningUnderXCTest(arguments: arguments, environment: environment)
        let terminalMode = !isTestHost && DarwinTerminalSessionIO().isTTY
        let terminalHostAtLaunch = terminalMode ? NSWorkspace.shared.frontmostApplication : nil
        let application = NSApplication.shared
        application.setActivationPolicy(terminalMode ? .accessory : .regular)
        let delegate = AppDelegate(
            terminalMode: terminalMode,
            terminalHostAtLaunch: terminalHostAtLaunch
        )
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
