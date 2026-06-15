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
        throw AssemblerError.unknownInstruction(instruction.mnemonic)
    }

    // MARK: - MOV

    /// One of the three operand shapes that can appear on the source side
    /// of MOV. The destination is restricted to register/memory in
    /// `parseMov` after both operands are classified.
    private enum AnyOperand {
        case register(X86.Register)
        case memory(X86.MemoryOperand)
        case immediate(Int64)
    }

    private static func parseMov(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "mov",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let dstParsed = try parseAnyOperand(instruction.operands[0], mnemonic: "mov")
        let srcParsed = try parseAnyOperand(instruction.operands[1], mnemonic: "mov")

        // Width inference: width comes from whichever operand is a register.
        // mem-mem and imm-mem (without an explicit size hint) are unsupported
        // in Phase 3; the latter belongs to Phase 4.
        switch (dstParsed, srcParsed) {
        case (.register(let d), .register(let s)):
            guard d.width == s.width else {
                throw AssemblerError.unsupportedOperand(
                    "mov requires matching operand widths (\(d.widthSuffix) vs \(s.widthSuffix))"
                )
            }
            return .mov(destination: .register(d), source: .register(s))

        case (.register(let d), .memory(let m)):
            return .mov(destination: .register(d), source: .memory(m, width: d.width))

        case (.register(let d), .immediate(let v)):
            try validateImmediateRange(v, width: d.width, mnemonic: "mov")
            return .mov(destination: .register(d), source: .immediate(v))

        case (.memory(let m), .register(let s)):
            return .mov(destination: .memory(m, width: s.width), source: .register(s))

        case (.memory, .memory):
            throw AssemblerError.unsupportedOperand("mov cannot have two memory operands")

        case (.memory, .immediate):
            throw AssemblerError.unsupportedOperand("mov mem, imm requires an explicit size hint (deferred)")

        case (.immediate, _):
            throw AssemblerError.unsupportedOperand("mov destination cannot be an immediate")
        }
    }

    private static func parseAnyOperand(_ text: String, mnemonic: String) throws -> AnyOperand {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed))
        }
        if let register = try? register(trimmed) {
            return .register(register)
        }
        let immediate = try immediateAny(trimmed)
        return .immediate(immediate)
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
