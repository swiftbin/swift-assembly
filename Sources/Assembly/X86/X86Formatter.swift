import Foundation

internal enum X86InstructionFormatter {
    /// Render a decoded instruction as Intel-syntax text.
    static func format(_ instruction: X86.Instruction) -> String {
        switch instruction {
        case .zeroOperand(let kind):
            return kind.rawValue
        case .mov(let destination, let source):
            return "mov \(formatDestination(destination)), \(formatSource(source))"
        }
    }

    // MARK: - Operands

    private static func formatDestination(_ destination: X86.MovDestination) -> String {
        switch destination {
        case .register(let register):
            return X86.RegisterTable.canonicalName(for: register)
        case .memory(let memory, _):
            return formatMemory(memory)
        }
    }

    private static func formatSource(_ source: X86.MovSource) -> String {
        switch source {
        case .register(let register):
            return X86.RegisterTable.canonicalName(for: register)
        case .memory(let memory, _):
            return formatMemory(memory)
        case .immediate(let value):
            return String(value)
        }
    }

    /// Render a memory operand in canonical Intel syntax:
    /// `[base + index*scale + disp]`, with terms omitted when absent and
    /// the displacement printed as a signed decimal so positive vs.
    /// negative is visible at a glance.
    private static func formatMemory(_ memory: X86.MemoryOperand) -> String {
        var parts: [String] = []
        if memory.ripRelative {
            parts.append("rip")
        } else if let base = memory.base {
            parts.append(X86.RegisterTable.canonicalName(for: base))
        }
        if let index = memory.index {
            let name = X86.RegisterTable.canonicalName(for: index)
            parts.append(memory.scale == 1 ? name : "\(name)*\(memory.scale)")
        }

        let body: String
        if parts.isEmpty {
            // `[disp32]` absolute form. Always show the displacement.
            body = String(memory.displacement)
        } else {
            body = parts.joined(separator: " + ")
        }

        if memory.displacement == 0 && !parts.isEmpty {
            return "[\(body)]"
        }
        if parts.isEmpty {
            return "[\(body)]"
        }
        // Non-zero displacement combined with at least one register term.
        if memory.displacement >= 0 {
            return "[\(body) + \(memory.displacement)]"
        } else {
            return "[\(body) - \(-memory.displacement)]"
        }
    }
}
