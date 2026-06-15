import Foundation

internal enum X86InstructionEncoder {
    /// Encode a single source-level instruction into its byte sequence.
    ///
    /// `pc` is the byte offset of this instruction within the program and is
    /// used by future label-relative encodings (jumps, RIP-relative loads).
    /// The zero-operand family ignores it.
    static func encode(
        _ instruction: ParsedInstruction,
        pc: Int64,
        labels: [String: Int64]
    ) throws -> [UInt8] {
        let resolved = try X86Parser.parse(instruction)
        return encode(resolved)
    }

    static func encode(_ instruction: X86.Instruction) -> [UInt8] {
        switch instruction {
        case .zeroOperand(let kind):
            return kind.bytes
        }
    }
}
