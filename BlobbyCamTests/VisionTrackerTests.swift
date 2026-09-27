import CoreMedia
import CoreVideo
import Darwin
import XCTest
@testable import BlobbyCam

final class VisionTrackerTests: XCTestCase {
    func testBusyTrackerDropsIntermediateFramesAndPublishesCoherentTimestamps() throws {
        let analyzer = GatedVisionAnalyzer()
        let tracker = VisionTracker(analyzer: analyzer)
        let delivered = expectation(description: "first and newest snapshots are published")
        delivered.expectedFulfillmentCount = 2
        let snapshots = LockedSnapshots()
        tracker.onSnapshot = { snapshot in
            snapshots.append(snapshot)
            delivered.fulfill()
        }

        tracker.submit(try makeFrame(timestamp: 1))
        XCTAssertEqual(analyzer.firstAnalysisStarted.wait(timeout: .now() + 2), .success)
        tracker.submit(try makeFrame(timestamp: 2))
        tracker.submit(try makeFrame(timestamp: 3))
        analyzer.releaseFirstAnalysis.signal()

        wait(for: [delivered], timeout: 3)

        XCTAssertEqual(analyzer.processedTimestamps, [1, 3])
        let published = snapshots.values
        XCTAssertEqual(published.map(\.timestamp.value), [1, 3])
        for snapshot in published {
            XCTAssertEqual(snapshot.detections[.nose]?.timestamp, snapshot.timestamp)
        }
        XCTAssertEqual(tracker.latestSnapshot?.timestamp.value, 3)
        XCTAssertNil(tracker.latestError)
    }

    func testOutOfOrderInputIsIgnored() throws {
        let analyzer = RecordingVisionAnalyzer()
        let tracker = VisionTracker(analyzer: analyzer)
        let delivered = expectation(description: "newer snapshot arrives")
        tracker.onSnapshot = { _ in delivered.fulfill() }

        tracker.submit(try makeFrame(timestamp: 5))
        tracker.submit(try makeFrame(timestamp: 4))
        wait(for: [delivered], timeout: 3)

        XCTAssertEqual(analyzer.processedTimestamps, [5])
        XCTAssertEqual(tracker.latestSnapshot?.timestamp.value, 5)
    }

    func testFrameSnapshotCallbackKeepsTheAnalyzedFramePairedWithItsSnapshot() throws {
        let tracker = VisionTracker(analyzer: RecordingVisionAnalyzer())
        let received = expectation(description: "analyzed source frame and snapshot arrive together")
        let pairs = LockedFrameSnapshotPairs()
        tracker.onFrameSnapshot = { frame, snapshot in
            pairs.append(frame.timestamp, snapshot.timestamp)
            received.fulfill()
        }

        tracker.submit(try makeFrame(timestamp: 17))
        wait(for: [received], timeout: 3)

        XCTAssertEqual(pairs.values.count, 1)
        XCTAssertEqual(pairs.values.first?.frame.value, 17)
        XCTAssertEqual(pairs.values.first?.snapshot.value, 17)
    }

    func testAppleVisionRequestsProduceSourceStampedSnapshotFromOnePixelBuffer() throws {
        let tracker = VisionTracker()
        let received = expectation(description: "Vision processes a synthetic camera frame")
        tracker.onSnapshot = { _ in received.fulfill() }
        tracker.submit(try makeFrame(timestamp: 30))

        wait(for: [received], timeout: 10)

        let snapshot = try XCTUnwrap(tracker.latestSnapshot)
        XCTAssertEqual(snapshot.timestamp, CMTime(value: 30, timescale: 30))
        XCTAssertTrue(snapshot.detections.keys.allSatisfy {
            [.leftEye, .rightEye, .nose, .mouth, .leftHand, .rightHand].contains($0)
        })
        XCTAssertTrue(snapshot.detections.values.allSatisfy { $0.timestamp == snapshot.timestamp })
    }

    private func makeFrame(timestamp: Int64) throws -> CameraFrame {
        let width = 64
        let height = 64
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            ),
            kCVReturnSuccess
        )
        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            memset(baseAddress, 0, CVPixelBufferGetBytesPerRow(buffer) * height)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return CameraFrame(
            pixelBuffer: buffer,
            timestamp: CMTime(value: timestamp, timescale: 30),
            orientation: .up,
            isMirrored: false
        )
    }
}

private final class LockedSnapshots {
    private let lock = NSLock()
    private var storage: [TrackingSnapshot] = []

    var values: [TrackingSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ snapshot: TrackingSnapshot) {
        lock.lock()
        storage.append(snapshot)
        lock.unlock()
    }
}

private final class LockedFrameSnapshotPairs {
    private let lock = NSLock()
    private var storage: [(frame: CMTime, snapshot: CMTime)] = []

    var values: [(frame: CMTime, snapshot: CMTime)] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ frame: CMTime, _ snapshot: CMTime) {
        lock.lock()
        storage.append((frame, snapshot))
        lock.unlock()
    }
}

private final class GatedVisionAnalyzer: VisionFrameAnalyzing, @unchecked Sendable {
    let firstAnalysisStarted = DispatchSemaphore(value: 0)
    let releaseFirstAnalysis = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var processed: [Int64] = []

    var processedTimestamps: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return processed
    }

    func analyze(_ frame: CameraFrame) throws -> TrackingSnapshot {
        lock.lock()
        let isFirst = processed.isEmpty
        processed.append(frame.timestamp.value)
        lock.unlock()
        if isFirst {
            firstAnalysisStarted.signal()
            releaseFirstAnalysis.wait()
        }

        let detection = FeatureDetection(
            id: .nose,
            normalizedRect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            confidence: 0.9,
            timestamp: .zero
        )
        return TrackingSnapshot(timestamp: .zero, detections: [.nose: detection])
    }
}

private final class RecordingVisionAnalyzer: VisionFrameAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var processed: [Int64] = []

    var processedTimestamps: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return processed
    }

    func analyze(_ frame: CameraFrame) throws -> TrackingSnapshot {
        lock.lock()
        processed.append(frame.timestamp.value)
        lock.unlock()
        return TrackingSnapshot(timestamp: frame.timestamp, detections: [:])
    }
}
