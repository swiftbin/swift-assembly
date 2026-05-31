import Foundation

public enum ARM64Assembler {
    public enum Architecture: Equatable, Sendable {
        case arm64
        case arm64e
    }

    public static func assemble(_ source: String, architecture: Architecture = .arm64, endianness: Endianness = .little) throws -> [UInt8] {
        let words = try assembleWords(source, architecture: architecture)
        return words.flatMap { word in
            switch endianness {
            case .little:
                return [
                    UInt8(truncatingIfNeeded: word),
                    UInt8(truncatingIfNeeded: word >> 8),
                    UInt8(truncatingIfNeeded: word >> 16),
                    UInt8(truncatingIfNeeded: word >> 24),
                ]
            case .big:
                return [
                    UInt8(truncatingIfNeeded: word >> 24),
                    UInt8(truncatingIfNeeded: word >> 16),
                    UInt8(truncatingIfNeeded: word >> 8),
                    UInt8(truncatingIfNeeded: word),
                ]
            }
        }
    }

    public static func assembleWords(_ source: String, architecture: Architecture = .arm64) throws -> [UInt32] {
        let program = try SourceParser.program(source)
        return try program.instructions.enumerated().map { index, instruction in
            try encode(instruction, pc: Int64(index * 4), labels: program.labels, architecture: architecture)
        }
    }

    public static func assembleWord(_ instruction: String, architecture: Architecture = .arm64) throws -> UInt32 {
        let words = try assembleWords(instruction, architecture: architecture)
        guard words.count == 1 else {
            throw AssemblerError.invalidOperandCount(instruction: instruction, expected: "exactly one instruction", actual: words.count)
        }
        return words[0]
    }

    public static func disassemble(_ bytes: [UInt8], endianness: Endianness = .little) throws -> String {
        guard bytes.count.isMultiple(of: 4) else { throw AssemblerError.invalidByteCount(bytes.count) }
        var words: [UInt32] = []
        words.reserveCapacity(bytes.count / 4)

        for index in stride(from: 0, to: bytes.count, by: 4) {
            let word: UInt32
            switch endianness {
            case .little:
                word = UInt32(bytes[index])
                | (UInt32(bytes[index + 1]) << 8)
                | (UInt32(bytes[index + 2]) << 16)
                | (UInt32(bytes[index + 3]) << 24)
            case .big:
                word = (UInt32(bytes[index]) << 24)
                | (UInt32(bytes[index + 1]) << 16)
                | (UInt32(bytes[index + 2]) << 8)
                | UInt32(bytes[index + 3])
            }
            words.append(word)
        }

        return try disassembleWords(words).joined(separator: "\n")
    }

    public static func disassembleWords(_ words: [UInt32]) throws -> [String] {
        try words.map(disassembleWord)
    }

    public static func disassembleWord(_ word: UInt32) throws -> String {
        try A64InstructionFormatter.format(A64InstructionDecoder.decode(word))
    }
}

