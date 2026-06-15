import Foundation

internal enum X86InstructionFormatter {
    /// Render a decoded instruction as Intel-syntax text.
    static func format(_ instruction: X86.Instruction) -> String {
        switch instruction {
        case .zeroOperand(let kind):
            return kind.rawValue
        case .mov(let destination, let source):
            return formatMov(destination: destination, source: source)
        }
    }

    // MARK: - MOV

    private static func formatMov(destination: X86.Register, source: X86.MovSource) -> String {
        let dst = X86.RegisterTable.canonicalName(for: destination)
        let src = formatSource(source)
        return "mov \(dst), \(src)"
    }

    private static func formatSource(_ source: X86.MovSource) -> String {
        switch source {
        case .register(let register):
            return X86.RegisterTable.canonicalName(for: register)
        case .immediate(let value):
            return formatImmediate(value)
        }
    }

    /// Print an immediate as a signed decimal literal. The bit pattern is
    /// what matters for re-assembly; the parser accepts either form, and
    /// decimal keeps round-trip text compact for small values.
    private static func formatImmediate(_ value: Int64) -> String {
        String(value)
    }
}
