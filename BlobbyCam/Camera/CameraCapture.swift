import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import ImageIO

enum CameraCaptureError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case permissionRestricted
    case permissionUndetermined
    case noCameraAvailable
    case cannotCreateInput(String)
    case cannotAddInput
    case cannotAddOutput
    case sessionStartFailed
    case runtimeError(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access was denied. Allow access in System Settings to start the camera."
        case .permissionRestricted:
            return "Camera access is restricted on this Mac."
        case .permissionUndetermined:
            return "Camera permission has not been resolved."
        case .noCameraAvailable:
            return "No video capture device is currently available."
        case let .cannotCreateInput(message), let .runtimeError(message):
            return message
        case .cannotAddInput:
            return "The camera input could not be added to the capture session."
        case .cannotAddOutput:
            return "The video output could not be added to the capture session."
        case .sessionStartFailed:
            return "The camera capture session did not start."
        }
    }
}

enum CameraCaptureState: Equatable {
    case stopped
    case requestingPermission
    case starting
    case running
    case interrupted
    case stopping
    case failed(CameraCaptureError)
}

enum CameraPipelineEvent: Equatable, Sendable {
    case running
    case interrupted
    case failed(CameraCaptureError)
}

@MainActor
protocol CameraCapturePipeline: AnyObject {
    func installHandlers(
        onFrame: @escaping (CameraFrame) -> Void,
        onEvent: @escaping @Sendable (CameraPipelineEvent) -> Void
    )
    func start(completion: @escaping @Sendable (Result<Void, CameraCaptureError>) -> Void)
    func stop(completion: @escaping @Sendable () -> Void)
}

@MainActor
final class CameraCapture: ObservableObject {
    @Published private(set) var state: CameraCaptureState = .stopped
    @Published private(set) var lastError: CameraCaptureError?

    private let permission: CameraPermission
    private let pipeline: CameraCapturePipeline
    private var wantsRunning = false
    private var startGeneration = 0

    convenience init(
        onFrame: @escaping (CameraFrame) -> Void = { _ in },
        frameStore: LatestFrameStore = InMemoryLatestFrameStore()
    ) {
        self.init(
            permission: CameraPermission(),
            pipeline: AVCaptureCameraPipeline(),
            frameStore: frameStore,
            onFrame: onFrame
        )
    }

    init(
        permission: CameraPermission,
        pipeline: CameraCapturePipeline,
        frameStore: LatestFrameStore = InMemoryLatestFrameStore(),
        onFrame: @escaping (CameraFrame) -> Void = { _ in }
    ) {
        self.permission = permission
        self.pipeline = pipeline
        pipeline.installHandlers(
            onFrame: { frame in
                frameStore.replace(with: frame)
                onFrame(frame)
            },
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
        )
    }

    func start() {
        if wantsRunning {
            if case .failed = state {
                startPipeline(generation: startGeneration)
            }
            return
        }

        wantsRunning = true
        startGeneration &+= 1
        let generation = startGeneration
        lastError = nil
        state = .requestingPermission

        permission.requestAccessIfNeeded { [weak self] permissionStatus in
            guard let self, self.wantsRunning, self.startGeneration == generation else { return }
            guard permissionStatus.allowsCapture else {
                let error: CameraCaptureError
                switch permissionStatus {
                case .denied:
                    error = .permissionDenied
                case .restricted:
                    error = .permissionRestricted
                case .notDetermined:
                    error = .permissionUndetermined
                case .authorized:
                    return
                }
                self.wantsRunning = false
                self.fail(error)
                return
            }

            self.startPipeline(generation: generation)
        }
    }

    func stop() {
        guard wantsRunning || state != .stopped && state != .stopping else { return }
        wantsRunning = false
        startGeneration &+= 1
        lastError = nil
        state = .stopping
        pipeline.stop { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.wantsRunning else { return }
                self.state = .stopped
            }
        }
    }

    private func startPipeline(generation: Int) {
        state = .starting
        pipeline.start { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.wantsRunning, self.startGeneration == generation else { return }
                switch result {
                case .success:
                    self.lastError = nil
                    self.state = .running
                case let .failure(error):
                    self.fail(error)
                }
            }
        }
    }

    private func handle(_ event: CameraPipelineEvent) {
        guard wantsRunning else { return }
        switch event {
        case .running:
            lastError = nil
            state = .running
        case .interrupted:
            state = .interrupted
        case let .failed(error):
            fail(error)
        }
    }

    private func fail(_ error: CameraCaptureError) {
        lastError = error
        state = .failed(error)
    }
}

@MainActor
private final class AVCaptureCameraPipeline: CameraCapturePipeline {
    private let worker = AVCaptureSessionWorker()

    func installHandlers(
        onFrame: @escaping (CameraFrame) -> Void,
        onEvent: @escaping @Sendable (CameraPipelineEvent) -> Void
    ) {
        worker.installHandlers(onFrame: onFrame, onEvent: onEvent)
    }

    func start(completion: @escaping @Sendable (Result<Void, CameraCaptureError>) -> Void) {
        worker.start(completion: completion)
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        worker.stop(completion: completion)
    }
}

