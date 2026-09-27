import SwiftUI

struct FeatureControlRow: View {
    let featureID: FeatureID
    @ObservedObject var appState: AppState
    @State private var isExpanded = false

    private var configuration: FeatureConfiguration {
        appState.features[featureID] ?? .default
    }

    private var windowSize: CGSize {
        configuration.windowSizeOverride ?? CGSize(
            width: FeatureWindowManager.defaultPanelSize.width * configuration.windowScale,
            height: FeatureWindowManager.defaultPanelSize.height * configuration.windowScale
        )
    }

    private var isFaceFeature: Bool {
        switch featureID {
        case .leftEye, .rightEye, .nose, .mouth: true
        case .leftHand, .rightHand: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(featureID == .leftEye || featureID == .nose || featureID == .leftHand ? BlobbyTheme.accent : BlobbyTheme.base)
                    .frame(width: 12, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: 1.5))

                Text(featureID.windowTitle)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(0.35)

                Spacer(minLength: 0)

                Button {
                    appState.setFeatureEnabled(!configuration.isEnabled, for: featureID)
                } label: {
                    Text(configuration.isEnabled ? "ON" : "OFF")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .frame(minWidth: 60, minHeight: BlobbyTheme.hitTargetHeight)
                        .foregroundStyle(configuration.isEnabled ? BlobbyTheme.paper : BlobbyTheme.ink)
                        .background(configuration.isEnabled ? BlobbyTheme.base : BlobbyTheme.paper, in: RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: BlobbyTheme.borderWidth))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(featureID.windowTitle) \(configuration.isEnabled ? "on" : "off")")
                .accessibilityValue(configuration.isEnabled ? "On" : "Off")
            }

            Button {
                appState.setFeatureFrozen(!configuration.isFrozen, for: featureID)
            } label: {
                Text(configuration.isFrozen ? "UNFREEZE FRAME" : "FREEZE FRAME")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: BlobbyTheme.hitTargetHeight)
                    .foregroundStyle(configuration.isFrozen ? BlobbyTheme.paper : BlobbyTheme.ink)
                    .background(configuration.isFrozen ? BlobbyTheme.accent : BlobbyTheme.paper, in: RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: BlobbyTheme.borderWidth))
            }
            .buttonStyle(.plain)
            .disabled(!configuration.isEnabled)
            .accessibilityLabel("\(featureID.windowTitle) freeze frame")
            .accessibilityValue(configuration.isFrozen ? "On" : "Off")

            HStack(spacing: 6) {
                Text("WINDOW SIZE")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.45)
                    .lineLimit(1)

                Text("\(Int(windowSize.width.rounded())) × \(Int(windowSize.height.rounded()))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .accessibilityLabel("Window size \(Int(windowSize.width.rounded())) by \(Int(windowSize.height.rounded())) points")

                Spacer(minLength: 0)

                Button {
                    appState.setWindowScale(1, for: featureID)
                } label: {
                    Text("RESET")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.3)
                        .frame(minWidth: 50, minHeight: BlobbyTheme.hitTargetHeight)
                        .foregroundStyle(BlobbyTheme.ink)
                        .background(BlobbyTheme.paper, in: RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset \(featureID.windowTitle) window size")
            }
            .frame(minHeight: BlobbyTheme.hitTargetHeight)

            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text(isExpanded ? "LESS SETTINGS" : "MORE SETTINGS")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .black))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(BlobbyTheme.baseDeep)
                .frame(maxWidth: .infinity, minHeight: BlobbyTheme.hitTargetHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isExpanded ? "Hide" : "Show") advanced settings for \(featureID.windowTitle)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                advancedSettings
            }
        }
        .padding(10)
        .foregroundStyle(BlobbyTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(BlobbyTheme.ink, lineWidth: BlobbyTheme.borderWidth)
        }
        .background(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(BlobbyTheme.ink)
                .offset(x: 2, y: 3)
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(BlobbyTheme.ink.opacity(0.3))

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("WINDOW PLACEMENT")
                HStack(spacing: 12) {
                    compactSlider(
                        title: "X",
                        value: CGFloatBinding(
                            get: { configuration.windowOffsetX },
                            set: { appState.setWindowOffsetX($0, for: featureID) }
                        ),
                        range: -1_000...1_000,
                        step: 10,
                        valueText: "\(Int(configuration.windowOffsetX)) PT"
                    )
                    compactSlider(
                        title: "Y",
                        value: CGFloatBinding(
                            get: { configuration.windowOffsetY },
                            set: { appState.setWindowOffsetY($0, for: featureID) }
                        ),
                        range: -1_000...1_000,
                        step: 10,
                        valueText: "\(Int(configuration.windowOffsetY)) PT"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("CROP FRAMING")
                compactSlider(
                    title: "ZOOM",
                    value: CGFloatBinding(
                        get: { configuration.cropZoom },
                        set: { appState.setCropZoom($0, for: featureID) }
                    ),
                    range: Double(FeatureConfiguration.cropZoomRange.lowerBound)...Double(FeatureConfiguration.cropZoomRange.upperBound),
                    step: 0.25,
                    valueText: String(format: "%.2f×", Double(configuration.cropZoom))
                )

                HStack(spacing: 12) {
                    compactSlider(
                        title: "PAN X",
                        value: CGFloatBinding(
                            get: { configuration.cropOffsetX },
                            set: { appState.setCropOffsetX($0, for: featureID) }
                        ),
                        range: -1...1,
                        step: 0.05,
                        valueText: String(format: "%+.2f", Double(configuration.cropOffsetX))
                    )
                    compactSlider(
                        title: "PAN Y",
                        value: CGFloatBinding(
                            get: { configuration.cropOffsetY },
                            set: { appState.setCropOffsetY($0, for: featureID) }
                        ),
                        range: -1...1,
                        step: 0.05,
                        valueText: String(format: "%+.2f", Double(configuration.cropOffsetY))
                    )
                }

                compactSlider(
                    title: "CROP PADDING",
                    value: CGFloatBinding(
                        get: { configuration.cropPadding },
                        set: { appState.setCropPadding($0, for: featureID) }
                    ),
                    range: 0...1,
                    step: 0.05,
                    valueText: "\(Int((configuration.cropPadding * 100).rounded()))%"
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("DETECTION")
                compactSlider(
                    title: isFaceFeature ? "OBSERVATION + GEOMETRY" : "JOINT CONFIDENCE",
                    value: Binding(
                        get: { Double(configuration.detectionThreshold) },
                        set: { appState.setDetectionThreshold(Float($0), for: featureID) }
                    ),
                    range: 0...1,
                    step: 0.05,
                    valueText: String(format: "%.2f", Double(configuration.detectionThreshold))
                )
                if isFaceFeature {
                    Text("Face observation and valid geometry threshold; Vision does not score each landmark.")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(BlobbyTheme.ink.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 2)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .black, design: .rounded))
            .tracking(0.85)
            .foregroundStyle(BlobbyTheme.baseDeep)
    }

    private func compactSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(valueText)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Slider(value: value, in: range, step: step)
                .tint(BlobbyTheme.base)
                .frame(height: BlobbyTheme.hitTargetHeight)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, minHeight: BlobbyTheme.hitTargetHeight)
    }
}

private func CGFloatBinding(get: @escaping () -> CGFloat, set: @escaping (CGFloat) -> Void) -> Binding<Double> {
    Binding(
        get: { Double(get()) },
        set: { set(CGFloat($0)) }
    )
}
