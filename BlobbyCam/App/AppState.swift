import Combine
import CoreGraphics

enum CameraStatus: Equatable {
    case idle
    case requestingPermission
    case starting
    case live
    case stopping
    case interrupted
    case denied
    case restricted
    case unavailable
    case error(String)

    var terminalLabel: String {
        switch self {
        case .idle: "IDLE"
        case .requestingPermission: "ASKING PERMISSION"
        case .starting: "STARTING"
        case .live: "LIVE"
        case .stopping: "STOPPING"
        case .interrupted: "INTERRUPTED"
        case .denied: "ACCESS DENIED"
        case .restricted: "ACCESS RESTRICTED"
        case .unavailable: "NO CAMERA"
        case let .error(message): "CAMERA ERROR: \(Self.ascii(message))"
        }
    }

    private static func ascii(_ value: String) -> String {
        let printable = value.unicodeScalars.map { scalar -> Character in
            guard scalar.value >= 0x20, scalar.value <= 0x7E else { return " " }
            return Character(scalar)
        }
        let compact = String(printable).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(compact.prefix(48))
    }
}

@MainActor
final class AppState: ObservableObject {
    static let defaultSmoothing: CGFloat = 0
    static let maximumWindowCount = 32

    @Published private(set) var isLive = false
    @Published private(set) var showAll = true
    @Published private(set) var syphonEnabled = false
    @Published private(set) var follow = false
    @Published private(set) var autoCropScale = false
    @Published private(set) var smoothing = AppState.defaultSmoothing
    @Published private(set) var mirror = MirrorPolicy.selfieOrientationByDefault
    @Published private(set) var windowIDsByFeature: [FeatureID: [WindowInstanceID]]
    @Published private(set) var configurationsByWindowID: [WindowInstanceID: FeatureConfiguration]
    @Published private(set) var features: [FeatureID: FeatureConfiguration]
    @Published private(set) var cameraStatus: CameraStatus = .idle

    private var nextSerialByFeature: [FeatureID: UInt64]

