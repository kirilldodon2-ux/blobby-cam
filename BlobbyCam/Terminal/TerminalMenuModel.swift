import Foundation

enum TerminalKey: Equatable {
    case up
    case down
    case left
    case right
    case enter
    case escape
    case quit
}

enum TerminalFeatureField: CaseIterable, Equatable {
    case enabled
    case freeze
    case hideUIBar
    case sizeReset
    case windowX
    case windowY
    case cropZoom
    case panX
    case panY
    case padding
    case detection
}

enum TerminalMenuAction: Equatable {
    case toggleLive
    case toggleAllUIBars
    case toggleAll
    case toggleFollow
    case toggleAutoCropScale
    case toggleMirror
    case resetAll
    /// A direction of -1 or +1; one step is 0.05 in the current controls.
    case adjustSmoothing(Int)
    case toggleFeature(FeatureID)
    case toggleFreeze(FeatureID)
    case resetFeatureSize(FeatureID)
    /// A direction of -1 or +1. The controller maps it to the selected field's step.
    case adjustFeature(FeatureID, TerminalFeatureField, Int)
    case adjustWindowCount(FeatureID, Int)
    case toggleWindowEnabled(WindowInstanceID)
    case toggleWindowFreeze(WindowInstanceID)
    case resetWindowSize(WindowInstanceID)
    case adjustWindow(WindowInstanceID, TerminalFeatureField, Int)
    case toggleGoofyUI
    case quit
}

/// Immutable display values copied from AppState for one render/input turn.
struct TerminalFeatureSnapshot: Equatable {
    let isEnabled: Bool
    let isFrozen: Bool
    let hidesUIBar: Bool
    let windowSize: CGSize
    let windowOffsetX: CGFloat
    let windowOffsetY: CGFloat
    let cropZoom: CGFloat
    let cropOffsetX: CGFloat
    let cropOffsetY: CGFloat
    let cropPadding: CGFloat
    let detectionThreshold: Float

    init(configuration: FeatureConfiguration, windowSize: CGSize) {
        isEnabled = configuration.isEnabled
        isFrozen = configuration.isFrozen
        hidesUIBar = configuration.hidesUIBar
        self.windowSize = windowSize
        windowOffsetX = configuration.windowOffsetX
        windowOffsetY = configuration.windowOffsetY
        cropZoom = configuration.cropZoom
        cropOffsetX = configuration.cropOffsetX
        cropOffsetY = configuration.cropOffsetY
        cropPadding = configuration.cropPadding
        detectionThreshold = configuration.detectionThreshold
    }
}

/// A point-in-time view of AppState used by the pure menu model and renderer.
struct TerminalMenuSnapshot: Equatable {
    let isLive: Bool
    let showAll: Bool
    let follow: Bool
    let autoCropScale: Bool
    let mirror: Bool
    let smoothing: CGFloat
    let cameraStatus: String
    let goofyUIVisible: Bool
    let maximumWindowCount: Int
    /// Legacy first-window projection, retained for existing views and test fixtures.
    let features: [FeatureID: TerminalFeatureSnapshot]
    let windowIDsByFeature: [FeatureID: [WindowInstanceID]]
    let windowsByID: [WindowInstanceID: TerminalFeatureSnapshot]

    init(
        isLive: Bool,
        showAll: Bool,
        follow: Bool,
        autoCropScale: Bool = false,
        mirror: Bool,
        smoothing: CGFloat,
        cameraStatus: String = "IDLE",
        goofyUIVisible: Bool,
        maximumWindowCount: Int = 32,
        features: [FeatureID: TerminalFeatureSnapshot],
        windowIDsByFeature: [FeatureID: [WindowInstanceID]] = [:],
        windowsByID: [WindowInstanceID: TerminalFeatureSnapshot] = [:]
    ) {
        self.isLive = isLive
        self.showAll = showAll
        self.follow = follow
        self.autoCropScale = autoCropScale
        self.mirror = mirror
        self.smoothing = smoothing
        self.cameraStatus = cameraStatus
        self.goofyUIVisible = goofyUIVisible
        self.maximumWindowCount = maximumWindowCount
        self.features = features

        var resolvedIDs: [FeatureID: [WindowInstanceID]] = [:]
        var resolvedWindows: [WindowInstanceID: TerminalFeatureSnapshot] = [:]
        for featureID in FeatureID.allCases {
            guard let firstSnapshot = features[featureID] else { continue }
            let ids = windowIDsByFeature[featureID] ?? [WindowInstanceID(featureID: featureID, serial: 1)]
            resolvedIDs[featureID] = ids
            for id in ids {
                resolvedWindows[id] = windowsByID[id] ?? firstSnapshot
            }
        }
        self.windowIDsByFeature = resolvedIDs
        self.windowsByID = resolvedWindows
    }

    func windowIDs(for featureID: FeatureID) -> [WindowInstanceID] {
        windowIDsByFeature[featureID] ?? []
    }

