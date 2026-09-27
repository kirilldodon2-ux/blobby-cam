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
}
