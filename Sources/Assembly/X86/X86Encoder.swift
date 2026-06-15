import Foundation

internal enum X86InstructionEncoder {
    /// Result of encoding a single instruction: the byte sequence plus
    /// any patch records describing label-relative fields that must be
    /// filled in after the second pass of label resolution.
    struct Encoded {
        var bytes: [UInt8]
        var patches: [Patch]
    }

    /// A record of one rel8 / rel32 field that needs the target label's
    /// final byte offset filled in after the encoder has visited every
    /// instruction. `byteOffset` is the position of the first byte of
    /// the field within `bytes`; `instructionEndOffset` is the position
    /// just past the end of the instruction (rel is measured from there).
    struct Patch {
        var byteOffset: Int
        var width: Int
        var label: String
        var instructionEndOffset: Int
    }

    /// Encode a single source-level instruction into its byte sequence.
    /// Phase 5 and earlier instructions emit no patches; Phase 6 adds
    /// branches whose `BranchTarget == .label(_)` produces a placeholder
    /// rel field with a paired `Patch` to be filled in later.
    static func encode(
        _ instruction: ParsedInstruction,
        pc: Int64,
        labels: [String: Int64]
    ) throws -> Encoded {
        let resolved = try X86Parser.parse(instruction)
        return try encode(resolved, pc: pc, labels: labels)
    }

    /// Legacy single-instruction entry point used by non-branch tests.
    /// Branches require the full `pc`/`labels` context; this overload
    /// errors if any branch case sneaks through.
    static func encode(_ instruction: X86.Instruction) throws -> [UInt8] {
        let encoded = try encode(instruction, pc: 0, labels: [:])
        guard encoded.patches.isEmpty else {
            throw AssemblerError.unsupportedOperand("internal: branch encoded without pc/labels")
        }
        return encoded.bytes
    }

    static func encode(_ instruction: X86.Instruction, pc: Int64, labels: [String: Int64]) throws -> Encoded {
        switch instruction {
        case .zeroOperand(let kind):
            return Encoded(bytes: kind.bytes, patches: [])
        case .mov(let destination, let source):
            return Encoded(bytes: try encodeMov(destination: destination, source: source), patches: [])
        case .binaryAlu(let kind, let destination, let source):
            return Encoded(bytes: try encodeBinaryAlu(kind, destination: destination, source: source), patches: [])
        case .unaryAlu(let kind, let target):
            return Encoded(bytes: try encodeUnaryAlu(kind, target: target), patches: [])
        case .test(let left, let right):
            return Encoded(bytes: try encodeTest(left: left, right: right), patches: [])
        case .shift(let kind, let target, let count):
            return Encoded(bytes: try encodeShift(kind, target: target, count: count), patches: [])
        case .doubleShift(let kind, let target, let source, let count):
            return Encoded(bytes: try encodeDoubleShift(kind, target: target, source: source, count: count), patches: [])
        case .jump(let target):
            return try encodeJump(target: target, pc: pc, labels: labels)
        case .conditionalJump(let cond, let target):
            return try encodeConditionalJump(condition: cond, target: target, pc: pc, labels: labels)
        case .call(let target):
            return try encodeCall(target: target, pc: pc, labels: labels)
        case .loop(let kind, let target):
            return try encodeLoop(kind, target: target, pc: pc, labels: labels)
        }
    }

    // MARK: - Branches

    /// JMP supports both rel8 (`EB ib`, 2 bytes) and rel32
    /// (`E9 id`, 5 bytes); the encoder picks the shorter form
    /// whenever the delta is known and fits Int8. Forward label
    /// references emit a rel32 placeholder so the late patch pass
    /// can fill the field in once every label position is known.
    private static func encodeJump(target: X86.BranchTarget, pc: Int64, labels: [String: Int64]) throws -> Encoded {
        let mnemonic = "jmp"
        switch target {
        case .offset(let delta):
            if delta >= -0x80 && delta <= 0x7F {
                return Encoded(bytes: [0xEB, UInt8(bitPattern: Int8(truncatingIfNeeded: delta))], patches: [])
            }
            guard delta >= Int64(Int32.min) && delta <= Int64(Int32.max) else {
                throw AssemblerError.branchOutOfRange(instruction: mnemonic, label: "#\(delta)", byteOffset: delta)
            }
            var bytes: [UInt8] = [0xE9]
            appendLE32(UInt32(truncatingIfNeeded: delta), into: &bytes)
            return Encoded(bytes: bytes, patches: [])
        case .label(let name):
            if let labelOffset = labels[name] {
                let deltaShort = labelOffset - (pc + 2)
                if deltaShort >= -0x80 && deltaShort <= 0x7F {
                    return Encoded(
                        bytes: [0xEB, UInt8(bitPattern: Int8(truncatingIfNeeded: deltaShort))],
                        patches: []
                    )
                }
                let deltaLong = labelOffset - (pc + 5)
                guard deltaLong >= Int64(Int32.min) && deltaLong <= Int64(Int32.max) else {
                    throw AssemblerError.branchOutOfRange(instruction: mnemonic, label: name, byteOffset: deltaLong)
                }
                var bytes: [UInt8] = [0xE9]
                appendLE32(UInt32(truncatingIfNeeded: deltaLong), into: &bytes)
                return Encoded(bytes: bytes, patches: [])
            }
            // Forward reference — emit the rel32 form so we have enough
            // budget for any in-range delta.
            return Encoded(
                bytes: [0xE9, 0x00, 0x00, 0x00, 0x00],
                patches: [Patch(byteOffset: 1, width: 4, label: name, instructionEndOffset: 5)]
            )
        }
    }

