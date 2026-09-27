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
    case toggleGoofyUI
    case quit
}

/// Immutable display values copied from AppState for one render/input turn.
struct TerminalFeatureSnapshot: Equatable {
    let isEnabled: Bool
    let isFrozen: Bool
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
    let features: [FeatureID: TerminalFeatureSnapshot]

    init(
        isLive: Bool,
        showAll: Bool,
        follow: Bool,
        autoCropScale: Bool = false,
        mirror: Bool,
        smoothing: CGFloat,
        cameraStatus: String = "IDLE",
        goofyUIVisible: Bool,
        features: [FeatureID: TerminalFeatureSnapshot]
    ) {
        self.isLive = isLive
        self.showAll = showAll
        self.follow = follow
        self.autoCropScale = autoCropScale
        self.mirror = mirror
        self.smoothing = smoothing
        self.cameraStatus = cameraStatus
        self.goofyUIVisible = goofyUIVisible
        self.features = features
    }

    /// Capture current AppState values and the six already-resolved panel sizes.
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
        features = Dictionary(uniqueKeysWithValues: FeatureID.allCases.compactMap { id in
            guard
                let configuration = appState.features[id],
                let windowSize = windowSizes[id]
            else {
                return nil
            }
            return (id, TerminalFeatureSnapshot(configuration: configuration, windowSize: windowSize))
        })
    }
}

/// Navigation only. Mutable application values always come from TerminalMenuSnapshot.
struct TerminalMenuModel {
    private(set) var selectedHomeIndex = 0
    private(set) var selectedFeature: FeatureID?
    private(set) var selectedFeatureField: TerminalFeatureField = .enabled

    static let homeItemCount = 15
    static let firstFeatureIndex = 7

    var isShowingFeatureDetails: Bool { selectedFeature != nil }
    var selectedFeatureFieldIndex: Int? { TerminalFeatureField.allCases.firstIndex(of: selectedFeatureField) }

    mutating func handle(_ key: TerminalKey) -> TerminalMenuAction? {
        if key == .quit {
            return .quit
        }

        if let featureID = selectedFeature {
            return handleFeatureKey(key, featureID: featureID)
        }

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

    private mutating func handleFeatureKey(_ key: TerminalKey, featureID: FeatureID) -> TerminalMenuAction? {
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
            return adjustFeatureSelection(featureID: featureID, direction: -1)
        case .right:
            return adjustFeatureSelection(featureID: featureID, direction: 1)
        case .enter:
            switch selectedFeatureField {
            case .enabled:
                return .toggleFeature(featureID)
            case .freeze:
                return .toggleFreeze(featureID)
            case .sizeReset:
                return .resetFeatureSize(featureID)
            case .windowX, .windowY, .cropZoom, .panX, .panY, .padding, .detection:
                return nil
            }
        case .escape:
            selectedFeature = nil
            return nil
        case .quit:
            return .quit
        }
    }

    private func adjustFeatureSelection(featureID: FeatureID, direction: Int) -> TerminalMenuAction? {
        switch selectedFeatureField {
        case .enabled:
            return .toggleFeature(featureID)
        case .freeze:
            return .toggleFreeze(featureID)
        case .sizeReset:
            return nil
        case .windowX, .windowY, .cropZoom, .panX, .panY, .padding, .detection:
            return .adjustFeature(featureID, selectedFeatureField, direction)
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
        case 13: return .toggleGoofyUI
        case 7...12: return .toggleFeature(FeatureID.allCases[selectedHomeIndex - Self.firstFeatureIndex])
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
        case 6: return .resetAll
        case 7...12:
            let featureID = FeatureID.allCases[selectedHomeIndex - Self.firstFeatureIndex]
            selectedFeature = featureID
            selectedFeatureField = .enabled
            return nil
        case 13: return .toggleGoofyUI
        case 14: return .quit
        default: return nil
        }
    }
}
