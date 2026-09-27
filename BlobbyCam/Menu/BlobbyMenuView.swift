import SwiftUI

struct BlobbyMenuView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                header
                globalControls
                featureSectionHeading

                LazyVStack(spacing: 9) {
                    ForEach(FeatureID.allCases, id: \.self) { featureID in
                        FeatureControlRow(featureID: featureID, appState: appState)
                    }
                }

                footer
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(BlobbyTheme.paper)
        .frame(width: 360, height: 620)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            // This bordered tile reserves the eventual logo position; it remains intentionally empty.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BlobbyTheme.accentSoft)
                .frame(width: 42, height: 42)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BlobbyTheme.ink, lineWidth: BlobbyTheme.borderWidth)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("BLOBBY")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .tracking(-0.5)
                Text("CAM")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(BlobbyTheme.baseDeep)
            }
            .foregroundStyle(BlobbyTheme.ink)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isLive ? BlobbyTheme.base : BlobbyTheme.accent)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(BlobbyTheme.ink, lineWidth: 1.5))
                Text(appState.isLive ? "CAM LIVE" : "CAM IDLE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.3)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(BlobbyTheme.paper, in: Capsule())
            .overlay(Capsule().stroke(BlobbyTheme.ink, lineWidth: BlobbyTheme.borderWidth))
            .accessibilityLabel(appState.isLive ? "Camera live" : "Camera idle")
        }
        .frame(minHeight: 44)
    }

    private var globalControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CAMERA CONTROL")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.1)
                Spacer()
                Button(action: appState.reset) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("RESET")
                    }
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .frame(minWidth: 76, minHeight: BlobbyTheme.hitTargetHeight)
                    .foregroundStyle(BlobbyTheme.ink)
                    .background(BlobbyTheme.paper, in: RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: BlobbyTheme.borderWidth))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset all controls")
            }

            HStack(spacing: 7) {
                stateButton(
                    title: appState.isLive ? "LIVE ON" : "START LIVE",
                    isOn: appState.isLive,
                    accessibilityLabel: appState.isLive ? "Stop live camera" : "Start live camera",
                    rainbow: true
                ) {
                    appState.setLive(!appState.isLive)
                }

                stateButton(
                    title: appState.showAll ? "HIDE ALL" : "SHOW ALL",
                    isOn: appState.showAll,
                    accessibilityLabel: appState.showAll ? "Hide all feature windows" : "Show all feature windows"
                ) {
                    appState.setShowAll(!appState.showAll)
                }
            }

            HStack(spacing: 7) {
                stateButton(title: "FOLLOW", isOn: appState.follow, accessibilityLabel: "Follow feature positions") {
                    appState.setFollow(!appState.follow)
                }
                stateButton(title: "MIRROR", isOn: appState.mirror, accessibilityLabel: "Selfie mirror") {
                    appState.setMirror(!appState.mirror)
                }
            }

            stateButton(
                title: "AUTO CROP SCALE",
                isOn: appState.autoCropScale,
                accessibilityLabel: "Scale facial crops with landmark size"
            ) {
                appState.setAutoCropScale(!appState.autoCropScale)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("SMOOTHING")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.8)
                    Spacer()
                    Text(String(format: "%.2f", Double(appState.smoothing)))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                }
                Slider(value: smoothingBinding, in: 0...1, step: 0.05)
                    .tint(BlobbyTheme.base)
                    .frame(height: BlobbyTheme.hitTargetHeight)
                    .accessibilityLabel("Smoothing")
            }
            .frame(minHeight: BlobbyTheme.hitTargetHeight)
        }
        .padding(12)
        .foregroundStyle(BlobbyTheme.ink)
        .background(.white, in: RoundedRectangle(cornerRadius: BlobbyTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BlobbyTheme.cornerRadius, style: .continuous)
                .stroke(BlobbyTheme.ink, lineWidth: BlobbyTheme.borderWidth)
        }
        .background(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: BlobbyTheme.cornerRadius, style: .continuous)
                .fill(BlobbyTheme.ink)
                .offset(x: BlobbyTheme.shadowX, y: BlobbyTheme.shadowY)
        }
    }

    private var featureSectionHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("FEATURE WINDOWS")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.1)
                Spacer()
                Text("6")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .frame(width: 24, height: 24)
                    .background(BlobbyTheme.accentSoft, in: Circle())
                    .overlay(Circle().stroke(BlobbyTheme.ink, lineWidth: 1.5))
            }
            Text("Drag a window edge to resize; crop framing stays independent.")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BlobbyTheme.ink.opacity(0.72))
        }
        .foregroundStyle(BlobbyTheme.ink)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Text("BLOBBY CAM")
                .fontWeight(.black)
            Circle().fill(BlobbyTheme.accentSoft).frame(width: 5, height: 5)
            Text("SIX CAMERA WINDOWS")
                .fontWeight(.bold)
            Spacer(minLength: 0)
        }
        .font(.system(size: 8, design: .rounded))
        .tracking(0.4)
        .foregroundStyle(BlobbyTheme.baseDeep)
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var smoothingBinding: Binding<Double> {
        Binding(
            get: { Double(appState.smoothing) },
            set: { appState.setSmoothing(CGFloat($0)) }
        )
    }

    private func stateButton(
        title: String,
        isOn: Bool,
        accessibilityLabel: String,
        rainbow: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: BlobbyTheme.hitTargetHeight)
                .foregroundStyle(isOn && !rainbow ? BlobbyTheme.paper : BlobbyTheme.ink)
                .background {
                    if rainbow && isOn {
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { index in
                                Rectangle().fill(Self.rainbowColors[index])
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous)
                            .fill(isOn ? BlobbyTheme.base : BlobbyTheme.paper)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: BlobbyTheme.borderWidth))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private static let rainbowColors: [Color] = [
        Color(red: 1.00, green: 0.36, blue: 0.57),
        Color(red: 1.00, green: 0.60, blue: 0.36),
        Color(red: 1.00, green: 0.85, blue: 0.37),
        Color(red: 0.47, green: 0.87, blue: 0.47),
        Color(red: 0.39, green: 0.75, blue: 1.00),
        Color(red: 0.70, green: 0.51, blue: 1.00),
        Color(red: 1.00, green: 0.44, blue: 0.82)
    ]
}
