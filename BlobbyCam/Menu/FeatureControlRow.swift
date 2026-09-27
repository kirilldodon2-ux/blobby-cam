import SwiftUI

struct FeatureControlRow: View {
    let featureID: FeatureID
    @ObservedObject var appState: AppState

    private var windowIDs: [WindowInstanceID] {
        appState.windowIDs(for: featureID)
    }

    private var enabledStates: [Bool] {
        windowIDs.compactMap { appState.configuration(for: $0)?.isEnabled }
    }

    private var isEveryWindowEnabled: Bool {
        !enabledStates.isEmpty && enabledStates.allSatisfy { $0 }
    }

    private var isEveryWindowDisabled: Bool {
        !enabledStates.isEmpty && enabledStates.allSatisfy { !$0 }
    }

    private var globalStateTitle: String {
        if isEveryWindowEnabled { "ON" }
        else if isEveryWindowDisabled { "OFF" }
        else { "MIXED" }
    }

    private var globalStateValue: String {
        if isEveryWindowEnabled { "On" }
        else if isEveryWindowDisabled { "Off" }
        else { "Mixed" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            featureHeader
            windowCountControl

            VStack(spacing: 6) {
                ForEach(Array(windowIDs.enumerated()), id: \.element) { index, id in
                    FeatureInstanceControlRow(
                        featureID: featureID,
                        instanceID: id,
                        ordinal: index + 1,
                        appState: appState
                    )
                }
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

    private var featureHeader: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(featureID == .leftEye || featureID == .nose || featureID == .leftHand ? BlobbyTheme.accent : BlobbyTheme.base)
                .frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: 1.5))
                .accessibilityHidden(true)

            Text(featureID.windowTitle)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(0.35)

            Spacer(minLength: 0)

            Button {
                appState.setFeatureEnabled(!isEveryWindowEnabled, for: featureID)
            } label: {
                Text(globalStateTitle)
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .frame(minWidth: 64, minHeight: 38)
                    .foregroundStyle(isEveryWindowEnabled ? BlobbyTheme.paper : BlobbyTheme.ink)
                    .background(isEveryWindowEnabled ? BlobbyTheme.base : BlobbyTheme.paper, in: RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: BlobbyTheme.controlCornerRadius, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: BlobbyTheme.borderWidth))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set all \(featureID.windowTitle.lowercased()) windows")
            .accessibilityValue(globalStateValue)
            .accessibilityIdentifier("feature-global-\(featureID.rawValue)")
        }
    }

    private var windowCountControl: some View {
        HStack(spacing: 7) {
            Text("WINDOWS")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.75)

            Spacer(minLength: 2)

            Button {
                appState.setWindowCount(windowIDs.count - 1, for: featureID)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .black))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(BlobbyTheme.ink)
                    .background(BlobbyTheme.paper, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(windowIDs.count <= 1)
            .accessibilityLabel("Remove last \(featureID.windowTitle.lowercased()) window")
            .accessibilityIdentifier("window-count-decrement-\(featureID.rawValue)")

            Text("\(windowIDs.count) / \(AppState.maximumWindowCount)")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .monospacedDigit()
                .frame(minWidth: 48)
                .accessibilityLabel("Window count")
                .accessibilityValue("\(windowIDs.count) of \(AppState.maximumWindowCount)")
                .accessibilityIdentifier("window-count-\(featureID.rawValue)")

            Button {
                appState.setWindowCount(windowIDs.count + 1, for: featureID)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .black))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(BlobbyTheme.ink)
                    .background(BlobbyTheme.paper, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(windowIDs.count >= AppState.maximumWindowCount)
            .accessibilityLabel("Add \(featureID.windowTitle.lowercased()) window")
            .accessibilityIdentifier("window-count-increment-\(featureID.rawValue)")
        }
        .frame(minHeight: 38)
    }
}

private struct FeatureInstanceControlRow: View {
    let featureID: FeatureID
    let instanceID: WindowInstanceID
    let ordinal: Int
    @ObservedObject var appState: AppState
    @State private var isExpanded = false

    private var title: String {
        "\(featureID.windowTitle) \(ordinal)"
    }

