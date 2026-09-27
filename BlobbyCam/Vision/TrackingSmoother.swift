import CoreGraphics
import CoreMedia

struct SmoothedFeatureState {
    let detection: FeatureDetection?
    let lifecycle: WindowLifecycleState
    /// Remains 1 through the grace interval, fades to 0, and is 0 when hidden.
    let fadeOpacity: CGFloat

    var isFading: Bool { fadeOpacity > 0 && fadeOpacity < 1 }
}

struct TrackingSmoother {
    static let defaultSmoothing: CGFloat = 0
    static let defaultShowThreshold: Float = 0.55
    static let defaultHoldThreshold: Float = 0.40
    static let graceDuration: TimeInterval = 0.25
    static let hideFadeDuration: TimeInterval = 0.12

    private struct FeatureTrack {
        var detection: FeatureDetection
        var lastSeen: CMTime
        var lifecycle: WindowLifecycleState
        var fadeOpacity: CGFloat
    }

    private var tracks: [FeatureID: FeatureTrack] = [:]
    private var lastSnapshotTimestamp: CMTime?

    /// Processes only newer source timestamps. Missing features hold their last valid geometry
    /// during grace and fade; their coordinates are never replaced with an origin sentinel.
    mutating func process(
        _ snapshot: TrackingSnapshot,
        configurations: [FeatureID: FeatureConfiguration],
        smoothing: CGFloat = defaultSmoothing
    ) -> [FeatureID: SmoothedFeatureState] {
        for id in FeatureID.allCases where configurations[id]?.isEnabled != true {
            tracks.removeValue(forKey: id)
        }

        guard snapshot.timestamp.isValid else { return outputStates() }
        if let lastSnapshotTimestamp,
           CMTimeCompare(snapshot.timestamp, lastSnapshotTimestamp) <= 0 {
            return outputStates()
        }
        lastSnapshotTimestamp = snapshot.timestamp

        // The UI expresses smoothing strength: zero follows each new detection exactly.
        // Keep a small response even at maximum strength so landmarks never freeze in place.
        let alpha = max(0.05, 1 - boundedSmoothing(smoothing))
        for id in FeatureID.allCases {
            guard let configuration = configurations[id], configuration.isEnabled else { continue }
            let detection = snapshot.detections[id].flatMap { candidate in
                candidate.id == id && isValid(candidate) ? candidate : nil
            }
            update(
                id: id,
                detection: detection,
                at: snapshot.timestamp,
                showThreshold: boundedThreshold(configuration.detectionThreshold),
                smoothing: alpha
            )
        }
        return outputStates()
    }

    /// Clears all held geometry and timestamp history, for camera stop or full reset.
    mutating func reset() {
        tracks.removeAll(keepingCapacity: false)
        lastSnapshotTimestamp = nil
    }

    private mutating func update(
        id: FeatureID,
        detection: FeatureDetection?,
        at timestamp: CMTime,
        showThreshold: Float,
        smoothing: CGFloat
    ) {
        // Keep the default hold threshold at 0.40 while never making hold harder than show.
        let holdThreshold = min(showThreshold, Self.defaultHoldThreshold)
        if var track = tracks[id] {
            if let detection, detection.confidence >= holdThreshold {
                track.detection = smoothed(from: track.detection, toward: detection, alpha: smoothing)
                track.lastSeen = timestamp
                track.lifecycle = .visible
                track.fadeOpacity = 1
                tracks[id] = track
                return
            }

            let elapsed = CMTimeGetSeconds(CMTimeSubtract(timestamp, track.lastSeen))
            guard elapsed.isFinite, elapsed >= 0 else { return }
            if elapsed <= Self.graceDuration {
                track.lifecycle = .grace(lastSeen: track.lastSeen)
                track.fadeOpacity = 1
                tracks[id] = track
            } else if elapsed < Self.graceDuration + Self.hideFadeDuration {
                let fadeProgress = (elapsed - Self.graceDuration) / Self.hideFadeDuration
                track.lifecycle = .grace(lastSeen: track.lastSeen)
                track.fadeOpacity = CGFloat(1 - fadeProgress)
                tracks[id] = track
            } else {
                tracks.removeValue(forKey: id)
            }
            return
        }

        guard let detection, detection.confidence >= showThreshold else { return }
        tracks[id] = FeatureTrack(
            detection: detection,
            lastSeen: timestamp,
            lifecycle: .visible,
            fadeOpacity: 1
        )
    }

    private func outputStates() -> [FeatureID: SmoothedFeatureState] {
        Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { id in
            guard let track = tracks[id] else {
                return (id, SmoothedFeatureState(detection: nil, lifecycle: .hidden, fadeOpacity: 0))
            }
            return (id, SmoothedFeatureState(
                detection: track.detection,
                lifecycle: track.lifecycle,
                fadeOpacity: track.fadeOpacity
            ))
        })
    }

    private func smoothed(from previous: FeatureDetection, toward current: FeatureDetection, alpha: CGFloat) -> FeatureDetection {
        let old = previous.normalizedRect
        let new = current.normalizedRect
        let rect = CGRect(
            x: old.minX + alpha * (new.minX - old.minX),
            y: old.minY + alpha * (new.minY - old.minY),
            width: old.width + alpha * (new.width - old.width),
            height: old.height + alpha * (new.height - old.height)
        )
        let referenceSize: CGSize?
        if let oldSize = previous.cropReferenceSize, let newSize = current.cropReferenceSize {
            referenceSize = CGSize(
                width: oldSize.width + alpha * (newSize.width - oldSize.width),
                height: oldSize.height + alpha * (newSize.height - oldSize.height)
            )
        } else {
            referenceSize = current.cropReferenceSize
        }
        return FeatureDetection(
            id: current.id,
            normalizedRect: rect,
            confidence: current.confidence,
            timestamp: current.timestamp,
            cropReferenceSize: referenceSize
        )
    }

    private func isValid(_ detection: FeatureDetection) -> Bool {
        let rect = detection.normalizedRect
        return rect.minX.isFinite && rect.minY.isFinite
            && rect.maxX.isFinite && rect.maxY.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
            && rect.minX >= 0 && rect.minY >= 0
            && rect.maxX <= 1 && rect.maxY <= 1
            && detection.confidence.isFinite
            && (0...1).contains(detection.confidence)
            && (detection.cropReferenceSize.map {
                $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0
            } ?? true)
    }

    private func boundedSmoothing(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return Self.defaultSmoothing }
        return min(max(value, 0), 1)
    }

    private func boundedThreshold(_ value: Float) -> Float {
        guard value.isFinite else { return Self.defaultShowThreshold }
        return min(max(value, 0), 1)
    }
}
