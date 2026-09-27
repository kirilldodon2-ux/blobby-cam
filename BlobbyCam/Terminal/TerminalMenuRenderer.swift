import Foundation

struct TerminalMenuRenderer {
    static let defaultColumns = 80
    static let defaultRows = 24

    private static let pinkStart = "\u{001B}[38;2;255;112;184m"
    private static let colorReset = "\u{001B}[0m"
    private static let rainbowColors = [
        "\u{001B}[38;2;255;92;146m",
        "\u{001B}[38;2;255;153;91m",
        "\u{001B}[38;2;255;218;94m",
        "\u{001B}[38;2;119;221;119m",
        "\u{001B}[38;2;100;190;255m",
        "\u{001B}[38;2;178;130;255m",
        "\u{001B}[38;2;255;112;208m"
    ]

    private struct Screen {
        var lines: [String]
        var selectedLine: Int
    }

    func renderLoading(cameraStatus: String, width: Int, height: Int) -> String {
        let contentWidth = max(1, min(64, width) - 2)
        let status = cameraStatus == "IDLE" ? "STARTING" : cameraStatus
        let caption: String
        switch status {
        case "LIVE": caption = "camera ready"
        case "DENIED": caption = "camera access denied"
        case "ERROR": caption = "camera error"
        default: caption = "connecting camera..."
        }
        let art = [
            #"     _           _"#,
            #"  __| | ___   __| | ___  _ __    ___  _ __   ___"#,
            #" / _` |/ _ \ / _` |/ _ \| '_ \  / _ \| '_ \ / _ \"#,
            #"| (_| | (_) | (_| | (_) | | | || (_) | | | |  __/"#,
            #" \__,_|\___/ \__,_|\___/|_| |_(_)___/|_| |_|\___|"#,
            "",
            "      ヽ(◕‿◕)ノ",
            #"                    __/ o\_____.,>  hello from dodon.one!"#,
            #"                    \____________.-'"#,
            "                    ~~~~~~~~~~~~~~~~~~~"
        ]
        var lines = ["┌" + String(repeating: "─", count: contentWidth) + "┐"]
        lines.append(box(centered("B L O B B Y   C A M", width: contentWidth), width: contentWidth))
        lines.append(section("LOADING", width: contentWidth))
        lines.append(box("", width: contentWidth))
        lines.append(contentsOf: art.map { box(centered($0, width: contentWidth), width: contentWidth) })
        lines.append(box("", width: contentWidth))
        lines.append(box(centered("CAMERA: \(status)", width: contentWidth), width: contentWidth))
        lines.append(box(centered(caption, width: contentWidth), width: contentWidth))
        lines.append("└" + String(repeating: "─", count: contentWidth) + "┘")
        return Array(lines.prefix(max(0, height))).joined(separator: "\n")
    }

    func render(
        model: TerminalMenuModel,
        snapshot: TerminalMenuSnapshot,
        width: Int = Self.defaultColumns,
        height: Int = Self.defaultRows
    ) -> String {
        let columns = max(3, width)
        let rows = max(0, height)
        guard rows > 0 else { return "" }
        let contentWidth = columns - 2
        let border = "┌" + String(repeating: "─", count: contentWidth) + "┐"

        let screen: Screen
        if let featureID = model.selectedFeature {
            if model.isEditingWindowSettings, let windowID = model.selectedWindowInstanceID {
                screen = featureLines(
                    featureID: featureID,
                    windowID: windowID,
                    model: model,
                    snapshot: snapshot,
                    border: border,
                    contentWidth: contentWidth,
                    height: rows
                )
            } else {
                screen = windowListLines(
                    featureID: featureID,
                    model: model,
                    snapshot: snapshot,
                    border: border,
                    contentWidth: contentWidth,
                    height: rows
                )
            }
        } else {
            screen = homeLines(model: model, snapshot: snapshot, border: border, contentWidth: contentWidth, height: rows)
        }
        return fit(screen, rows: rows).joined(separator: "\n")
    }

