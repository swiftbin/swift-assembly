import Foundation

internal enum X86InstructionEncoder {
    /// Encode a single source-level instruction into its byte sequence.
    ///
    /// `pc` is the byte offset of this instruction within the program and is
    /// used by future label-relative encodings (jumps, RIP-relative loads).
    /// Phase 0 ignores it because the only encoded instruction is `nop`.
    static func encode(
        _ instruction: ParsedInstruction,
        pc: Int64,
        labels: [String: Int64]
    ) throws -> [UInt8] {
        let resolved = try X86Parser.parse(instruction)
        return try encode(resolved)
    }

    static func encode(_ instruction: X86.Instruction) throws -> [UInt8] {
        switch instruction {
        case .nop:
            return X86.FixedOpcode.nop
        }
    }
}
