import Foundation

enum FeatureID: String, CaseIterable, Codable {
    case leftEye
    case rightEye
    case nose
    case mouth
    case leftHand
    case rightHand

    var windowTitle: String {
        switch self {
        case .leftEye: "LEFT EYE"
        case .rightEye: "RIGHT EYE"
        case .nose: "NOSE"
        case .mouth: "MOUTH"
        case .leftHand: "LEFT HAND"
        case .rightHand: "RIGHT HAND"
        }
    }

    func windowTitle(ordinal: Int) -> String {
        "\(windowTitle) \(ordinal)"
    }
}

/// Stable identity for one native window belonging to a feature.
/// Ordinal titles are presentation only; the serial is never reused during an AppState lifetime.
struct WindowInstanceID: Hashable, Codable {
    let featureID: FeatureID
    let serial: UInt64

    init(featureID: FeatureID, serial: UInt64) {
        self.featureID = featureID
        self.serial = serial
    }
}
