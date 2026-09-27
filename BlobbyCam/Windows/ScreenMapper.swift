import AppKit
import ImageIO

struct ScreenGeometry: Equatable {
    let displayIdentifier: String
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScaleFactor: CGFloat
    let isPrimary: Bool
}

struct PanelPlacement: Equatable {
    /// AppKit screen coordinates are measured in points, including on Retina displays.
    let frame: CGRect
    let displayIdentifier: String
    let backingScaleFactor: CGFloat
}

/// Defines one mirror decision for both sampled pixels and their screen-space locations.
/// Feature IDs remain anatomical labels; only their displayed rectangles are reflected.
enum MirrorPolicy {
    static let selfieOrientationByDefault = true

    static func requiresAdditionalMirror(sourceIsMirrored: Bool, selfieOrientation: Bool) -> Bool {
        sourceIsMirrored != selfieOrientation
    }

    static func displayedRect(
        _ rect: CGRect,
        sourceIsMirrored: Bool,
        selfieOrientation: Bool
    ) -> CGRect {
        guard requiresAdditionalMirror(
            sourceIsMirrored: sourceIsMirrored,
            selfieOrientation: selfieOrientation
        ) else { return rect }
        return CGRect(x: 1 - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

enum ScreenMapper {
    private static let normalizedBounds = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Resolves close feature targets into stable, visible frames that do not overlap. Isolated
    /// features are placed first; nearby face regions then use the closest free position around
    /// their target. Candidate ordering uses only feature identity and geometry, so equal inputs
    /// always produce the same slightly irregular spacing.
    static func collisionFreePanelFrames(
        preferredFrames: [FeatureID: CGRect],
        inside visibleFrame: CGRect,
        avoiding reservedFrames: [CGRect] = [],
        minimumGap: CGFloat = 14
    ) -> [FeatureID: CGRect] {
        guard isValid(visibleFrame), !preferredFrames.isEmpty else { return [:] }
        let ids = FeatureID.allCases.filter { preferredFrames[$0] != nil }
        let boundedFrames = Dictionary(uniqueKeysWithValues: ids.compactMap { id -> (FeatureID, CGRect)? in
            guard let preferred = preferredFrames[id],
                  let bounded = clampedPanelFrame(origin: preferred.origin, size: preferred.size, on: ScreenGeometry(
                    displayIdentifier: "layout",
                    frame: visibleFrame,
                    visibleFrame: visibleFrame,
                    backingScaleFactor: 1,
                    isPrimary: true
                  ))
            else { return nil }
            return (id, bounded)
        })
        guard !boundedFrames.isEmpty else { return [:] }

        let priority = boundedFrames.keys.sorted { lhs, rhs in
            let leftDistance = nearestTargetDistance(for: lhs, among: boundedFrames)
            let rightDistance = nearestTargetDistance(for: rhs, among: boundedFrames)
            if abs(leftDistance - rightDistance) > 0.001 { return leftDistance > rightDistance }
            return featureOrder(lhs) < featureOrder(rhs)
        }
        let usableReserved = reservedFrames.filter(isValid)
        var result: [FeatureID: CGRect] = [:]

        for id in priority {
            guard let anchor = boundedFrames[id] else { continue }
            let alreadyPlaced = Array(result.values) + usableReserved
            let candidates = panelCandidates(around: anchor, inside: visibleFrame, gap: minimumGap, feature: id)
            let chosen = candidates.first { candidate in
                alreadyPlaced.allSatisfy { separated(candidate, from: $0, by: minimumGap) }
            } ?? candidates.first { candidate in
                alreadyPlaced.allSatisfy { separated(candidate, from: $0, by: 0) }
            }
            if let chosen { result[id] = chosen }
        }

        return result
    }

    /// Vision receives the camera orientation and returns detections in oriented normalized
    /// coordinates. Convert those rectangles back to the raw pixel-buffer orientation for crop
    /// sampling. The pixel buffer's own mirror state is already reflected in those coordinates.
    static func sourcePixelRect(
        fromOrientedNormalizedRect rect: CGRect,
        sourcePixelSize: CGSize,
        orientation: CGImagePropertyOrientation
    ) -> CGRect? {
        guard isValid(rect),
              sourcePixelSize.width.isFinite, sourcePixelSize.height.isFinite,
              sourcePixelSize.width > 0, sourcePixelSize.height > 0
        else { return nil }

        let clipped = rect.intersection(normalizedBounds)
        guard isValid(clipped) else { return nil }

        let orientedCorners = [
            CGPoint(x: clipped.minX, y: clipped.minY),
            CGPoint(x: clipped.maxX, y: clipped.minY),
            CGPoint(x: clipped.minX, y: clipped.maxY),
            CGPoint(x: clipped.maxX, y: clipped.maxY)
        ]
        let sourceCorners = orientedCorners.map { sourceNormalizedPoint(fromOrientedPoint: $0, orientation: orientation) }
        guard sourceCorners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }

        let minX = sourceCorners.map(\.x).min()! * sourcePixelSize.width
        let maxX = sourceCorners.map(\.x).max()! * sourcePixelSize.width
        let minY = sourceCorners.map(\.y).min()! * sourcePixelSize.height
        let maxY = sourceCorners.map(\.y).max()! * sourcePixelSize.height
        let pixelRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard isValid(pixelRect),
              pixelRect.minX >= 0, pixelRect.minY >= 0,
              pixelRect.maxX <= sourcePixelSize.width,
              pixelRect.maxY <= sourcePixelSize.height
        else { return nil }
        return pixelRect
    }

    /// Mirror exactly once relative to the pixels delivered by the capture output.
    static func requiresAdditionalMirror(sourceIsMirrored: Bool, requestedMirror: Bool) -> Bool {
        MirrorPolicy.requiresAdditionalMirror(
            sourceIsMirrored: sourceIsMirrored,
            selfieOrientation: requestedMirror
        )
    }

    /// Maps an oriented-image detection to a panel frame on an explicitly selected display.
    /// The caller selects the display containing the menu window; if unavailable, use the primary
    /// display. Panel positions are in AppKit points, and the backing scale is returned separately
    /// for renderer sizing. Oversized panels are reduced to the display's visible frame.
    static func panelPlacement(
        for detectionRect: CGRect,
        panelSize: CGSize,
        on screen: ScreenGeometry,
        sourceIsMirrored: Bool,
        requestedMirror: Bool
    ) -> PanelPlacement? {
        guard isValid(detectionRect),
              panelSize.width.isFinite, panelSize.height.isFinite,
              panelSize.width > 0, panelSize.height > 0,
              isValid(screen.frame), isValid(screen.visibleFrame),
              screen.backingScaleFactor.isFinite, screen.backingScaleFactor > 0
        else { return nil }

        let normalizedRect = detectionRect.intersection(normalizedBounds)
        guard isValid(normalizedRect) else { return nil }

        let displayedRect = MirrorPolicy.displayedRect(
            normalizedRect,
            sourceIsMirrored: sourceIsMirrored,
            selfieOrientation: requestedMirror
        )
        let normalizedCenter = CGPoint(x: displayedRect.midX, y: displayedRect.midY)
        let targetCenter = CGPoint(
            x: screen.visibleFrame.minX + normalizedCenter.x * screen.visibleFrame.width,
            y: screen.visibleFrame.minY + normalizedCenter.y * screen.visibleFrame.height
        )

        let width = min(panelSize.width, screen.visibleFrame.width)
        let height = min(panelSize.height, screen.visibleFrame.height)
        guard let frame = clampedPanelFrame(
            origin: CGPoint(x: targetCenter.x - width / 2, y: targetCenter.y - height / 2),
            size: CGSize(width: width, height: height),
            on: screen
        ) else { return nil }

        return PanelPlacement(
            frame: frame,
            displayIdentifier: screen.displayIdentifier,
            backingScaleFactor: screen.backingScaleFactor
        )
    }

    /// Keeps a previously chosen panel origin visible while preserving as much of it as possible.
    static func clampedPanelFrame(origin: CGPoint, size: CGSize, on screen: ScreenGeometry) -> CGRect? {
        guard origin.x.isFinite, origin.y.isFinite,
              size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              isValid(screen.visibleFrame)
        else { return nil }

        let width = min(size.width, screen.visibleFrame.width)
        let height = min(size.height, screen.visibleFrame.height)
        let minX = clamp(origin.x, lower: screen.visibleFrame.minX, upper: screen.visibleFrame.maxX - width)
        let minY = clamp(origin.y, lower: screen.visibleFrame.minY, upper: screen.visibleFrame.maxY - height)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Prefer the display under the menu window's center, then the primary display, then the
    /// first available screen. Callers pass the menu frame so display choice stays centralized.
    static func selectedScreen(
        from screens: [ScreenGeometry],
        menuWindowFrame: CGRect?
    ) -> ScreenGeometry? {
        guard !screens.isEmpty else { return nil }
        if let menuWindowFrame,
           isValid(menuWindowFrame),
           let menuScreen = screens.first(where: { $0.frame.contains(CGPoint(x: menuWindowFrame.midX, y: menuWindowFrame.midY)) }) {
            return menuScreen
        }
        return screens.first(where: \.isPrimary) ?? screens.first
    }

    private static func sourceNormalizedPoint(
        fromOrientedPoint point: CGPoint,
        orientation: CGImagePropertyOrientation
    ) -> CGPoint {
        // These are inverse EXIF transforms in normalized bottom-left coordinates.
        switch orientation {
        case .up:
            return point
        case .upMirrored:
            return CGPoint(x: 1 - point.x, y: point.y)
        case .down:
            return CGPoint(x: 1 - point.x, y: 1 - point.y)
        case .downMirrored:
            return CGPoint(x: point.x, y: 1 - point.y)
        case .left:
            return CGPoint(x: point.y, y: 1 - point.x)
        case .leftMirrored:
            return CGPoint(x: 1 - point.y, y: 1 - point.x)
        case .right:
            return CGPoint(x: 1 - point.y, y: point.x)
        case .rightMirrored:
            return CGPoint(x: point.y, y: point.x)
        @unknown default:
            return point
        }
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite &&
        rect.width.isFinite && rect.height.isFinite &&
        rect.width > 0 && rect.height > 0
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private static func nearestTargetDistance(for id: FeatureID, among frames: [FeatureID: CGRect]) -> CGFloat {
        guard let frame = frames[id] else { return 0 }
        return frames.reduce(CGFloat.greatestFiniteMagnitude) { distance, entry in
            guard entry.key != id else { return distance }
            let dx = frame.midX - entry.value.midX
            let dy = frame.midY - entry.value.midY
            return min(distance, hypot(dx, dy))
        }
    }

    private static func panelCandidates(
        around anchor: CGRect,
        inside bounds: CGRect,
        gap: CGFloat,
        feature: FeatureID
    ) -> [CGRect] {
        struct OriginKey: Hashable {
            let x: Int
            let y: Int
        }

        let order = featureOrder(feature)
        let phase = Double(order) * 0.19
        let step = max(10, min(anchor.width, anchor.height) * 0.055)
        let maximumRadius = max(anchor.width, anchor.height) * 1.75 + gap
        let directions = 20
        var seen = Set<OriginKey>()
        var candidates: [CGRect] = []

        func append(_ origin: CGPoint) {
            let bounded = CGRect(
                x: clamp(origin.x, lower: bounds.minX, upper: bounds.maxX - anchor.width),
                y: clamp(origin.y, lower: bounds.minY, upper: bounds.maxY - anchor.height),
                width: anchor.width,
                height: anchor.height
            )
            let key = OriginKey(x: Int((bounded.minX * 2).rounded()), y: Int((bounded.minY * 2).rounded()))
            guard seen.insert(key).inserted else { return }
            candidates.append(bounded)
        }

        append(anchor.origin)
        let rings = Int(ceil(maximumRadius / step))
        if rings > 0 {
            for ring in 1...rings {
                let radius = CGFloat(ring) * step
                for direction in 0..<directions {
                    let angle = (Double(direction) * 2 * .pi / Double(directions)) + phase
                    append(CGPoint(
                        x: anchor.minX + cos(angle) * radius,
                        y: anchor.minY + sin(angle) * radius
                    ))
                }
            }
        }

        // A coarse full-display scan guarantees useful fallback positions when all local spots
        // around clustered face features are occupied. Cell steps leave the requested gap.
        let xStep = max(anchor.width + gap, step)
        let yStep = max(anchor.height + gap, step)
        var y = bounds.minY
        while y <= bounds.maxY - anchor.height + 0.5 {
            var x = bounds.minX
            while x <= bounds.maxX - anchor.width + 0.5 {
                append(CGPoint(x: x, y: y))
                x += xStep
            }
            append(CGPoint(x: bounds.maxX - anchor.width, y: y))
            y += yStep
        }
        append(CGPoint(x: bounds.minX, y: bounds.maxY - anchor.height))
        append(CGPoint(x: bounds.maxX - anchor.width, y: bounds.maxY - anchor.height))

        let indexed = candidates.enumerated().map { index, frame in
            let dx = frame.minX - anchor.minX
            let dy = frame.minY - anchor.minY
            return (index, frame, dx * dx + dy * dy)
        }
        return indexed.sorted { lhs, rhs in
            if abs(lhs.2 - rhs.2) > 0.001 { return lhs.2 < rhs.2 }
            return lhs.0 < rhs.0
        }.map(\.1)
    }

    private static func separated(_ lhs: CGRect, from rhs: CGRect, by gap: CGFloat) -> Bool {
        lhs.insetBy(dx: -gap / 2, dy: -gap / 2)
            .intersects(rhs.insetBy(dx: -gap / 2, dy: -gap / 2)) == false
    }

    private static func featureOrder(_ id: FeatureID) -> Int {
        FeatureID.allCases.firstIndex(of: id) ?? 0
    }
}
