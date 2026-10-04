import AppKit
import CoreMedia

@MainActor
final class FeatureWindowManager {
    static let defaultPanelSize = NSSize(width: 240, height: 180)

    /// The six original panels stay alive for the manager's full lifetime. Extra panels move
    /// between the active map and a bounded per-feature reuse pool as AppState changes IDs.
    private(set) var panels: [FeatureID: FeaturePanel]
    private(set) var panelsByWindowID: [WindowInstanceID: FeaturePanel]
    private(set) var reusablePanelsByFeature: [FeatureID: [FeaturePanel]] = [:]

    private var renderer: SharedRenderer?
    private var smoother = TrackingSmoother()
    private var lastAppliedTimestamp: CMTime?
    private var positionedWindowIDs = Set<WindowInstanceID>()
    private var configuredSizes: [WindowInstanceID: NSSize] = [:]
    private var lastWindowOffsets: [WindowInstanceID: CGPoint] = [:]
    private var followLayoutOffsets: [WindowInstanceID: CGPoint] = [:]

    var onUserResize: ((WindowInstanceID, NSSize) -> Void)?
    var onUserClose: ((WindowInstanceID) -> Void)?

    init(initialFrame: NSRect? = nil) {
        let frame = initialFrame ?? NSRect(origin: .zero, size: Self.defaultPanelSize)
        let originals = Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { featureID in
            (featureID, FeaturePanel(featureID: featureID, frame: frame))
        })
        panels = originals
        panelsByWindowID = Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { featureID in
            let id = WindowInstanceID(featureID: featureID, serial: 1)
            return (id, originals[featureID]!)
        })
        for panel in originals.values { configureCallbacks(on: panel) }
    }

    func panel(for featureID: FeatureID) -> FeaturePanel {
        // These are the six original persistent native panels.
        panels[featureID]!
    }

    func panel(for windowID: WindowInstanceID) -> FeaturePanel {
        panelsByWindowID[windowID]!
    }

    /// Reconciles only explicit AppState identity changes. Camera frames never create or destroy
    /// panels, and surviving IDs retain their exact native NSPanel objects and positions.
    func reconcileWindowIDs(_ windowIDsByFeature: [FeatureID: [WindowInstanceID]]) {
        let boundedIDsByFeature = Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { featureID in
            (featureID, Array((windowIDsByFeature[featureID] ?? []).prefix(AppState.maximumWindowCount)))
        })
        let desiredIDs = Set(FeatureID.allCases.flatMap { boundedIDsByFeature[$0] ?? [] })
        let removedIDs = Set(panelsByWindowID.keys).subtracting(desiredIDs)
        for id in removedIDs {
            let retiredPanel = panelsByWindowID.removeValue(forKey: id)
            retiredPanel?.orderOut(nil)
            if id.serial != 1 {
                retiredPanel?.onUserClose = nil
                retiredPanel?.onUserResize = nil
                retiredPanel?.delegate = nil
                if let retiredPanel {
                    var reusablePanels = reusablePanelsByFeature[id.featureID, default: []]
                    if reusablePanels.count < Self.reusablePanelCapacity {
                        reusablePanels.append(retiredPanel)
                        reusablePanelsByFeature[id.featureID] = reusablePanels
                    }
                }
            }
            configuredSizes.removeValue(forKey: id)
            lastWindowOffsets.removeValue(forKey: id)
            followLayoutOffsets.removeValue(forKey: id)
            positionedWindowIDs.remove(id)
        }

        for featureID in FeatureID.allCases {
            let ids = boundedIDsByFeature[featureID] ?? []
            for (index, id) in ids.enumerated() where panelsByWindowID[id] == nil {
                let panel: FeaturePanel
                if id.serial == 1 {
                    panel = self.panels[featureID]!
                } else {
                    let anchor = panelsByWindowID[ids.first ?? id] ?? self.panels[featureID]!
                    let stagger = CGFloat(index) * 24
                    let seedFrame = anchor.frame.offsetBy(dx: stagger, dy: stagger)
                    var reusablePanels = reusablePanelsByFeature[featureID, default: []]
                    if let reusablePanel = reusablePanels.popLast() {
                        reusablePanel.prepareForReuse(as: id)
                        reusablePanel.setFrame(seedFrame, display: false)
                        panel = reusablePanel
                        reusablePanelsByFeature[featureID] = reusablePanels
                    } else {
                        panel = FeaturePanel(windowID: id, frame: seedFrame)
                    }
                }
                panelsByWindowID[id] = panel
                configureCallbacks(on: panel)
                if let renderer {
                    panel.installRenderView(renderer.makeRenderView(for: id))
                }
            }

            for (index, id) in ids.enumerated() {
                guard let panel = panelsByWindowID[id] else { continue }
                panel.title = ids.count == 1
                    ? featureID.windowTitle
                    : "\(featureID.windowTitle) \(index + 1)"
            }
        }
    }

    func show(_ featureID: FeatureID) {
        show(WindowInstanceID(featureID: featureID, serial: 1))
    }

    func show(_ windowID: WindowInstanceID) {
        guard let featurePanel = panelsByWindowID[windowID], !featurePanel.isVisible else { return }
        featurePanel.orderFrontRegardless()
    }

    func hide(_ featureID: FeatureID) {
        hide(WindowInstanceID(featureID: featureID, serial: 1))
    }

    func hide(_ windowID: WindowInstanceID) {
        panelsByWindowID[windowID]?.orderOut(nil)
    }

    func move(_ featureID: FeatureID, to origin: NSPoint) {
        move(WindowInstanceID(featureID: featureID, serial: 1), to: origin)
    }

    func move(_ windowID: WindowInstanceID, to origin: NSPoint) {
        panelsByWindowID[windowID]?.setFrameOrigin(origin)
    }

    func resize(_ featureID: FeatureID, to size: NSSize) {
        resize(WindowInstanceID(featureID: featureID, serial: 1), to: size)
    }

    func resize(_ windowID: WindowInstanceID, to size: NSSize) {
        guard let featurePanel = panelsByWindowID[windowID] else { return }
        let origin = featurePanel.frame.origin
        featurePanel.setContentSize(size)
        // AppKit preserves the top edge when the content height changes. Keep size changes
        // independent from window placement by restoring the existing lower-left origin.
        featurePanel.setFrameOrigin(origin)
    }

    func setFrame(_ frame: NSRect, for featureID: FeatureID) {
        setFrame(frame, for: WindowInstanceID(featureID: featureID, serial: 1))
    }

    func setFrame(_ frame: NSRect, for windowID: WindowInstanceID) {
        guard let featurePanel = panelsByWindowID[windowID], featurePanel.frame != frame else { return }
        featurePanel.setFrame(frame, display: true)
    }

    func installRenderView(_ view: NSView, for featureID: FeatureID) {
        installRenderView(view, for: WindowInstanceID(featureID: featureID, serial: 1))
    }

    func installRenderView(_ view: NSView, for windowID: WindowInstanceID) {
        panelsByWindowID[windowID]?.installRenderView(view)
    }

    func installRenderer(_ renderer: SharedRenderer) {
        self.renderer = renderer
        for id in panelsByWindowID.keys {
            installRenderView(renderer.makeRenderView(for: id), for: id)
        }
    }

    /// Compatibility wrapper for callers that still use one configuration per feature.
    func apply(
        snapshot: TrackingSnapshot,
        frame: CameraFrame,
        configurations: [FeatureID: FeatureConfiguration],
        isLive: Bool,
        showAll: Bool,
        follow: Bool,
        smoothing: CGFloat,
        mirror: Bool,
        screens: [ScreenGeometry],
        menuWindowFrame: CGRect?,
        autoCropScale: Bool = false
    ) {
        let instanceConfigurations = Dictionary(uniqueKeysWithValues: configurations.map { featureID, configuration in
            (WindowInstanceID(featureID: featureID, serial: 1), configuration)
        })
        let ids = Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { featureID in
            (featureID, [WindowInstanceID(featureID: featureID, serial: 1)])
        })
        reconcileWindowIDs(ids)
        apply(
            snapshot: snapshot,
            frame: frame,
            windowIDsByFeature: ids,
            configurations: instanceConfigurations,
            isLive: isLive,
            showAll: showAll,
            follow: follow,
            smoothing: smoothing,
            mirror: mirror,
            screens: screens,
            menuWindowFrame: menuWindowFrame,
            autoCropScale: autoCropScale
        )
    }

    func apply(
        snapshot: TrackingSnapshot,
        frame: CameraFrame,
        windowIDsByFeature: [FeatureID: [WindowInstanceID]],
        configurations: [WindowInstanceID: FeatureConfiguration],
        isLive: Bool,
        showAll: Bool,
        follow: Bool,
        smoothing: CGFloat,
        mirror: Bool,
        screens: [ScreenGeometry],
        menuWindowFrame: CGRect?,
        autoCropScale: Bool = false
    ) {
        guard snapshot.timestamp.isValid, frame.timestamp.isValid,
              CMTimeCompare(snapshot.timestamp, frame.timestamp) == 0
        else { return }
        if let lastAppliedTimestamp,
           CMTimeCompare(snapshot.timestamp, lastAppliedTimestamp) < 0 {
            return
        }

        applyWindowChrome(configurations: configurations)

        guard isLive else {
            pausePresentation(configurations: configurations, showAll: showAll)
            return
        }

        if let lastAppliedTimestamp {
            if CMTimeCompare(snapshot.timestamp, lastAppliedTimestamp) > 0 {
                self.lastAppliedTimestamp = snapshot.timestamp
            }
        } else {
            lastAppliedTimestamp = snapshot.timestamp
        }
        let states = smoother.process(snapshot, configurations: configurations, smoothing: smoothing)

        if !showAll, renderer?.syphonEnabled == true {
            renderer?.update(frame: frame, featureStates: states, configurations: configurations, requestedMirror: mirror, autoCropScale: autoCropScale)
        }
        guard showAll else {
            hideAll()
            return
        }
        guard let screen = ScreenMapper.selectedScreen(from: screens, menuWindowFrame: menuWindowFrame) else {
            hideAll()
            renderer?.clear()
            return
        }

        renderer?.update(
            frame: frame,
            featureStates: states,
            configurations: configurations,
            requestedMirror: mirror,
            autoCropScale: autoCropScale
        )

        // Native resize gestures own each NSPanel's frame until AppKit completes the gesture.
        guard !panelsByWindowID.values.contains(where: \.isUserResizing) else { return }

        let orderedIDs = FeatureID.allCases.flatMap { windowIDsByFeature[$0] ?? [] }
        var naturalPlacements: [WindowInstanceID: CGRect] = [:]
        var preferredFrames: [WindowInstanceID: CGRect] = [:]
        var baseFollowFrames: [WindowInstanceID: CGRect] = [:]
        var naturalPrimaryFrames: [FeatureID: CGRect] = [:]
        var requestedOffsets: [WindowInstanceID: CGPoint] = [:]
        var initialPlacementIDs = Set<WindowInstanceID>()

        for windowID in orderedIDs {
            guard let panel = panelsByWindowID[windowID],
                  let configuration = configurations[windowID]
            else { continue }

            if configuration.isEnabled,
               configuration.isFrozen,
               renderer?.hasFrame(for: windowID) == true {
                show(windowID)
                continue
            }
            guard configuration.isEnabled,
                  let state = states[windowID],
                  state.fadeOpacity > 0,
                  let detection = state.detection
            else {
                hide(windowID)
                continue
            }

            let boundedScale = configuration.windowScale.isFinite
                ? min(max(configuration.windowScale, 0.25), 4)
                : 1
            let scaledContentSize = NSSize(
                width: Self.defaultPanelSize.width * boundedScale,
                height: Self.defaultPanelSize.height * boundedScale
            )
            let requestedContentSize = configuration.windowSizeOverride ?? scaledContentSize
            let configurationChanged = configuredSizes[windowID] != requestedContentSize
            configuredSizes[windowID] = requestedContentSize
            if !panel.isUserResizing &&
                (configurationChanged || panel.contentView?.frame.size != requestedContentSize) {
                resize(windowID, to: requestedContentSize)
            }

            guard let placement = ScreenMapper.panelPlacement(
                for: detection.normalizedRect,
                panelSize: panel.frame.size,
                on: screen,
                sourceIsMirrored: frame.isMirrored,
                requestedMirror: mirror
            ) else {
                hide(windowID)
                continue
            }

            naturalPlacements[windowID] = placement.frame
            if windowID.serial == 1 { naturalPrimaryFrames[windowID.featureID] = placement.frame }
            let requestedOffset = CGPoint(x: configuration.windowOffsetX, y: configuration.windowOffsetY)
            requestedOffsets[windowID] = requestedOffset
            if follow {
                preferredFrames[windowID] = placement.frame.offsetBy(dx: requestedOffset.x, dy: requestedOffset.y)
            } else if positionedWindowIDs.contains(windowID) {
                // AUTO FOLLOW OFF keeps the native frame. Only an explicit offset edit moves it.
                let previousOffset = lastWindowOffsets[windowID] ?? requestedOffset
                preferredFrames[windowID] = panel.frame.offsetBy(
                    dx: requestedOffset.x - previousOffset.x,
                    dy: requestedOffset.y - previousOffset.y
                )
            } else {
                preferredFrames[windowID] = placement.frame.offsetBy(
                    dx: requestedOffset.x,
                    dy: requestedOffset.y
                )
                initialPlacementIDs.insert(windowID)
            }
        }

        let semanticPrimaryFrames = faceLayoutFrames(
            from: naturalPrimaryFrames,
            inside: screen.visibleFrame
        )
        for id in orderedIDs where follow || initialPlacementIDs.contains(id) {
            guard let natural = naturalPlacements[id],
                  let requestedOffset = requestedOffsets[id]
            else { continue }
            let shift: CGPoint
            if let originalPrimary = naturalPrimaryFrames[id.featureID],
               let semanticPrimary = semanticPrimaryFrames[id.featureID] {
                shift = CGPoint(
                    x: semanticPrimary.minX - originalPrimary.minX,
                    y: semanticPrimary.minY - originalPrimary.minY
                )
            } else {
                shift = .zero
            }
            let base = natural.offsetBy(
                dx: requestedOffset.x + shift.x,
                dy: requestedOffset.y + shift.y
            )
            baseFollowFrames[id] = base
            if follow {
                let copyOffset = followLayoutOffsets[id] ?? .zero
                preferredFrames[id] = base.offsetBy(dx: copyOffset.x, dy: copyOffset.y)
            } else {
                preferredFrames[id] = base
            }
        }

        let layoutIDs: [WindowInstanceID]
        if follow {
            layoutIDs = orderedIDs.filter { preferredFrames[$0] != nil }
        } else {
            layoutIDs = orderedIDs.filter { initialPlacementIDs.contains($0) }
        }
        let fixedFrames = orderedIDs.compactMap { id -> CGRect? in
            guard !layoutIDs.contains(id),
                  let panel = panelsByWindowID[id],
                  positionedWindowIDs.contains(id)
            else { return nil }
            return panel.frame
        }
        let frozenFrames = orderedIDs.compactMap { id -> CGRect? in
            guard configurations[id]?.isFrozen == true,
                  let panel = panelsByWindowID[id]
            else { return nil }
            return panel.frame
        }
        var placedFrames = layoutFrames(
            preferredFrames: preferredFrames.filter { layoutIDs.contains($0.key) },
            orderedIDs: layoutIDs,
            inside: screen,
            avoiding: fixedFrames + frozenFrames + (menuWindowFrame.map { [$0] } ?? [])
        )
        if !follow {
            for id in orderedIDs where !initialPlacementIDs.contains(id) {
                if let frame = preferredFrames[id] { placedFrames[id] = frame }
            }
        }

        for windowID in orderedIDs {
            guard let configuration = configurations[windowID] else { continue }
            if configuration.isEnabled,
               configuration.isFrozen,
               renderer?.hasFrame(for: windowID) == true {
                show(windowID)
                continue
            }
            guard let targetFrame = placedFrames[windowID],
                  let panel = panelsByWindowID[windowID]
            else {
                hide(windowID)
                continue
            }
            if panel.frame != targetFrame { setFrame(targetFrame, for: windowID) }
            positionedWindowIDs.insert(windowID)
            if let requestedOffset = requestedOffsets[windowID] {
                lastWindowOffsets[windowID] = requestedOffset
            }
            if follow, let preferred = preferredFrames[windowID] {
                let base = baseFollowFrames[windowID] ?? preferred
                followLayoutOffsets[windowID] = CGPoint(
                    x: targetFrame.minX - base.minX,
                    y: targetFrame.minY - base.minY
                )
            } else if initialPlacementIDs.contains(windowID), let preferred = preferredFrames[windowID] {
                followLayoutOffsets[windowID] = CGPoint(
                    x: targetFrame.minX - preferred.minX,
                    y: targetFrame.minY - preferred.minY
                )
            }
            show(windowID)
        }
    }

    /// Compatibility wrapper for the original single-window-per-feature call path.
    func pausePresentation(configurations: [FeatureID: FeatureConfiguration], showAll: Bool) {
        let instanceConfigurations = Dictionary(uniqueKeysWithValues: configurations.map { featureID, configuration in
            (WindowInstanceID(featureID: featureID, serial: 1), configuration)
        })
        pausePresentation(configurations: instanceConfigurations, showAll: showAll)
    }

    func pausePresentation(configurations: [WindowInstanceID: FeatureConfiguration], showAll: Bool) {
        applyWindowChrome(configurations: configurations)
        smoother.reset()
        lastAppliedTimestamp = nil
        renderer?.retainFrozen(configurations: configurations)
        for id in panelsByWindowID.keys {
            if showAll,
               configurations[id]?.isEnabled == true,
               configurations[id]?.isFrozen == true,
               renderer?.hasFrame(for: id) == true {
                show(id)
            } else {
                hide(id)
            }
        }
    }

    func applyWindowChrome(configurations: [WindowInstanceID: FeatureConfiguration]) {
        for (id, configuration) in configurations {
            guard let panel = panelsByWindowID[id], !panel.isUserResizing else { continue }
            panel.setUIBarHidden(configuration.hidesUIBar)
        }
    }

    func resetPresentation() {
        smoother.reset()
        lastAppliedTimestamp = nil
        positionedWindowIDs.removeAll(keepingCapacity: false)
        lastWindowOffsets.removeAll(keepingCapacity: false)
        followLayoutOffsets.removeAll(keepingCapacity: false)
        renderer?.clear()
        hideAll()
    }

    private func configureCallbacks(on panel: FeaturePanel) {
        panel.onUserResize = { [weak self] windowID, size in
            self?.onUserResize?(windowID, size)
        }
        panel.onUserClose = { [weak self] windowID in
            self?.onUserClose?(windowID)
        }
    }

    private static var reusablePanelCapacity: Int {
        AppState.maximumWindowCount
    }

    private func hideAll() {
        for id in panelsByWindowID.keys { hide(id) }
    }

    private func faceLayoutFrames(
        from source: [FeatureID: CGRect],
        inside bounds: CGRect
    ) -> [FeatureID: CGRect] {
        var frames = source
        guard let leftEye = frames[.leftEye], let rightEye = frames[.rightEye] else { return frames }

        let eyeCenterX = (leftEye.midX + rightEye.midX) / 2
        let eyeRowBottom = min(leftEye.minY, rightEye.minY)
        if var nose = frames[.nose] {
            nose.origin.x = eyeCenterX - nose.width / 2
            nose.origin.y = eyeRowBottom - nose.height - 18
            frames[.nose] = nose
        }
        if var mouth = frames[.mouth], let nose = frames[.nose] {
            mouth.origin.x = nose.midX - mouth.width / 2
            mouth.origin.y = nose.minY - mouth.height - 24
            frames[.mouth] = mouth
        }

        let faceIDs: [FeatureID] = [.leftEye, .rightEye, .nose, .mouth]
        let faceFrames = faceIDs.compactMap { frames[$0] }
        guard let faceBounds = faceFrames.dropFirst().reduce(faceFrames.first, { partial, frame in
            partial?.union(frame)
        }) else { return frames }
        let minimumShift = bounds.minY - faceBounds.minY
        let maximumShift = bounds.maxY - faceBounds.maxY
        let verticalShift = min(max(0, minimumShift), maximumShift)
        for featureID in faceIDs {
            guard var faceFrame = frames[featureID] else { continue }
            faceFrame.origin.y += verticalShift
            frames[featureID] = faceFrame
        }
        return frames
    }

    private func layoutFrames(
        preferredFrames: [WindowInstanceID: CGRect],
        orderedIDs: [WindowInstanceID],
        inside screen: ScreenGeometry,
        avoiding framesToAvoid: [CGRect]
    ) -> [WindowInstanceID: CGRect] {
        var placed: [WindowInstanceID: CGRect] = [:]
        var reserved = framesToAvoid
        for id in orderedIDs {
            guard let preferred = preferredFrames[id],
                  let candidate = nearestFreeFrame(for: preferred, inside: screen, avoiding: reserved)
            else { continue }
            placed[id] = candidate
            reserved.append(candidate)
        }
        return placed
    }

    private func nearestFreeFrame(
        for preferred: CGRect,
        inside screen: ScreenGeometry,
        avoiding reserved: [CGRect]
    ) -> CGRect? {
        guard let origin = ScreenMapper.clampedPanelFrame(
            origin: preferred.origin,
            size: preferred.size,
            on: screen
        ) else { return nil }
        let gap: CGFloat = 16
        let xStep = max(1, origin.width + gap)
        let yStep = max(1, origin.height + gap)
        let maxRing = Int(ceil(max(screen.visibleFrame.width / xStep, screen.visibleFrame.height / yStep))) + 1
        var seen = Set<String>()

        func candidate(dx: CGFloat, dy: CGFloat) -> CGRect? {
            guard let bounded = ScreenMapper.clampedPanelFrame(
                origin: CGPoint(x: origin.minX + dx, y: origin.minY + dy),
                size: origin.size,
                on: screen
            ) else { return nil }
            let key = "\(Int((bounded.minX * 2).rounded())):\(Int((bounded.minY * 2).rounded()))"
            guard seen.insert(key).inserted else { return nil }
            let spaced = reserved.allSatisfy { other in
                !bounded.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(other)
            }
            return spaced ? bounded : nil
        }

        if let anchor = candidate(dx: 0, dy: 0) { return anchor }
        if maxRing > 0 {
            for ring in 1...maxRing {
                let r = CGFloat(ring)
                let offsets: [(CGFloat, CGFloat)] = [
                    (r, 0), (0, r), (-r, 0), (0, -r),
                    (r, r), (-r, r), (-r, -r), (r, -r)
                ]
                for (x, y) in offsets {
                    if let frame = candidate(dx: x * xStep, dy: y * yStep) { return frame }
                }
            }
        }
        return origin
    }
}