    func window(for id: WindowInstanceID) -> TerminalFeatureSnapshot? {
        windowsByID[id]
    }

    /// Capture current AppState values. `windowSizes` remains the legacy first-panel callback;
    /// additional panels are sized directly from their own configuration.
    @MainActor
    init(appState: AppState, goofyUIVisible: Bool, windowSizes: [FeatureID: CGSize]) {
        isLive = appState.isLive
        showAll = appState.showAll
        follow = appState.follow
        autoCropScale = appState.autoCropScale
        mirror = appState.mirror
        smoothing = appState.smoothing
        cameraStatus = appState.cameraStatus.terminalLabel
        self.goofyUIVisible = goofyUIVisible
        maximumWindowCount = AppState.maximumWindowCount

        var featureSnapshots: [FeatureID: TerminalFeatureSnapshot] = [:]
        var idsByFeature: [FeatureID: [WindowInstanceID]] = [:]
        var windowSnapshots: [WindowInstanceID: TerminalFeatureSnapshot] = [:]
        for featureID in FeatureID.allCases {
            let ids = appState.windowIDs(for: featureID)
            idsByFeature[featureID] = ids
            for (index, id) in ids.enumerated() {
                guard let configuration = appState.configuration(for: id) else { continue }
                let scale = configuration.windowScale.isFinite
                    ? min(max(configuration.windowScale, 0.25), 4)
                    : 1
                let configuredSize = configuration.windowSizeOverride ?? CGSize(
                    width: 240 * scale,
                    height: 180 * scale
                )
                let size = index == 0 ? (windowSizes[featureID] ?? configuredSize) : configuredSize
                let snapshot = TerminalFeatureSnapshot(configuration: configuration, windowSize: size)
                windowSnapshots[id] = snapshot
                if index == 0 { featureSnapshots[featureID] = snapshot }
            }
        }
        features = featureSnapshots
        windowIDsByFeature = idsByFeature
        windowsByID = windowSnapshots
    }
}

/// Navigation only. Mutable application values always come from TerminalMenuSnapshot.
struct TerminalMenuModel {
    private(set) var selectedHomeIndex = 0
    private(set) var selectedFeature: FeatureID?
    private(set) var selectedWindowInstanceID: WindowInstanceID?
    private(set) var isEditingWindowSettings = false
    private(set) var selectedFeatureField: TerminalFeatureField = .enabled
    private(set) var selectedWindowIndex = 0

    static let homeItemCount = 16
    static let firstFeatureIndex = 8

    var isShowingWindowList: Bool { selectedFeature != nil && !isEditingWindowSettings }
    var isShowingFeatureDetails: Bool { selectedFeature != nil && isEditingWindowSettings }
    var selectedFeatureFieldIndex: Int? { TerminalFeatureField.allCases.firstIndex(of: selectedFeatureField) }

    /// Keeps navigation attached to stable IDs when copies are removed or their ordinal changes.
    mutating func reconcile(with snapshot: TerminalMenuSnapshot) {
        guard let featureID = selectedFeature else { return }
        let ids = snapshot.windowIDs(for: featureID)
        guard !ids.isEmpty else {
            selectedWindowInstanceID = nil
            selectedWindowIndex = 0
            return
        }

        guard let selectedWindowInstanceID else {
            selectedWindowIndex = min(selectedWindowIndex, ids.count - 1)
            return
        }
        if let currentIndex = ids.firstIndex(of: selectedWindowInstanceID) {
            selectedWindowIndex = currentIndex
        } else {
            // If the selected ID was removed, prefer the surviving item immediately before it.
            selectedWindowIndex = max(0, min(selectedWindowIndex - 1, ids.count - 1))
            self.selectedWindowInstanceID = ids[selectedWindowIndex]
        }
    }

    mutating func handle(_ key: TerminalKey, snapshot: TerminalMenuSnapshot? = nil) -> TerminalMenuAction? {
        if let snapshot { reconcile(with: snapshot) }
        if key == .quit { return .quit }

        guard let featureID = selectedFeature else {
            return handleHomeKey(key)
        }
        guard isEditingWindowSettings, let windowID = selectedWindowInstanceID else {
            return handleWindowListKey(key, featureID: featureID, snapshot: snapshot)
        }
        return handleWindowKey(key, featureID: featureID, windowID: windowID)
    }

    private mutating func handleHomeKey(_ key: TerminalKey) -> TerminalMenuAction? {
        switch key {
        case .up:
            selectedHomeIndex = max(0, selectedHomeIndex - 1)
            return nil
        case .down:
            selectedHomeIndex = min(Self.homeItemCount - 1, selectedHomeIndex + 1)
            return nil
        case .left:
            return adjustHomeSelection(direction: -1)
        case .right:
            return adjustHomeSelection(direction: 1)
        case .enter:
            return activateHomeSelection()
        case .escape, .quit:
            return nil
        }
    }

