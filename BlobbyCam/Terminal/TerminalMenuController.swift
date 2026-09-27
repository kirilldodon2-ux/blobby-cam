import Combine
import CoreGraphics
import Foundation

@MainActor
final class TerminalMenuController {
    private let appState: AppState
    private let session: TerminalSession
    private let renderer: TerminalMenuRenderer
    private let windowSizes: () -> [FeatureID: CGSize]
    private let goofyUIVisible: () -> Bool
    private let onToggleGoofyUI: () -> Void
    private let onResetFeatureSize: (FeatureID) -> Void
    private let onQuit: () -> Void
    private let onSessionFailure: (TerminalSessionError) -> Void
    private(set) var model = TerminalMenuModel()
    private var subscriptions = Set<AnyCancellable>()
    private var resizeTimer: Timer?
    private var renderedSize: (columns: Int, rows: Int)?
    private var showingStartupLoading = true

    init(
        appState: AppState,
        session: TerminalSession = TerminalSession(),
        windowSizes: @escaping () -> [FeatureID: CGSize],
        goofyUIVisible: @escaping () -> Bool,
        onToggleGoofyUI: @escaping () -> Void,
        onResetFeatureSize: @escaping (FeatureID) -> Void,
        onQuit: @escaping () -> Void,
        onSessionFailure: @escaping (TerminalSessionError) -> Void
    ) {
        self.appState = appState
        self.session = session
        self.windowSizes = windowSizes
        self.goofyUIVisible = goofyUIVisible
        self.onToggleGoofyUI = onToggleGoofyUI
        self.onResetFeatureSize = onResetFeatureSize
        self.onQuit = onQuit
        self.onSessionFailure = onSessionFailure
        renderer = TerminalMenuRenderer()

        appState.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.redrawIfRunning()
                }
            }
            .store(in: &subscriptions)
    }

    var isRunning: Bool { session.isRunning }

    func start() throws {
        try session.start(
            onKey: { [weak self] key in
                Task { @MainActor [weak self] in self?.handle(key) }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in self?.onSessionFailure(error) }
            }
        )
        do {
            try session.redraw(renderCurrentFrame())
            resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.redrawIfSizeChanged() }
            }
        } catch let error as TerminalSessionError {
            onSessionFailure(error)
            throw error
        } catch {
            let normalized = TerminalSessionError.ioFailure(String(describing: error))
            onSessionFailure(normalized)
            throw normalized
        }
    }

    func stop() {
        resizeTimer?.invalidate()
        resizeTimer = nil
        session.stop()
    }

    /// Applies the same typed key path as the production terminal input callback.
    func handle(_ key: TerminalKey) {
        showingStartupLoading = false
        let snapshot = makeSnapshot()
        if let action = model.handle(key, snapshot: snapshot) {
            dispatch(action)
        }
        redrawIfRunning()
    }

    func dispatch(_ action: TerminalMenuAction) {
        switch action {
        case .toggleLive:
            appState.setLive(!appState.isLive)
        case .toggleAll:
            appState.setShowAll(!appState.showAll)
        case .toggleFollow:
            appState.setFollow(!appState.follow)
        case .toggleAutoCropScale:
            appState.setAutoCropScale(!appState.autoCropScale)
        case .toggleMirror:
            appState.setMirror(!appState.mirror)
        case .resetAll:
            appState.reset()
        case let .adjustSmoothing(direction):
            appState.setSmoothing(bounded(appState.smoothing + CGFloat(direction) * 0.05, to: 0...1))
        case let .toggleFeature(featureID):
            guard let configuration = appState.features[featureID] else { return }
            appState.setFeatureEnabled(!configuration.isEnabled, for: featureID)
        case let .toggleFreeze(featureID):
            guard let configuration = appState.features[featureID], configuration.isEnabled else { return }
            appState.setFeatureFrozen(!configuration.isFrozen, for: featureID)
        case let .resetFeatureSize(featureID):
            appState.setWindowScale(1, for: featureID)
            onResetFeatureSize(featureID)
        case let .adjustFeature(featureID, field, direction):
            adjustFeature(featureID, field: field, direction: direction)
        case let .adjustWindowCount(featureID, direction):
            appState.setWindowCount(
                appState.windowCount(for: featureID) + direction,
                for: featureID
            )
        case let .toggleWindowEnabled(windowID):
            guard let configuration = appState.configuration(for: windowID) else { return }
            appState.setFeatureEnabled(!configuration.isEnabled, for: windowID)
        case let .toggleWindowFreeze(windowID):
            guard let configuration = appState.configuration(for: windowID), configuration.isEnabled else { return }
            appState.setFeatureFrozen(!configuration.isFrozen, for: windowID)
        case let .resetWindowSize(windowID):
            appState.setWindowScale(1, for: windowID)
            if appState.windowIDs(for: windowID.featureID).first == windowID {
                onResetFeatureSize(windowID.featureID)
            }
        case let .adjustWindow(windowID, field, direction):
            adjustWindow(windowID, field: field, direction: direction)
        case .toggleGoofyUI:
            onToggleGoofyUI()
        case .quit:
            session.stop()
            onQuit()
        }
    }

    private func adjustFeature(_ featureID: FeatureID, field: TerminalFeatureField, direction: Int) {
        guard let configuration = appState.features[featureID] else { return }
        switch field {
        case .enabled:
            appState.setFeatureEnabled(!configuration.isEnabled, for: featureID)
        case .freeze:
            appState.setFeatureFrozen(!configuration.isFrozen, for: featureID)
        case .sizeReset:
            break
        case .windowX:
            appState.setWindowOffsetX(configuration.windowOffsetX + CGFloat(direction) * 10, for: featureID)
        case .windowY:
            appState.setWindowOffsetY(configuration.windowOffsetY + CGFloat(direction) * 10, for: featureID)
        case .cropZoom:
            appState.setCropZoom(configuration.cropZoom + CGFloat(direction) * 0.25, for: featureID)
        case .panX:
            appState.setCropOffsetX(configuration.cropOffsetX + CGFloat(direction) * 0.05, for: featureID)
        case .panY:
            appState.setCropOffsetY(configuration.cropOffsetY + CGFloat(direction) * 0.05, for: featureID)
        case .padding:
            appState.setCropPadding(bounded(configuration.cropPadding + CGFloat(direction) * 0.05, to: 0...1), for: featureID)
        case .detection:
            appState.setDetectionThreshold(configuration.detectionThreshold + Float(direction) * 0.05, for: featureID)
        }
    }

    private func adjustWindow(_ windowID: WindowInstanceID, field: TerminalFeatureField, direction: Int) {
        guard let configuration = appState.configuration(for: windowID) else { return }
        switch field {
        case .enabled:
            appState.setFeatureEnabled(!configuration.isEnabled, for: windowID)
        case .freeze:
            appState.setFeatureFrozen(!configuration.isFrozen, for: windowID)
        case .sizeReset:
            break
        case .windowX:
            appState.setWindowOffsetX(configuration.windowOffsetX + CGFloat(direction) * 10, for: windowID)
        case .windowY:
            appState.setWindowOffsetY(configuration.windowOffsetY + CGFloat(direction) * 10, for: windowID)
        case .cropZoom:
            appState.setCropZoom(configuration.cropZoom + CGFloat(direction) * 0.25, for: windowID)
        case .panX:
            appState.setCropOffsetX(configuration.cropOffsetX + CGFloat(direction) * 0.05, for: windowID)
        case .panY:
            appState.setCropOffsetY(configuration.cropOffsetY + CGFloat(direction) * 0.05, for: windowID)
        case .padding:
            appState.setCropPadding(bounded(configuration.cropPadding + CGFloat(direction) * 0.05, to: 0...1), for: windowID)
        case .detection:
            appState.setDetectionThreshold(configuration.detectionThreshold + Float(direction) * 0.05, for: windowID)
        }
    }

    private func bounded(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func makeSnapshot() -> TerminalMenuSnapshot {
        let snapshot = TerminalMenuSnapshot(
            appState: appState,
            goofyUIVisible: goofyUIVisible(),
            windowSizes: windowSizes()
        )
        model.reconcile(with: snapshot)
        return snapshot
    }

    private func renderCurrentFrame() -> String {
        let size = session.terminalSize
        renderedSize = size
        let snapshot = makeSnapshot()
        if showingStartupLoading, snapshot.isLive {
            if ["IDLE", "STARTING", "ASKING PERMISSION"].contains(snapshot.cameraStatus) {
                return renderer.renderLoading(
                    cameraStatus: snapshot.cameraStatus,
                    width: min(64, max(3, size.columns - 1)),
                    height: max(0, size.rows - 1)
                )
            }
            showingStartupLoading = false
        }
        return renderer.render(
            model: model,
            snapshot: snapshot,
            width: min(52, max(3, size.columns - 1)),
            height: min(24, max(0, size.rows - 1))
        )
    }

    private func redrawIfSizeChanged() {
        let size = session.terminalSize
        guard renderedSize?.columns != size.columns || renderedSize?.rows != size.rows else { return }
        redrawIfRunning()
    }

    private func redrawIfRunning() {
        guard session.isRunning else { return }
        do {
            try session.redraw(renderCurrentFrame())
        } catch let error as TerminalSessionError {
            onSessionFailure(error)
        } catch {
            onSessionFailure(.ioFailure(String(describing: error)))
        }
    }
}