    private var configuration: FeatureConfiguration {
        appState.configuration(for: instanceID) ?? .default
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .black))
                        Text(title)
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(0.3)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(BlobbyTheme.baseDeep)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded ? "Hide" : "Show") settings for \(title)")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("instance-expand-\(featureID.rawValue)-\(ordinal)")

                Button {
                    appState.setFeatureEnabled(!configuration.isEnabled, for: instanceID)
                } label: {
                    Text(configuration.isEnabled ? "ON" : "OFF")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .frame(width: 48, height: 32)
                        .foregroundStyle(configuration.isEnabled ? BlobbyTheme.paper : BlobbyTheme.ink)
                        .background(configuration.isEnabled ? BlobbyTheme.base : BlobbyTheme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) visibility")
                .accessibilityValue(configuration.isEnabled ? "On" : "Off")
                .accessibilityIdentifier("instance-enabled-\(featureID.rawValue)-\(ordinal)")
            }

            if isExpanded {
                instanceSettings
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(BlobbyTheme.paper.opacity(0.56), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var instanceSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                appState.setFeatureFrozen(!configuration.isFrozen, for: instanceID)
            } label: {
                Text(configuration.isFrozen ? "UNFREEZE FRAME" : "FREEZE FRAME")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(configuration.isFrozen ? BlobbyTheme.paper : BlobbyTheme.ink)
                    .background(configuration.isFrozen ? BlobbyTheme.accent : .white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(!configuration.isEnabled)
            .accessibilityLabel("\(title) freeze frame")
            .accessibilityValue(configuration.isFrozen ? "On" : "Off")
            .accessibilityIdentifier("instance-freeze-\(featureID.rawValue)-\(ordinal)")

            HStack(spacing: 5) {
                Text("SIZE \(Int(windowSize.width.rounded())) × \(Int(windowSize.height.rounded())) PT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("\(title) window size \(Int(windowSize.width.rounded())) by \(Int(windowSize.height.rounded())) points")

                Spacer(minLength: 0)

                Button {
                    appState.setWindowScale(1, for: instanceID)
                } label: {
                    Text("RESET SIZE")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .frame(minWidth: 64, minHeight: 32)
                        .foregroundStyle(BlobbyTheme.ink)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BlobbyTheme.ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset \(title) window size")
                .accessibilityIdentifier("instance-size-reset-\(featureID.rawValue)-\(ordinal)")
            }
            .frame(minHeight: 32)

            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("WINDOW PLACEMENT")
                HStack(spacing: 9) {
                    compactSlider(
                        title: "X",
                        value: CGFloatBinding(
                            get: { configuration.windowOffsetX },
                            set: { appState.setWindowOffsetX($0, for: instanceID) }
                        ),
                        range: -1_000...1_000,
                        step: 10,
                        valueText: "\(Int(configuration.windowOffsetX)) PT"
                    )
                    compactSlider(
                        title: "Y",
                        value: CGFloatBinding(
                            get: { configuration.windowOffsetY },
                            set: { appState.setWindowOffsetY($0, for: instanceID) }
                        ),
                        range: -1_000...1_000,
                        step: 10,
                        valueText: "\(Int(configuration.windowOffsetY)) PT"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("CROP FRAMING")
                compactSlider(
                    title: "ZOOM",
                    value: CGFloatBinding(
                        get: { configuration.cropZoom },
                        set: { appState.setCropZoom($0, for: instanceID) }
                    ),
                    range: Double(FeatureConfiguration.cropZoomRange.lowerBound)...Double(FeatureConfiguration.cropZoomRange.upperBound),
                    step: 0.25,
                    valueText: String(format: "%.2f×", Double(configuration.cropZoom))
                )

                HStack(spacing: 9) {
                    compactSlider(
                        title: "PAN X",
                        value: CGFloatBinding(
                            get: { configuration.cropOffsetX },
                            set: { appState.setCropOffsetX($0, for: instanceID) }
                        ),
                        range: -1...1,
                        step: 0.05,
                        valueText: String(format: "%+.2f", Double(configuration.cropOffsetX))
                    )
                    compactSlider(
                        title: "PAN Y",
                        value: CGFloatBinding(
                            get: { configuration.cropOffsetY },
                            set: { appState.setCropOffsetY($0, for: instanceID) }
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
                        set: { appState.setCropPadding($0, for: instanceID) }
                    ),
                    range: 0...1,
                    step: 0.05,
                    valueText: "\(Int((configuration.cropPadding * 100).rounded()))%"
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("DETECTION")
                compactSlider(
                    title: isFaceFeature ? "OBSERVATION + GEOMETRY" : "JOINT CONFIDENCE",
                    value: Binding(
                        get: { Double(configuration.detectionThreshold) },
                        set: { appState.setDetectionThreshold(Float($0), for: instanceID) }
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

    private func sectionLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 7, weight: .black, design: .rounded))
            .tracking(0.75)
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
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(valueText)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Slider(value: value, in: range, step: step)
                .tint(BlobbyTheme.base)
                .frame(height: 36)
                .accessibilityLabel("\(self.title) \(title)")
                .accessibilityIdentifier("instance-slider-\(featureID.rawValue)-\(instanceID.serial)-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        }
        .frame(maxWidth: .infinity, minHeight: 36)
    }
}

private func CGFloatBinding(get: @escaping () -> CGFloat, set: @escaping (CGFloat) -> Void) -> Binding<Double> {
    Binding(
        get: { Double(get()) },
        set: { set(CGFloat($0)) }
    )
}
