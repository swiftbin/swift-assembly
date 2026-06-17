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
        case .jumpIndirect(let target):
            return Encoded(bytes: try encodeIndirect(target: target, slashDigit: 4, mnemonic: "jmp"), patches: [])
        case .callIndirect(let target):
            return Encoded(bytes: try encodeIndirect(target: target, slashDigit: 2, mnemonic: "call"), patches: [])
        case .enter(let allocation, let nesting):
            var bytes: [UInt8] = [0xC8]
            appendLE16(allocation, into: &bytes)
            bytes.append(nesting)
            return Encoded(bytes: bytes, patches: [])
        case .mulDiv(let kind, let target):
            return Encoded(bytes: try encodeMulDiv(kind, target: target), patches: [])
        case .imulRegister(let dst, let src):
            return Encoded(bytes: try encodeImulRegister(destination: dst, source: src), patches: [])
        case .imulImmediate(let dst, let src, let imm):
            return Encoded(bytes: try encodeImulImmediate(destination: dst, source: src, immediate: imm), patches: [])
        case .push(let operand):
            return Encoded(bytes: try encodePush(operand), patches: [])
        case .pop(let target):
            return Encoded(bytes: try encodePop(target), patches: [])
        case .lea(let dst, let mem):
            return Encoded(bytes: try encodeLea(destination: dst, source: mem), patches: [])
        case .extendingMove(let kind, let dst, let src):
            return Encoded(bytes: try encodeExtendingMove(kind, destination: dst, source: src), patches: [])
        case .bswap(let reg):
            return Encoded(bytes: try encodeBswap(reg), patches: [])
        case .xchg(let target, let register):
            return Encoded(bytes: try encodeXchg(target: target, register: register), patches: [])
        case .xadd(let target, let source):
            return Encoded(bytes: try encodeXaddCmpxchg(target: target, source: source, kindByte: 0xC0, kindNonByte: 0xC1, mnemonic: "xadd"), patches: [])
        case .cmpxchg(let target, let source):
            return Encoded(bytes: try encodeXaddCmpxchg(target: target, source: source, kindByte: 0xB0, kindNonByte: 0xB1, mnemonic: "cmpxchg"), patches: [])
        case .cmpxchgWide(let kind, let mem):
            return Encoded(bytes: try encodeCmpxchgWide(kind, memory: mem), patches: [])
        case .cmovcc(let cond, let dst, let src):
            return Encoded(bytes: try encodeCmovcc(cond, destination: dst, source: src), patches: [])
        case .setcc(let cond, let target):
            return Encoded(bytes: try encodeSetcc(cond, target: target), patches: [])
        case .bitTest(let kind, let target, let source):
            return Encoded(bytes: try encodeBitTest(kind, target: target, source: source), patches: [])
        case .bitScan(let kind, let dst, let source):
            return Encoded(bytes: try encodeBitScan(kind, destination: dst, source: source), patches: [])
        case .bitCount(let kind, let dst, let source):
            return Encoded(bytes: try encodeBitCount(kind, destination: dst, source: source), patches: [])
        case .stringOp(let kind, let prefix):
            var bytes: [UInt8] = []
            if let prefix { bytes.append(prefix.byte) }
            bytes.append(contentsOf: kind.baseBytes)
            return Encoded(bytes: bytes, patches: [])
        case .inFromPort(let target, let port):
            return Encoded(bytes: encodePortIO(register: target, port: port, isOut: false), patches: [])
        case .outToPort(let source, let port):
            return Encoded(bytes: encodePortIO(register: source, port: port, isOut: true), patches: [])
        case .interrupt(let vector):
            return Encoded(bytes: [0xCD, vector], patches: [])
        case .clflush(let mem):
            return Encoded(bytes: try encodeMemoryOnlySys(escape2: 0xAE, slashDigit: 7, memory: mem), patches: [])
        case .invlpg(let mem):
            return Encoded(bytes: try encodeMemoryOnlySys(escape2: 0x01, slashDigit: 7, memory: mem), patches: [])
        case .descriptorTable(let kind, let mem):
            return Encoded(bytes: try encodeMemoryOnlySys(escape2: 0x01, slashDigit: kind.slashDigit, memory: mem), patches: [])
        case .systemRM(let kind, let target):
            return Encoded(bytes: try encodeSystemRM(kind, target: target), patches: [])
        case .movFromSystemRegister(let kind, let dst, let number):
            return Encoded(bytes: encodeMovSystemRegister(kind: kind, sysregNumber: number, register: dst, isRead: true), patches: [])
        case .movToSystemRegister(let kind, let number, let source):
            return Encoded(bytes: encodeMovSystemRegister(kind: kind, sysregNumber: number, register: source, isRead: false), patches: [])
        case .lar(let dst, let src):
            return Encoded(bytes: try encodeLarLsl(opcode2: 0x02, destination: dst, source: src, mnemonic: "lar"), patches: [])
        case .lsl(let dst, let src):
            return Encoded(bytes: try encodeLarLsl(opcode2: 0x03, destination: dst, source: src, mnemonic: "lsl"), patches: [])
        case .sseMov(let kind, let dst, let src):
            return Encoded(bytes: try encodeSSEMov(kind, destination: dst, source: src), patches: [])
        case .sseArithmetic(let kind, let dst, let src):
            return Encoded(bytes: try encodeSSEArithmetic(kind, destination: dst, source: src), patches: [])
        case .sseIntToFloat(let kind, let dst, let src):
            return Encoded(bytes: try encodeSSEIntToFloat(kind, destination: dst, source: src), patches: [])
        case .sseFloatToInt(let kind, let dst, let src):
            return Encoded(bytes: try encodeSSEFloatToInt(kind, destination: dst, source: src), patches: [])
        case .movDQ(let kind, let direction, let xmm, let gpr):
            return Encoded(bytes: try encodeMovDQ(kind, direction: direction, xmm: xmm, gpr: gpr), patches: [])
        case .ssePackedInteger(let kind, let dst, let src):
            return Encoded(bytes: try encodeSSEPackedInteger(kind, destination: dst, source: src), patches: [])
        case .sseShiftImmediate(let kind, let target, let imm):
            return Encoded(bytes: encodeSSEImmediateShift(kind, target: target, immediate: imm), patches: [])
        case .sseShuffle(let kind, let dst, let src, let imm):
            return Encoded(bytes: try encodeSSEShuffle(kind, destination: dst, source: src, immediate: imm), patches: [])
        case .sseCompare(let kind, let dst, let src, let pred):
            return Encoded(bytes: try encodeSSECompare(kind, destination: dst, source: src, predicate: pred), patches: [])
        case .sseHalfMove(let kind, let dst, let src):
            return Encoded(bytes: try encodeSSEHalfMove(kind, destination: dst, source: src), patches: [])
        case .sseMaskExtract(let kind, let dst, let src):
            return Encoded(bytes: try encodeSSEMaskExtract(kind, destination: dst, source: src), patches: [])
        case .maskMovDqu(let source, let mask):
            return Encoded(bytes: encodeMaskMovDqu(source: source, mask: mask), patches: [])
        case .mxcsr(let kind, let memory):
            return Encoded(bytes: try encodeMXCSR(kind, memory: memory), patches: [])
        case .sseNonTemporalStore(let kind, let memory, let source):
            return Encoded(bytes: try encodeSSENonTemporalStore(kind, memory: memory, source: source), patches: [])
        case .movnti(let memory, let source):
            return Encoded(bytes: try encodeMovnti(memory: memory, source: source), patches: [])
        case .prefetch(let kind, let memory):
            return Encoded(bytes: try encodePrefetch(kind, memory: memory), patches: [])
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
        case .xmmword:
            throw AssemblerError.unsupportedOperand("mov: xmmword immediate not supported")
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

    // MARK: - MUL / IMUL / DIV / IDIV (1-operand) and IMUL (2/3-operand)

    private static func encodeMulDiv(_ kind: X86.MulDivKind, target: X86.RegisterOrMemory) throws -> [UInt8] {
        let width = target.width
        if case .register(let r) = target {
            try checkRegisterRegisterCompat([r], mnemonic: kind.rawValue)
        }
        let forceREX: Bool
        if case .register(let r) = target { forceREX = needsForcedREX([r]) } else { forceREX = false }
        return try emitOperandPair(
            opcode: width == .byte ? 0xF6 : 0xF7,
            width: width,
            rmOperand: target,
            regHigh: 0,
            regLow: kind.slashDigit,
            forceREX: forceREX
        )
    }

    /// 2-operand IMUL (`0F AF /r`). Dst is `reg`, source is `r/m`.
    /// No byte form exists for this variant.
    private static func encodeImulRegister(destination dst: X86.Register, source: X86.RegisterOrMemory) throws -> [UInt8] {
        guard dst.width != .byte else {
            throw AssemblerError.unsupportedOperand("imul: 2-operand form requires word/dword/qword")
        }
        if case .register(let r) = source {
            try checkRegisterRegisterCompat([dst, r], mnemonic: "imul")
        } else {
            try checkRegisterRegisterCompat([dst], mnemonic: "imul")
        }
        let forceREX: Bool
        if case .register(let r) = source { forceREX = needsForcedREX([dst, r]) }
        else { forceREX = needsForcedREX([dst]) }
        return try emitOperandPair(
            opcodeBytes: [0x0F, 0xAF],
            width: dst.width,
            rmOperand: source,
            regHigh: dst.highBit,
            regLow: dst.lowBits,
            forceREX: forceREX
        )
    }

    /// 3-operand IMUL. The encoder picks the shorter `6B /r ib` form
    /// when the immediate sign-extends from int8; otherwise the
    /// `69 /r iw/id` form. The qword form sign-extends imm32 to int64,
    /// so a value outside Int32 range is rejected — there is no imm64
    /// form for IMUL.
    private static func encodeImulImmediate(destination dst: X86.Register, source: X86.RegisterOrMemory, immediate imm: Int64) throws -> [UInt8] {
        guard dst.width != .byte else {
            throw AssemblerError.unsupportedOperand("imul: 3-operand form requires word/dword/qword")
        }
        try X86Parser.validateImmediateRange(imm, width: dst.width, mnemonic: "imul")
        if dst.width == .qword { try requireFitsInt32(imm, mnemonic: "imul") }

        if case .register(let r) = source {
            try checkRegisterRegisterCompat([dst, r], mnemonic: "imul")
        } else {
            try checkRegisterRegisterCompat([dst], mnemonic: "imul")
        }
        let forceREX: Bool
        if case .register(let r) = source { forceREX = needsForcedREX([dst, r]) }
        else { forceREX = needsForcedREX([dst]) }

        let fitsInt8 = Int64(Int8(truncatingIfNeeded: imm)) == imm
        var bytes = try emitOperandPair(
            opcode: fitsInt8 ? 0x6B : 0x69,
            width: dst.width,
            rmOperand: source,
            regHigh: dst.highBit,
            regLow: dst.lowBits,
            forceREX: forceREX
        )
        if fitsInt8 {
            bytes.append(UInt8(bitPattern: Int8(truncatingIfNeeded: imm)))
        } else {
            try appendWidthImmediate(imm, width: dst.width, into: &bytes)
        }
        return bytes
    }

    // MARK: - PUSH / POP / LEA

    private static func encodePush(_ operand: X86.Operand) throws -> [UInt8] {
        switch operand {
        case .register(let r):
            // Short form 50+rd. Default operand size is qword in long
            // mode; the 0x66 prefix selects the word form.
            var bytes: [UInt8] = []
            if r.width == .word { bytes.append(X86.operandSizeOverride) }
            if let rex = X86.REX.build(b: r.highBit) { bytes.append(rex) }
            bytes.append(0x50 | r.lowBits)
            return bytes
        case .memory(let mem, let width):
            return try emitOperandPair(
                opcode: 0xFF,
                width: width,
                rmOperand: .memory(mem, width: width),
                regHigh: 0,
                regLow: 6,
                useREXW: false
            )
        case .immediate(let imm):
            // 6A ib (sign-extended to the stack slot) when the value
            // fits int8; otherwise 68 id (sign-extended imm32).
            if Int64(Int8(truncatingIfNeeded: imm)) == imm {
                return [0x6A, UInt8(bitPattern: Int8(truncatingIfNeeded: imm))]
            }
            var bytes: [UInt8] = [0x68]
            appendLE32(UInt32(truncatingIfNeeded: imm), into: &bytes)
            return bytes
        }
    }

    private static func encodePop(_ target: X86.RegisterOrMemory) throws -> [UInt8] {
        switch target {
        case .register(let r):
            var bytes: [UInt8] = []
            if r.width == .word { bytes.append(X86.operandSizeOverride) }
            if let rex = X86.REX.build(b: r.highBit) { bytes.append(rex) }
            bytes.append(0x58 | r.lowBits)
            return bytes
        case .memory(let mem, let width):
            return try emitOperandPair(
                opcode: 0x8F,
                width: width,
                rmOperand: .memory(mem, width: width),
                regHigh: 0,
                regLow: 0,
                useREXW: false
            )
        }
    }

    /// LEA r, m. The source is a pure address expression — its width
    /// only matters insofar as REX.W is set for a qword destination.
    private static func encodeLea(destination dst: X86.Register, source mem: X86.MemoryOperand) throws -> [UInt8] {
        try checkRegisterRegisterCompat([dst], mnemonic: "lea")
        return try emitOperandPair(
            opcode: 0x8D,
            width: dst.width,
            rmOperand: .memory(mem, width: dst.width),
            regHigh: dst.highBit,
            regLow: dst.lowBits,
            forceREX: needsForcedREX([dst])
        )
    }

    // MARK: - MOVSX / MOVSXD / MOVZX and BSWAP

    /// Encode MOVSX / MOVZX / MOVSXD. The source's width selects the
    /// opcode byte; the destination's width drives the operand-size
    /// prefix and REX.W.
    private static func encodeExtendingMove(_ kind: X86.ExtendingMoveKind, destination dst: X86.Register, source: X86.RegisterOrMemory) throws -> [UInt8] {
        if case .register(let r) = source {
            try checkRegisterRegisterCompat([dst, r], mnemonic: kind.rawValue)
        } else {
            try checkRegisterRegisterCompat([dst], mnemonic: kind.rawValue)
        }
        let forceREX: Bool
        if case .register(let r) = source { forceREX = needsForcedREX([dst, r]) }
        else { forceREX = needsForcedREX([dst]) }

        switch kind {
        case .movsx, .movzx:
            let isByteSource = source.width == .byte
            let opcode2: UInt8
            switch (kind, isByteSource) {
            case (.movsx, true):  opcode2 = 0xBE
            case (.movsx, false): opcode2 = 0xBF
            case (.movzx, true):  opcode2 = 0xB6
            case (.movzx, false): opcode2 = 0xB7
            default: throw AssemblerError.unsupportedOperand("\(kind.rawValue): internal width error")
            }
            return try emitOperandPair(
                opcodeBytes: [0x0F, opcode2],
                width: dst.width,
                rmOperand: source,
                regHigh: dst.highBit,
                regLow: dst.lowBits,
                forceREX: forceREX
            )

        case .movsxd:
            return try emitOperandPair(
                opcode: 0x63,
                width: dst.width,
                rmOperand: source,
                regHigh: dst.highBit,
                regLow: dst.lowBits,
                forceREX: forceREX
            )
        }
    }

    /// `BSWAP r32/r64` rides the 0F-escape `C8+rd` form. The 16-bit
    /// form is undefined and rejected by the parser.
    private static func encodeBswap(_ reg: X86.Register) throws -> [UInt8] {
        var bytes: [UInt8] = []
        let rexW: UInt8 = reg.width == .qword ? 1 : 0
        if let rex = X86.REX.build(w: rexW, b: reg.highBit) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(0xC8 | reg.lowBits)
        return bytes
    }

    // MARK: - IN / OUT

    /// IN/OUT opcodes are paired across direction and port form:
    /// E4/E5 IN imm, E6/E7 OUT imm, EC/ED IN DX, EE/EF OUT DX. The
    /// low bit selects byte (0) vs word/dword (1).
    private static func encodePortIO(register reg: X86.Register, port: X86.PortSource, isOut: Bool) -> [UInt8] {
        let isByte = reg.width == .byte
        var bytes: [UInt8] = []
        if reg.width == .word { bytes.append(X86.operandSizeOverride) }
        let opcode: UInt8
        switch (port, isOut) {
        case (.immediate, false): opcode = isByte ? 0xE4 : 0xE5
        case (.immediate, true):  opcode = isByte ? 0xE6 : 0xE7
        case (.dx, false):        opcode = isByte ? 0xEC : 0xED
        case (.dx, true):         opcode = isByte ? 0xEE : 0xEF
        }
        bytes.append(opcode)
        if case .immediate(let imm) = port { bytes.append(imm) }
        return bytes
    }

    /// SLDT/STR/LLDT/LTR/VERR/VERW/SMSW/LMSW share the `0F (00|01) /n`
    /// shape with a single r/m operand. Width follows the standard 0x66
    /// / REX.W rules: r/m16 with the 0x66 prefix, r/m64 with REX.W, and
    /// r/m32 by default.
    private static func encodeSystemRM(_ kind: X86.SystemRMKind, target: X86.RegisterOrMemory) throws -> [UInt8] {
        if case .register(let r) = target {
            try checkRegisterRegisterCompat([r], mnemonic: kind.rawValue)
        }
        let forceREX: Bool
        if case .register(let r) = target { forceREX = needsForcedREX([r]) } else { forceREX = false }
        return try emitOperandPair(
            opcodeBytes: [0x0F, kind.escape2],
            width: target.width,
            rmOperand: target,
            regHigh: 0,
            regLow: kind.slashDigit,
            forceREX: forceREX
        )
    }

    // MARK: - SSE arithmetic (ADD/SUB/MUL/DIV/MIN/MAX/SQRT)

    /// All SSE arithmetic ops share the `prefix? 0F 5x /r` shape with
    /// `xmm` destination and `xmm/m` source. The shared helper writes
    /// the mandatory prefix, the REX byte for any extended XMM register
    /// references, the 0F escape, the operation opcode, and the
    /// ModR/M+SIB+disp body for the source.
    private static func encodeSSEArithmetic(_ kind: X86.SSEArithmeticKind, destination dst: X86.XMMRegister, source: X86.XMMOrMemory) throws -> [UInt8] {
        var bytes: [UInt8] = []
        if let prefix = kind.mandatoryPrefix { bytes.append(prefix) }
        switch source {
        case .register(let rm):
            if let rex = X86.REX.build(r: dst.highBit, b: rm.highBit) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.opcode2)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: dst.lowBits, rm: rm.lowBits))
        case .memory(let mem):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: dst.lowBits)
            if let rex = X86.REX.build(r: dst.highBit, x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.opcode2)
            bytes.append(contentsOf: addressing)
        }
        return bytes
    }

    // MARK: - SSE2 imm8 SIMD shifts

    /// `66 [REX] 0F 71/72/73 /n ib` with `mod == 11` — the shift count
    /// is the imm8 byte and the target is the XMM register named by
    /// `r/m` (REX.B extends it). REX.R is unused because the `reg`
    /// field is a slash-digit selector.
    private static func encodeSSEImmediateShift(_ kind: X86.SSEImmediateShiftKind, target: X86.XMMRegister, immediate: UInt8) -> [UInt8] {
        var bytes: [UInt8] = [0x66]
        if let rex = X86.REX.build(b: target.highBit) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(kind.opcode2)
        bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: kind.slashDigit, rm: target.lowBits))
        bytes.append(immediate)
        return bytes
    }

    // MARK: - SSE2 packed integer ops

    /// All SSE2 packed-integer ops share the same `66 0F xx /r` shape
    /// with `xmm` destination and `xmm/m128` source — same wiring as
    /// the SSE arithmetic family, just with a fixed 0x66 prefix.
    private static func encodeSSEPackedInteger(_ kind: X86.SSEPackedIntegerKind, destination dst: X86.XMMRegister, source: X86.XMMOrMemory) throws -> [UInt8] {
        var bytes: [UInt8] = [0x66]
        switch source {
        case .register(let rm):
            if let rex = X86.REX.build(r: dst.highBit, b: rm.highBit) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.opcode2)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: dst.lowBits, rm: rm.lowBits))
        case .memory(let mem):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: dst.lowBits)
            if let rex = X86.REX.build(r: dst.highBit, x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.opcode2)
            bytes.append(contentsOf: addressing)
        }
        return bytes
    }

    // MARK: - SSE shuffles (imm8)

    /// `[prefix] 0F 70/C6 /r ib` — three-operand shuffle with imm8.
    private static func encodeSSEShuffle(_ kind: X86.SSEShuffleKind, destination dst: X86.XMMRegister, source: X86.XMMOrMemory, immediate: UInt8) throws -> [UInt8] {
        var bytes: [UInt8] = []
        if let prefix = kind.mandatoryPrefix {
            bytes.append(prefix)
        }
        switch source {
        case .register(let rm):
            if let rex = X86.REX.build(r: dst.highBit, b: rm.highBit) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.opcode2)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: dst.lowBits, rm: rm.lowBits))
        case .memory(let mem):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: dst.lowBits)
            if let rex = X86.REX.build(r: dst.highBit, x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.opcode2)
            bytes.append(contentsOf: addressing)
        }
        bytes.append(immediate)
        return bytes
    }

    // MARK: - SSE compares (imm8 predicate)

    /// `[prefix] 0F C2 /r ib` — same ModR/M wiring as the shuffle
    /// family, but the opcode is fixed at 0xC2.
    private static func encodeSSECompare(_ kind: X86.SSECompareKind, destination dst: X86.XMMRegister, source: X86.XMMOrMemory, predicate: UInt8) throws -> [UInt8] {
        var bytes: [UInt8] = []
        if let prefix = kind.mandatoryPrefix {
            bytes.append(prefix)
        }
        switch source {
        case .register(let rm):
            if let rex = X86.REX.build(r: dst.highBit, b: rm.highBit) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(0xC2)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: dst.lowBits, rm: rm.lowBits))
        case .memory(let mem):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: dst.lowBits)
            if let rex = X86.REX.build(r: dst.highBit, x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(0xC2)
            bytes.append(contentsOf: addressing)
        }
        bytes.append(predicate)
        return bytes
    }

    // MARK: - SSE half-vector moves (MOV*PS / MOV*PD / MOVHLPS / MOVLHPS)

    /// `[66] 0F 12/13/16/17 /r`. Load opcode (12/16) is used when the
    /// destination is a register; store opcode (13/17) when it is
    /// memory. The register-only kinds (MOVHLPS / MOVLHPS) always use
    /// the load opcode.
    private static func encodeSSEHalfMove(_ kind: X86.SSEHalfMoveKind, destination: X86.XMMOrMemory, source: X86.XMMOrMemory) throws -> [UInt8] {
        var bytes: [UInt8] = []
        if let prefix = kind.mandatoryPrefix {
            bytes.append(prefix)
        }
        switch (destination, source) {
        case let (.register(dst), .register(src)):
            guard kind.allowsRegister else {
                throw AssemblerError.unsupportedOperand("\(kind.rawValue): requires a memory operand")
            }
            if let rex = X86.REX.build(r: dst.highBit, b: src.highBit) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.loadOpcode)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: dst.lowBits, rm: src.lowBits))
        case let (.register(dst), .memory(mem)):
            guard kind.allowsMemory else {
                throw AssemblerError.unsupportedOperand("\(kind.rawValue): operands must both be XMM registers")
            }
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: dst.lowBits)
            if let rex = X86.REX.build(r: dst.highBit, x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.loadOpcode)
            bytes.append(contentsOf: addressing)
        case let (.memory(mem), .register(src)):
            guard kind.allowsMemory else {
                throw AssemblerError.unsupportedOperand("\(kind.rawValue): operands must both be XMM registers")
            }
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: src.lowBits)
            if let rex = X86.REX.build(r: src.highBit, x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.loadOpcode + 1)
            bytes.append(contentsOf: addressing)
        case (.memory, .memory):
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): cannot have two memory operands")
        }
        return bytes
    }

    // MARK: - SSE mask extract (PMOVMSKB / MOVMSKPS / MOVMSKPD)

    /// `[66] 0F D7|50 /r` — `reg` is the destination GPR, `rm` is the
    /// source XMM. REX.W picks r64 over r32.
    private static func encodeSSEMaskExtract(_ kind: X86.SSEMaskExtractKind, destination dst: X86.Register, source src: X86.XMMRegister) throws -> [UInt8] {
        guard dst.width == .dword || dst.width == .qword else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be a 32- or 64-bit GPR")
        }
        var bytes: [UInt8] = []
        if let prefix = kind.mandatoryPrefix {
            bytes.append(prefix)
        }
        let rexW: UInt8 = dst.width == .qword ? 1 : 0
        if let rex = X86.REX.build(w: rexW, r: dst.highBit, b: src.highBit) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(kind.opcode2)
        bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: dst.lowBits, rm: src.lowBits))
        return bytes
    }

    // MARK: - MASKMOVDQU

    /// `66 0F F7 /r` — `reg` is the source XMM (bytes to store at
    /// `[RDI]`), `rm` is the mask XMM whose per-byte sign bits select.
    private static func encodeMaskMovDqu(source: X86.XMMRegister, mask: X86.XMMRegister) -> [UInt8] {
        var bytes: [UInt8] = [0x66]
        if let rex = X86.REX.build(r: source.highBit, b: mask.highBit) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(0xF7)
        bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: source.lowBits, rm: mask.lowBits))
        return bytes
    }

    // MARK: - LDMXCSR / STMXCSR

    /// `0F AE /2` (ldmxcsr) or `/3` (stmxcsr) — single m32 operand.
    private static func encodeMXCSR(_ kind: X86.MXCSRKind, memory: X86.MemoryOperand) throws -> [UInt8] {
        var bytes: [UInt8] = []
        let (addressing, rexX, rexB) = try encodeMemoryAddressing(memory, regField: kind.slashDigit)
        if let rex = X86.REX.build(x: rexX, b: rexB) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(0xAE)
        bytes.append(contentsOf: addressing)
        return bytes
    }

    // MARK: - Non-temporal SSE stores (MOVNTPS / MOVNTPD / MOVNTDQ)

    private static func encodeSSENonTemporalStore(_ kind: X86.SSENonTemporalKind, memory: X86.MemoryOperand, source: X86.XMMRegister) throws -> [UInt8] {
        var bytes: [UInt8] = []
        if let prefix = kind.mandatoryPrefix {
            bytes.append(prefix)
        }
        let (addressing, rexX, rexB) = try encodeMemoryAddressing(memory, regField: source.lowBits)
        if let rex = X86.REX.build(r: source.highBit, x: rexX, b: rexB) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(kind.opcode2)
        bytes.append(contentsOf: addressing)
        return bytes
    }

    // MARK: - MOVNTI

    /// `0F C3 /r` — m32/m64 ← r32/r64. REX.W picks the 64-bit form.
    private static func encodeMovnti(memory: X86.MemoryOperand, source: X86.Register) throws -> [UInt8] {
        guard source.width == .dword || source.width == .qword else {
            throw AssemblerError.unsupportedOperand("movnti: source must be a 32- or 64-bit GPR")
        }
        var bytes: [UInt8] = []
        let rexW: UInt8 = source.width == .qword ? 1 : 0
        let (addressing, rexX, rexB) = try encodeMemoryAddressing(memory, regField: source.lowBits)
        if let rex = X86.REX.build(w: rexW, r: source.highBit, x: rexX, b: rexB) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(0xC3)
        bytes.append(contentsOf: addressing)
        return bytes
    }

    // MARK: - PREFETCH family

    /// `0F 18 /n` or `0F 0D /1` — single byte-pointer memory operand,
    /// hint encoded in ModR/M.reg.
    private static func encodePrefetch(_ kind: X86.PrefetchKind, memory: X86.MemoryOperand) throws -> [UInt8] {
        var bytes: [UInt8] = []
        let (addressing, rexX, rexB) = try encodeMemoryAddressing(memory, regField: kind.slashDigit)
        if let rex = X86.REX.build(x: rexX, b: rexB) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(kind.opcode2)
        bytes.append(contentsOf: addressing)
        return bytes
    }

    // MARK: - MOVD / MOVQ (XMM ↔ GPR/memory)

    /// `66 [REX.W] 0F 6E/7E /r` — load (6E) or store (7E) the low
    /// dword/qword of an XMM register against a GPR or memory operand.
    /// REX.W selects MOVQ over MOVD.
    private static func encodeMovDQ(_ kind: X86.MovDQKind, direction: X86.MovDQDirection, xmm: X86.XMMRegister, gpr: X86.RegisterOrMemory) throws -> [UInt8] {
        var bytes: [UInt8] = [0x66]
        let rexW: UInt8 = kind == .movq ? 1 : 0
        let opcode2: UInt8 = direction == .load ? 0x6E : 0x7E
        switch gpr {
        case .register(let r):
            try checkRegisterRegisterCompat([r], mnemonic: kind.rawValue)
            if let rex = X86.REX.build(w: rexW, r: xmm.highBit, b: r.highBit, forceEmit: needsForcedREX([r])) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(opcode2)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: xmm.lowBits, rm: r.lowBits))
        case .memory(let mem, _):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: xmm.lowBits)
            if let rex = X86.REX.build(w: rexW, r: xmm.highBit, x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(opcode2)
            bytes.append(contentsOf: addressing)
        }
        return bytes
    }

    // MARK: - SSE GPR ↔ XMM conversions

    /// `CVTSI2SS xmm, r/m32-or-64` / `CVTSI2SD xmm, r/m32-or-64` —
    /// `F3/F2 0F 2A /r`. REX.W rides the source GPR's width.
    private static func encodeSSEIntToFloat(_ kind: X86.SSEIntToFloatKind, destination dst: X86.XMMRegister, source: X86.RegisterOrMemory) throws -> [UInt8] {
        var bytes: [UInt8] = [kind.mandatoryPrefix]
        let rexW: UInt8 = source.width == .qword ? 1 : 0
        switch source {
        case .register(let rm):
            try checkRegisterRegisterCompat([rm], mnemonic: kind.rawValue)
            if let rex = X86.REX.build(w: rexW, r: dst.highBit, b: rm.highBit, forceEmit: needsForcedREX([rm])) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(0x2A)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: dst.lowBits, rm: rm.lowBits))
        case .memory(let mem, _):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: dst.lowBits)
            if let rex = X86.REX.build(w: rexW, r: dst.highBit, x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(0x2A)
            bytes.append(contentsOf: addressing)
        }
        return bytes
    }

    /// `CVTSx2SI` / `CVTTSx2SI r32-or-64, xmm/m32-or-m64` —
    /// `F3/F2 0F 2C-or-2D /r`. REX.W rides the destination GPR's width.
    private static func encodeSSEFloatToInt(_ kind: X86.SSEFloatToIntKind, destination dst: X86.Register, source: X86.XMMOrMemory) throws -> [UInt8] {
        try checkRegisterRegisterCompat([dst], mnemonic: kind.rawValue)
        var bytes: [UInt8] = [kind.mandatoryPrefix]
        let rexW: UInt8 = dst.width == .qword ? 1 : 0
        switch source {
        case .register(let rm):
            if let rex = X86.REX.build(w: rexW, r: dst.highBit, b: rm.highBit, forceEmit: needsForcedREX([dst])) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.opcode2)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: dst.lowBits, rm: rm.lowBits))
        case .memory(let mem):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: dst.lowBits)
            if let rex = X86.REX.build(w: rexW, r: dst.highBit, x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.opcode2)
            bytes.append(contentsOf: addressing)
        }
        return bytes
    }

    // MARK: - SSE MOV

    /// SSE/SSE2 MOV family. Each kind has its own mandatory prefix
    /// (none/66/F2/F3) and a load/store opcode pair. The encoder picks
    /// the form by which side is the register vs memory.
    private static func encodeSSEMov(_ kind: X86.SSEMovKind, destination: X86.XMMOrMemory, source: X86.XMMOrMemory) throws -> [UInt8] {
        let isLoad: Bool
        let xmm: X86.XMMRegister
        let rm: X86.XMMOrMemory
        switch (destination, source) {
        case (.register(let dst), _):
            isLoad = true
            xmm = dst
            rm = source
        case (_, .register(let src)):
            isLoad = false
            xmm = src
            rm = destination
        default:
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): cannot have two memory operands")
        }

        var bytes: [UInt8] = []
        if let prefix = kind.mandatoryPrefix { bytes.append(prefix) }
        let opcode2 = isLoad ? kind.loadOpcode : kind.storeOpcode

        switch rm {
        case .register(let rmReg):
            if let rex = X86.REX.build(r: xmm.highBit, b: rmReg.highBit) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(opcode2)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: xmm.lowBits, rm: rmReg.lowBits))
        case .memory(let mem):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: xmm.lowBits)
            if let rex = X86.REX.build(r: xmm.highBit, x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(opcode2)
            bytes.append(contentsOf: addressing)
        }
        return bytes
    }

    // MARK: - MOV CR/DR + LAR / LSL

    /// MOV r64, CRn/DRn and MOV CRn/DRn, r64. Operand is implicitly
    /// 64-bit in long mode, so REX.W is not set. REX.R extends the
    /// system-register number (the modrm.reg field); REX.B extends
    /// the GPR (the modrm.rm field).
    private static func encodeMovSystemRegister(kind: X86.SystemRegisterKind, sysregNumber: UInt8, register reg: X86.Register, isRead: Bool) -> [UInt8] {
        let opcode2 = isRead ? kind.readOpcode2 : kind.writeOpcode2
        let rexR: UInt8 = (sysregNumber >> 3) & 0x1
        let rexB: UInt8 = reg.highBit
        var bytes: [UInt8] = []
        if let rex = X86.REX.build(r: rexR, b: rexB) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(opcode2)
        bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: sysregNumber & 0x7, rm: reg.lowBits))
        return bytes
    }

    /// LAR and LSL share the same `r, r/m` shape as CMOVcc.
    private static func encodeLarLsl(opcode2: UInt8, destination dst: X86.Register, source: X86.RegisterOrMemory, mnemonic: String) throws -> [UInt8] {
        guard dst.width != .byte else {
            throw AssemblerError.unsupportedOperand("\(mnemonic): byte destination not supported")
        }
        if case .register(let r) = source {
            try checkRegisterRegisterCompat([dst, r], mnemonic: mnemonic)
        } else {
            try checkRegisterRegisterCompat([dst], mnemonic: mnemonic)
        }
        let forceREX: Bool
        if case .register(let r) = source { forceREX = needsForcedREX([dst, r]) }
        else { forceREX = needsForcedREX([dst]) }
        return try emitOperandPair(
            opcodeBytes: [0x0F, opcode2],
            width: dst.width,
            rmOperand: source,
            regHigh: dst.highBit,
            regLow: dst.lowBits,
            forceREX: forceREX
        )
    }

    // MARK: - Memory-only system instructions

    /// Encode one of the system instructions whose only operand is a
    /// memory reference and whose width is intrinsic to the mnemonic
    /// (CLFLUSH, INVLPG, the upcoming SGDT/SIDT/LGDT/LIDT family).
    /// The two-byte opcode is 0F <escape2>; the `/n` slash-digit picks
    /// the specific operation. No operand-size prefix, no REX.W.
    private static func encodeMemoryOnlySys(escape2: UInt8, slashDigit: UInt8, memory: X86.MemoryOperand) throws -> [UInt8] {
        let (addressing, rexX, rexB) = try encodeMemoryAddressing(memory, regField: slashDigit)
        var bytes: [UInt8] = []
        if let rex = X86.REX.build(x: rexX, b: rexB) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(escape2)
        bytes.append(contentsOf: addressing)
        return bytes
    }

    // MARK: - CMOVcc / SETcc

    /// CMOVcc r, r/m — `0F (40 | cc) /r`. No byte form.
    private static func encodeCmovcc(_ cond: X86.Condition, destination dst: X86.Register, source: X86.RegisterOrMemory) throws -> [UInt8] {
        if case .register(let r) = source {
            try checkRegisterRegisterCompat([dst, r], mnemonic: "cmov\(cond.rawValue)")
        } else {
            try checkRegisterRegisterCompat([dst], mnemonic: "cmov\(cond.rawValue)")
        }
        let forceREX: Bool
        if case .register(let r) = source { forceREX = needsForcedREX([dst, r]) }
        else { forceREX = needsForcedREX([dst]) }
        return try emitOperandPair(
            opcodeBytes: [0x0F, 0x40 | cond.encoding],
            width: dst.width,
            rmOperand: source,
            regHigh: dst.highBit,
            regLow: dst.lowBits,
            forceREX: forceREX
        )
    }

    /// SETcc r/m8 — `0F (90 | cc) /0`. The ModR/M `reg` field is don't-
    /// care; we always emit /0 for canonical disassembly.
    private static func encodeSetcc(_ cond: X86.Condition, target: X86.RegisterOrMemory) throws -> [UInt8] {
        if case .register(let r) = target {
            try checkRegisterRegisterCompat([r], mnemonic: "set\(cond.rawValue)")
        }
        let forceREX: Bool
        if case .register(let r) = target { forceREX = needsForcedREX([r]) } else { forceREX = false }
        return try emitOperandPair(
            opcodeBytes: [0x0F, 0x90 | cond.encoding],
            width: .byte,
            rmOperand: target,
            regHigh: 0,
            regLow: 0,
            forceREX: forceREX
        )
    }

    // MARK: - BT / BTS / BTR / BTC and BSF / BSR

    private static func encodeBitTest(_ kind: X86.BitTestKind, target: X86.RegisterOrMemory, source: X86.BitTestSource) throws -> [UInt8] {
        let width = target.width
        if case .register(let r) = target {
            try checkRegisterRegisterCompat([r], mnemonic: kind.rawValue)
        }
        switch source {
        case .register(let r):
            try checkRegisterRegisterCompat([r], mnemonic: kind.rawValue)
            let forceREX: Bool
            if case .register(let t) = target { forceREX = needsForcedREX([t, r]) }
            else { forceREX = needsForcedREX([r]) }
            return try emitOperandPair(
                opcodeBytes: [0x0F, kind.registerFormOpcode],
                width: width,
                rmOperand: target,
                regHigh: r.highBit,
                regLow: r.lowBits,
                forceREX: forceREX
            )
        case .immediate(let imm):
            let forceREX: Bool
            if case .register(let t) = target { forceREX = needsForcedREX([t]) } else { forceREX = false }
            var bytes = try emitOperandPair(
                opcodeBytes: [0x0F, 0xBA],
                width: width,
                rmOperand: target,
                regHigh: 0,
                regLow: kind.slashDigit,
                forceREX: forceREX
            )
            bytes.append(imm)
            return bytes
        }
    }

    /// POPCNT / LZCNT / TZCNT share `0F B8/BC/BD` with the F3
    /// mandatory prefix. Without the F3 prefix the same opcodes mean
    /// BSF/BSR (and the B8 form is undefined in 64-bit mode).
    ///
    /// Prefix order is `66 F3 REX 0F ..` — the operand-size override
    /// comes first, followed by the mandatory F3, followed by the REX
    /// byte. Inlined rather than going through emitOperandPair because
    /// that helper places its single legacy prefix (0x66) directly
    /// before REX, leaving no slot for F3.
    private static func encodeBitCount(_ kind: X86.BitCountKind, destination dst: X86.Register, source: X86.RegisterOrMemory) throws -> [UInt8] {
        let width = dst.width
        if case .register(let r) = source {
            try checkRegisterRegisterCompat([dst, r], mnemonic: kind.rawValue)
        } else {
            try checkRegisterRegisterCompat([dst], mnemonic: kind.rawValue)
        }
        let forceREX: Bool
        if case .register(let r) = source { forceREX = needsForcedREX([dst, r]) }
        else { forceREX = needsForcedREX([dst]) }

        var bytes: [UInt8] = []
        if width == .word { bytes.append(X86.operandSizeOverride) }
        bytes.append(0xF3)
        let rexW: UInt8 = width == .qword ? 1 : 0

        switch source {
        case .register(let rm):
            if let rex = X86.REX.build(w: rexW, r: dst.highBit, x: 0, b: rm.highBit, forceEmit: forceREX) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.opcode2)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: dst.lowBits, rm: rm.lowBits))
        case .memory(let mem, _):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: dst.lowBits)
            if let rex = X86.REX.build(w: rexW, r: dst.highBit, x: rexX, b: rexB, forceEmit: forceREX) {
                bytes.append(rex)
            }
            bytes.append(0x0F)
            bytes.append(kind.opcode2)
            bytes.append(contentsOf: addressing)
        }
        return bytes
    }

    private static func encodeBitScan(_ kind: X86.BitScanKind, destination dst: X86.Register, source: X86.RegisterOrMemory) throws -> [UInt8] {
        if case .register(let r) = source {
            try checkRegisterRegisterCompat([dst, r], mnemonic: kind.rawValue)
        } else {
            try checkRegisterRegisterCompat([dst], mnemonic: kind.rawValue)
        }
        let forceREX: Bool
        if case .register(let r) = source { forceREX = needsForcedREX([dst, r]) }
        else { forceREX = needsForcedREX([dst]) }
        return try emitOperandPair(
            opcodeBytes: [0x0F, kind.opcode2],
            width: dst.width,
            rmOperand: source,
            regHigh: dst.highBit,
            regLow: dst.lowBits,
            forceREX: forceREX
        )
    }

    // MARK: - XCHG / XADD / CMPXCHG / CMPXCHG8B / 16B

    /// XCHG picks the short form (`90+rd` with the operand-size prefix)
    /// when exactly one operand is rAX and the width is non-byte; the
    /// long form (86/87 `/r` MR) is used in all other cases. Both forms
    /// are symmetric in semantics so the parser-derived `target` may be
    /// either side.
    private static func encodeXchg(target: X86.RegisterOrMemory, register: X86.Register) throws -> [UInt8] {
        let width = register.width
        if case .register(let r) = target {
            guard r.width == width else {
                throw AssemblerError.unsupportedOperand("xchg: width mismatch")
            }
            if width != .byte {
                // Short form when exactly one operand is rAX.
                if r.number == 0 && register.number != 0 {
                    return encodeXchgShort(other: register, width: width)
                }
                if register.number == 0 && r.number != 0 {
                    return encodeXchgShort(other: r, width: width)
                }
            }
            try checkRegisterRegisterCompat([r, register], mnemonic: "xchg")
            return try emitOperandPair(
                opcode: width == .byte ? 0x86 : 0x87,
                width: width,
                rmOperand: .register(r),
                regHigh: register.highBit,
                regLow: register.lowBits,
                forceREX: needsForcedREX([r, register])
            )
        }
        // Memory target — MR form is the only available encoding.
        try checkRegisterRegisterCompat([register], mnemonic: "xchg")
        return try emitOperandPair(
            opcode: width == .byte ? 0x86 : 0x87,
            width: width,
            rmOperand: target,
            regHigh: register.highBit,
            regLow: register.lowBits,
            forceREX: needsForcedREX([register])
        )
    }

    private static func encodeXchgShort(other: X86.Register, width: X86.RegisterWidth) -> [UInt8] {
        var bytes: [UInt8] = []
        if width == .word { bytes.append(X86.operandSizeOverride) }
        let rexW: UInt8 = width == .qword ? 1 : 0
        if let rex = X86.REX.build(w: rexW, b: other.highBit) {
            bytes.append(rex)
        }
        bytes.append(0x90 | other.lowBits)
        return bytes
    }

    /// XADD and CMPXCHG share the same MR shape (`0F C0/C1 /r` and
    /// `0F B0/B1 /r`); only the second opcode byte differs.
    private static func encodeXaddCmpxchg(target: X86.RegisterOrMemory, source: X86.Register, kindByte: UInt8, kindNonByte: UInt8, mnemonic: String) throws -> [UInt8] {
        let width = source.width
        if case .register(let r) = target {
            guard r.width == width else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): width mismatch")
            }
            try checkRegisterRegisterCompat([r, source], mnemonic: mnemonic)
        } else {
            try checkRegisterRegisterCompat([source], mnemonic: mnemonic)
        }
        let forceREX: Bool
        if case .register(let r) = target { forceREX = needsForcedREX([r, source]) }
        else { forceREX = needsForcedREX([source]) }
        return try emitOperandPair(
            opcodeBytes: [0x0F, width == .byte ? kindByte : kindNonByte],
            width: width,
            rmOperand: target,
            regHigh: source.highBit,
            regLow: source.lowBits,
            forceREX: forceREX
        )
    }

    /// CMPXCHG8B / CMPXCHG16B (`0F C7 /1`). The 16-byte variant is the
    /// REX.W form. The memory operand's width is implicit in the
    /// mnemonic, so it doesn't ride emitOperandPair's width logic.
    private static func encodeCmpxchgWide(_ kind: X86.CmpxchgWideKind, memory mem: X86.MemoryOperand) throws -> [UInt8] {
        let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: 1)
        var bytes: [UInt8] = []
        let rexW: UInt8 = kind == .cmpxchg16b ? 1 : 0
        if let rex = X86.REX.build(w: rexW, x: rexX, b: rexB) {
            bytes.append(rex)
        }
        bytes.append(0x0F)
        bytes.append(0xC7)
        bytes.append(contentsOf: addressing)
        return bytes
    }

    // MARK: - Indirect JMP / CALL (FF /4 and FF /2)

    /// In 64-bit mode JMP / CALL with an `r/m` operand are always r/m64;
    /// no REX.W is needed because qword is the default operand size for
    /// these forms. The `r/m` slot rides the shared operand-pair emitter
    /// at width = qword but suppresses the REX.W bit explicitly.
    private static func encodeIndirect(target: X86.RegisterOrMemory, slashDigit: UInt8, mnemonic: String) throws -> [UInt8] {
        switch target {
        case .register(let reg):
            guard reg.width == .qword else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): indirect target must be 64-bit")
            }
            var bytes: [UInt8] = []
            if let rex = X86.REX.build(b: reg.highBit) {
                bytes.append(rex)
            }
            bytes.append(0xFF)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: slashDigit, rm: reg.lowBits))
            return bytes
        case .memory(let mem, let width):
            guard width == .qword else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): indirect target must be 64-bit")
            }
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: slashDigit)
            var bytes: [UInt8] = []
            if let rex = X86.REX.build(x: rexX, b: rexB) {
                bytes.append(rex)
            }
            bytes.append(0xFF)
            bytes.append(contentsOf: addressing)
            return bytes
        }
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
        forceREX: Bool = false,
        useREXW: Bool = true
    ) throws -> [UInt8] {
        try emitOperandPair(
            opcodeBytes: [opcode],
            width: width,
            rmOperand: rmOperand,
            regHigh: regHigh,
            regLow: regLow,
            forceREX: forceREX,
            useREXW: useREXW
        )
    }

    /// Variant accepting a multi-byte opcode (e.g. `[0x0F, 0xAF]` for
    /// IMUL r, r/m). When `useREXW` is `false`, REX.W is suppressed even
    /// for qword operands — used by instructions whose operand size is
    /// implicitly 64-bit in long mode (PUSH/POP, indirect CALL/JMP).
    private static func emitOperandPair(
        opcodeBytes: [UInt8],
        width: X86.RegisterWidth,
        rmOperand: X86.RegisterOrMemory,
        regHigh: UInt8,
        regLow: UInt8,
        forceREX: Bool = false,
        useREXW: Bool = true
    ) throws -> [UInt8] {
        var bytes: [UInt8] = []
        if width == .word { bytes.append(X86.operandSizeOverride) }
        let rexW: UInt8 = (useREXW && width == .qword) ? 1 : 0
        switch rmOperand {
        case .register(let rm):
            if let rex = X86.REX.build(w: rexW, r: regHigh, x: 0, b: rm.highBit, forceEmit: forceREX) {
                bytes.append(rex)
            }
            bytes.append(contentsOf: opcodeBytes)
            bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: regLow, rm: rm.lowBits))
        case .memory(let mem, _):
            let (addressing, rexX, rexB) = try encodeMemoryAddressing(mem, regField: regLow)
            if let rex = X86.REX.build(w: rexW, r: regHigh, x: rexX, b: rexB, forceEmit: forceREX) {
                bytes.append(rex)
            }
            bytes.append(contentsOf: opcodeBytes)
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
        case .xmmword:
            throw AssemblerError.unsupportedOperand("xmmword immediate not supported")
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
