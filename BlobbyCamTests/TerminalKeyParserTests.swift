import Foundation
import XCTest
@testable import BlobbyCam

final class TerminalKeyParserTests: XCTestCase {
    func testArrowSequencesParseIncrementallyIncludingModifiers() {
        var parser = TerminalKeyParser()

        XCTAssertEqual(parser.consume([0x1B]), [])
        XCTAssertTrue(parser.hasPendingSequence)
        XCTAssertEqual(parser.consume([0x5B, 0x41]), [.up])
        XCTAssertEqual(parser.consume([0x1B, 0x5B, 0x42]), [.down])
        XCTAssertEqual(parser.consume([0x1B, 0x5B, 0x43]), [.right])
        XCTAssertEqual(parser.consume([0x1B, 0x5B, 0x44]), [.left])
        XCTAssertEqual(parser.consume([0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x44]), [.left])
        XCTAssertFalse(parser.hasPendingSequence)
    }

    func testEnterAndCtrlCMapToTypedKeys() {
        var parser = TerminalKeyParser()
        XCTAssertEqual(parser.consume([0x0D]), [.enter])
        XCTAssertEqual(parser.consume([0x0A]), [.enter])
        XCTAssertEqual(parser.consume([0x03]), [.quit])
    }

    func testStandaloneEscapeAndIncompleteControlSequencesTimeOutCleanly() {
        var parser = TerminalKeyParser()
        XCTAssertEqual(parser.consume([0x1B]), [])
        XCTAssertEqual(parser.flushTimedOutSequence(), [.escape])
        XCTAssertFalse(parser.hasPendingSequence)

        XCTAssertEqual(parser.consume([0x1B, 0x5B]), [])
        XCTAssertEqual(parser.flushTimedOutSequence(), [])
        XCTAssertFalse(parser.hasPendingSequence)

        XCTAssertEqual(parser.consume([0x1B, 0x5B, 0x41]), [.up])
    }

    func testEscapeFollowedByEnterEmitsBothKeys() {
        var parser = TerminalKeyParser()
        XCTAssertEqual(parser.consume([0x1B, 0x0D]), [.escape, .enter])
        XCTAssertFalse(parser.hasPendingSequence)
    }
}

final class TerminalSessionTests: XCTestCase {
    func testSessionRedrawsAndRestoresTerminalAfterCtrlC() throws {
        let io = FakeTerminalSessionIO()
        let session = TerminalSession(io: io)
        let quitDelivered = expectation(description: "Ctrl-C delivers quit")
        let keyLock = NSLock()
        var keys: [TerminalKey] = []

        try session.start(onKey: { key in
            keyLock.lock()
            keys.append(key)
            keyLock.unlock()
            if key == .quit { quitDelivered.fulfill() }
        })
        XCTAssertTrue(session.isRunning)
        try session.redraw("frame-for-tests")
        io.enqueue([0x1B, 0x5B, 0x41, 0x0D, 0x03])

        wait(for: [quitDelivered], timeout: 2)
        session.stop()

        keyLock.lock()
        let deliveredKeys = keys
        keyLock.unlock()
        XCTAssertEqual(deliveredKeys, [.up, .enter, .quit])
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(io.rawModeEntryCount, 1)
        XCTAssertEqual(io.restoreCount, 1)

        let output = io.writtenText
        XCTAssertTrue(output.contains("\u{001B}[?1049h"), "Session enters the alternate screen")
        XCTAssertTrue(output.contains("\u{001B}[?25l"), "Session hides the cursor")
        XCTAssertTrue(output.contains("frame-for-tests"), "Session draws the supplied frame")
        XCTAssertFalse(output.contains("\n") && !output.contains("\r\n"), "Raw-mode output must return to column zero after each line")
        XCTAssertTrue(output.contains("\u{001B}[?25h"), "Session restores the cursor")
        XCTAssertTrue(output.contains("\u{001B}[?1049l"), "Session exits the alternate screen")
    }

    func testMultilineRedrawUsesCarriageReturnLineFeedsInRawMode() throws {
        let io = FakeTerminalSessionIO()
        let session = TerminalSession(io: io)
        try session.start(onKey: { _ in })
        try session.redraw("first\nsecond\nthird")
        session.stop()
        XCTAssertTrue(io.writtenText.contains("first\r\nsecond\r\nthird"))
    }

