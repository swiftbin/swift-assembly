import Foundation

internal enum X86InstructionFormatter {
    /// Render a decoded instruction as Intel-syntax text (the canonical
    /// disassembly form used by the project).
    ///
    /// Surface-level aliases (e.g. `fwait`, `xlat`) are *not* emitted: the
    /// formatter always returns the canonical mnemonic carried by the
    /// `Instruction` value, so a round-trip from raw bytes is deterministic.
    static func format(_ instruction: X86.Instruction) -> String {
        switch instruction {
        case .zeroOperand(let kind):
            return kind.rawValue
        }
    }
}