    private func homeLines(
        model: TerminalMenuModel,
        snapshot: TerminalMenuSnapshot,
        border: String,
        contentWidth: Int,
        height: Int
    ) -> Screen {
        var lines = [
            border,
            box(centered("D O D O N . O N E   —   B L O B B Y   C A M", width: contentWidth), width: contentWidth),
            box(" MAIN MENU  |  CAMERA: \(snapshot.cameraStatus)", width: contentWidth),
            section("GLOBAL", width: contentWidth)
        ]

        lines.append(menuRow(0, "LIVE", snapshot.isLive ? "ON" : "OFF", active: snapshot.isLive, model: model, width: contentWidth, rainbow: snapshot.isLive))
        lines.append(menuRow(1, snapshot.showAll ? "HIDE ALL" : "SHOW ALL", snapshot.showAll ? "ON" : "OFF", active: snapshot.showAll, model: model, width: contentWidth))
        lines.append(menuRow(2, "AUTO FOLLOW", snapshot.follow ? "ON" : "OFF", active: snapshot.follow, model: model, width: contentWidth))
        lines.append(menuRow(3, "MIRROR", snapshot.mirror ? "ON" : "OFF", active: snapshot.mirror, model: model, width: contentWidth))
        lines.append(menuRow(4, "SMOOTHING", decimal(snapshot.smoothing), active: false, model: model, width: contentWidth))
        lines.append(menuRow(5, "AUTO CROP SCALE", snapshot.autoCropScale ? "ON" : "OFF", active: snapshot.autoCropScale, model: model, width: contentWidth))
        lines.append(menuRow(6, "RESET ALL", "ENTER", active: false, model: model, width: contentWidth))
        lines.append(section("FEATURE WINDOWS", width: contentWidth))

        for (offset, featureID) in FeatureID.allCases.enumerated() {
            let windows = snapshot.windowIDs(for: featureID).compactMap(snapshot.window(for:))
            let count = windows.count
            let enabledCount = windows.filter(\.isEnabled).count
            let status = enabledCount == 0 ? "OFF" : (enabledCount == count ? "ON" : "MIXED")
            let value = count == 0 ? "NO DATA" : "\(status)  ·  \(count)"
            lines.append(menuRow(
                7 + offset,
                featureID.windowTitle,
                value,
                active: enabledCount > 0,
                model: model,
                width: contentWidth
            ))
        }

        lines.append(menuRow(
            13,
            snapshot.goofyUIVisible ? "HIDE GOOFY UI" : "SHOW GOOFY UI",
            snapshot.goofyUIVisible ? "ON" : "OFF",
            active: snapshot.goofyUIVisible,
            model: model,
            width: contentWidth
        ))
        lines.append(menuRow(14, "QUIT", "ENTER", active: false, model: model, width: contentWidth))
        let help = contentWidth < 44
            ? " ↑/↓ MOVE  ←/→ CHANGE  ENTER: WINDOWS"
            : " ↑/↓ SELECT  ←/→ CHANGE  ENTER: WINDOWS"
        lines.append(box(help, width: contentWidth))
        lines.append(rainbowLink(width: contentWidth))
        lines.append("└" + String(repeating: "─", count: contentWidth) + "┘")
        addFiller(to: &lines, targetHeight: height, contentWidth: contentWidth, footerCount: 3)
        return Screen(lines: lines, selectedLine: homeSelectedLine(model.selectedHomeIndex))
    }

    private func windowListLines(
        featureID: FeatureID,
        model: TerminalMenuModel,
        snapshot: TerminalMenuSnapshot,
        border: String,
        contentWidth: Int,
        height: Int
    ) -> Screen {
        let ids = snapshot.windowIDs(for: featureID)
        var lines = [
            border,
            box(centered("D O D O N . O N E   —   B L O B B Y   C A M", width: contentWidth), width: contentWidth),
            box(centered("WINDOWS / \(featureID.windowTitle)", width: contentWidth), width: contentWidth),
            box(" CAMERA: \(snapshot.cameraStatus)", width: contentWidth),
            section("WINDOWS", width: contentWidth)
        ]
        let count = ids.count
        let maximum = snapshot.maximumWindowCount
        lines.append(rowBox(
            label: "WINDOWS",
            value: "\(count) / \(maximum)",
            selected: model.selectedWindowInstanceID == nil,
            active: false,
            width: contentWidth
        ))

        for (index, id) in ids.enumerated() {
            let title = featureID.windowTitle(ordinal: index + 1)
            let instance = snapshot.window(for: id)
            let value = instance.map { $0.isFrozen ? "FROZEN" : ($0.isEnabled ? "ON" : "OFF") } ?? "NO DATA"
            lines.append(rowBox(
                label: title,
                value: value,
                selected: model.selectedWindowInstanceID == id,
                active: instance?.isEnabled == true,
                width: contentWidth
            ))
        }

        lines.append(box(" ↑/↓ SELECT  ←/→ WINDOWS  ENTER: SETTINGS  ESC: BACK", width: contentWidth))
        lines.append(rainbowLink(width: contentWidth))
        lines.append("└" + String(repeating: "─", count: contentWidth) + "┘")
        addFiller(to: &lines, targetHeight: height, contentWidth: contentWidth, footerCount: 3)
        let selectedLine = model.selectedWindowInstanceID.flatMap(ids.firstIndex(of:)).map { $0 + 6 } ?? 5
        return Screen(lines: lines, selectedLine: selectedLine)
    }

