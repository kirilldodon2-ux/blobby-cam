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

    @Published private(set) var isLive = false
    @Published private(set) var showAll = true
    @Published private(set) var follow = false
    @Published private(set) var autoCropScale = false
    @Published private(set) var smoothing = AppState.defaultSmoothing
    @Published private(set) var mirror = MirrorPolicy.selfieOrientationByDefault
    @Published private(set) var features: [FeatureID: FeatureConfiguration]
    @Published private(set) var cameraStatus: CameraStatus = .idle

    init() {
        features = Self.makeDefaultFeatures()
    }

    func setLive(_ isLive: Bool) {
        self.isLive = isLive
    }

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
        updateFeature(id) {
            $0.isEnabled = isEnabled
            if !isEnabled { $0.isFrozen = false }
        }
    }

    func setFeatureFrozen(_ isFrozen: Bool, for id: FeatureID) {
        updateFeature(id) {
            $0.isFrozen = isFrozen && $0.isEnabled
        }
    }

    func setWindowScale(_ windowScale: CGFloat, for id: FeatureID) {
        let boundedScale = Self.clamp(windowScale, to: 0.25...4, nanFallback: 1.0)
        updateFeature(id) {
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
        updateFeature(id) { $0.windowSizeOverride = bounded }
    }

    func setCropPadding(_ cropPadding: CGFloat, for id: FeatureID) {
        updateFeature(id) { $0.cropPadding = cropPadding }
    }

    func setCropZoom(_ cropZoom: CGFloat, for id: FeatureID) {
        let fallback: CGFloat = (id == .leftEye || id == .rightEye) ? 0.5 : 1
        let bounded = Self.clamp(cropZoom, to: FeatureConfiguration.cropZoomRange, nanFallback: fallback)
        updateFeature(id) { $0.cropZoom = bounded }
    }

    func setCropOffsetX(_ cropOffsetX: CGFloat, for id: FeatureID) {
        let bounded = Self.clamp(cropOffsetX, to: -1...1, nanFallback: 0)
        updateFeature(id) { $0.cropOffsetX = bounded }
    }

    func setCropOffsetY(_ cropOffsetY: CGFloat, for id: FeatureID) {
        let bounded = Self.clamp(cropOffsetY, to: -1...1, nanFallback: 0)
        updateFeature(id) { $0.cropOffsetY = bounded }
    }

    func setWindowOffsetX(_ windowOffsetX: CGFloat, for id: FeatureID) {
        let bounded = Self.clamp(
            windowOffsetX,
            to: FeatureConfiguration.windowOffsetRange,
            nanFallback: 0
        )
        updateFeature(id) { $0.windowOffsetX = bounded }
    }

    func setWindowOffsetY(_ windowOffsetY: CGFloat, for id: FeatureID) {
        let bounded = Self.clamp(
            windowOffsetY,
            to: FeatureConfiguration.windowOffsetRange,
            nanFallback: 0
        )
        updateFeature(id) { $0.windowOffsetY = bounded }
    }

    func setDetectionThreshold(_ detectionThreshold: Float, for id: FeatureID) {
        let boundedThreshold = Self.clamp(detectionThreshold, to: 0...1, nanFallback: FeatureConfiguration.default.detectionThreshold)
        updateFeature(id) { $0.detectionThreshold = boundedThreshold }
    }

    func reset() {
        isLive = false
        showAll = true
        follow = false
        autoCropScale = false
        smoothing = Self.defaultSmoothing
        mirror = MirrorPolicy.selfieOrientationByDefault
        features = Self.makeDefaultFeatures()
    }

    private func updateFeature(_ id: FeatureID, _ update: (inout FeatureConfiguration) -> Void) {
        guard var configuration = features[id] else { return }
        update(&configuration)
        features[id] = configuration
    }

    private static func makeDefaultFeatures() -> [FeatureID: FeatureConfiguration] {
        Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { id in
            var configuration = FeatureConfiguration.default
            if id == .leftEye || id == .rightEye { configuration.cropZoom = 0.5 }
            return (id, configuration)
        })
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
