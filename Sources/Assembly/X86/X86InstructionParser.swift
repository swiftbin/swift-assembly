import Foundation

internal enum X86Parser {
    /// Lower the parsed source line into an `X86.Instruction`.
    ///
    /// Phase 0 only recognises `nop`; any other mnemonic raises
    /// `unknownInstruction`. Subsequent phases will dispatch on the mnemonic
    /// to per-family parsers (analogous to the mnemonic switch inside
    /// `A64InstructionEncoder.encodeInstruction`).
    static func parse(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        switch instruction.mnemonic {
        case "nop":
            guard instruction.operands.isEmpty else {
                throw AssemblerError.invalidOperandCount(
                    instruction: "nop",
                    expected: "no operands",
                    actual: instruction.operands.count
                )
            }
            return .nop
        default:
            throw AssemblerError.unknownInstruction(instruction.mnemonic)
        }
    }
}
