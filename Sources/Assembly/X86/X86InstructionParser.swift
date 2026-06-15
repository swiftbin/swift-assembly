import Foundation

internal enum X86Parser {
    /// Lower the parsed source line into an `X86.Instruction`.
    ///
    /// The mnemonic table is consulted first; surface-level aliases
    /// (`fwait`/`xlat`) are folded onto their canonical `ZeroOperandKind`
    /// inside `ZeroOperandKind.resolve` so the rest of the pipeline sees a
    /// single representative. Mnemonics outside the implemented families
    /// raise `unknownInstruction`.
    static func parse(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        if let kind = X86.ZeroOperandKind.resolve(mnemonic: instruction.mnemonic) {
            guard instruction.operands.isEmpty else {
                throw AssemblerError.invalidOperandCount(
                    instruction: instruction.mnemonic,
                    expected: "no operands",
                    actual: instruction.operands.count
                )
            }
            return .zeroOperand(kind)
        }
        throw AssemblerError.unknownInstruction(instruction.mnemonic)
    }
}
