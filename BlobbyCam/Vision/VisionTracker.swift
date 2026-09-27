import CoreMedia
import Vision

protocol VisionFrameAnalyzing: AnyObject {
    func analyze(_ frame: CameraFrame) throws -> TrackingSnapshot
}

final class VisionTracker: @unchecked Sendable {
    private let analyzer: VisionFrameAnalyzing
    private let analysisQueue = DispatchQueue(label: "com.blobbycam.vision.analysis")
    private let pendingLock = NSLock()
    private var pendingFrame: CameraFrame?
    private var drainScheduled = false
    private var newestSubmittedTimestamp: CMTime?

    private let resultLock = NSLock()
    private var latestSnapshotStorage: TrackingSnapshot?
    private var latestErrorStorage: String?
    private var snapshotHandler: ((TrackingSnapshot) -> Void)?
    private var frameSnapshotHandler: ((CameraFrame, TrackingSnapshot) -> Void)?
    private var errorHandler: ((String) -> Void)?

    convenience init() {
        self.init(analyzer: AppleVisionFrameAnalyzer())
    }

    init(analyzer: VisionFrameAnalyzing) {
        self.analyzer = analyzer
    }

    var latestSnapshot: TrackingSnapshot? {
        resultLock.lock()
        defer { resultLock.unlock() }
        return latestSnapshotStorage
    }

    var latestError: String? {
        resultLock.lock()
        defer { resultLock.unlock() }
        return latestErrorStorage
    }

    var onSnapshot: ((TrackingSnapshot) -> Void)? {
        get {
            resultLock.lock()
            defer { resultLock.unlock() }
            return snapshotHandler
        }
        set {
            resultLock.lock()
            snapshotHandler = newValue
            resultLock.unlock()
        }
    }

    /// Delivers the source frame together with the snapshot analyzed from that exact frame.
    /// UI/rendering clients use this instead of pairing independently sampled latest values.
    var onFrameSnapshot: ((CameraFrame, TrackingSnapshot) -> Void)? {
        get {
            resultLock.lock()
            defer { resultLock.unlock() }
            return frameSnapshotHandler
        }
        set {
            resultLock.lock()
            frameSnapshotHandler = newValue
            resultLock.unlock()
        }
    }

    var onError: ((String) -> Void)? {
        get {
            resultLock.lock()
            defer { resultLock.unlock() }
            return errorHandler
        }
        set {
            resultLock.lock()
            errorHandler = newValue
            resultLock.unlock()
        }
    }

    /// Replaces the pending frame. While Vision is busy, intermediate frames are discarded.
    func submit(_ frame: CameraFrame) {
        guard frame.timestamp.isValid else { return }
        var shouldScheduleDrain = false

        pendingLock.lock()
        if let newestSubmittedTimestamp,
           CMTimeCompare(frame.timestamp, newestSubmittedTimestamp) <= 0 {
            pendingLock.unlock()
            return
        }

        newestSubmittedTimestamp = frame.timestamp
        pendingFrame = frame
        if !drainScheduled {
            drainScheduled = true
            shouldScheduleDrain = true
        }
        pendingLock.unlock()

        if shouldScheduleDrain {
            analysisQueue.async { [self] in drainPendingFrames() }
        }
    }

    private func drainPendingFrames() {
        while true {
            pendingLock.lock()
            guard let frame = pendingFrame else {
                drainScheduled = false
                pendingLock.unlock()
                return
            }
            pendingFrame = nil
            pendingLock.unlock()

            do {
                let analyzed = try analyzer.analyze(frame)
                let detections = analyzed.detections.mapValues { detection in
                    FeatureDetection(
                        id: detection.id,
                        normalizedRect: detection.normalizedRect,
                        confidence: detection.confidence,
                        timestamp: frame.timestamp
                    )
                }
                publish(TrackingSnapshot(timestamp: frame.timestamp, detections: detections), from: frame)
            } catch {
                publish(error: error.localizedDescription)
            }
        }
    }

    private func publish(_ snapshot: TrackingSnapshot, from frame: CameraFrame) {
        resultLock.lock()
        latestSnapshotStorage = snapshot
        latestErrorStorage = nil
        let handler = snapshotHandler
        let frameSnapshotHandler = frameSnapshotHandler
        resultLock.unlock()
        handler?(snapshot)
        frameSnapshotHandler?(frame, snapshot)
    }

    private func publish(error: String) {
        resultLock.lock()
        latestErrorStorage = error
        let handler = errorHandler
        resultLock.unlock()
        handler?(error)
    }
}

private final class AppleVisionFrameAnalyzer: VisionFrameAnalyzing {
    private let sequenceHandler = VNSequenceRequestHandler()
    private let faceRequest = VNDetectFaceLandmarksRequest()
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let faceRegionExtractor = FaceRegionExtractor()
    private let handRegionExtractor = HandRegionExtractor()

    init() {
        handRequest.maximumHandCount = 2
    }

    func analyze(_ frame: CameraFrame) throws -> TrackingSnapshot {
        // Vision receives orientation once and returns oriented full-image normalized geometry.
        // Mirror stays metadata for the later screen/render mapping stage.
        try sequenceHandler.perform(
            [faceRequest, handRequest],
            on: frame.pixelBuffer,
            orientation: frame.orientation
        )

        var detections: [FeatureID: FeatureDetection] = [:]
        let faces = faceRequest.results ?? []
        if let primaryFace = faces.max(by: {
            // V0 follows the largest visible face; confidence breaks exact area ties.
            if $0.boundingBox.area == $1.boundingBox.area {
                return $0.confidence < $1.confidence
            }
            return $0.boundingBox.area < $1.boundingBox.area
        }) {
            for detection in faceRegionExtractor.extract(from: primaryFace, timestamp: frame.timestamp) {
                detections[detection.id] = detection
            }
        }

        let hands = handRequest.results ?? []
        for hand in hands {
            guard let detection = handRegionExtractor.extract(from: hand, timestamp: frame.timestamp) else { continue }
            if let existing = detections[detection.id], existing.confidence >= detection.confidence { continue }
            detections[detection.id] = detection
        }

        return TrackingSnapshot(timestamp: frame.timestamp, detections: detections)
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
