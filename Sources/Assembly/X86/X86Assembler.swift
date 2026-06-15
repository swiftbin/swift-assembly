import Foundation

public enum X86Assembler {
    public enum Architecture: Equatable, Sendable {
        case x86_64
    }

    /// Assemble Intel-syntax source text into a flat byte sequence.
    ///
    /// x86 instructions are variable-length, so unlike `ARM64Assembler.assemble`
    /// there is no fixed-size word slice — the returned array is the linear
    /// program image as it would appear in memory.
    public static func assemble(
        _ source: String,
        architecture: Architecture = .x86_64
    ) throws -> [UInt8] {
        let program = try SourceParser.program(source)
        var output: [UInt8] = []
        for instruction in program.instructions {
            let bytes = try X86InstructionEncoder.encode(
                instruction,
                pc: Int64(output.count),
                labels: program.labels
            )
            output.append(contentsOf: bytes)
        }
        return output
    }

    /// Assemble a single instruction line.
    public static func assembleInstruction(
        _ instruction: String,
        architecture: Architecture = .x86_64
    ) throws -> [UInt8] {
        try assemble(instruction, architecture: architecture)
    }

    /// Disassemble a byte sequence into one line per instruction.
    public static func disassemble(
        _ bytes: [UInt8],
        architecture: Architecture = .x86_64
    ) throws -> String {
        try disassembleInstructions(bytes, architecture: architecture).joined(separator: "\n")
    }

    /// Disassemble a byte sequence into a list of formatted instruction
    /// strings. The cursor advances by each decoded instruction's length;
    /// excess trailing bytes raise `unknownEncoding` on the offending byte.
    public static func disassembleInstructions(
        _ bytes: [UInt8],
        architecture: Architecture = .x86_64
    ) throws -> [String] {
        var lines: [String] = []
        var offset = 0
        while offset < bytes.count {
            let decoded = try X86InstructionDecoder.decode(bytes, offset: offset)
            lines.append(X86InstructionFormatter.format(decoded.instruction))
            offset += decoded.length
        }
        return lines
    }
}