    private func featureLines(
        featureID: FeatureID,
        windowID: WindowInstanceID,
        model: TerminalMenuModel,
        snapshot: TerminalMenuSnapshot,
        border: String,
        contentWidth: Int,
        height: Int
    ) -> Screen {
        let feature = snapshot.window(for: windowID)
        let ids = snapshot.windowIDs(for: featureID)
        let ordinal = (ids.firstIndex(of: windowID) ?? model.selectedWindowIndex) + 1
        var lines = [
            border,
            box(centered("D O D O N . O N E   —   B L O B B Y   C A M", width: contentWidth), width: contentWidth),
            box(centered("FEATURE / \(featureID.windowTitle(ordinal: ordinal))", width: contentWidth), width: contentWidth),
            box(" CAMERA: \(snapshot.cameraStatus)", width: contentWidth),
            section("SETTINGS", width: contentWidth)
        ]

        for field in TerminalFeatureField.allCases {
            lines.append(featureRow(
                field: field,
                featureID: featureID,
                windowID: windowID,
                feature: feature,
                model: model,
                width: contentWidth
            ))
        }

        lines.append(box(" ↑/↓ SELECT  ←/→ ADJUST  ENTER ACTIVATE  ESC: BACK", width: contentWidth))
        lines.append(rainbowLink(width: contentWidth))
        lines.append("└" + String(repeating: "─", count: contentWidth) + "┘")
        addFiller(to: &lines, targetHeight: height, contentWidth: contentWidth, footerCount: 3)
        return Screen(lines: lines, selectedLine: 5 + (model.selectedFeatureFieldIndex ?? 0))
    }

    private func menuRow(
        _ index: Int,
        _ label: String,
        _ value: String,
        active: Bool,
        model: TerminalMenuModel,
        width: Int,
        rainbow: Bool = false
    ) -> String {
        let selected = model.selectedFeature == nil && model.selectedHomeIndex == index
        return rowBox(label: label, value: value, selected: selected, active: active, width: width, rainbow: rainbow)
    }

    private func featureRow(
        field: TerminalFeatureField,
        featureID: FeatureID,
        windowID: WindowInstanceID,
        feature: TerminalFeatureSnapshot?,
        model: TerminalMenuModel,
        width: Int
    ) -> String {
        let value: String
        switch field {
        case .enabled:
            value = feature.map { $0.isEnabled ? "ON" : "OFF" } ?? "NO DATA"
        case .freeze:
            value = feature.map { $0.isFrozen ? "ON" : "OFF" } ?? "NO DATA"
        case .sizeReset:
            if let size = feature?.windowSize {
                value = "\(integer(size.width))x\(integer(size.height)) PT / ENTER=RESET"
            } else {
                value = "SIZE UNAVAILABLE"
            }
        case .windowX:
            value = feature.map { "\(signedInteger($0.windowOffsetX)) PT" } ?? "--"
        case .windowY:
            value = feature.map { "\(signedInteger($0.windowOffsetY)) PT" } ?? "--"
        case .cropZoom:
            value = feature.map { "\(decimal($0.cropZoom))X" } ?? "--"
        case .panX:
            value = feature.map { signedDecimal($0.cropOffsetX) } ?? "--"
        case .panY:
            value = feature.map { signedDecimal($0.cropOffsetY) } ?? "--"
        case .padding:
            value = feature.map { "\(integer($0.cropPadding * 100))%" } ?? "--"
        case .detection:
            value = feature.map { decimal(CGFloat($0.detectionThreshold)) } ?? "--"
        }

        let selected = model.selectedFeature == featureID
            && model.selectedWindowInstanceID == windowID
            && model.selectedFeatureField == field
        let active = (field == .enabled && feature?.isEnabled == true)
            || (field == .freeze && feature?.isFrozen == true)
        return rowBox(label: fieldLabel(field), value: value, selected: selected, active: active, width: width)
    }

    private func fieldLabel(_ field: TerminalFeatureField) -> String {
        switch field {
        case .enabled: "ENABLED"
        case .freeze: "FREEZE FRAME"
        case .sizeReset: "WINDOW SIZE"
        case .windowX: "WINDOW X"
        case .windowY: "WINDOW Y"
        case .cropZoom: "CROP ZOOM"
        case .panX: "PAN X"
        case .panY: "PAN Y"
        case .padding: "CROP PADDING"
        case .detection: "DETECTION"
        }
    }

