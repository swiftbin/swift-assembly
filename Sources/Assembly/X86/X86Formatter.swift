import Foundation

internal enum X86InstructionFormatter {
    /// Render a decoded instruction as Intel-syntax text (the canonical
    /// disassembly form used by the project).
    static func format(_ instruction: X86.Instruction) -> String {
        switch instruction {
        case .nop:
            return "nop"
        }
    }
}