private final class AVCaptureSessionWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.blobbycam.capture.session")
    private let sampleBufferQueue = DispatchQueue(label: "com.blobbycam.capture.video-output")
    private let callbackLock = NSLock()

    private var activeInput: AVCaptureDeviceInput?
    private var outputWasAdded = false
    private var wantsRunning = false
    private var frameDeliveryEnabled = false
    private var frameHandler: ((CameraFrame) -> Void)?
    private var eventHandler: (@Sendable (CameraPipelineEvent) -> Void)?
    private var notificationTokens: [NSObjectProtocol] = []

    override init() {
        super.init()
        observeCaptureLifecycle()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func installHandlers(
        onFrame: @escaping (CameraFrame) -> Void,
        onEvent: @escaping @Sendable (CameraPipelineEvent) -> Void
    ) {
        callbackLock.lock()
        frameHandler = onFrame
        eventHandler = onEvent
        callbackLock.unlock()
    }

    func start(completion: @escaping @Sendable (Result<Void, CameraCaptureError>) -> Void) {
        sessionQueue.async { [self] in
            wantsRunning = true
            do {
                try configureAndStart()
                completion(.success(()))
            } catch let error as CameraCaptureError {
                completion(.failure(error))
            } catch {
                completion(.failure(.runtimeError(error.localizedDescription)))
            }
        }
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        sessionQueue.async { [self] in
            wantsRunning = false
            setFrameDeliveryEnabled(false)
            if session.isRunning {
                session.stopRunning()
            }
            sampleBufferQueue.async(execute: completion)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isFrameDeliveryEnabled,
              let frame = makeCameraFrame(from: sampleBuffer, isMirrored: connection.isVideoMirrored)
        else { return }

        callbackLock.lock()
        let handler = frameHandler
        callbackLock.unlock()
        handler?(frame)
    }

    private func configureAndStart() throws {
        session.beginConfiguration()
        do {
            if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }

            try configureInputIfNeeded()
            try configureOutputIfNeeded()
            configureVideoConnection()
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            throw error
        }

        if !session.isRunning {
            session.startRunning()
        }
        guard session.isRunning else { throw CameraCaptureError.sessionStartFailed }
        setFrameDeliveryEnabled(true)
    }

    private func configureInputIfNeeded() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraCaptureError.noCameraAvailable
        }

        if let activeInput,
           activeInput.device.uniqueID == device.uniqueID,
           activeInput.device.isConnected,
           session.inputs.contains(where: { $0 === activeInput }) {
            return
        }

        if let activeInput {
            session.removeInput(activeInput)
            self.activeInput = nil
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraCaptureError.cannotCreateInput(error.localizedDescription)
        }
        guard session.canAddInput(input) else { throw CameraCaptureError.cannotAddInput }
        session.addInput(input)
        activeInput = input
    }

    private func configureOutputIfNeeded() throws {
        guard !outputWasAdded else { return }
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraCaptureError.cannotAddOutput }
        session.addOutput(videoOutput)
        outputWasAdded = true
    }

    private func configureVideoConnection() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    private func observeCaptureLifecycle() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in
                guard let self, self.wantsRunning else { return }
                self.setFrameDeliveryEnabled(false)
                self.emit(.interrupted)
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in self?.restartAfterInterruption() }
        })
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            self?.sessionQueue.async { [weak self] in self?.recoverFromRuntimeError(notification) }
        })
        notificationTokens.append(center.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.sessionQueue.async { [weak self] in self?.handleDeviceDisconnected(notification) }
        })
        notificationTokens.append(center.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in self?.restartAfterInterruption() }
        })
    }

    private func restartAfterInterruption() {
        guard wantsRunning else { return }
        do {
            try configureAndStart()
            emit(.running)
        } catch CameraCaptureError.noCameraAvailable {
            setFrameDeliveryEnabled(false)
            emit(.interrupted)
        } catch let error as CameraCaptureError {
            setFrameDeliveryEnabled(false)
            emit(.failed(error))
        } catch {
            setFrameDeliveryEnabled(false)
            emit(.failed(.runtimeError(error.localizedDescription)))
        }
    }

    private func recoverFromRuntimeError(_ notification: Notification) {
        guard wantsRunning else { return }
        setFrameDeliveryEnabled(false)
        emit(.interrupted)
        let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
            ?? "The camera capture session encountered a runtime error."
        do {
            try configureAndStart()
            emit(.running)
        } catch CameraCaptureError.noCameraAvailable {
            emit(.interrupted)
        } catch let error as CameraCaptureError {
            emit(.failed(error))
        } catch {
            emit(.failed(.runtimeError(message)))
        }
    }

    private func handleDeviceDisconnected(_ notification: Notification) {
        guard wantsRunning,
              let device = notification.object as? AVCaptureDevice,
              activeInput?.device.uniqueID == device.uniqueID
        else { return }
        setFrameDeliveryEnabled(false)
        emit(.interrupted)
    }

    private func emit(_ event: CameraPipelineEvent) {
        callbackLock.lock()
        let handler = eventHandler
        callbackLock.unlock()
        handler?(event)
    }

    private var isFrameDeliveryEnabled: Bool {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        return frameDeliveryEnabled
    }

    private func setFrameDeliveryEnabled(_ enabled: Bool) {
        callbackLock.lock()
        frameDeliveryEnabled = enabled
        callbackLock.unlock()
    }
}

func makeCameraFrame(from sampleBuffer: CMSampleBuffer, isMirrored: Bool) -> CameraFrame? {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
    return CameraFrame(
        pixelBuffer: pixelBuffer,
        timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
        orientation: .up,
        isMirrored: isMirrored
    )
}