    private func homeSelectedLine(_ index: Int) -> Int {
        index < 7 ? 4 + index : 5 + index
    }

    private func addFiller(to lines: inout [String], targetHeight: Int, contentWidth: Int, footerCount: Int) {
        let fillerCount = max(0, targetHeight - lines.count)
        guard fillerCount > 0 else { return }
        let insertion = max(0, lines.count - footerCount)
        lines.insert(contentsOf: repeatElement(box("", width: contentWidth), count: fillerCount), at: insertion)
    }

    private func fit(_ screen: Screen, rows: Int) -> [String] {
        let lines = screen.lines
        guard lines.count > rows else { return lines }
        guard rows >= 7 else { return Array(lines.prefix(rows)) }

        let headerCount = 3
        let footerCount = 3
        let bodyStart = headerCount
        let bodyEnd = lines.count - footerCount
        let bodyCapacity = max(1, rows - headerCount - footerCount)
        let maximumStart = max(bodyStart, bodyEnd - bodyCapacity)
        let desiredStart = screen.selectedLine - bodyCapacity / 2
        let start = min(max(bodyStart, desiredStart), maximumStart)
        let end = min(bodyEnd, start + bodyCapacity)
        let body = Array(lines[start..<end])
        let result = Array(lines.prefix(headerCount)) + body + Array(lines.suffix(footerCount))
        return Array(result.prefix(rows))
    }

    private func section(_ title: String, width: Int) -> String {
        let label = title.isEmpty ? "" : "── \(title) "
        let suffixCount = max(0, width - label.count)
        return box(label + String(repeating: "─", count: suffixCount), width: width)
    }

    private func box(_ text: String, width: Int) -> String {
        let clipped = String(text.prefix(max(0, width)))
        return "│" + clipped + String(repeating: " ", count: max(0, width - clipped.count)) + "│"
    }

    private func rowBox(label: String, value: String, selected: Bool, active: Bool, width: Int, rainbow: Bool = false) -> String {
        let prefix = selected ? "> " : "  "
        let bodyWidth = max(0, width - prefix.count)
        let clippedLabel = String(label.prefix(bodyWidth))
        let clippedValue = String(value.prefix(bodyWidth))
        let gapCount = max(2, bodyWidth - clippedLabel.count - clippedValue.count)
        var visible = prefix + clippedLabel + String(repeating: " ", count: gapCount) + clippedValue
        if visible.count > width {
            visible = String(visible.prefix(width))
        } else if visible.count < width {
            visible += String(repeating: " ", count: width - visible.count)
        }

        let styled: String
        if rainbow {
            let marker = String(visible.prefix(prefix.count))
            let content = String(visible.dropFirst(prefix.count))
            styled = (selected ? "\(Self.pinkStart)\(marker)\(Self.colorReset)" : marker) + rainbowStyled(content)
        } else if selected {
            styled = "\(Self.pinkStart)\(visible)\(Self.colorReset)"
        } else if active {
            let unstyledPrefix = String(visible.prefix(prefix.count))
            let activeContent = String(visible.dropFirst(prefix.count))
            styled = "\(unstyledPrefix)\(Self.pinkStart)\(activeContent)\(Self.colorReset)"
        } else {
            styled = visible
        }
        return "│\(styled)│"
    }

    private func rainbowLink(width: Int) -> String {
        let link = "dodon.one"
        let leftPadding = max(0, (width - link.count) / 2)
        let rightPadding = max(0, width - leftPadding - link.count)
        let coloredLink = rainbowStyled(link)
        return "│" + String(repeating: " ", count: leftPadding) + coloredLink + String(repeating: " ", count: rightPadding) + "│"
    }

    private func rainbowStyled(_ text: String) -> String {
        text.enumerated().map { index, character in
            "\(Self.rainbowColors[index % Self.rainbowColors.count])\(character)\(Self.colorReset)"
        }.joined()
    }

    private func centered(_ text: String, width: Int) -> String {
        let clipped = String(text.prefix(max(0, width)))
        let left = max(0, (width - clipped.count) / 2)
        return String(repeating: " ", count: left) + clipped
    }

    private func decimal(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    private func signedDecimal(_ value: CGFloat) -> String {
        String(format: "%+.2f", Double(value))
    }

    private func integer(_ value: CGFloat) -> String {
        String(Int(value.rounded()))
    }

    private func signedInteger(_ value: CGFloat) -> String {
        String(format: "%+.0f", Double(value))
    }
}
