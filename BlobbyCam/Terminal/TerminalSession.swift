import Darwin
import Foundation

enum TerminalReadResult: Equatable {
    case bytes([UInt8])
    case timedOut
    case endOfFile
}

protocol TerminalSessionIO: AnyObject {
    var isTTY: Bool { get }
    var terminalSize: (columns: Int, rows: Int) { get }
    func enterRawMode() throws
    func restoreTerminalMode() throws
    func read(timeout: TimeInterval) throws -> TerminalReadResult
    func write(_ text: String) throws
}

extension TerminalSessionIO {
    var terminalSize: (columns: Int, rows: Int) { (80, 24) }
}

enum TerminalSessionError: Error, Equatable, LocalizedError {
    case requiresTTY
    case alreadyStarted
    case notRunning
    case ioFailure(String)

    var errorDescription: String? {
        switch self {
        case .requiresTTY:
            "Terminal controls require an attached TTY for both input and output."
        case .alreadyStarted:
            "A TerminalSession can only be started once."
        case .notRunning:
            "The TerminalSession is not running."
        case let .ioFailure(message):
            message
        }
    }
}

/// Owns raw-mode input and terminal screen cleanup. Key callbacks run off the main thread.
final class TerminalSession {
    static let escapeTimeout: TimeInterval = 0.15
    static let idleReadTimeout: TimeInterval = 0.25

    private enum Lifecycle: Equatable {
        case idle
        case starting
        case running
        case stopping
        case stopped
    }

    private static let enterScreen = "\u{001B}[?1049h\u{001B}[?25l\u{001B}[2J\u{001B}[H"
    private static let restoreScreen = "\u{001B}[0m\u{001B}[?25h\u{001B}[?1049l"

    private let io: TerminalSessionIO
    private let lifecycleLock = NSLock()
    private let outputLock = NSLock()
    private let inputQueue = DispatchQueue(label: "com.blobbycam.terminal-input", qos: .userInteractive)
    private let inputQueueKey = DispatchSpecificKey<Bool>()
    private let finished = DispatchGroup()

    private var lifecycle: Lifecycle = .idle
    private var stopRequested = false
    private var onKey: ((TerminalKey) -> Void)?
    private var onError: ((TerminalSessionError) -> Void)?

    init(io: TerminalSessionIO = DarwinTerminalSessionIO()) {
        self.io = io
        inputQueue.setSpecific(key: inputQueueKey, value: true)
    }

    var isRunning: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return lifecycle == .running
    }

    var terminalSize: (columns: Int, rows: Int) { io.terminalSize }

    /// Starts the one local TTY session. `onKey` runs on the terminal input queue.
    func start(
        onKey: @escaping (TerminalKey) -> Void,
        onError: ((TerminalSessionError) -> Void)? = nil
    ) throws {
        lifecycleLock.lock()
        guard lifecycle == .idle else {
            lifecycleLock.unlock()
            throw TerminalSessionError.alreadyStarted
        }
        finished.enter()
        lifecycle = .starting
        lifecycleLock.unlock()

        guard io.isTTY else {
            markStoppedAndSignal()
            throw TerminalSessionError.requiresTTY
        }

        do {
            try io.enterRawMode()
        } catch {
            try? io.restoreTerminalMode()
            markStoppedAndSignal()
            throw normalize(error)
        }

        do {
            try writeTerminal(Self.enterScreen)
        } catch {
            try? writeTerminal(Self.restoreScreen)
            try? io.restoreTerminalMode()
            markStoppedAndSignal()
            throw normalize(error)
        }

        lifecycleLock.lock()
        self.onKey = onKey
        self.onError = onError
        let shouldStopImmediately = stopRequested
        lifecycle = shouldStopImmediately ? .stopping : .running
        lifecycleLock.unlock()

        inputQueue.async {
            self.readLoop()
        }
    }

    /// Redraws within the alternate screen. The supplied frame should be plain rendered menu text.
    func redraw(_ frame: String) throws {
        outputLock.lock()
        lifecycleLock.lock()
        let canDraw = lifecycle == .running
        lifecycleLock.unlock()
        guard canDraw else {
            outputLock.unlock()
            throw TerminalSessionError.notRunning
        }
        do {
            // cfmakeraw disables ONLCR: an LF alone does not return to column zero.
            try io.write("\u{001B}[H\u{001B}[2J" + frame.replacingOccurrences(of: "\n", with: "\r\n") + "\u{001B}[0m")
            outputLock.unlock()
        } catch {
            outputLock.unlock()
            stop()
            throw normalize(error)
        }
    }

    /// Requests cleanup and waits for raw mode, cursor, and alternate screen restoration.
    func stop() {
        lifecycleLock.lock()
        switch lifecycle {
        case .idle:
            lifecycle = .stopped
            lifecycleLock.unlock()
            return
        case .starting, .running:
            lifecycle = .stopping
            stopRequested = true
        case .stopping:
            stopRequested = true
        case .stopped:
            lifecycleLock.unlock()
            return
        }
        lifecycleLock.unlock()

        if DispatchQueue.getSpecific(key: inputQueueKey) != true {
            finished.wait()
        }
    }

    private func readLoop() {
        var parser = TerminalKeyParser()

        while !shouldStop {
            do {
                let timeout = parser.hasPendingSequence ? Self.escapeTimeout : Self.idleReadTimeout
                switch try io.read(timeout: timeout) {
                case let .bytes(bytes):
                    if !deliver(parser.consume(bytes)) { break }
                case .timedOut:
                    if !deliver(parser.flushTimedOutSequence()) { break }
                case .endOfFile:
                    _ = deliver([.quit])
                    _ = requestStop()
                    break
                }
            } catch {
                let shouldReport = requestStop()
                if shouldReport { onError?(normalize(error)) }
                break
            }
        }

        finish()
    }

    /// Returns false when quit or an external stop should end the loop.
    private func deliver(_ keys: [TerminalKey]) -> Bool {
        for key in keys {
            guard !shouldStop else { return false }
            onKey?(key)
            if key == .quit {
                _ = requestStop()
                return false
            }
        }
        return !shouldStop
    }

    private var shouldStop: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return stopRequested || lifecycle == .stopping || lifecycle == .stopped
    }

    /// Returns true only for the caller that initiated the transition to stopping.
    private func requestStop() -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard lifecycle != .stopping && lifecycle != .stopped else { return false }
        lifecycle = .stopping
        stopRequested = true
        return true
    }

    private func finish() {
        outputLock.lock()
        var cleanupError: TerminalSessionError?
        do {
            try io.write(Self.restoreScreen)
        } catch {
            cleanupError = normalize(error)
        }
        do {
            try io.restoreTerminalMode()
        } catch {
            if cleanupError == nil { cleanupError = normalize(error) }
        }
        outputLock.unlock()

        lifecycleLock.lock()
        lifecycle = .stopped
        let errorHandler = onError
        lifecycleLock.unlock()
        finished.leave()

        if let cleanupError { errorHandler?(cleanupError) }
    }

    private func writeTerminal(_ text: String) throws {
        outputLock.lock()
        defer { outputLock.unlock() }
        try io.write(text)
    }

    private func markStoppedAndSignal() {
        lifecycleLock.lock()
        lifecycle = .stopped
        lifecycleLock.unlock()
        finished.leave()
    }

    private func normalize(_ error: Error) -> TerminalSessionError {
        if let terminalError = error as? TerminalSessionError { return terminalError }
        return .ioFailure(String(describing: error))
    }
}