    /// Jcc has the same rel8 vs. rel32 split as JMP but pays an extra
    /// 0x0F prefix byte on the long form (`70+cc ib`, 2 bytes; or
    /// `0F 80+cc id`, 6 bytes).
    private static func encodeConditionalJump(condition: X86.Condition, target: X86.BranchTarget, pc: Int64, labels: [String: Int64]) throws -> Encoded {
        let mnemonic = "j\(condition.rawValue)"
        let shortOp: UInt8 = 0x70 | condition.encoding
        let longOp2: UInt8 = 0x80 | condition.encoding
        switch target {
        case .offset(let delta):
            if delta >= -0x80 && delta <= 0x7F {
                return Encoded(bytes: [shortOp, UInt8(bitPattern: Int8(truncatingIfNeeded: delta))], patches: [])
            }
            guard delta >= Int64(Int32.min) && delta <= Int64(Int32.max) else {
                throw AssemblerError.branchOutOfRange(instruction: mnemonic, label: "#\(delta)", byteOffset: delta)
            }
            var bytes: [UInt8] = [0x0F, longOp2]
            appendLE32(UInt32(truncatingIfNeeded: delta), into: &bytes)
            return Encoded(bytes: bytes, patches: [])
        case .label(let name):
            if let labelOffset = labels[name] {
                let deltaShort = labelOffset - (pc + 2)
                if deltaShort >= -0x80 && deltaShort <= 0x7F {
                    return Encoded(
                        bytes: [shortOp, UInt8(bitPattern: Int8(truncatingIfNeeded: deltaShort))],
                        patches: []
                    )
                }
                let deltaLong = labelOffset - (pc + 6)
                guard deltaLong >= Int64(Int32.min) && deltaLong <= Int64(Int32.max) else {
                    throw AssemblerError.branchOutOfRange(instruction: mnemonic, label: name, byteOffset: deltaLong)
                }
                var bytes: [UInt8] = [0x0F, longOp2]
                appendLE32(UInt32(truncatingIfNeeded: deltaLong), into: &bytes)
                return Encoded(bytes: bytes, patches: [])
            }
            return Encoded(
                bytes: [0x0F, longOp2, 0x00, 0x00, 0x00, 0x00],
                patches: [Patch(byteOffset: 2, width: 4, label: name, instructionEndOffset: 6)]
            )
        }
    }

    /// CALL has only the rel32 form in long mode (`E8 id`, 5 bytes).
    private static func encodeCall(target: X86.BranchTarget, pc: Int64, labels: [String: Int64]) throws -> Encoded {
        let mnemonic = "call"
        switch target {
        case .offset(let delta):
            guard delta >= Int64(Int32.min) && delta <= Int64(Int32.max) else {
                throw AssemblerError.branchOutOfRange(instruction: mnemonic, label: "#\(delta)", byteOffset: delta)
            }
            var bytes: [UInt8] = [0xE8]
            appendLE32(UInt32(truncatingIfNeeded: delta), into: &bytes)
            return Encoded(bytes: bytes, patches: [])
        case .label(let name):
            if let labelOffset = labels[name] {
                let delta = labelOffset - (pc + 5)
                guard delta >= Int64(Int32.min) && delta <= Int64(Int32.max) else {
                    throw AssemblerError.branchOutOfRange(instruction: mnemonic, label: name, byteOffset: delta)
                }
                var bytes: [UInt8] = [0xE8]
                appendLE32(UInt32(truncatingIfNeeded: delta), into: &bytes)
                return Encoded(bytes: bytes, patches: [])
            }
            return Encoded(
                bytes: [0xE8, 0x00, 0x00, 0x00, 0x00],
                patches: [Patch(byteOffset: 1, width: 4, label: name, instructionEndOffset: 5)]
            )
        }
    }