    private mutating func handleWindowListKey(
        _ key: TerminalKey,
        featureID: FeatureID,
        snapshot: TerminalMenuSnapshot?
    ) -> TerminalMenuAction? {
        let ids = snapshot?.windowIDs(for: featureID) ?? []
        switch key {
        case .up:
            if selectedWindowInstanceID != nil {
                if selectedWindowIndex == 0 {
                    self.selectedWindowInstanceID = nil
                } else {
                    selectedWindowIndex -= 1
                    self.selectedWindowInstanceID = ids.indices.contains(selectedWindowIndex)
                        ? ids[selectedWindowIndex]
                        : nil
                }
            }
            return nil
        case .down:
            guard !ids.isEmpty else { return nil }
            if selectedWindowInstanceID == nil {
                selectedWindowIndex = 0
                selectedWindowInstanceID = ids[0]
            } else if selectedWindowIndex + 1 < ids.count {
                selectedWindowIndex += 1
                selectedWindowInstanceID = ids[selectedWindowIndex]
            }
            return nil
        case .left:
            guard snapshot.map({ $0.windowIDs(for: featureID).count > 1 }) ?? true else { return nil }
            return .adjustWindowCount(featureID, -1)
        case .right:
            guard snapshot.map({ $0.windowIDs(for: featureID).count < $0.maximumWindowCount }) ?? true else { return nil }
            return .adjustWindowCount(featureID, 1)
        case .enter:
            guard selectedWindowInstanceID != nil else { return nil }
            selectedFeatureField = .enabled
            isEditingWindowSettings = true
            return nil
        case .escape:
            selectedFeature = nil
            selectedWindowInstanceID = nil
            isEditingWindowSettings = false
            selectedWindowIndex = 0
            return nil
        case .quit:
            return .quit
        }
    }

    private mutating func handleWindowKey(
        _ key: TerminalKey,
        featureID: FeatureID,
        windowID: WindowInstanceID
    ) -> TerminalMenuAction? {
        let fields = TerminalFeatureField.allCases
        guard let fieldIndex = fields.firstIndex(of: selectedFeatureField) else { return nil }
        switch key {
        case .up:
            selectedFeatureField = fields[max(0, fieldIndex - 1)]
            return nil
        case .down:
            selectedFeatureField = fields[min(fields.count - 1, fieldIndex + 1)]
            return nil
        case .left:
            return adjustWindowSelection(windowID: windowID, direction: -1)
        case .right:
            return adjustWindowSelection(windowID: windowID, direction: 1)
        case .enter:
            switch selectedFeatureField {
            case .enabled:
                return .toggleWindowEnabled(windowID)
            case .freeze:
                return .toggleWindowFreeze(windowID)
            case .hideUIBar:
                return .adjustWindow(windowID, .hideUIBar, 1)
            case .sizeReset:
                return .resetWindowSize(windowID)
            case .windowX, .windowY, .cropZoom, .panX, .panY, .padding, .detection:
                return nil
            }
        case .escape:
            isEditingWindowSettings = false
            return nil
        case .quit:
            return .quit
        }
    }

    private func adjustWindowSelection(windowID: WindowInstanceID, direction: Int) -> TerminalMenuAction? {
        switch selectedFeatureField {
        case .enabled:
            return .toggleWindowEnabled(windowID)
        case .freeze:
            return .toggleWindowFreeze(windowID)
        case .hideUIBar:
            return .adjustWindow(windowID, .hideUIBar, direction)
        case .sizeReset:
            return nil
        case .windowX, .windowY, .cropZoom, .panX, .panY, .padding, .detection:
            return .adjustWindow(windowID, selectedFeatureField, direction)
        }
    }

    private func adjustHomeSelection(direction: Int) -> TerminalMenuAction? {
        switch selectedHomeIndex {
        case 0: return .toggleLive
        case 1: return .toggleAll
        case 2: return .toggleFollow
        case 3: return .toggleMirror
        case 4: return .adjustSmoothing(direction)
        case 5: return .toggleAutoCropScale
        case 6: return .toggleAllUIBars
        case 14: return .toggleGoofyUI
        case 8...13: return .toggleFeature(FeatureID.allCases[selectedHomeIndex - Self.firstFeatureIndex])
        default: return nil
        }
    }

    private mutating func activateHomeSelection() -> TerminalMenuAction? {
        switch selectedHomeIndex {
        case 0: return .toggleLive
        case 1: return .toggleAll
        case 2: return .toggleFollow
        case 3: return .toggleMirror
        case 4: return nil
        case 5: return .toggleAutoCropScale
        case 6: return .toggleAllUIBars
        case 7: return .resetAll
        case 8...13:
            let featureID = FeatureID.allCases[selectedHomeIndex - Self.firstFeatureIndex]
            selectedFeature = featureID
            selectedWindowInstanceID = nil
            isEditingWindowSettings = false
            selectedWindowIndex = 0
            selectedFeatureField = .enabled
            return nil
        case 14: return .toggleGoofyUI
        case 15: return .quit
        default: return nil
        }
    }
}