    init() {
        let initial = Self.makeDefaultWindowState()
        windowIDsByFeature = initial.ids
        configurationsByWindowID = initial.configurations
        features = Self.legacyProjection(ids: initial.ids, configurations: initial.configurations)
        nextSerialByFeature = Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { ($0, 2) })
    }

    func setLive(_ isLive: Bool) {
        self.isLive = isLive
    }

    /// The global control applies a value to all instances; there is no second override state.
    var allUIBarsHidden: Bool {
        !configurationsByWindowID.isEmpty && configurationsByWindowID.values.allSatisfy(\.hidesUIBar)
    }

    func setAllUIBarsHidden(_ hidden: Bool) {
        for id in allWindowIDs() { setUIBarHidden(hidden, for: id) }
    }

    func setUIBarHidden(_ hidden: Bool, for id: WindowInstanceID) {
        updateConfiguration(for: id) { $0.hidesUIBar = hidden }
    }

    func setSyphonEnabled(_ enabled: Bool) { syphonEnabled = enabled }

    func setShowAll(_ showAll: Bool) {
        self.showAll = showAll
    }

    func setFollow(_ follow: Bool) {
        self.follow = follow
    }

    func setAutoCropScale(_ enabled: Bool) {
        autoCropScale = enabled
    }

    func setSmoothing(_ smoothing: CGFloat) {
        self.smoothing = smoothing
    }

    func setMirror(_ mirror: Bool) {
        self.mirror = mirror
    }

    func setCameraStatus(_ cameraStatus: CameraStatus) {
        self.cameraStatus = cameraStatus
    }

    func setFeatureEnabled(_ isEnabled: Bool, for id: FeatureID) {
        for instanceID in windowIDs(for: id) {
            updateConfiguration(for: instanceID) {
                $0.isEnabled = isEnabled
                if !isEnabled { $0.isFrozen = false }
            }
        }
    }

    func setFeatureEnabled(_ isEnabled: Bool, for id: WindowInstanceID) {
        updateConfiguration(for: id) {
            $0.isEnabled = isEnabled
            if !isEnabled { $0.isFrozen = false }
        }
    }

    func setFeatureFrozen(_ isFrozen: Bool, for id: FeatureID) {
        updateFirstInstance(for: id) {
            $0.isFrozen = isFrozen && $0.isEnabled
        }
    }

    func setFeatureFrozen(_ isFrozen: Bool, for id: WindowInstanceID) {
        updateConfiguration(for: id) {
            $0.isFrozen = isFrozen && $0.isEnabled
        }
    }

    func setWindowScale(_ windowScale: CGFloat, for id: FeatureID) {
        let boundedScale = Self.clamp(windowScale, to: 0.25...4, nanFallback: 1.0)
        updateFirstInstance(for: id) {
            $0.windowScale = boundedScale
            $0.windowSizeOverride = nil
        }
    }

    func setWindowScale(_ windowScale: CGFloat, for id: WindowInstanceID) {
        let boundedScale = Self.clamp(windowScale, to: 0.25...4, nanFallback: 1.0)
        updateConfiguration(for: id) {
            $0.windowScale = boundedScale
            $0.windowSizeOverride = nil
        }
    }

    func setWindowSize(_ size: CGSize, for id: FeatureID) {
        guard size.width.isFinite, size.height.isFinite else { return }
        let bounded = CGSize(
            width: Self.clamp(size.width, to: 80...960, nanFallback: 240),
            height: Self.clamp(size.height, to: 60...720, nanFallback: 180)
        )
        updateFirstInstance(for: id) { $0.windowSizeOverride = bounded }
    }

    func setWindowSize(_ size: CGSize, for id: WindowInstanceID) {
        guard size.width.isFinite, size.height.isFinite else { return }
        let bounded = CGSize(
            width: Self.clamp(size.width, to: 80...960, nanFallback: 240),
            height: Self.clamp(size.height, to: 60...720, nanFallback: 180)
        )
        updateConfiguration(for: id) { $0.windowSizeOverride = bounded }
    }

    func setCropPadding(_ cropPadding: CGFloat, for id: FeatureID) {
        updateFirstInstance(for: id) { $0.cropPadding = cropPadding }
    }

    func setCropPadding(_ cropPadding: CGFloat, for id: WindowInstanceID) {
        updateConfiguration(for: id) { $0.cropPadding = cropPadding }
    }

    func setCropZoom(_ cropZoom: CGFloat, for id: FeatureID) {
        let bounded = Self.boundedCropZoom(cropZoom, for: id)
        updateFirstInstance(for: id) { $0.cropZoom = bounded }
    }

    func setCropZoom(_ cropZoom: CGFloat, for id: WindowInstanceID) {
        let bounded = Self.boundedCropZoom(cropZoom, for: id.featureID)
        updateConfiguration(for: id) { $0.cropZoom = bounded }
    }

    func setCropOffsetX(_ cropOffsetX: CGFloat, for id: FeatureID) {
        let bounded = Self.clamp(cropOffsetX, to: -1...1, nanFallback: 0)
        updateFirstInstance(for: id) { $0.cropOffsetX = bounded }
    }

    func setCropOffsetX(_ cropOffsetX: CGFloat, for id: WindowInstanceID) {
        let bounded = Self.clamp(cropOffsetX, to: -1...1, nanFallback: 0)
        updateConfiguration(for: id) { $0.cropOffsetX = bounded }
    }

    func setCropOffsetY(_ cropOffsetY: CGFloat, for id: FeatureID) {
        let bounded = Self.clamp(cropOffsetY, to: -1...1, nanFallback: 0)
        updateFirstInstance(for: id) { $0.cropOffsetY = bounded }
    }

    func setCropOffsetY(_ cropOffsetY: CGFloat, for id: WindowInstanceID) {
        let bounded = Self.clamp(cropOffsetY, to: -1...1, nanFallback: 0)
        updateConfiguration(for: id) { $0.cropOffsetY = bounded }
    }

    func setWindowOffsetX(_ windowOffsetX: CGFloat, for id: FeatureID) {
        let bounded = Self.clamp(
            windowOffsetX,
            to: FeatureConfiguration.windowOffsetRange,
            nanFallback: 0
        )
        updateFirstInstance(for: id) { $0.windowOffsetX = bounded }
    }

    func setWindowOffsetX(_ windowOffsetX: CGFloat, for id: WindowInstanceID) {
        let bounded = Self.clamp(
            windowOffsetX,
            to: FeatureConfiguration.windowOffsetRange,
            nanFallback: 0
        )
        updateConfiguration(for: id) { $0.windowOffsetX = bounded }
    }

    func setWindowOffsetY(_ windowOffsetY: CGFloat, for id: FeatureID) {
        let bounded = Self.clamp(
            windowOffsetY,
            to: FeatureConfiguration.windowOffsetRange,
            nanFallback: 0
        )
        updateFirstInstance(for: id) { $0.windowOffsetY = bounded }
    }

    func setWindowOffsetY(_ windowOffsetY: CGFloat, for id: WindowInstanceID) {
        let bounded = Self.clamp(
            windowOffsetY,
            to: FeatureConfiguration.windowOffsetRange,
            nanFallback: 0
        )
        updateConfiguration(for: id) { $0.windowOffsetY = bounded }
    }

    func setDetectionThreshold(_ detectionThreshold: Float, for id: FeatureID) {
        let boundedThreshold = Self.clamp(detectionThreshold, to: 0...1, nanFallback: FeatureConfiguration.default.detectionThreshold)
        updateFirstInstance(for: id) { $0.detectionThreshold = boundedThreshold }
    }

    func setDetectionThreshold(_ detectionThreshold: Float, for id: WindowInstanceID) {
        let boundedThreshold = Self.clamp(detectionThreshold, to: 0...1, nanFallback: FeatureConfiguration.default.detectionThreshold)
        updateConfiguration(for: id) { $0.detectionThreshold = boundedThreshold }
    }

    func windowIDs(for featureID: FeatureID) -> [WindowInstanceID] {
        windowIDsByFeature[featureID] ?? []
    }

    func allWindowIDs() -> [WindowInstanceID] {
        FeatureID.allCases.flatMap { windowIDs(for: $0) }
    }

    func windowCount(for featureID: FeatureID) -> Int {
        windowIDs(for: featureID).count
    }

    func configuration(for id: WindowInstanceID) -> FeatureConfiguration? {
        configurationsByWindowID[id]
    }

    /// Changes the desired number of instances. Shrinking always retires IDs from the end.
    func setWindowCount(_ count: Int, for featureID: FeatureID) {
        let desiredCount = min(max(count, 1), Self.maximumWindowCount)
        var ids = windowIDs(for: featureID)
        guard desiredCount != ids.count,
              let firstID = ids.first,
              let firstConfiguration = configurationsByWindowID[firstID]
        else { return }

        if desiredCount < ids.count {
            let removedIDs = Array(ids[desiredCount...])
            ids.removeSubrange(desiredCount...)
            for removedID in removedIDs {
                configurationsByWindowID.removeValue(forKey: removedID)
            }
            windowIDsByFeature[featureID] = ids
            publishLegacyFeature(for: featureID)
            return
        }

        while ids.count < desiredCount {
            guard let serial = nextSerialByFeature[featureID], serial < UInt64.max else { break }
            let newID = WindowInstanceID(featureID: featureID, serial: serial)
            nextSerialByFeature[featureID] = serial + 1
            configurationsByWindowID[newID] = firstConfiguration
            ids.append(newID)
        }
        windowIDsByFeature[featureID] = ids
        publishLegacyFeature(for: featureID)
    }

    /// Removes the requested instance. The final panel remains allocated and turns its feature off.
    @discardableResult
    func closeWindowInstance(_ id: WindowInstanceID) -> Bool {
        var ids = windowIDs(for: id.featureID)
        guard let index = ids.firstIndex(of: id) else { return false }

        if ids.count == 1 {
            updateConfiguration(for: id) {
                $0.isEnabled = false
                $0.isFrozen = false
            }
            return true
        }

        ids.remove(at: index)
        windowIDsByFeature[id.featureID] = ids
        configurationsByWindowID.removeValue(forKey: id)
        publishLegacyFeature(for: id.featureID)
        return true
    }

    func reset() {
        isLive = false
        showAll = true
        syphonEnabled = false
        follow = false
        autoCropScale = false
        smoothing = Self.defaultSmoothing
        mirror = MirrorPolicy.selfieOrientationByDefault
        var resetIDs: [FeatureID: [WindowInstanceID]] = [:]
        var resetConfigurations: [WindowInstanceID: FeatureConfiguration] = [:]
        for featureID in FeatureID.allCases {
            let retainedID = windowIDsByFeature[featureID]?.first
                ?? WindowInstanceID(featureID: featureID, serial: 1)
            resetIDs[featureID] = [retainedID]
            resetConfigurations[retainedID] = Self.defaultConfiguration(for: featureID)
        }
        windowIDsByFeature = resetIDs
        configurationsByWindowID = resetConfigurations
        features = Self.legacyProjection(ids: resetIDs, configurations: resetConfigurations)
    }

    private func updateFirstInstance(
        for featureID: FeatureID,
        _ update: (inout FeatureConfiguration) -> Void
    ) {
        guard let firstID = windowIDsByFeature[featureID]?.first else { return }
        updateConfiguration(for: firstID, update)
    }

    private func updateConfiguration(
        for id: WindowInstanceID,
        _ update: (inout FeatureConfiguration) -> Void
    ) {
        guard var configuration = configurationsByWindowID[id] else { return }
        update(&configuration)
        configurationsByWindowID[id] = configuration
        if windowIDsByFeature[id.featureID]?.first == id {
            features[id.featureID] = configuration
        }
    }

    private func publishLegacyFeature(for featureID: FeatureID) {
        guard let firstID = windowIDsByFeature[featureID]?.first,
              let configuration = configurationsByWindowID[firstID]
        else { return }
        // Keep `$features` useful to existing observers for count changes as well.
        features[featureID] = configuration
    }

    private static func legacyProjection(
        ids: [FeatureID: [WindowInstanceID]],
        configurations: [WindowInstanceID: FeatureConfiguration]
    ) -> [FeatureID: FeatureConfiguration] {
        Dictionary(uniqueKeysWithValues: FeatureID.allCases.compactMap { featureID in
            guard let firstID = ids[featureID]?.first,
                  let configuration = configurations[firstID]
            else { return nil }
            return (featureID, configuration)
        })
    }

    private static func makeDefaultWindowState() -> (
        ids: [FeatureID: [WindowInstanceID]],
        configurations: [WindowInstanceID: FeatureConfiguration]
    ) {
        var ids: [FeatureID: [WindowInstanceID]] = [:]
        var configurations: [WindowInstanceID: FeatureConfiguration] = [:]
        for featureID in FeatureID.allCases {
            let id = WindowInstanceID(featureID: featureID, serial: 1)
            ids[featureID] = [id]
            configurations[id] = defaultConfiguration(for: featureID)
        }
        return (ids, configurations)
    }

    private static func defaultConfiguration(for featureID: FeatureID) -> FeatureConfiguration {
        var configuration = FeatureConfiguration.default
        if featureID == .leftEye || featureID == .rightEye { configuration.cropZoom = 0.5 }
        return configuration
    }

    private static func boundedCropZoom(_ cropZoom: CGFloat, for featureID: FeatureID) -> CGFloat {
        let fallback: CGFloat = (featureID == .leftEye || featureID == .rightEye) ? 0.5 : 1
        return clamp(cropZoom, to: FeatureConfiguration.cropZoomRange, nanFallback: fallback)
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>, nanFallback: CGFloat) -> CGFloat {
        guard !value.isNaN else { return nanFallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>, nanFallback: Float) -> Float {
        guard !value.isNaN else { return nanFallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
