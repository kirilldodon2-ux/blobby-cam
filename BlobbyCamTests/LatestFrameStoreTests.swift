import AVFoundation
import CoreMedia
import CoreVideo
import XCTest
@testable import BlobbyCam

final class LatestFrameStoreTests: XCTestCase {
    func testReplacementKeepsOnlyNewestFrameAndTimestamp() throws {
        let store = InMemoryLatestFrameStore()
        let first = try makeFrame(timestamp: 1, width: 8)
        let newest = try makeFrame(timestamp: 2, width: 16)

        XCTAssertNil(store.latest())
        XCTAssertNil(store.latestTimestamp)
        XCTAssertEqual(store.retainedFrameCount, 0)

        store.replace(with: first)
        XCTAssertEqual(store.latestTimestamp, first.timestamp)
        XCTAssertEqual(store.retainedFrameCount, 1)

        store.replace(with: newest)
        let latest = try XCTUnwrap(store.latest())
        XCTAssertEqual(latest.timestamp, newest.timestamp)
        XCTAssertEqual(store.latestTimestamp, newest.timestamp)
        XCTAssertEqual(CVPixelBufferGetWidth(latest.pixelBuffer), 16)
        XCTAssertEqual(store.retainedFrameCount, 1)
    }

    func testConcurrentReadersAndWritersRetainAtMostOneFrame() throws {
        let store = InMemoryLatestFrameStore()
        let buffer = try makePixelBuffer(width: 8)

        DispatchQueue.concurrentPerform(iterations: 500) { index in
            let frame = CameraFrame(
                pixelBuffer: buffer,
                timestamp: CMTime(value: Int64(index), timescale: 30),
                orientation: .up,
                isMirrored: false
            )
            store.replace(with: frame)
            _ = store.latest()
            _ = store.latestTimestamp
            _ = store.retainedFrameCount
        }

        XCTAssertNotNil(store.latest())
        XCTAssertNotNil(store.latestTimestamp)
        XCTAssertEqual(store.retainedFrameCount, 1)
    }

    @MainActor
    func testCaptureStoresFrameBeforeForwardingIt() async throws {
        let permission = CameraPermission(authorization: FakeCapturePermissionProviderForStore(status: .authorized))
        let pipeline = FakeCameraCapturePipelineForStore()
        let store = InMemoryLatestFrameStore()
        var forwardedTimestamp: CMTime?
        let capture = CameraCapture(
            permission: permission,
            pipeline: pipeline,
            frameStore: store,
            onFrame: { frame in
                forwardedTimestamp = frame.timestamp
                XCTAssertEqual(store.latestTimestamp, frame.timestamp)
            }
        )

        capture.start()
        pipeline.completeStart(.success(()))
        await Task.yield()

        let frame = try makeFrame(timestamp: 7, width: 12)
        pipeline.emit(frame)

        XCTAssertEqual(store.latestTimestamp, frame.timestamp)
        XCTAssertEqual(forwardedTimestamp, frame.timestamp)
        XCTAssertEqual(store.retainedFrameCount, 1)
    }

    private func makeFrame(timestamp: Int64, width: Int) throws -> CameraFrame {
        CameraFrame(
            pixelBuffer: try makePixelBuffer(width: width),
            timestamp: CMTime(value: timestamp, timescale: 30),
            orientation: .up,
            isMirrored: false
        )
    }

    private func makePixelBuffer(width: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                8,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            ),
            kCVReturnSuccess
        )
        return try XCTUnwrap(pixelBuffer)
    }
}

@MainActor
private final class FakeCapturePermissionProviderForStore: CameraAuthorizationProviding {
    private let status: AVAuthorizationStatus

    init(status: AVAuthorizationStatus) {
        self.status = status
    }

    var videoAuthorizationStatus: AVAuthorizationStatus { status }

    func requestVideoAccess(completion: @escaping @Sendable (Bool) -> Void) {
        completion(status == .authorized)
    }
}

@MainActor
private final class FakeCameraCapturePipelineForStore: CameraCapturePipeline {
    private var frameHandler: ((CameraFrame) -> Void)?
    private var startCompletion: (@Sendable (Result<Void, CameraCaptureError>) -> Void)?

    func installHandlers(
        onFrame: @escaping (CameraFrame) -> Void,
        onEvent: @escaping @Sendable (CameraPipelineEvent) -> Void
    ) {
        frameHandler = onFrame
    }

    func start(completion: @escaping @Sendable (Result<Void, CameraCaptureError>) -> Void) {
        startCompletion = completion
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        completion()
    }

    func completeStart(_ result: Result<Void, CameraCaptureError>) {
        startCompletion?(result)
        startCompletion = nil
    }

    func emit(_ frame: CameraFrame) {
        frameHandler?(frame)
    }
}
