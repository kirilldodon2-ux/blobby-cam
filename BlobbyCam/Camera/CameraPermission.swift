import AVFoundation

enum CameraPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    var allowsCapture: Bool {
        self == .authorized
    }

    static func map(_ status: AVAuthorizationStatus) -> CameraPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }
}

@MainActor
protocol CameraAuthorizationProviding {
    var videoAuthorizationStatus: AVAuthorizationStatus { get }
    func requestVideoAccess(completion: @escaping @Sendable (Bool) -> Void)
}

@MainActor
private struct SystemCameraAuthorizationProvider: CameraAuthorizationProviding {
    var videoAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestVideoAccess(completion: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }
}

@MainActor
final class CameraPermission {
    typealias Completion = @MainActor (CameraPermissionStatus) -> Void

    private let authorization: CameraAuthorizationProviding
    private var didRequestAccess = false
    private var requestPending = false
    private var pendingCompletions: [Completion] = []

    private(set) var status: CameraPermissionStatus

    init() {
        let authorization = SystemCameraAuthorizationProvider()
        self.authorization = authorization
        self.status = CameraPermissionStatus.map(authorization.videoAuthorizationStatus)
    }

    init(authorization: CameraAuthorizationProviding) {
        self.authorization = authorization
        self.status = CameraPermissionStatus.map(authorization.videoAuthorizationStatus)
    }

    func requestAccessIfNeeded(completion: @escaping Completion) {
        if requestPending {
            pendingCompletions.append(completion)
            return
        }

        let currentStatus = CameraPermissionStatus.map(authorization.videoAuthorizationStatus)
        if currentStatus != .notDetermined {
            status = currentStatus
            completion(currentStatus)
            return
        }

        guard !didRequestAccess else {
            completion(status)
            return
        }

        didRequestAccess = true
        requestPending = true
        pendingCompletions.append(completion)
        authorization.requestVideoAccess { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.finishRequest(granted: granted)
            }
        }
    }

    private func finishRequest(granted: Bool) {
        requestPending = false
        let currentStatus = CameraPermissionStatus.map(authorization.videoAuthorizationStatus)
        if currentStatus == .notDetermined {
            status = granted ? .authorized : .denied
        } else {
            status = currentStatus
        }

        let completions = pendingCompletions
        pendingCompletions.removeAll(keepingCapacity: false)
        completions.forEach { $0(status) }
    }
}
