import Foundation

public enum X86Assembler {
    public enum Architecture: Equatable, Sendable {
        case x86_64
    }

    /// Assemble Intel-syntax source text into a flat byte sequence.
    ///
    /// x86 instructions are variable-length, so unlike `ARM64Assembler`
    /// the program image is built by appending each instruction's bytes
    /// to a single output buffer. Label-relative branches are resolved
    /// via a backpatch pass after the linear sweep — forward references
    /// emit a rel32 placeholder during the sweep, and the patch list is
    /// walked at the end to fill them in.
    public static func assemble(
        _ source: String,
        architecture: Architecture = .x86_64
    ) throws -> [UInt8] {
        let program = try SourceParser.program(source)
        var output: [UInt8] = []
        var labelOffsets: [String: Int64] = [:]
        var patches: [PendingPatch] = []

        for (index, instruction) in program.instructions.enumerated() {
            // Any labels that point at this instruction now have their
            // byte offset fixed; record them before encoding so a
            // backward self-reference in the very first instruction
            // would see the correct value.
            for (label, labelIndex) in program.labels where labelIndex == index {
                labelOffsets[label] = Int64(output.count)
            }

            let encoded = try X86InstructionEncoder.encode(
                instruction,
                pc: Int64(output.count),
                labels: labelOffsets
            )
            let base = output.count
            output.append(contentsOf: encoded.bytes)
            for patch in encoded.patches {
                patches.append(PendingPatch(
                    absoluteByteOffset: base + patch.byteOffset,
                    width: patch.width,
                    label: patch.label,
                    instructionEndAbsoluteOffset: base + patch.instructionEndOffset
                ))
            }
        }

        // A trailing label sitting at end-of-file points one past the
        // final instruction.
        for (label, labelIndex) in program.labels where labelIndex == program.instructions.count {
            labelOffsets[label] = Int64(output.count)
        }

        try applyPatches(patches, labels: labelOffsets, into: &output)
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
    /// strings.
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

    // MARK: - Internals

    private struct PendingPatch {
        var absoluteByteOffset: Int
        var width: Int
        var label: String
        var instructionEndAbsoluteOffset: Int
    }

    private static func applyPatches(
        _ patches: [PendingPatch],
        labels: [String: Int64],
        into output: inout [UInt8]
    ) throws {
        for patch in patches {
            guard let target = labels[patch.label] else {
                throw AssemblerError.labelNotFound(patch.label)
            }
            let delta = target - Int64(patch.instructionEndAbsoluteOffset)
            switch patch.width {
            case 1:
                guard delta >= -0x80 && delta <= 0x7F else {
                    throw AssemblerError.branchOutOfRange(
                        instruction: "rel8",
                        label: patch.label,
                        byteOffset: delta
                    )
                }
                output[patch.absoluteByteOffset] = UInt8(bitPattern: Int8(truncatingIfNeeded: delta))
            case 4:
                guard delta >= Int64(Int32.min) && delta <= Int64(Int32.max) else {
                    throw AssemblerError.branchOutOfRange(
                        instruction: "rel32",
                        label: patch.label,
                        byteOffset: delta
                    )
                }
                let value = UInt32(truncatingIfNeeded: delta)
                for i in 0..<4 {
                    output[patch.absoluteByteOffset + i] = UInt8(truncatingIfNeeded: value >> (i * 8))
                }
            default:
                throw AssemblerError.unsupportedOperand("internal: bad patch width \(patch.width)")
            }
        }
    }
}
