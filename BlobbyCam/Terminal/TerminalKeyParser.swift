import Foundation

/// Converts terminal bytes into menu keys without assuming a read contains a full key sequence.
struct TerminalKeyParser {
    private enum State {
        case ground
        case escape
        case controlSequence
    }

    private var state: State = .ground

    var hasPendingSequence: Bool { state != .ground }

    mutating func consume(_ bytes: [UInt8]) -> [TerminalKey] {
        var keys: [TerminalKey] = []
        for byte in bytes {
            switch state {
            case .ground:
                consumeGroundByte(byte, into: &keys)
            case .escape:
                if byte == 0x5B { // '[' starts a CSI sequence.
                    state = .controlSequence
                } else if byte == 0x1B {
                    keys.append(.escape)
                    state = .escape
                } else {
                    state = .ground
                    keys.append(.escape)
                    consumeGroundByte(byte, into: &keys)
                }
            case .controlSequence:
                if byte == 0x03 {
                    state = .ground
                    keys.append(.quit)
                } else if byte == 0x1B {
                    state = .escape
                } else if (0x40...0x7E).contains(byte) {
                    state = .ground
                    switch byte {
                    case 0x41: keys.append(.up)    // A
                    case 0x42: keys.append(.down)  // B
                    case 0x43: keys.append(.right) // C
                    case 0x44: keys.append(.left)  // D
                    default: break // Ignore other CSI keys, such as function keys.
                    }
                } else if byte < 0x20 || byte > 0x3F {
                    state = .ground
                    consumeGroundByte(byte, into: &keys)
                }
            }
        }
        return keys
    }

    /// Call after the escape-key ambiguity timeout. Incomplete CSI sequences are discarded.
    mutating func flushTimedOutSequence() -> [TerminalKey] {
        let shouldEmitEscape: Bool
        switch state {
        case .ground:
            shouldEmitEscape = false
        case .escape:
            shouldEmitEscape = true
        case .controlSequence:
            shouldEmitEscape = false
        }
        state = .ground
        return shouldEmitEscape ? [.escape] : []
    }

    private mutating func consumeGroundByte(_ byte: UInt8, into keys: inout [TerminalKey]) {
        switch byte {
        case 0x1B:
            state = .escape
        case 0x03:
            keys.append(.quit)
        case 0x0D, 0x0A:
            keys.append(.enter)
        default:
            break
        }
    }
}
