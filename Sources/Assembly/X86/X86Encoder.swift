import Foundation

internal enum X86InstructionEncoder {
    /// Encode a single source-level instruction into its byte sequence.
    static func encode(
        _ instruction: ParsedInstruction,
        pc: Int64,
        labels: [String: Int64]
    ) throws -> [UInt8] {
        let resolved = try X86Parser.parse(instruction)
        return try encode(resolved)
    }

    static func encode(_ instruction: X86.Instruction) throws -> [UInt8] {
        switch instruction {
        case .zeroOperand(let kind):
            return kind.bytes
        case .mov(let destination, let source):
            return try encodeMov(destination: destination, source: source)
        }
    }

    // MARK: - MOV

    private static func encodeMov(destination: X86.RegisterOrMemory, source: X86.Operand) throws -> [UInt8] {
        switch (destination, source) {
        case (.register(let dst), .register(let src)):
            return try encodeMovRegRegister(destination: dst, source: src)
        case (.register(let dst), .immediate(let imm)):
            return try encodeMovRegImmediate(destination: dst, immediate: imm)
        case (.register(let dst), .memory(let mem, let width)):
            return try encodeMovRegMemory(destination: dst, memory: mem, width: width)
        case (.memory(let mem, let width), .register(let src)):
            return try encodeMovMemRegister(memory: mem, width: width, source: src)
        case (.memory(let mem, let width), .immediate(let imm)):
            return try encodeMovMemImmediate(memory: mem, width: width, immediate: imm)
        case (.memory, .memory):
            throw AssemblerError.unsupportedOperand("mov: cannot have two memory operands")
        }
    }