    /// LOOP / LOOPE / LOOPNE / JECXZ / JRCXZ are rel8-only. An
    /// out-of-range delta — either a numeric literal or a label too
    /// far away — is an error, since the family has no long form.
    private static func encodeLoop(_ kind: X86.LoopKind, target: X86.BranchTarget, pc: Int64, labels: [String: Int64]) throws -> Encoded {
        var bytes: [UInt8] = []
        var prefixBytes = 0
        if kind.needsAddressSize {
            bytes.append(0x67)
            prefixBytes = 1
        }
        bytes.append(kind.opcode)
        let instructionSize = prefixBytes + 2  // prefix(?) + opcode + ib

        switch target {
        case .offset(let delta):
            guard delta >= -0x80 && delta <= 0x7F else {
                throw AssemblerError.branchOutOfRange(instruction: kind.rawValue, label: "#\(delta)", byteOffset: delta)
            }
            bytes.append(UInt8(bitPattern: Int8(truncatingIfNeeded: delta)))
            return Encoded(bytes: bytes, patches: [])
        case .label(let name):
            if let labelOffset = labels[name] {
                let delta = labelOffset - (pc + Int64(instructionSize))
                guard delta >= -0x80 && delta <= 0x7F else {
                    throw AssemblerError.branchOutOfRange(instruction: kind.rawValue, label: name, byteOffset: delta)
                }
                bytes.append(UInt8(bitPattern: Int8(truncatingIfNeeded: delta)))
                return Encoded(bytes: bytes, patches: [])
            }
            bytes.append(0x00)
            return Encoded(
                bytes: bytes,
                patches: [Patch(byteOffset: prefixBytes + 1, width: 1, label: name, instructionEndOffset: instructionSize)]
            )
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

    // MARK: - Shift / Rotate

    /// Encode the single-operand shift / rotate family. The opcode group
    /// is selected by `count`:
    ///
    /// * `.one` → D0 (byte) / D1 (non-byte), no immediate.
    /// * `.cl`  → D2 / D3, no immediate.
    /// * `.immediate(n)` → C0 / C1 with `n` appended.
    private static func encodeShift(_ kind: X86.ShiftKind, target: X86.RegisterOrMemory, count: X86.ShiftCount) throws -> [UInt8] {
        let width = target.width
        let isByte = width == .byte
        if case .register(let r) = target {
            try checkRegisterRegisterCompat([r], mnemonic: kind.rawValue)
        }
        let forceREX: Bool
        if case .register(let r) = target { forceREX = needsForcedREX([r]) } else { forceREX = false }

        let opcode: UInt8
        switch count {
        case .one:  opcode = isByte ? 0xD0 : 0xD1
        case .cl:   opcode = isByte ? 0xD2 : 0xD3
        case .immediate: opcode = isByte ? 0xC0 : 0xC1
        }

        var bytes = try emitOperandPair(
            opcode: opcode,
            width: width,
            rmOperand: target,
            regHigh: 0,
            regLow: kind.slashDigit,
            forceREX: forceREX
        )
        if case .immediate(let imm) = count {
            bytes.append(imm)
        }
        return bytes
    }

    /// Encode `SHLD` / `SHRD`. Both forms use the 0F-escape opcode.
    private static func encodeDoubleShift(_ kind: X86.DoubleShiftKind, target: X86.RegisterOrMemory, source: X86.Register, count: X86.ShiftCount) throws -> [UInt8] {
        let width = source.width
        if case .register(let r) = target {
            try checkRegisterRegisterCompat([r, source], mnemonic: kind.rawValue)
        } else {
            try checkRegisterRegisterCompat([source], mnemonic: kind.rawValue)
        }
        let forceREX: Bool
        if case .register(let r) = target {
            forceREX = needsForcedREX([r, source])
        } else {
            forceREX = needsForcedREX([source])
        }

        let opcode2: UInt8
        switch count {
        case .immediate, .one: opcode2 = kind.immediateOpcode
        case .cl:              opcode2 = kind.clOpcode
        }

        // Two-byte 0F-escape opcode: emit the prefix bytes, then 0F, then
        // the operand-pair body.
        var bytes: [UInt8] = []
        if width == .word { bytes.append(X86.operandSizeOverride) }
        let rexW: UInt8 = width == .qword ? 1 : 0
        switch target {
        case .register(let rm):
            if let rex = X86.REX.build(w: rexW, r: source.highBit, x: 0, b: rm.highBit, forceEmit: forceREX) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(opcode2)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: source.lowBits, rm: rm.lowBits))
        case .memory(let mem, _):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: source.lowBits)
            if let rex = X86.REX.build(w: rexW, r: source.highBit, x: rexX, b: rexB, forceEmit: forceREX) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(opcode2)
            bytes.append(contentsOf: addressing)
        }

        if case .immediate(let imm) = count {
            bytes.append(imm)
        }
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