    func testReadErrorRestoresTerminalAndNotifiesHandler() throws {
        let io = FakeTerminalSessionIO()
        io.failNextRead(with: .ioFailure("injected read failure"))
        let session = TerminalSession(io: io)
        let errorDelivered = expectation(description: "read error delivered")
        var receivedError: TerminalSessionError?

        try session.start(onKey: { _ in XCTFail("No key should be delivered") }, onError: { error in
            receivedError = error
            errorDelivered.fulfill()
        })

        wait(for: [errorDelivered], timeout: 2)
        session.stop()

        XCTAssertEqual(receivedError, .ioFailure("injected read failure"))
        XCTAssertEqual(io.rawModeEntryCount, 1)
        XCTAssertEqual(io.restoreCount, 1)
        XCTAssertTrue(io.writtenText.contains("\u{001B}[?1049l"))
    }

    func testStartRequiresTTYAndDoesNotChangeTerminalWhenAbsent() {
        let io = FakeTerminalSessionIO(isTTY: false)
        let session = TerminalSession(io: io)

        XCTAssertThrowsError(try session.start(onKey: { _ in })) { error in
            XCTAssertEqual(error as? TerminalSessionError, .requiresTTY)
        }
        XCTAssertEqual(io.rawModeEntryCount, 0)
        XCTAssertEqual(io.restoreCount, 0)
        XCTAssertTrue(io.writtenText.isEmpty)
    }

    func testStopIsIdempotentAndRedrawRequiresRunningSession() throws {
        let io = FakeTerminalSessionIO()
        let session = TerminalSession(io: io)

        XCTAssertThrowsError(try session.redraw("no session")) { error in
            XCTAssertEqual(error as? TerminalSessionError, .notRunning)
        }
        try session.start(onKey: { _ in })
        session.stop()
        session.stop()

        XCTAssertEqual(io.rawModeEntryCount, 1)
        XCTAssertEqual(io.restoreCount, 1)
        XCTAssertThrowsError(try session.redraw("after stop")) { error in
            XCTAssertEqual(error as? TerminalSessionError, .notRunning)
        }
        XCTAssertThrowsError(try session.start(onKey: { _ in })) { error in
            XCTAssertEqual(error as? TerminalSessionError, .alreadyStarted)
        }
    }

    func testRedrawWriteFailureStopsAndRestoresTheTerminal() throws {
        let io = FakeTerminalSessionIO()
        let session = TerminalSession(io: io)
        try session.start(onKey: { _ in })
        io.failNextWrite(with: .ioFailure("injected redraw failure"))

        XCTAssertThrowsError(try session.redraw("frame that cannot be written")) { error in
            XCTAssertEqual(error as? TerminalSessionError, .ioFailure("injected redraw failure"))
        }
        session.stop()

        XCTAssertEqual(io.rawModeEntryCount, 1)
        XCTAssertEqual(io.restoreCount, 1)
        XCTAssertTrue(io.writtenText.contains("\u{001B}[?25h"))
        XCTAssertTrue(io.writtenText.contains("\u{001B}[?1049l"))
    }
}

private final class FakeTerminalSessionIO: TerminalSessionIO {
    private enum ReadItem {
        case bytes([UInt8])
        case failure(TerminalSessionError)
    }

    private let condition = NSCondition()
    private let tty: Bool
    private var pendingReads: [ReadItem] = []
    private var output = ""
    private var rawEntries = 0
    private var restores = 0
    private var nextWriteFailure: TerminalSessionError?

    init(isTTY: Bool = true) {
        tty = isTTY
    }

    var isTTY: Bool { tty }

    var rawModeEntryCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return rawEntries
    }

    var restoreCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return restores
    }

    var writtenText: String {
        condition.lock()
        defer { condition.unlock() }
        return output
    }

    func enterRawMode() throws {
        condition.lock()
        rawEntries += 1
        condition.unlock()
    }

    func restoreTerminalMode() throws {
        condition.lock()
        restores += 1
        condition.unlock()
    }

    func read(timeout: TimeInterval) throws -> TerminalReadResult {
        condition.lock()
        defer { condition.unlock() }
        if pendingReads.isEmpty {
            _ = condition.wait(until: Date(timeIntervalSinceNow: timeout))
        }
        guard !pendingReads.isEmpty else { return .timedOut }
        switch pendingReads.removeFirst() {
        case let .bytes(bytes): return .bytes(bytes)
        case let .failure(error): throw error
        }
    }

    func write(_ text: String) throws {
        condition.lock()
        if let error = nextWriteFailure {
            nextWriteFailure = nil
            condition.unlock()
            throw error
        }
        output.append(text)
        condition.unlock()
    }

    func enqueue(_ bytes: [UInt8]) {
        condition.lock()
        pendingReads.append(.bytes(bytes))
        condition.signal()
        condition.unlock()
    }

    func failNextRead(with error: TerminalSessionError) {
        condition.lock()
        pendingReads.append(.failure(error))
        condition.signal()
        condition.unlock()
    }

    func failNextWrite(with error: TerminalSessionError) {
        condition.lock()
        nextWriteFailure = error
        condition.unlock()
    }
}
