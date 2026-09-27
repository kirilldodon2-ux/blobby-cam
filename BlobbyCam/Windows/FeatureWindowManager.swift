import AppKit
import CoreMedia

@MainActor
final class FeatureWindowManager {
    static let defaultPanelSize = NSSize(width: 240, height: 180)

    private(set) var panels: [FeatureID: FeaturePanel]
    private var renderer: SharedRenderer?
    private var smoother = TrackingSmoother()
    private var lastAppliedTimestamp: CMTime?
    private var positionedFeatures = Set<FeatureID>()
    private var configuredSizes: [FeatureID: NSSize] = [:]
    private var lastWindowOffsets: [FeatureID: CGPoint] = [:]
    var onUserResize: ((FeatureID, NSSize) -> Void)?
    var onUserClose: ((FeatureID) -> Void)?

    init(initialFrame: NSRect? = nil) {
        let frame = initialFrame ?? NSRect(origin: .zero, size: Self.defaultPanelSize)
        panels = Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { featureID in
            (featureID, FeaturePanel(featureID: featureID, frame: frame))
        })
        for panel in panels.values {
            panel.onUserResize = { [weak self] featureID, size in
                self?.onUserResize?(featureID, size)
            }
            panel.onUserClose = { [weak self] featureID in
                self?.onUserClose?(featureID)
            }
        }
    }

    func panel(for featureID: FeatureID) -> FeaturePanel {
        // The manager constructs one panel for every FeatureID during initialization.
        panels[featureID]!
    }

    func show(_ featureID: FeatureID) {
        let featurePanel = panel(for: featureID)
        guard !featurePanel.isVisible else { return }
        featurePanel.orderFrontRegardless()
    }

    func hide(_ featureID: FeatureID) {
        panel(for: featureID).orderOut(nil)
    }

    func move(_ featureID: FeatureID, to origin: NSPoint) {
        let featurePanel = panel(for: featureID)
        featurePanel.setFrameOrigin(origin)
    }

    func resize(_ featureID: FeatureID, to size: NSSize) {
        let featurePanel = panel(for: featureID)
        let origin = featurePanel.frame.origin
        featurePanel.setContentSize(size)
        // AppKit preserves the top edge when the content height changes. Keep size changes
        // independent from window placement by restoring the existing lower-left origin.
        featurePanel.setFrameOrigin(origin)
    }

    func setFrame(_ frame: NSRect, for featureID: FeatureID) {
        let featurePanel = panel(for: featureID)
        guard featurePanel.frame != frame else { return }
        featurePanel.setFrame(frame, display: true)
    }

    func installRenderView(_ view: NSView, for featureID: FeatureID) {
        panel(for: featureID).installRenderView(view)
    }

    func installRenderer(_ renderer: SharedRenderer) {
        self.renderer = renderer
        for featureID in FeatureID.allCases {
            installRenderView(renderer.makeRenderView(for: featureID), for: featureID)
        }
    }

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
        guard snapshot.timestamp.isValid, frame.timestamp.isValid,
              CMTimeCompare(snapshot.timestamp, frame.timestamp) == 0
        else { return }
        if let lastAppliedTimestamp,
           CMTimeCompare(snapshot.timestamp, lastAppliedTimestamp) < 0 {
            return
        }

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

        // AppKit owns the panel frame for the duration of a native resize gesture. Tracking
        // continues to update the video, then all panel positions settle on resize completion.
        guard !panels.values.contains(where: \.isUserResizing) else { return }

        var preferredFrames: [FeatureID: CGRect] = [:]
        var featuresNeedingInitialPlacement = Set<FeatureID>()

        for featureID in FeatureID.allCases {
            if configurations[featureID]?.isEnabled == true,
               configurations[featureID]?.isFrozen == true,
               renderer?.hasFrame(for: featureID) == true {
                // Freeze retains the last crop and the panel's current native position.
                show(featureID)
                continue
            }
            guard let configuration = configurations[featureID],
                  configuration.isEnabled,
                  let state = states[featureID],
                  state.fadeOpacity > 0,
                  let detection = state.detection
            else {
                hide(featureID)
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
            let panel = panel(for: featureID)
            let configurationChanged = configuredSizes[featureID] != requestedContentSize
            configuredSizes[featureID] = requestedContentSize
            if !panel.isUserResizing &&
                (configurationChanged || panel.contentView?.frame.size != requestedContentSize) {
                resize(featureID, to: requestedContentSize)
            }

            let placement = ScreenMapper.panelPlacement(
                for: detection.normalizedRect,
                panelSize: panel.frame.size,
                on: screen,
                sourceIsMirrored: frame.isMirrored,
                requestedMirror: mirror
            )
            guard let placement else {
                hide(featureID)
                continue
            }

            let requestedOffset = CGPoint(x: configuration.windowOffsetX, y: configuration.windowOffsetY)
            let targetFrame: CGRect
            if follow || !positionedFeatures.contains(featureID) {
                let offsetOrigin = CGPoint(
                    x: placement.frame.minX + requestedOffset.x,
                    y: placement.frame.minY + requestedOffset.y
                )
                targetFrame = ScreenMapper.clampedPanelFrame(
                    origin: offsetOrigin,
                    size: placement.frame.size,
                    on: screen
                ) ?? placement.frame
                if !follow { featuresNeedingInitialPlacement.insert(featureID) }
            } else {
                // With follow disabled, retain the panel's exact native frame. Only apply a
                // deliberate offset-control change; never clamp or collision-resolve a window
                // the user has already placed.
                let previousOffset = lastWindowOffsets[featureID] ?? requestedOffset
                targetFrame = panel.frame.offsetBy(
                    dx: requestedOffset.x - previousOffset.x,
                    dy: requestedOffset.y - previousOffset.y
                )
            }
            lastWindowOffsets[featureID] = requestedOffset
            preferredFrames[featureID] = targetFrame
        }

        let placedFrames: [FeatureID: CGRect]
        if follow {
            applyFaceLayout(to: &preferredFrames, configurations: configurations, inside: screen.visibleFrame)
            placedFrames = ScreenMapper.collisionFreePanelFrames(
                preferredFrames: preferredFrames,
                inside: screen.visibleFrame,
                avoiding: panels.compactMap { id, panel in
                    configurations[id]?.isFrozen == true && panel.isVisible ? panel.frame : nil
                } + (menuWindowFrame.map { [$0] } ?? []),
                minimumGap: 16
            )
        } else if !featuresNeedingInitialPlacement.isEmpty {
            // Lay out a newly detected group around the established windows, while keeping
            // every previously positioned panel out of the collision solver's write set.
            applyFaceLayout(to: &preferredFrames, configurations: configurations, inside: screen.visibleFrame)
            let fixedFrames = FeatureID.allCases.compactMap { featureID -> CGRect? in
                guard !featuresNeedingInitialPlacement.contains(featureID),
                      let panel = panels[featureID], panel.isVisible
                else { return nil }
                return panel.frame
            }
            let initialFrames = preferredFrames.filter { featuresNeedingInitialPlacement.contains($0.key) }
            placedFrames = ScreenMapper.collisionFreePanelFrames(
                preferredFrames: initialFrames,
                inside: screen.visibleFrame,
                avoiding: fixedFrames + (menuWindowFrame.map { [$0] } ?? []),
                minimumGap: 16
            )
        } else {
            placedFrames = preferredFrames
        }

        for featureID in FeatureID.allCases {
            if configurations[featureID]?.isEnabled == true,
               configurations[featureID]?.isFrozen == true,
               renderer?.hasFrame(for: featureID) == true {
                show(featureID)
                continue
            }
            guard let targetFrame = placedFrames[featureID] else {
                hide(featureID)
                continue
            }
            let panel = panel(for: featureID)
            if panel.frame != targetFrame {
                setFrame(targetFrame, for: featureID)
            }
            positionedFeatures.insert(featureID)
            show(featureID)
        }
    }

    func resetPresentation() {
        smoother.reset()
        lastAppliedTimestamp = nil
        positionedFeatures.removeAll(keepingCapacity: false)
        lastWindowOffsets.removeAll(keepingCapacity: false)
        renderer?.clear()
        hideAll()
    }

    func pausePresentation(configurations: [FeatureID: FeatureConfiguration], showAll: Bool) {
        smoother.reset()
        lastAppliedTimestamp = nil
        renderer?.retainFrozen(configurations: configurations)
        for id in FeatureID.allCases {
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

    private func hideAll() {
        for featureID in FeatureID.allCases { hide(featureID) }
    }

    /// Keep facial crops in a compact reading order: detected eyes form the top row, then the
    /// nose and mouth sit below their semantic center. Unequal gaps and detected eye geometry
    /// preserve a little variation while manual per-window offsets still move each crop.
    private func applyFaceLayout(
        to frames: inout [FeatureID: CGRect],
        configurations: [FeatureID: FeatureConfiguration],
        inside bounds: CGRect
    ) {
        guard let leftEye = frames[.leftEye],
              let rightEye = frames[.rightEye]
        else { return }

        let eyeCenterX = (leftEye.midX + rightEye.midX) / 2
        let eyeRowBottom = min(leftEye.minY, rightEye.minY)

        if var nose = frames[.nose], let configuration = configurations[.nose] {
            nose.origin.x = eyeCenterX - nose.width / 2 + configuration.windowOffsetX
            nose.origin.y = eyeRowBottom - nose.height - 18 + configuration.windowOffsetY
            frames[.nose] = nose
        }

        if var mouth = frames[.mouth],
           let nose = frames[.nose],
           let configuration = configurations[.mouth] {
            mouth.origin.x = nose.midX - mouth.width / 2 + configuration.windowOffsetX
            mouth.origin.y = nose.minY - mouth.height - 24 + configuration.windowOffsetY
            frames[.mouth] = mouth
        }

        let faceIDs: [FeatureID] = [.leftEye, .rightEye, .nose, .mouth]
        let faceFrames = faceIDs.compactMap { frames[$0] }
        guard let faceBounds = faceFrames.dropFirst().reduce(faceFrames.first, { partial, frame in
            partial?.union(frame)
        }) else { return }
        let minimumShift = bounds.minY - faceBounds.minY
        let maximumShift = bounds.maxY - faceBounds.maxY
        let verticalShift = min(max(0, minimumShift), maximumShift)
        for featureID in faceIDs {
            guard var frame = frames[featureID] else { continue }
            frame.origin.y += verticalShift
            frames[featureID] = frame
        }
    }
}
