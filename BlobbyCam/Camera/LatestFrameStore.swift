import CoreMedia

protocol LatestFrameStore: Sendable {
    func replace(with frame: CameraFrame)
    func latest() -> CameraFrame?
    var latestTimestamp: CMTime? { get }
}

/// Thread-safe storage for exactly one current frame. Replacing the value releases
/// the store's strong reference to the previous pixel buffer after outstanding
/// readers finish using their own copied `CameraFrame` values.
final class InMemoryLatestFrameStore: LatestFrameStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedFrame: CameraFrame?

    func replace(with frame: CameraFrame) {
        lock.lock()
        storedFrame = frame
        lock.unlock()
    }

    func latest() -> CameraFrame? {
        lock.lock()
        defer { lock.unlock() }
        return storedFrame
    }

    var latestTimestamp: CMTime? {
        lock.lock()
        defer { lock.unlock() }
        return storedFrame?.timestamp
    }

    /// A small diagnostic for verifying that this store never retains a history.
    var retainedFrameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedFrame == nil ? 0 : 1
    }
}
