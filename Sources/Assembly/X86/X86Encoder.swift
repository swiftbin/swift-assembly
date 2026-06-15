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
        case .binaryAlu(let kind, let destination, let source):
            return try encodeBinaryAlu(kind, destination: destination, source: source)
        case .unaryAlu(let kind, let target):
            return try encodeUnaryAlu(kind, target: target)
        case .test(let left, let right):
            return try encodeTest(left: left, right: right)
        }
    }

    // MARK: - MOV

    private static func encodeMov(destination: X86.RegisterOrMemory, source: X86.Operand) throws -> [UInt8] {
        switch (destination, source) {
        case (.register(let dst), .register(let src)):
            try checkRegisterRegisterCompat([dst, src], mnemonic: "mov")
            return try emitOperandPair(
                opcode: dst.width == .byte ? 0x88 : 0x89,
                width: dst.width,
                rmOperand: .register(dst),
                regHigh: src.highBit,
                regLow: src.lowBits,
                forceREX: needsForcedREX([dst, src])
            )
        case (.register(let dst), .memory(let mem, let width)):
            try checkRegisterRegisterCompat([dst], mnemonic: "mov")
            return try emitOperandPair(
                opcode: width == .byte ? 0x8A : 0x8B,
                width: width,
                rmOperand: .memory(mem, width: width),
                regHigh: dst.highBit,
                regLow: dst.lowBits,
                forceREX: needsForcedREX([dst])
            )
        case (.memory(let mem, let width), .register(let src)):
            try checkRegisterRegisterCompat([src], mnemonic: "mov")
            return try emitOperandPair(
                opcode: width == .byte ? 0x88 : 0x89,
                width: width,
                rmOperand: .memory(mem, width: width),
                regHigh: src.highBit,
                regLow: src.lowBits,
                forceREX: needsForcedREX([src])
            )
        case (.register(let dst), .immediate(let imm)):
            return try encodeMovRegImmediate(destination: dst, immediate: imm)
        case (.memory(let mem, let width), .immediate(let imm)):
            return try encodeMovMemImmediate(memory: mem, width: width, immediate: imm)
        case (.memory, .memory):
            throw AssemblerError.unsupportedOperand("mov: cannot have two memory operands")
        }
    }

    /// `B0+rb ib` / `B8+rd` short forms, plus the `REX.W C7 /0 id` fallback
    /// for r64 immediates that fit in Int32.
    private static func encodeMovRegImmediate(destination dst: X86.Register, immediate imm: Int64) throws -> [UInt8] {
        try X86Parser.validateImmediateRange(imm, width: dst.width, mnemonic: "mov")
        try checkRegisterRegisterCompat([dst], mnemonic: "mov")
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

    /// MOV mem, imm via C6 /0 / C7 /0 with mod != 11.
    private static func encodeMovMemImmediate(memory mem: X86.MemoryOperand, width: X86.RegisterWidth, immediate imm: Int64) throws -> [UInt8] {
        try X86Parser.validateImmediateRange(imm, width: width, mnemonic: "mov")
        if width == .qword {
            try requireFitsInt32(imm, mnemonic: "mov qword ptr [..], imm")
        }
        var bytes = try emitOperandPair(
            opcode: width == .byte ? 0xC6 : 0xC7,
            width: width,
            rmOperand: .memory(mem, width: width),
            regHigh: 0,
            regLow: 0
        )
        try appendWidthImmediate(imm, width: width, into: &bytes)
        return bytes
    }

    // MARK: - Binary ALU (ADD/OR/ADC/SBB/AND/SUB/XOR/CMP)

    private static func encodeBinaryAlu(_ kind: X86.BinaryAluKind, destination: X86.RegisterOrMemory, source: X86.Operand) throws -> [UInt8] {
        switch (destination, source) {
        case (.register(let dst), .register(let src)):
            try checkRegisterRegisterCompat([dst, src], mnemonic: kind.rawValue)
            return try emitOperandPair(
                opcode: kind.mrOpcode(byte: dst.width == .byte),
                width: dst.width,
                rmOperand: .register(dst),
                regHigh: src.highBit,
                regLow: src.lowBits,
                forceREX: needsForcedREX([dst, src])
            )
        case (.register(let dst), .memory(let mem, let width)):
            try checkRegisterRegisterCompat([dst], mnemonic: kind.rawValue)
            return try emitOperandPair(
                opcode: kind.rmOpcode(byte: width == .byte),
                width: width,
                rmOperand: .memory(mem, width: width),
                regHigh: dst.highBit,
                regLow: dst.lowBits,
                forceREX: needsForcedREX([dst])
            )
        case (.memory(let mem, let width), .register(let src)):
            try checkRegisterRegisterCompat([src], mnemonic: kind.rawValue)
            return try emitOperandPair(
                opcode: kind.mrOpcode(byte: width == .byte),
                width: width,
                rmOperand: .memory(mem, width: width),
                regHigh: src.highBit,
                regLow: src.lowBits,
                forceREX: needsForcedREX([src])
            )
        case (.register(let dst), .immediate(let imm)):
            return try encodeBinaryAluImmediate(kind, destination: .register(dst), width: dst.width, immediate: imm, dstIsAccumulator: dst.number == 0)
        case (.memory(let mem, let width), .immediate(let imm)):
            return try encodeBinaryAluImmediate(kind, destination: .memory(mem, width: width), width: width, immediate: imm, dstIsAccumulator: false)
        case (.memory, .memory):
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): cannot have two memory operands")
        }
    }

    /// Pick the shortest valid immediate encoding for a binary ALU op:
    ///
    /// 1. 83 /n ib (sign-extended) — non-byte width, imm fits Int8.
    /// 2. 04/05+8n short form — destination is the accumulator (rAX).
    /// 3. 80/81 /n — general MI form.
    private static func encodeBinaryAluImmediate(
        _ kind: X86.BinaryAluKind,
        destination: X86.RegisterOrMemory,
        width: X86.RegisterWidth,
        immediate imm: Int64,
        dstIsAccumulator: Bool
    ) throws -> [UInt8] {
        try X86Parser.validateImmediateRange(imm, width: width, mnemonic: kind.rawValue)
        if width == .qword {
            try requireFitsInt32(imm, mnemonic: kind.rawValue)
        }

        let fitsInt8 = Int64(Int8(truncatingIfNeeded: imm)) == imm

        // 83 /n ib — only for non-byte widths when imm sign-extends from Int8.
        if width != .byte && fitsInt8 {
            var bytes = try emitOperandPair(
                opcode: 0x83,
                width: width,
                rmOperand: destination,
                regHigh: 0,
                regLow: kind.opcodeIndex
            )
            bytes.append(UInt8(bitPattern: Int8(truncatingIfNeeded: imm)))
            return bytes
        }

        // Accumulator short form (only when the destination is rAX itself).
        if dstIsAccumulator, case .register(let dst) = destination {
            var bytes: [UInt8] = []
            if width == .word { bytes.append(X86.operandSizeOverride) }
            let rexW: UInt8 = width == .qword ? 1 : 0
            let forceREX = needsForcedREX([dst])
            if let rex = X86.REX.build(w: rexW, forceEmit: forceREX) { bytes.append(rex) }
            bytes.append(kind.accumulatorOpcode(byte: width == .byte))
            try appendWidthImmediate(imm, width: width, into: &bytes)
            return bytes
        }

        // 80 / 81 /n general MI form.
        var bytes = try emitOperandPair(
            opcode: width == .byte ? 0x80 : 0x81,
            width: width,
            rmOperand: destination,
            regHigh: 0,
            regLow: kind.opcodeIndex
        )
        try appendWidthImmediate(imm, width: width, into: &bytes)
        return bytes
    }

    // MARK: - Unary ALU (INC/DEC/NOT/NEG)

    private static func encodeUnaryAlu(_ kind: X86.UnaryAluKind, target: X86.RegisterOrMemory) throws -> [UInt8] {
        let width = target.width
        if case .register(let r) = target {
            try checkRegisterRegisterCompat([r], mnemonic: kind.rawValue)
        }
        let forceREX: Bool
        if case .register(let r) = target { forceREX = needsForcedREX([r]) } else { forceREX = false }
        return try emitOperandPair(
            opcode: kind.opcode(byte: width == .byte),
            width: width,
            rmOperand: target,
            regHigh: 0,
            regLow: kind.slashDigit,
            forceREX: forceREX
        )
    }

    // MARK: - TEST

    /// TEST has only the MR form for register/memory operands (no RM
    /// counterpart), the A8/A9 accumulator short form, and the F6/F7 /0
    /// general MI form.
    private static func encodeTest(left: X86.RegisterOrMemory, right: X86.Operand) throws -> [UInt8] {
        switch (left, right) {
        case (.register(let l), .register(let r)):
            try checkRegisterRegisterCompat([l, r], mnemonic: "test")
            return try emitOperandPair(
                opcode: l.width == .byte ? 0x84 : 0x85,
                width: l.width,
                rmOperand: .register(l),
                regHigh: r.highBit,
                regLow: r.lowBits,
                forceREX: needsForcedREX([l, r])
            )

        case (.register(let l), .memory(let m, let w)):
            try checkRegisterRegisterCompat([l], mnemonic: "test")
            // TEST has no RM form; route through the MR form with mem in
            // the r/m slot. Disassembly renders mem-first as a result.
            return try emitOperandPair(
                opcode: w == .byte ? 0x84 : 0x85,
                width: w,
                rmOperand: .memory(m, width: w),
                regHigh: l.highBit,
                regLow: l.lowBits,
                forceREX: needsForcedREX([l])
            )

        case (.memory(let m, let w), .register(let r)):
            try checkRegisterRegisterCompat([r], mnemonic: "test")
            return try emitOperandPair(
                opcode: w == .byte ? 0x84 : 0x85,
                width: w,
                rmOperand: .memory(m, width: w),
                regHigh: r.highBit,
                regLow: r.lowBits,
                forceREX: needsForcedREX([r])
            )

        case (.register(let l), .immediate(let imm)):
            return try encodeTestImmediate(target: .register(l), width: l.width, immediate: imm, dstIsAccumulator: l.number == 0)

        case (.memory(let m, let w), .immediate(let imm)):
            return try encodeTestImmediate(target: .memory(m, width: w), width: w, immediate: imm, dstIsAccumulator: false)

        case (.memory, .memory):
            throw AssemblerError.unsupportedOperand("test: cannot have two memory operands")
        }
    }

    private static func encodeTestImmediate(
        target: X86.RegisterOrMemory,
        width: X86.RegisterWidth,
        immediate imm: Int64,
        dstIsAccumulator: Bool
    ) throws -> [UInt8] {
        try X86Parser.validateImmediateRange(imm, width: width, mnemonic: "test")
        if width == .qword { try requireFitsInt32(imm, mnemonic: "test") }

        if dstIsAccumulator, case .register(let r) = target {
            var bytes: [UInt8] = []
            if width == .word { bytes.append(X86.operandSizeOverride) }
            let rexW: UInt8 = width == .qword ? 1 : 0
            if let rex = X86.REX.build(w: rexW, forceEmit: needsForcedREX([r])) { bytes.append(rex) }
            bytes.append(width == .byte ? 0xA8 : 0xA9)
            try appendWidthImmediate(imm, width: width, into: &bytes)
            return bytes
        }

        var bytes = try emitOperandPair(
            opcode: width == .byte ? 0xF6 : 0xF7,
            width: width,
            rmOperand: target,
            regHigh: 0,
            regLow: 0
        )
        try appendWidthImmediate(imm, width: width, into: &bytes)
        return bytes
    }

    // MARK: - Shared low-level emitters

    /// Emit the prefix bytes + opcode + ModR/M (+ SIB + disp) for a
    /// 2-operand instruction whose `r/m` side may be a register or a
    /// memory reference. The `reg` field is supplied by the caller (it's
    /// the *other* operand's low 3 bits, or a `/n` slash-digit for MI
    /// forms); REX.R comes from the caller via `regHigh`.
    private static func emitOperandPair(
        opcode: UInt8,
        width: X86.RegisterWidth,
        rmOperand: X86.RegisterOrMemory,
        regHigh: UInt8,
        regLow: UInt8,
        forceREX: Bool = false
    ) throws -> [UInt8] {
        var bytes: [UInt8] = []
        if width == .word { bytes.append(X86.operandSizeOverride) }
        let rexW: UInt8 = width == .qword ? 1 : 0
        switch rmOperand {
        case .register(let rm):
            if let rex = X86.REX.build(w: rexW, r: regHigh, x: 0, b: rm.highBit, forceEmit: forceREX) {
                bytes.append(rex)
            }
            bytes.append(opcode)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: regLow, rm: rm.lowBits))
        case .memory(let mem, _):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: regLow)
            if let rex = X86.REX.build(w: rexW, r: regHigh, x: rexX, b: rexB, forceEmit: forceREX) {
                bytes.append(rex)
            }
            bytes.append(opcode)
            bytes.append(contentsOf: addressing)
        }
        return bytes
    }

    // MARK: - ModR/M + SIB + disp

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

        if baseDecoded == nil {
            var bytes: [UInt8] = []
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modIndirect, reg: regField, rm: 0b100))
            bytes.append(X86.SIB.make(scale: scaleField, index: indexLow, base: X86.SIB.noBase))
            appendLE32(UInt32(truncatingIfNeeded: mem.displacement), into: &bytes)
            return (bytes, indexHigh, 0)
        }

        let base = baseDecoded!
        let needsSIB = mem.index != nil || base.lowBits == 0b100
        let cannotZeroDisp = base.lowBits == 0b101

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

    // MARK: - Validation / immediate helpers

    private static func validateDisplacement(_ value: Int64) throws {
        guard value >= Int64(Int32.min) && value <= Int64(Int32.max) else {
            throw AssemblerError.immediateOutOfRange(
                instruction: "memory operand",
                value: value,
                range: Int64(Int32.min)...Int64(Int32.max)
            )
        }
    }

    private static func requireFitsInt32(_ value: Int64, mnemonic: String) throws {
        guard Int64(Int32(truncatingIfNeeded: value)) == value else {
            throw AssemblerError.immediateOutOfRange(
                instruction: mnemonic,
                value: value,
                range: Int64(Int32.min)...Int64(Int32.max)
            )
        }
    }

    /// Append `imm` to `bytes` as a little-endian literal of the given
    /// width. The qword form writes 4 bytes (the immediate is later
    /// sign-extended by the CPU); callers are expected to have validated
    /// that the value fits Int32 via `requireFitsInt32`.
    private static func appendWidthImmediate(_ imm: Int64, width: X86.RegisterWidth, into bytes: inout [UInt8]) throws {
        switch width {
        case .byte:
            bytes.append(UInt8(truncatingIfNeeded: imm))
        case .word:
            appendLE16(UInt16(truncatingIfNeeded: imm), into: &bytes)
        case .dword, .qword:
            appendLE32(UInt32(truncatingIfNeeded: imm), into: &bytes)
        }
    }

    private static func checkRegisterRegisterCompat(_ registers: [X86.Register], mnemonic: String) throws {
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
