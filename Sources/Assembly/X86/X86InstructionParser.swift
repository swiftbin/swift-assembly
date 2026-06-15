import Foundation

internal enum X86Parser {
    /// Lower the parsed source line into an `X86.Instruction`.
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
        if instruction.mnemonic == "mov" {
            return try parseMov(instruction)
        }
        if let kind = X86.BinaryAluKind(rawValue: instruction.mnemonic) {
            let (dst, src) = try parseReadWritePair(instruction)
            return .binaryAlu(kind, destination: dst, source: src)
        }
        throw AssemblerError.unknownInstruction(instruction.mnemonic)
    }

    // MARK: - MOV

    /// One of the three operand shapes that can appear in a 2-operand
    /// instruction. Memory operands may carry an explicit size hint from
    /// the source (`byte ptr [...]`, `qword ptr [...]`, etc.); when none
    /// is present, the width is inferred from the paired register.
    enum ClassifiedOperand {
        case register(X86.Register)
        case memory(X86.MemoryOperand, explicitWidth: X86.RegisterWidth?)
        case immediate(Int64)
    }

    private static func parseMov(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        let (dst, src) = try parseReadWritePair(instruction)
        return .mov(destination: dst, source: src)
    }

    /// Classify and validate the two operands of any instruction whose
    /// destination is `r/m` and source is `r/m/imm`: MOV, the 8 binary
    /// ALU ops, and TEST share this shape. Width inference and the
    /// "mem,imm needs a size hint" rule live here in one place.
    static func parseReadWritePair(_ instruction: ParsedInstruction) throws -> (X86.RegisterOrMemory, X86.Operand) {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: instruction.mnemonic,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try classifyOperand(instruction.operands[0])
        let src = try classifyOperand(instruction.operands[1])
        let mnemonic = instruction.mnemonic

        switch (dst, src) {
        case (.register(let d), .register(let s)):
            try checkWidthsMatch(d.width, s.width, mnemonic: mnemonic)
            return (.register(d), .register(s))

        case (.register(let d), .memory(let m, let explicit)):
            let width = try resolveMemoryWidth(explicit: explicit, paired: d.width, mnemonic: mnemonic)
            return (.register(d), .memory(m, width: width))

        case (.register(let d), .immediate(let v)):
            try validateImmediateRange(v, width: d.width, mnemonic: mnemonic)
            return (.register(d), .immediate(v))

        case (.memory(let m, let explicit), .register(let s)):
            let width = try resolveMemoryWidth(explicit: explicit, paired: s.width, mnemonic: mnemonic)
            return (.memory(m, width: width), .register(s))

        case (.memory(let m, let explicit), .immediate(let v)):
            guard let width = explicit else {
                throw AssemblerError.unsupportedOperand(
                    "\(mnemonic) mem, imm requires an explicit size hint (e.g. `qword ptr [...]`)"
                )
            }
            try validateImmediateRange(v, width: width, mnemonic: mnemonic)
            return (.memory(m, width: width), .immediate(v))

        case (.memory, .memory):
            throw AssemblerError.unsupportedOperand("\(mnemonic): cannot have two memory operands")

        case (.immediate, _):
            throw AssemblerError.unsupportedOperand("\(mnemonic): destination cannot be an immediate")
        }
    }

    /// Classify a single operand string. Recognises bracketed memory
    /// expressions (optionally prefixed by a size hint), registers, and
    /// numeric immediates.
    static func classifyOperand(_ text: String) throws -> ClassifiedOperand {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (width, memoryText) = stripSizeHint(trimmed) {
            return .memory(try memoryOperand(memoryText), explicitWidth: width)
        }
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed), explicitWidth: nil)
        }
        if let register = try? register(trimmed) {
            return .register(register)
        }
        let immediate = try immediateAny(trimmed)
        return .immediate(immediate)
    }

    /// Detect and strip a leading size hint such as `byte ptr` or `qword`.
    /// Returns `nil` if no recognised hint is present.
    private static func stripSizeHint(_ text: String) -> (width: X86.RegisterWidth, rest: String)? {
        let lower = text.lowercased()
        let hints: [(prefix: String, width: X86.RegisterWidth)] = [
            ("byte ptr",  .byte),
            ("word ptr",  .word),
            ("dword ptr", .dword),
            ("qword ptr", .qword),
            ("byte",  .byte),
            ("word",  .word),
            ("dword", .dword),
            ("qword", .qword),
        ]
        for (prefix, width) in hints {
            guard lower.hasPrefix(prefix) else { continue }
            let prefixEnd = text.index(text.startIndex, offsetBy: prefix.count)
            // The hint must be followed by whitespace and then a `[...]` body.
            guard prefixEnd < text.endIndex, text[prefixEnd].isWhitespace else { continue }
            let rest = text[prefixEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.hasPrefix("[") { return (width, rest) }
        }
        return nil
    }

    private static func checkWidthsMatch(_ a: X86.RegisterWidth, _ b: X86.RegisterWidth, mnemonic: String) throws {
        guard a == b else {
            throw AssemblerError.unsupportedOperand(
                "\(mnemonic) requires matching operand widths"
            )
        }
    }

    /// Reconcile an optional size hint with the width implied by a paired
    /// register. When both are present they must agree.
    private static func resolveMemoryWidth(
        explicit: X86.RegisterWidth?,
        paired: X86.RegisterWidth,
        mnemonic: String
    ) throws -> X86.RegisterWidth {
        if let explicit, explicit != paired {
            throw AssemblerError.unsupportedOperand(
                "\(mnemonic): size hint disagrees with register width"
            )
        }
        return explicit ?? paired
    }

    // MARK: - Operand parsing

    static func register(_ text: String) throws -> X86.Register {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let register = X86.RegisterTable.lookup[key] {
            return register
        }
        throw AssemblerError.invalidRegister(text)
    }

    static func immediateAny(_ text: String) throws -> Int64 {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") { value.removeFirst() }
        value = value.replacingOccurrences(of: "_", with: "")
        let negative: Bool
        if value.hasPrefix("-") { negative = true; value.removeFirst() }
        else if value.hasPrefix("+") { negative = false; value.removeFirst() }
        else { negative = false }
        guard !value.isEmpty else { throw AssemblerError.invalidImmediate(text) }
        let radix: Int
        if value.hasPrefix("0x") { radix = 16; value.removeFirst(2) }
        else if value.hasPrefix("0b") { radix = 2; value.removeFirst(2) }
        else { radix = 10 }
        guard let magnitude = UInt64(value, radix: radix) else {
            throw AssemblerError.invalidImmediate(text)
        }
        if negative {
            guard magnitude <= (UInt64(Int64.max) + 1) else {
                throw AssemblerError.invalidImmediate(text)
            }
            return Int64(bitPattern: 0 &- magnitude)
        }
        return Int64(bitPattern: magnitude)
    }

    static func validateImmediateRange(_ value: Int64, width: X86.RegisterWidth, mnemonic: String) throws {
        switch width {
        case .byte:
            guard value >= -0x80 && value <= 0xFF else {
                throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: value, range: -0x80...0xFF)
            }
        case .word:
            guard value >= -0x8000 && value <= 0xFFFF else {
                throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: value, range: -0x8000...0xFFFF)
            }
        case .dword:
            guard value >= -0x8000_0000 && value <= 0xFFFF_FFFF else {
                throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: value, range: -0x8000_0000...0xFFFF_FFFF)
            }
        case .qword:
            break
        }
    }

    // MARK: - Memory operand parsing

    /// Parse a bracketed Intel-syntax memory expression, e.g. `[rax]`,
    /// `[rax + 8]`, `[rax + rbx*4 + 0x10]`, `[rip + 0x100]`, `[0x1000]`.
    /// Only 64-bit base/index registers are accepted; the 32-bit address
    /// form (`[esi+...]` with the 0x67 override) is deferred.
    static func memoryOperand(_ text: String) throws -> X86.MemoryOperand {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            throw AssemblerError.invalidMemoryOperand(text)
        }
        let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty else { throw AssemblerError.invalidMemoryOperand(text) }

        var base: X86.Register? = nil
        var index: X86.Register? = nil
        var scale: UInt8 = 1
        var displacement: Int64 = 0
        var ripRelative = false

        for (sign, atom) in splitAtomsBySign(inner) {
            let term = atom.trimmingCharacters(in: .whitespacesAndNewlines)
            if term.isEmpty { throw AssemblerError.invalidMemoryOperand(text) }

            // `reg * scale` or `scale * reg`
            if term.contains("*") {
                guard sign == 1 else { throw AssemblerError.invalidMemoryOperand(text) }
                guard index == nil else {
                    throw AssemblerError.invalidMemoryOperand("\(text): too many scaled index terms")
                }
                let (reg, factor) = try parseScaledTerm(term, original: text)
                guard reg.width == .qword else {
                    throw AssemblerError.invalidMemoryOperand("\(text): index must be 64-bit")
                }
                guard reg.number != 4 else {
                    throw AssemblerError.invalidMemoryOperand("\(text): rsp cannot be used as an index")
                }
                index = reg
                scale = factor
                continue
            }

            // Bare `rip` for RIP-relative addressing.
            if term.lowercased() == "rip" {
                guard sign == 1, base == nil, index == nil, !ripRelative else {
                    throw AssemblerError.invalidMemoryOperand(text)
                }
                ripRelative = true
                continue
            }

            // Bare register: base if absent, otherwise index with scale 1.
            if let reg = try? register(term) {
                guard sign == 1 else { throw AssemblerError.invalidMemoryOperand(text) }
                guard reg.width == .qword else {
                    throw AssemblerError.invalidMemoryOperand("\(text): base/index must be 64-bit")
                }
                if base == nil {
                    base = reg
                } else if index == nil {
                    guard reg.number != 4 else {
                        throw AssemblerError.invalidMemoryOperand("\(text): rsp cannot be used as an index")
                    }
                    index = reg
                    scale = 1
                } else {
                    throw AssemblerError.invalidMemoryOperand("\(text): too many registers")
                }
                continue
            }

            // Otherwise, displacement.
            let value = try immediateAny(term)
            displacement &+= sign * value
        }

        if ripRelative && (base != nil || index != nil) {
            throw AssemblerError.invalidMemoryOperand("\(text): rip cannot combine with base/index")
        }

        return X86.MemoryOperand(
            base: base,
            index: index,
            scale: scale,
            displacement: displacement,
            ripRelative: ripRelative
        )
    }

    /// Split an inner address expression into signed atoms. Each atom is a
    /// register, `reg*scale`, or an integer literal; `+`/`-` between atoms
    /// applies to the immediate value (signs against registers raise an
    /// error during atom interpretation).
    private static func splitAtomsBySign(_ text: String) -> [(sign: Int64, atom: String)] {
        var result: [(Int64, String)] = []
        var current = ""
        var sign: Int64 = 1
        for ch in text {
            if ch == "+" || ch == "-" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result.append((sign, trimmed))
                    current = ""
                    sign = (ch == "-") ? -1 : 1
                } else if ch == "-" {
                    // Leading or consecutive `-`: flip sign of the next atom.
                    sign = -sign
                }
                continue
            }
            current.append(ch)
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { result.append((sign, trimmed)) }
        return result
    }

    private static func parseScaledTerm(_ term: String, original: String) throws -> (register: X86.Register, scale: UInt8) {
        let parts = term.split(separator: "*", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2 else { throw AssemblerError.invalidMemoryOperand(original) }
        // Either `reg * scale` or `scale * reg`.
        let (regText, scaleText): (String, String)
        if let _ = try? register(parts[0]) {
            (regText, scaleText) = (parts[0], parts[1])
        } else if let _ = try? register(parts[1]) {
            (regText, scaleText) = (parts[1], parts[0])
        } else {
            throw AssemblerError.invalidMemoryOperand(original)
        }
        let reg = try register(regText)
        let scale = try immediateAny(scaleText)
        guard scale == 1 || scale == 2 || scale == 4 || scale == 8 else {
            throw AssemblerError.invalidMemoryOperand("\(original): scale must be 1, 2, 4, or 8")
        }
        return (reg, UInt8(scale))
    }
}
