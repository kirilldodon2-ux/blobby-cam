import SwiftUI

enum BlobbyTheme {
    static let paper = Color(rgb: 0xF4F2EA)
    static let ink = Color(rgb: 0x111113)
    static let base = Color(rgb: 0x7A17E0)
    static let baseDeep = Color(rgb: 0x4E0FA0)
    static let accent = Color(rgb: 0xFF70B8)
    static let accentSoft = Color(rgb: 0xFFA6D3)

    static let borderWidth: CGFloat = 2
    static let cornerRadius: CGFloat = 16
    static let controlCornerRadius: CGFloat = 11
    static let hitTargetHeight: CGFloat = 48
    static let shadowX: CGFloat = 3
    static let shadowY: CGFloat = 4
}

private extension Color {
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}