    /// MR form (88/89 `/r`), `mod == 11` — the canonical register/register encoding.
    private static func encodeMovRegRegister(destination dst: X86.Register, source src: X86.Register) throws -> [UInt8] {
        try validateByteRegisterCompatibility([dst, src], mnemonic: "mov")
        let width = dst.width
        var bytes: [UInt8] = []
        if width == .word { bytes.append(X86.operandSizeOverride) }
        let rexW: UInt8 = width == .qword ? 1 : 0
        let forceREX = needsForcedREX([dst, src])
        if let rex = X86.REX.build(w: rexW, r: src.highBit, x: 0, b: dst.highBit, forceEmit: forceREX) {
            bytes.append(rex)
        }
        bytes.append(width == .byte ? 0x88 : 0x89)
        bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: src.lowBits, rm: dst.lowBits))
        return bytes
    }

    /// `B0+rb ib` / `B8+rd` short forms, plus the `REX.W C7 /0 id` fallback
    /// for r64 immediates that fit in Int32.
    private static func encodeMovRegImmediate(destination dst: X86.Register, immediate imm: Int64) throws -> [UInt8] {
        try X86Parser.validateImmediateRange(imm, width: dst.width, mnemonic: "mov")
        try validateByteRegisterCompatibility([dst], mnemonic: "mov")
        switch dst.width {
        case .byte:
            var bytes: [UInt8] = []
            if let rex = X86.REX.build(b: dst.highBit, forceEmit: needsForcedREX([dst])) {
                bytes.append(rex)
            }
            bytes.append(0xB0 | dst.lowBits)
            bytes.append(UInt8(truncatingIfNeeded: imm))
            return bytes

        case .word:
            var bytes: [UInt8] = [X86.operandSizeOverride]
            if let rex = X86.REX.build(b: dst.highBit) { bytes.append(rex) }
            bytes.append(0xB8 | dst.lowBits)
            appendLE16(UInt16(truncatingIfNeeded: imm), into: &bytes)
            return bytes

        case .dword:
            var bytes: [UInt8] = []
            if let rex = X86.REX.build(b: dst.highBit) { bytes.append(rex) }
            bytes.append(0xB8 | dst.lowBits)
            appendLE32(UInt32(truncatingIfNeeded: imm), into: &bytes)
            return bytes

        case .qword:
            let fitsInt32 = Int64(Int32(truncatingIfNeeded: imm)) == imm
            if fitsInt32 {
                var bytes: [UInt8] = []
                bytes.append(X86.REX.build(w: 1, b: dst.highBit)!)
                bytes.append(0xC7)
                bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: 0, rm: dst.lowBits))
                appendLE32(UInt32(truncatingIfNeeded: imm), into: &bytes)
                return bytes
            } else {
                var bytes: [UInt8] = []
                bytes.append(X86.REX.build(w: 1, b: dst.highBit)!)
                bytes.append(0xB8 | dst.lowBits)
                appendLE64(UInt64(bitPattern: imm), into: &bytes)
                return bytes
            }
        }
    }

    /// RM form (8A/8B `/r`), `mod != 11` — register destination, memory source.
    private static func encodeMovRegMemory(destination dst: X86.Register, memory mem: X86.MemoryOperand, width: X86.RegisterWidth) throws -> [UInt8] {
        try validateByteRegisterCompatibility([dst], mnemonic: "mov")
        let opcode: UInt8 = width == .byte ? 0x8A : 0x8B
        return try encodeMovWithMemory(opcode: opcode, regField: dst.lowBits, regHigh: dst.highBit, width: width, memory: mem, forceREX: needsForcedREX([dst]))
    }

    /// MR form (88/89 `/r`), `mod != 11` — memory destination, register source.
    private static func encodeMovMemRegister(memory mem: X86.MemoryOperand, width: X86.RegisterWidth, source src: X86.Register) throws -> [UInt8] {
        try validateByteRegisterCompatibility([src], mnemonic: "mov")
        let opcode: UInt8 = width == .byte ? 0x88 : 0x89
        return try encodeMovWithMemory(opcode: opcode, regField: src.lowBits, regHigh: src.highBit, width: width, memory: mem, forceREX: needsForcedREX([src]))
    }

    /// MI form (C6 /0 / C7 /0), `mod != 11`. The qword form sign-extends
    /// imm32 to 64 bits; immediates that do not fit Int32 are rejected.
    private static func encodeMovMemImmediate(memory mem: X86.MemoryOperand, width: X86.RegisterWidth, immediate imm: Int64) throws -> [UInt8] {
        try X86Parser.validateImmediateRange(imm, width: width, mnemonic: "mov")
        if width == .qword {
            // C7 /0 id sign-extends; reject values that would change bits.
            guard Int64(Int32(truncatingIfNeeded: imm)) == imm else {
                throw AssemblerError.immediateOutOfRange(
                    instruction: "mov qword ptr [..], imm",
                    value: imm,
                    range: Int64(Int32.min)...Int64(Int32.max)
                )
            }
        }
        let opcode: UInt8 = width == .byte ? 0xC6 : 0xC7
        let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: 0)
        var bytes: [UInt8] = []
        if width == .word { bytes.append(X86.operandSizeOverride) }
        let rexW: UInt8 = width == .qword ? 1 : 0
        if let rex = X86.REX.build(w: rexW, r: 0, x: rexX, b: rexB) {
            bytes.append(rex)
        }
        bytes.append(opcode)
        bytes.append(contentsOf: addressing)
        switch width {
        case .byte:  bytes.append(UInt8(truncatingIfNeeded: imm))
        case .word:  appendLE16(UInt16(truncatingIfNeeded: imm), into: &bytes)
        case .dword: appendLE32(UInt32(truncatingIfNeeded: imm), into: &bytes)
        case .qword: appendLE32(UInt32(truncatingIfNeeded: imm), into: &bytes)
        }
        return bytes
    }

    private static func encodeMovWithMemory(
        opcode: UInt8,
        regField: UInt8,
        regHigh: UInt8,
        width: X86.RegisterWidth,
        memory: X86.MemoryOperand,
        forceREX: Bool
    ) throws -> [UInt8] {
        let (addressing, rexX, rexB) = try encodeMemoryAddressing(memory, regField: regField)
        var bytes: [UInt8] = []
        if width == .word { bytes.append(X86.operandSizeOverride) }
        let rexW: UInt8 = width == .qword ? 1 : 0
        if let rex = X86.REX.build(w: rexW, r: regHigh, x: rexX, b: rexB, forceEmit: forceREX) {
            bytes.append(rex)
        }
        bytes.append(opcode)
        bytes.append(contentsOf: addressing)
        return bytes
    }

    // MARK: - ModR/M + SIB + disp emission

    /// Build the ModR/M byte, optional SIB byte, and optional displacement
    /// for a memory operand. Returns the REX.X / REX.B bits that the caller
    /// must fold into the prefix (REX.R comes from the *other* operand's
    /// register number).
    ///
    /// Canonicalisation: a sole index with `scale == 1` and no base is
    /// promoted to a bare base register (`[rax*1]` ⇒ `[rax]`), preferring
    /// the shorter encoding.
    private static func encodeMemoryAddressing(
        _ original: X86.MemoryOperand,
        regField: UInt8
    ) throws -> (bytes: [UInt8], rexX: UInt8, rexB: UInt8) {
        var mem = original
        if mem.base == nil && mem.index != nil && mem.scale == 1 && !mem.ripRelative {
            mem.base = mem.index
            mem.index = nil
        }

        try validateDisplacement(mem.displacement)

        if mem.ripRelative {
            var bytes: [UInt8] = []
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modIndirect, reg: regField, rm: 0b101))
            appendLE32(UInt32(truncatingIfNeeded: mem.displacement), into: &bytes)
            return (bytes, 0, 0)
        }

        let scaleField = mem.scaleField ?? 0
        let indexLow = mem.index?.lowBits ?? X86.SIB.noIndex
        let indexHigh = mem.index?.highBit ?? 0
        let baseDecoded = mem.base

        // Case 1: no base at all. `[disp32]` or `[index*scale + disp32]`.
        if baseDecoded == nil {
            var bytes: [UInt8] = []
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modIndirect, reg: regField, rm: 0b100))
            bytes.append(X86.SIB.make(scale: scaleField, index: indexLow, base: X86.SIB.noBase))
            appendLE32(UInt32(truncatingIfNeeded: mem.displacement), into: &bytes)
            return (bytes, indexHigh, 0)
        }

        let base = baseDecoded!
        let needsSIB = mem.index != nil || base.lowBits == 0b100   // RSP/R12 escape
        let cannotZeroDisp = base.lowBits == 0b101                  // RBP/R13: mod=00 base=5 is the no-base form

        let mod: UInt8
        let dispSize: Int
        if mem.displacement == 0 && !cannotZeroDisp {
            mod = X86.ModRM.modIndirect; dispSize = 0
        } else if mem.displacement >= -0x80 && mem.displacement <= 0x7F {
            mod = X86.ModRM.modDisp8; dispSize = 1
        } else {
            mod = X86.ModRM.modDisp32; dispSize = 4
        }

        var bytes: [UInt8] = []
        if needsSIB {
            bytes.append(X86.ModRM.make(mod: mod, reg: regField, rm: 0b100))
            bytes.append(X86.SIB.make(scale: scaleField, index: indexLow, base: base.lowBits))
        } else {
            bytes.append(X86.ModRM.make(mod: mod, reg: regField, rm: base.lowBits))
        }

        switch dispSize {
        case 1: bytes.append(UInt8(truncatingIfNeeded: mem.displacement))
        case 4: appendLE32(UInt32(truncatingIfNeeded: mem.displacement), into: &bytes)
        default: break
        }

        return (bytes, indexHigh, base.highBit)
    }

    private static func validateDisplacement(_ value: Int64) throws {
        guard value >= Int64(Int32.min) && value <= Int64(Int32.max) else {
            throw AssemblerError.immediateOutOfRange(
                instruction: "mov",
                value: value,
                range: Int64(Int32.min)...Int64(Int32.max)
            )
        }
    }

    // MARK: - Validation helpers

    private static func validateByteRegisterCompatibility(_ registers: [X86.Register], mnemonic: String) throws {
        let hasHighByte = registers.contains { $0.isHighByte }
        let needsREX = needsForcedREX(registers) || registers.contains { $0.isExtended }
        if hasHighByte && needsREX {
            throw AssemblerError.unsupportedOperand(
                "\(mnemonic): high-byte register (AH/BH/CH/DH) cannot be combined with R8..R15 or SPL/BPL/SIL/DIL"
            )
        }
    }

    private static func needsForcedREX(_ registers: [X86.Register]) -> Bool {
        registers.contains { $0.requiresREXForByte }
    }

    private static func appendLE16(_ value: UInt16, into bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func appendLE32(_ value: UInt32, into bytes: inout [UInt8]) {
        for shift in stride(from: 0, to: 32, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }

    private static func appendLE64(_ value: UInt64, into bytes: inout [UInt8]) {
        for shift in stride(from: 0, to: 64, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}
