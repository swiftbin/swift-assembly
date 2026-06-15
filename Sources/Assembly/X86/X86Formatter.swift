import Foundation

internal enum X86InstructionFormatter {
    /// Render a decoded instruction as Intel-syntax text.
    static func format(_ instruction: X86.Instruction) -> String {
        switch instruction {
        case .zeroOperand(let kind):
            return kind.rawValue
        case .mov(let destination, let source):
            return formatReadWrite(mnemonic: "mov", destination: destination, source: source)
        case .binaryAlu(let kind, let destination, let source):
            return formatReadWrite(mnemonic: kind.rawValue, destination: destination, source: source)
        case .unaryAlu(let kind, let target):
            return "\(kind.rawValue) \(formatStandaloneTarget(target))"
        case .test(let left, let right):
            return formatReadWrite(mnemonic: "test", destination: left, source: right)
        case .shift(let kind, let target, let count):
            return "\(kind.rawValue) \(formatStandaloneTarget(target)), \(formatShiftCount(count))"
        case .doubleShift(let kind, let target, let source, let count):
            // The source register supplies the width, so the memory target
            // doesn't need an explicit size hint.
            let dst = formatPairedTarget(target)
            let src = X86.RegisterTable.canonicalName(for: source)
            return "\(kind.rawValue) \(dst), \(src), \(formatShiftCount(count))"
        }
    }

    private static func formatPairedTarget(_ target: X86.RegisterOrMemory) -> String {
        switch target {
        case .register(let r): return X86.RegisterTable.canonicalName(for: r)
        case .memory(let m, _): return formatMemory(m)
        }
    }

    private static func formatShiftCount(_ count: X86.ShiftCount) -> String {
        switch count {
        case .one: return "1"
        case .cl: return "cl"
        case .immediate(let n): return String(n)
        }
    }

    /// Render a single-operand target. When the target is memory the width
    /// would otherwise be unknown, so a size hint is always prepended.
    private static func formatStandaloneTarget(_ target: X86.RegisterOrMemory) -> String {
        switch target {
        case .register(let r):
            return X86.RegisterTable.canonicalName(for: r)
        case .memory(let m, let w):
            return "\(sizeHintPrefix(w)) \(formatMemory(m))"
        }
    }

    /// Render a 2-operand "destination, source" line, prefixing the
    /// destination with a `byte ptr` / ... size hint when the source is
    /// an immediate and the destination is memory.
    private static func formatReadWrite(mnemonic: String, destination: X86.RegisterOrMemory, source: X86.Operand) -> String {
        let dst = formatDestination(destination, sizeHintWhenImmediate: source)
        return "\(mnemonic) \(dst), \(formatSource(source))"
    }

    // MARK: - Operands

    /// Render a destination operand. When `sizeHintWhenImmediate` is an
    /// `.immediate` and the destination is memory, the rendering is
    /// prefixed with `byte ptr` / `word ptr` / `dword ptr` / `qword ptr`
    /// so the width is unambiguous on re-assembly.
    static func formatDestination(_ destination: X86.RegisterOrMemory, sizeHintWhenImmediate source: X86.Operand?) -> String {
        switch destination {
        case .register(let register):
            return X86.RegisterTable.canonicalName(for: register)
        case .memory(let memory, let width):
            if case .immediate = source {
                return "\(sizeHintPrefix(width)) \(formatMemory(memory))"
            }
            return formatMemory(memory)
        }
    }

    static func formatSource(_ source: X86.Operand) -> String {
        switch source {
        case .register(let register):
            return X86.RegisterTable.canonicalName(for: register)
        case .memory(let memory, _):
            return formatMemory(memory)
        case .immediate(let value):
            return String(value)
        }
    }

    static func sizeHintPrefix(_ width: X86.RegisterWidth) -> String {
        switch width {
        case .byte:  return "byte ptr"
        case .word:  return "word ptr"
        case .dword: return "dword ptr"
        case .qword: return "qword ptr"
        }
    }

    /// Render a memory operand in canonical Intel syntax:
    /// `[base + index*scale + disp]`, with terms omitted when absent and
    /// the displacement printed as a signed decimal so positive vs.
    /// negative is visible at a glance.
    static func formatMemory(_ memory: X86.MemoryOperand) -> String {
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
        if memory.displacement >= 0 {
            return "[\(body) + \(memory.displacement)]"
        } else {
            return "[\(body) - \(-memory.displacement)]"
        }
    }
}
