import Foundation

struct FeatureConfiguration: Equatable {
    static let cropZoomRange: ClosedRange<CGFloat> = 0.25...8
    static let windowOffsetRange: ClosedRange<CGFloat> = -1_000...1_000

    var isEnabled: Bool
    var isFrozen: Bool = false
    var hidesUIBar: Bool = false
    var windowScale: CGFloat
    /// Native drag resize overrides the scale preset until a preset or RESET is chosen.
    var windowSizeOverride: CGSize? = nil
    var cropPadding: CGFloat
    var detectionThreshold: Float
    /// Multiplies crop magnification independently of physical panel size; 1 keeps the base crop.
    var cropZoom: CGFloat = 1
    /// Pan in normalized full-image coordinates. Zero keeps the detected feature centered.
    var cropOffsetX: CGFloat = 0
    var cropOffsetY: CGFloat = 0
    /// Panel placement offsets in AppKit screen points, applied before collision resolution.
    var windowOffsetX: CGFloat = 0
    var windowOffsetY: CGFloat = 0

    static let `default` = FeatureConfiguration(
        isEnabled: true,
        windowScale: 1.0,
        cropPadding: 0.25,
        detectionThreshold: 0.55,
        cropZoom: 1,
        cropOffsetX: 0,
        cropOffsetY: 0,
        windowOffsetX: 0,
        windowOffsetY: 0
    )
}