/// Production stdin/stdout adapter. Tests inject a fake TerminalSessionIO instead.
final class DarwinTerminalSessionIO: TerminalSessionIO {
    private let inputFD: Int32
    private let outputFD: Int32
    private var originalAttributes: termios?

    init(inputFD: Int32 = STDIN_FILENO, outputFD: Int32 = STDOUT_FILENO) {
        self.inputFD = inputFD
        self.outputFD = outputFD
    }

    var isTTY: Bool {
        isatty(inputFD) == 1 && isatty(outputFD) == 1
    }

    var terminalSize: (columns: Int, rows: Int) {
        var size = winsize()
        guard ioctl(outputFD, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 else {
            return (80, 24)
        }
        return (Int(size.ws_col), Int(size.ws_row))
    }

    func enterRawMode() throws {
        guard originalAttributes == nil else { return }
        var original = termios()
        guard tcgetattr(inputFD, &original) == 0 else { throw systemError("tcgetattr") }
        originalAttributes = original

        var raw = original
        cfmakeraw(&raw)
        withUnsafeMutableBytes(of: &raw.c_cc) { controlCharacters in
            // poll() supplies the timeout. Once readable, read() should wait for one byte
            // instead of returning 0 for an empty nonblocking-style read and looking like EOF.
            controlCharacters[Int(VMIN)] = 1
            controlCharacters[Int(VTIME)] = 0
        }
        guard tcsetattr(inputFD, TCSANOW, &raw) == 0 else { throw systemError("tcsetattr raw mode") }
    }

    func restoreTerminalMode() throws {
        guard var original = originalAttributes else { return }
        guard tcsetattr(inputFD, TCSANOW, &original) == 0 else { throw systemError("tcsetattr restore") }
        originalAttributes = nil
    }

    func read(timeout: TimeInterval) throws -> TerminalReadResult {
        var descriptor = pollfd(fd: inputFD, events: Int16(POLLIN), revents: 0)
        let milliseconds = Int32(min(max((timeout * 1_000).rounded(.up), 0), Double(Int32.max)))
        let pollResult = Darwin.poll(&descriptor, 1, milliseconds)
        if pollResult == 0 { return .timedOut }
        if pollResult < 0 {
            if errno == EINTR { return .timedOut }
            throw systemError("poll stdin")
        }

        if descriptor.revents & Int16(POLLIN) != 0 {
            var buffer = [UInt8](repeating: 0, count: 64)
            let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return Darwin.read(inputFD, baseAddress, rawBuffer.count)
            }
            if count > 0 { return .bytes(Array(buffer.prefix(count))) }
            if count == 0 {
                return descriptor.revents & Int16(POLLHUP) != 0 ? .endOfFile : .timedOut
            }
            if errno == EINTR || errno == EAGAIN { return .timedOut }
            throw systemError("read stdin")
        }
        if descriptor.revents & Int16(POLLHUP) != 0 { return .endOfFile }
        return .timedOut
    }

    func write(_ text: String) throws {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return Darwin.write(outputFD, baseAddress.advanced(by: offset), bytes.count - offset)
            }
            if written > 0 {
                offset += written
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                throw systemError("write stdout")
            }
        }
    }

    private func systemError(_ operation: String) -> TerminalSessionError {
        .ioFailure("\(operation): \(String(cString: strerror(errno)))")
    }
}
