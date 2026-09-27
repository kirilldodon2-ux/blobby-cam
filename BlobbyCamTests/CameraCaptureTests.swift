import AVFoundation
import CoreMedia
import CoreVideo
import XCTest
@testable import BlobbyCam

final class CameraCaptureTests: XCTestCase {
    @MainActor
    func testPermissionDenialNeverStartsCapture() {
        let permissionProvider = FakeCapturePermissionProvider(status: .denied)
        let permission = CameraPermission(authorization: permissionProvider)
        let pipeline = FakeCameraCapturePipeline()
        let capture = CameraCapture(permission: permission, pipeline: pipeline)

        capture.start()

        XCTAssertEqual(capture.state, .failed(.permissionDenied))
        XCTAssertEqual(capture.lastError, .permissionDenied)
        XCTAssertEqual(permissionProvider.requestCount, 0)
        XCTAssertEqual(pipeline.startCount, 0)
    }

    @MainActor
    func testAuthorizedStartAndStopAreIdempotent() async {
        let permission = CameraPermission(authorization: FakeCapturePermissionProvider(status: .authorized))
        let pipeline = FakeCameraCapturePipeline()
        let capture = CameraCapture(permission: permission, pipeline: pipeline)
        let started = expectation(description: "capture starts")

        capture.start()
        capture.start()
        pipeline.onStartCompletion = { started.fulfill() }
        pipeline.completeStart(.success(()))
        await fulfillment(of: [started], timeout: 2)
        await Task.yield()

        XCTAssertEqual(capture.state, .running)
        XCTAssertEqual(pipeline.startCount, 1)

        let stopped = expectation(description: "capture stops")
        pipeline.onStopCompletion = { stopped.fulfill() }
        capture.stop()
        capture.stop()
        pipeline.completeStop()
        await fulfillment(of: [stopped], timeout: 2)
        await Task.yield()

        XCTAssertEqual(capture.state, .stopped)
        XCTAssertEqual(pipeline.stopCount, 1)
    }

    @MainActor
    func testInterruptionAndRecoveryUpdateObservableState() async {
        let permission = CameraPermission(authorization: FakeCapturePermissionProvider(status: .authorized))
        let pipeline = FakeCameraCapturePipeline()
        let capture = CameraCapture(permission: permission, pipeline: pipeline)
        let started = expectation(description: "capture starts")
        pipeline.onStartCompletion = { started.fulfill() }

        capture.start()
        pipeline.completeStart(.success(()))
        await fulfillment(of: [started], timeout: 2)
        await Task.yield()

        let interrupted = expectation(description: "capture interruption is published")
        pipeline.emit(.interrupted)
        Task { @MainActor in
            await Task.yield()
            interrupted.fulfill()
        }
        await fulfillment(of: [interrupted], timeout: 2)
        XCTAssertEqual(capture.state, .interrupted)

        let recovered = expectation(description: "capture recovery is published")
        pipeline.emit(.running)
        Task { @MainActor in
            await Task.yield()
            recovered.fulfill()
        }
        await fulfillment(of: [recovered], timeout: 2)
        XCTAssertEqual(capture.state, .running)
    }

    func testSampleBufferBecomesTimestampedCameraFrame() throws {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA, nil, &pixelBuffer),
            kCVReturnSuccess
        )
        let imageBuffer = try XCTUnwrap(pixelBuffer)

        var formatDescription: CMVideoFormatDescription?
        XCTAssertEqual(
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                formatDescriptionOut: &formatDescription
            ),
            noErr
        )
        let format = try XCTUnwrap(formatDescription)
        let expectedTimestamp = CMTime(value: 3, timescale: 30)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: expectedTimestamp, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                formatDescription: format,
                sampleTiming: &timing,
                sampleBufferOut: &sampleBuffer
            ),
            noErr
        )

        let frame = try XCTUnwrap(makeCameraFrame(from: XCTUnwrap(sampleBuffer), isMirrored: false))
        XCTAssertEqual(frame.timestamp, expectedTimestamp)
        XCTAssertEqual(frame.orientation, .up)
        XCTAssertFalse(frame.isMirrored)
        XCTAssertTrue(CVPixelBufferGetWidth(frame.pixelBuffer) == 8)
    }
}

@MainActor
private final class FakeCapturePermissionProvider: CameraAuthorizationProviding {
    private(set) var videoAuthorizationStatus: AVAuthorizationStatus
    private(set) var requestCount = 0

    init(status: AVAuthorizationStatus) {
        videoAuthorizationStatus = status
    }

    func requestVideoAccess(completion: @escaping @Sendable (Bool) -> Void) {
        requestCount += 1
        completion(videoAuthorizationStatus == .authorized)
    }
}

@MainActor
private final class FakeCameraCapturePipeline: CameraCapturePipeline {
    private var startCompletion: (@Sendable (Result<Void, CameraCaptureError>) -> Void)?
    private var stopCompletion: (@Sendable () -> Void)?
    private var frameHandler: ((CameraFrame) -> Void)?
    private var eventHandler: (@Sendable (CameraPipelineEvent) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var onStartCompletion: (() -> Void)?
    var onStopCompletion: (() -> Void)?

    func installHandlers(
        onFrame: @escaping (CameraFrame) -> Void,
        onEvent: @escaping @Sendable (CameraPipelineEvent) -> Void
    ) {
        frameHandler = onFrame
        eventHandler = onEvent
    }

    func start(completion: @escaping @Sendable (Result<Void, CameraCaptureError>) -> Void) {
        startCount += 1
        startCompletion = completion
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        stopCount += 1
        stopCompletion = completion
    }

    func completeStart(_ result: Result<Void, CameraCaptureError>) {
        startCompletion?(result)
        onStartCompletion?()
        startCompletion = nil
    }

    func completeStop() {
        stopCompletion?()
        onStopCompletion?()
        stopCompletion = nil
    }

    func emit(_ event: CameraPipelineEvent) {
        eventHandler?(event)
    }

    func emit(_ frame: CameraFrame) {
        frameHandler?(frame)
    }
}
