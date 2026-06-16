import Foundation

internal enum X86InstructionDecoder {
    /// One decoded instruction plus the number of bytes it consumed.
    struct Decoded {
        var instruction: X86.Instruction
        var length: Int
    }

    private static let zeroOperandTable: [X86.ZeroOperandKind] =
        X86.ZeroOperandKind.allCases.sorted { $0.bytes.count > $1.bytes.count }

    /// Decode a single instruction starting at `bytes[offset]`.
    static func decode(_ bytes: [UInt8], offset: Int) throws -> Decoded {
        guard offset < bytes.count else {
            throw AssemblerError.invalidByteCount(bytes.count)
        }
        if let match = matchZeroOperand(bytes, offset: offset) {
            return Decoded(instruction: .zeroOperand(match.kind), length: match.length)
        }
        return try decodeOperandForm(bytes, offset: offset)
    }

    // MARK: - Zero-operand matcher

    private static func matchZeroOperand(_ bytes: [UInt8], offset: Int) -> (kind: X86.ZeroOperandKind, length: Int)? {
        for kind in zeroOperandTable {
            let pattern = kind.bytes
            guard offset + pattern.count <= bytes.count else { continue }
            var matches = true
            for (i, expected) in pattern.enumerated() where bytes[offset + i] != expected {
                matches = false
                break
            }
            if matches { return (kind, pattern.count) }
        }
        return nil
    }

    // MARK: - Operand-bearing instructions

    private struct Prefixes {
        var operandSize: Bool = false
        var addressSize: Bool = false
        /// The 0xF3 mandatory prefix. It doubles as the REP/REPZ string
        /// prefix when paired with MOVS/CMPS/SCAS/...; for SSE-style
        /// instructions and POPCNT/LZCNT/TZCNT it selects an alternate
        /// opcode at the 0F escape.
        var f3Prefix: Bool = false
        /// The 0xF2 prefix: REPNE/REPNZ on string ops, mandatory prefix
        /// for some SSE-style instructions.
        var f2Prefix: Bool = false
        var rex: UInt8? = nil

        var hasREX: Bool { rex != nil }
        var rexW: UInt8 { rex.map { X86.REX.w.extract($0) } ?? 0 }
        var rexR: UInt8 { rex.map { X86.REX.r.extract($0) } ?? 0 }
        var rexX: UInt8 { rex.map { X86.REX.x.extract($0) } ?? 0 }
        var rexB: UInt8 { rex.map { X86.REX.b.extract($0) } ?? 0 }
    }

    private struct Cursor {
        let bytes: [UInt8]
        let start: Int
        var offset: Int

        init(bytes: [UInt8], offset: Int) {
            self.bytes = bytes
            self.start = offset
            self.offset = offset
        }

        var consumed: Int { offset - start }

        mutating func takeByte() throws -> UInt8 {
            guard offset < bytes.count else { throw AssemblerError.invalidByteCount(bytes.count) }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func takeLE16() throws -> UInt16 {
            let lo = try takeByte()
            let hi = try takeByte()
            return UInt16(lo) | (UInt16(hi) << 8)
        }

        mutating func takeLE32() throws -> UInt32 {
            var value: UInt32 = 0
            for shift in stride(from: 0, to: 32, by: 8) {
                value |= UInt32(try takeByte()) << shift
            }
            return value
        }

        mutating func takeLE64() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 64, by: 8) {
                value |= UInt64(try takeByte()) << shift
            }
            return value
        }

        mutating func consumePrefixes() -> Prefixes {
            var prefixes = Prefixes()
            while offset < bytes.count {
                let byte = bytes[offset]
                if byte == X86.operandSizeOverride && !prefixes.operandSize {
                    prefixes.operandSize = true
                    offset += 1
                } else if byte == 0x67 && !prefixes.addressSize {
                    prefixes.addressSize = true
                    offset += 1
                } else if byte == 0xF3 && !prefixes.f3Prefix {
                    prefixes.f3Prefix = true
                    offset += 1
                } else if byte == 0xF2 && !prefixes.f2Prefix {
                    prefixes.f2Prefix = true
                    offset += 1
                } else if X86.REX.matches(byte) && prefixes.rex == nil {
                    prefixes.rex = byte
                    offset += 1
                } else {
                    break
                }
            }
            return prefixes
        }
    }

    private static func decodeOperandForm(_ bytes: [UInt8], offset: Int) throws -> Decoded {
        var cursor = Cursor(bytes: bytes, offset: offset)
        let prefixes = cursor.consumePrefixes()
        let opcode = try cursor.takeByte()

        // Binary ALU MR/RM/I family — 8 op groups of 6 opcodes in 0x00..0x3D.
        if opcode <= 0x3D, (opcode & 0x07) <= 5,
           let kind = X86.BinaryAluKind.decode(opcodeIndex: opcode >> 3) {
            return try decodeBinaryAlu(kind: kind, variant: opcode & 0x07, prefixes: prefixes, cursor: &cursor)
        }

        switch opcode {
        case 0x0F:
            let opcode2 = try cursor.takeByte()
            return try decodeTwoByteOpcode(opcode2: opcode2, prefixes: prefixes, cursor: &cursor)
        case 0x50...0x57:
            return try decodePushRegisterShort(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0x63:
            return try decodeMovsxd(prefixes: prefixes, cursor: &cursor)
        case 0x58...0x5F:
            return try decodePopRegisterShort(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0x68:
            return try decodePushImm32(cursor: &cursor)
        case 0x69, 0x6B:
            return try decodeImulImmediate(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0x6C, 0x6D, 0x6E, 0x6F:
            return try decodeStringOp(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0x6A:
            return try decodePushImm8(cursor: &cursor)
        case 0x70...0x7F:
            return try decodeJccRel8(opcode: opcode, cursor: &cursor)
        case 0x80, 0x81, 0x83:
            return try decodeBinaryAluMI(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0x84, 0x85:
            return try decodeTestMR(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0x86, 0x87:
            return try decodeXchgMR(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0x88, 0x89, 0x8A, 0x8B:
            return try decodeMovRegisterMemory(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0x8D:
            return try decodeLea(prefixes: prefixes, cursor: &cursor)
        case 0x8F:
            return try decodePopMemory(prefixes: prefixes, cursor: &cursor)
        case 0x90...0x97:
            // 0x90 alone is NOP and gets matched by the zero-operand
            // table earlier; if we land here, a prefix (REX or 0x66)
            // has been consumed, making this an XCHG short form.
            return try decodeXchgShort(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xA4, 0xA5, 0xA6, 0xA7, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF:
            return try decodeStringOp(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xE4, 0xE5:
            return try decodePortIO(opcode: opcode, isOut: false, withImmediate: true, prefixes: prefixes, cursor: &cursor)
        case 0xE6, 0xE7:
            return try decodePortIO(opcode: opcode, isOut: true, withImmediate: true, prefixes: prefixes, cursor: &cursor)
        case 0xEC, 0xED:
            return try decodePortIO(opcode: opcode, isOut: false, withImmediate: false, prefixes: prefixes, cursor: &cursor)
        case 0xEE, 0xEF:
            return try decodePortIO(opcode: opcode, isOut: true, withImmediate: false, prefixes: prefixes, cursor: &cursor)
        case 0xA8, 0xA9:
            return try decodeTestAccumulator(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xB0...0xB7:
            return try decodeMovImm8(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xB8...0xBF:
            return try decodeMovImmWord(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xC0, 0xC1, 0xD0, 0xD1, 0xD2, 0xD3:
            return try decodeShift(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xC6:
            return try decodeMovMI8(prefixes: prefixes, cursor: &cursor)
        case 0xC7:
            return try decodeMovMIWord(prefixes: prefixes, cursor: &cursor)
        case 0xC8:
            return try decodeEnter(cursor: &cursor)
        case 0xCD:
            let vector = try cursor.takeByte()
            return Decoded(instruction: .interrupt(vector: vector), length: cursor.consumed)
        case 0xE0, 0xE1, 0xE2, 0xE3:
            return try decodeLoop(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xE8:
            return try decodeCallRel32(cursor: &cursor)
        case 0xE9:
            return try decodeJmpRel32(cursor: &cursor)
        case 0xEB:
            return try decodeJmpRel8(cursor: &cursor)
        case 0xF6, 0xF7:
            return try decodeF6F7(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xFE, 0xFF:
            return try decodeFEFF(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        default:
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
    }

    // MARK: - Branches

    private static func decodeJmpRel8(cursor: inout Cursor) throws -> Decoded {
        let delta = Int64(Int8(bitPattern: try cursor.takeByte()))
        return Decoded(instruction: .jump(.offset(delta)), length: cursor.consumed)
    }

    private static func decodeJmpRel32(cursor: inout Cursor) throws -> Decoded {
        let delta = Int64(Int32(bitPattern: try cursor.takeLE32()))
        return Decoded(instruction: .jump(.offset(delta)), length: cursor.consumed)
    }

    private static func decodeJccRel8(opcode: UInt8, cursor: inout Cursor) throws -> Decoded {
        guard let cond = X86.Condition.decode(opcode & 0x0F) else {
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        let delta = Int64(Int8(bitPattern: try cursor.takeByte()))
        return Decoded(instruction: .conditionalJump(cond, .offset(delta)), length: cursor.consumed)
    }

    private static func decodeJccRel32(opcode2: UInt8, cursor: inout Cursor) throws -> Decoded {
        guard let cond = X86.Condition.decode(opcode2 & 0x0F) else {
            throw AssemblerError.unknownEncoding(UInt32(opcode2))
        }
        let delta = Int64(Int32(bitPattern: try cursor.takeLE32()))
        return Decoded(instruction: .conditionalJump(cond, .offset(delta)), length: cursor.consumed)
    }

    private static func decodeCallRel32(cursor: inout Cursor) throws -> Decoded {
        let delta = Int64(Int32(bitPattern: try cursor.takeLE32()))
        return Decoded(instruction: .call(.offset(delta)), length: cursor.consumed)
    }

    private static func decodeLoop(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        guard let kind = X86.LoopKind.decode(opcode: opcode, addressOverride: prefixes.addressSize) else {
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        let delta = Int64(Int8(bitPattern: try cursor.takeByte()))
        return Decoded(instruction: .loop(kind, .offset(delta)), length: cursor.consumed)
    }

    private static func decodeEnter(cursor: inout Cursor) throws -> Decoded {
        let allocation = try cursor.takeLE16()
        let nesting = try cursor.takeByte()
        return Decoded(
            instruction: .enter(allocation: allocation, nestingLevel: nesting),
            length: cursor.consumed
        )
    }

    // MARK: - 0F-escape two-byte opcodes

    private static func decodeTwoByteOpcode(opcode2: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        switch opcode2 {
        case 0x00:
            return try decodeOpcode0F00(prefixes: prefixes, cursor: &cursor)
        case 0x01:
            return try decodeOpcode0F01(prefixes: prefixes, cursor: &cursor)
        case 0x40...0x4F:
            return try decodeCmovcc(opcode2: opcode2, prefixes: prefixes, cursor: &cursor)
        case 0x80...0x8F:
            return try decodeJccRel32(opcode2: opcode2, cursor: &cursor)
        case 0x90...0x9F:
            return try decodeSetcc(opcode2: opcode2, prefixes: prefixes, cursor: &cursor)
        case 0xA3:
            return try decodeBitTestRegister(kind: .bt, prefixes: prefixes, cursor: &cursor)
        case 0xA4: return try decodeDoubleShift(kind: .shld, withImmediate: true,  prefixes: prefixes, cursor: &cursor)
        case 0xA5: return try decodeDoubleShift(kind: .shld, withImmediate: false, prefixes: prefixes, cursor: &cursor)
        case 0xAB:
            return try decodeBitTestRegister(kind: .bts, prefixes: prefixes, cursor: &cursor)
        case 0xAE:
            return try decodeOpcode0FAE(prefixes: prefixes, cursor: &cursor)
        case 0xAC: return try decodeDoubleShift(kind: .shrd, withImmediate: true,  prefixes: prefixes, cursor: &cursor)
        case 0xAD: return try decodeDoubleShift(kind: .shrd, withImmediate: false, prefixes: prefixes, cursor: &cursor)
        case 0xAF:
            return try decodeImulRegister(prefixes: prefixes, cursor: &cursor)
        case 0xB0, 0xB1:
            return try decodeXaddCmpxchg(opcode2: opcode2, isCmpxchg: true, prefixes: prefixes, cursor: &cursor)
        case 0xB3:
            return try decodeBitTestRegister(kind: .btr, prefixes: prefixes, cursor: &cursor)
        case 0xB6:
            return try decodeExtendingMove(kind: .movzx, sourceWidth: .byte, prefixes: prefixes, cursor: &cursor)
        case 0xB7:
            return try decodeExtendingMove(kind: .movzx, sourceWidth: .word, prefixes: prefixes, cursor: &cursor)
        case 0xB8:
            // POPCNT requires the F3 mandatory prefix; without F3, the
            // opcode is unassigned in 64-bit mode (legacy JMPE was
            // Itanium-only).
            guard prefixes.f3Prefix else {
                throw AssemblerError.unknownEncoding(UInt32(opcode2))
            }
            return try decodeBitCount(.popcnt, prefixes: prefixes, cursor: &cursor)
        case 0xBA:
            return try decodeBitTestImmediate(prefixes: prefixes, cursor: &cursor)
        case 0xBB:
            return try decodeBitTestRegister(kind: .btc, prefixes: prefixes, cursor: &cursor)
        case 0xBC:
            if prefixes.f3Prefix {
                return try decodeBitCount(.tzcnt, prefixes: prefixes, cursor: &cursor)
            }
            return try decodeBitScan(.bsf, prefixes: prefixes, cursor: &cursor)
        case 0xBD:
            if prefixes.f3Prefix {
                return try decodeBitCount(.lzcnt, prefixes: prefixes, cursor: &cursor)
            }
            return try decodeBitScan(.bsr, prefixes: prefixes, cursor: &cursor)
        case 0xBE:
            return try decodeExtendingMove(kind: .movsx, sourceWidth: .byte, prefixes: prefixes, cursor: &cursor)
        case 0xBF:
            return try decodeExtendingMove(kind: .movsx, sourceWidth: .word, prefixes: prefixes, cursor: &cursor)
        case 0xC0, 0xC1:
            return try decodeXaddCmpxchg(opcode2: opcode2, isCmpxchg: false, prefixes: prefixes, cursor: &cursor)
        case 0xC7:
            return try decodeCmpxchgWide(prefixes: prefixes, cursor: &cursor)
        case 0xC8...0xCF:
            return try decodeBswap(opcode2: opcode2, prefixes: prefixes, cursor: &cursor)
        default:
            throw AssemblerError.unknownEncoding(UInt32(opcode2))
        }
    }

    // MARK: - 0F 01 and 0F AE (system / fence groups)

    /// 0F 01 covers the descriptor-table family (SGDT/SIDT/LGDT/LIDT,
    /// SMSW/LMSW, INVLPG) plus mod=11 sub-encodings already in the
    /// zero-operand table (SWAPGS/RDTSCP/MONITOR/MWAIT).
    private static func decodeOpcode0F01(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        let nField = X86.ModRM.reg.extract(modrm)
        let modRegister = X86.ModRM.mod.extract(modrm) == X86.ModRM.modRegister

        // /4 SMSW and /6 LMSW accept r/m (register or memory); other
        // slash-digits are memory-only (SGDT/SIDT/LGDT/LIDT, INVLPG).
        if let kind = X86.SystemRMKind.decode(escape2: 0x01, slashDigit: nField) {
            let width = kind.allowsWideRegister ? selectWidth(prefixes: prefixes) : .word
            let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
            return Decoded(instruction: .systemRM(kind, target: target), length: cursor.consumed)
        }
        if modRegister {
            // mod=11 sub-encodings without a SystemRMKind entry are
            // SWAPGS/RDTSCP/MONITOR/MWAIT (zero-operand) or unmodelled.
            throw AssemblerError.unknownEncoding(0x01)
        }
        if nField == 7 {
            let memory = try decodeMemoryAddressing(modrm: modrm, prefixes: prefixes, cursor: &cursor)
            return Decoded(instruction: .invlpg(memory), length: cursor.consumed)
        }
        if let kind = X86.DescriptorTableKind.decode(slashDigit: nField) {
            let memory = try decodeMemoryAddressing(modrm: modrm, prefixes: prefixes, cursor: &cursor)
            return Decoded(instruction: .descriptorTable(kind, memory: memory), length: cursor.consumed)
        }
        throw AssemblerError.unknownEncoding(0x01)
    }

    /// 0F 00 covers SLDT/STR/LLDT/LTR/VERR/VERW — all r/m16 (with
    /// optional wider register destinations for the read variants).
    private static func decodeOpcode0F00(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        let nField = X86.ModRM.reg.extract(modrm)
        guard let kind = X86.SystemRMKind.decode(escape2: 0x00, slashDigit: nField) else {
            throw AssemblerError.unknownEncoding(0x00)
        }
        let width = kind.allowsWideRegister ? selectWidth(prefixes: prefixes) : .word
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        return Decoded(instruction: .systemRM(kind, target: target), length: cursor.consumed)
    }

    /// 0F AE covers FXSAVE/FXRSTOR/LDMXCSR/STMXCSR/XSAVE/XRSTOR and
    /// the three memory fences (LFENCE/MFENCE/SFENCE) plus CLFLUSH.
    /// The mod=11 sub-encodings of /5/6/7 are LFENCE/MFENCE/SFENCE and
    /// already in the zero-operand table; /7 mod!=11 is CLFLUSH.
    private static func decodeOpcode0FAE(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        let nField = X86.ModRM.reg.extract(modrm)
        if X86.ModRM.mod.extract(modrm) == X86.ModRM.modRegister {
            // mod=11 forms — LFENCE/MFENCE/SFENCE are zero-operand;
            // anything else here we don't model yet.
            throw AssemblerError.unknownEncoding(0xAE)
        }
        guard nField == 7 else {
            throw AssemblerError.unknownEncoding(0xAE)
        }
        let memory = try decodeMemoryAddressing(modrm: modrm, prefixes: prefixes, cursor: &cursor)
        return Decoded(instruction: .clflush(memory), length: cursor.consumed)
    }

    // MARK: - IN / OUT (port I/O)

    private static func decodePortIO(opcode: UInt8, isOut: Bool, withImmediate: Bool, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let isByte = (opcode & 0x01) == 0
        let width: X86.RegisterWidth
        if isByte             { width = .byte }
        else if prefixes.operandSize { width = .word }
        else                  { width = .dword }
        let register = X86.Register(number: 0, width: width)
        let port: X86.PortSource
        if withImmediate {
            port = .immediate(try cursor.takeByte())
        } else {
            port = .dx
        }
        let instruction: X86.Instruction = isOut
            ? .outToPort(source: register, port: port)
            : .inFromPort(target: register, port: port)
        return Decoded(instruction: instruction, length: cursor.consumed)
    }

    // MARK: - String operations

    private static func decodeStringOp(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        guard let kind = X86.StringOpKind.decode(
            opcode: opcode,
            operandSize: prefixes.operandSize,
            rexW: prefixes.rexW == 1
        ) else {
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        let prefix: X86.StringPrefix?
        if prefixes.f3Prefix       { prefix = .f3 }
        else if prefixes.f2Prefix  { prefix = .f2 }
        else                       { prefix = nil }
        return Decoded(instruction: .stringOp(kind, prefix: prefix), length: cursor.consumed)
    }

    // MARK: - CMOVcc / SETcc

    private static func decodeCmovcc(opcode2: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        guard let cond = X86.Condition.decode(opcode2 & 0x0F) else {
            throw AssemblerError.unknownEncoding(UInt32(opcode2))
        }
        let width = selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let destination = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let source = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        return Decoded(
            instruction: .cmovcc(cond, destination: destination, source: source),
            length: cursor.consumed
        )
    }

    private static func decodeSetcc(opcode2: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        guard let cond = X86.Condition.decode(opcode2 & 0x0F) else {
            throw AssemblerError.unknownEncoding(UInt32(opcode2))
        }
        let modrm = try cursor.takeByte()
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: .byte, cursor: &cursor)
        return Decoded(instruction: .setcc(cond, target: target), length: cursor.consumed)
    }

    // MARK: - BT / BTS / BTR / BTC and BSF / BSR

    private static func decodeBitTestRegister(kind: X86.BitTestKind, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let source = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        return Decoded(instruction: .bitTest(kind, target: target, source: .register(source)), length: cursor.consumed)
    }

    private static func decodeBitTestImmediate(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let nField = X86.ModRM.reg.extract(modrm)
        guard let kind = X86.BitTestKind.decode(slashDigit: nField) else {
            throw AssemblerError.unknownEncoding(0xBA)
        }
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        let imm = try cursor.takeByte()
        return Decoded(instruction: .bitTest(kind, target: target, source: .immediate(imm)), length: cursor.consumed)
    }

    private static func decodeBitScan(_ kind: X86.BitScanKind, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let destination = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let source = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        return Decoded(instruction: .bitScan(kind, destination: destination, source: source), length: cursor.consumed)
    }

    private static func decodeBitCount(_ kind: X86.BitCountKind, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let destination = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let source = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        return Decoded(instruction: .bitCount(kind, destination: destination, source: source), length: cursor.consumed)
    }

    // MARK: - XCHG / XADD / CMPXCHG / CMPXCHG8B / 16B

    private static func decodeXchgMR(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let isByte = (opcode == 0x86)
        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let register = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        return Decoded(instruction: .xchg(target: target, register: register), length: cursor.consumed)
    }

    /// Decode the `XCHG rAX, r` short form. Canonical disassembly places
    /// rAX first; the encoder produces the same bytes regardless of the
    /// source-level order.
    private static func decodeXchgShort(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let otherNumber = (prefixes.rexB << 3) | (opcode & 0x07)
        let other = X86.Register(number: otherNumber, width: width)
        let accumulator = X86.Register(number: 0, width: width)
        return Decoded(
            instruction: .xchg(target: .register(accumulator), register: other),
            length: cursor.consumed
        )
    }

    private static func decodeXaddCmpxchg(opcode2: UInt8, isCmpxchg: Bool, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let isByte = (opcode2 == 0xB0 || opcode2 == 0xC0)
        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let source = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        let instruction: X86.Instruction = isCmpxchg
            ? .cmpxchg(target: target, source: source)
            : .xadd(target: target, source: source)
        return Decoded(instruction: instruction, length: cursor.consumed)
    }

    private static func decodeCmpxchgWide(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        guard X86.ModRM.reg.extract(modrm) == 1 else {
            throw AssemblerError.unknownEncoding(0xC7)
        }
        guard X86.ModRM.mod.extract(modrm) != X86.ModRM.modRegister else {
            throw AssemblerError.unknownEncoding(0xC7)
        }
        let memory = try decodeMemoryAddressing(modrm: modrm, prefixes: prefixes, cursor: &cursor)
        let kind: X86.CmpxchgWideKind = prefixes.rexW == 1 ? .cmpxchg16b : .cmpxchg8b
        return Decoded(instruction: .cmpxchgWide(kind, memory), length: cursor.consumed)
    }

    // MARK: - MOVSX / MOVSXD / MOVZX and BSWAP

    private static func decodeMovsxd(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        // Only the REX.W form is modelled here. The variants without
        // REX.W are deprecated in long mode and read like a plain MOV.
        guard prefixes.rexW == 1 else {
            throw AssemblerError.unknownEncoding(0x63)
        }
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let destination = makeRegister(number: regNum, width: .qword, hasREX: prefixes.hasREX)
        let source = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: .dword, cursor: &cursor)
        return Decoded(
            instruction: .extendingMove(.movsxd, destination: destination, source: source),
            length: cursor.consumed
        )
    }

    private static func decodeExtendingMove(kind: X86.ExtendingMoveKind, sourceWidth: X86.RegisterWidth, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let dstWidth = selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let destination = makeRegister(number: regNum, width: dstWidth, hasREX: prefixes.hasREX)
        let source = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: sourceWidth, cursor: &cursor)
        return Decoded(
            instruction: .extendingMove(kind, destination: destination, source: source),
            length: cursor.consumed
        )
    }

    private static func decodeBswap(opcode2: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width: X86.RegisterWidth = prefixes.rexW == 1 ? .qword : .dword
        let number = (prefixes.rexB << 3) | (opcode2 & 0x07)
        let register = X86.Register(number: number, width: width)
        return Decoded(instruction: .bswap(register), length: cursor.consumed)
    }

    // MARK: - PUSH / POP / LEA

    /// PUSH/POP operand size is implicitly qword in long mode; the 0x66
    /// prefix selects word. REX.W is ignored.
    private static func selectPushPopWidth(prefixes: Prefixes) -> X86.RegisterWidth {
        prefixes.operandSize ? .word : .qword
    }

    private static func decodePushRegisterShort(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectPushPopWidth(prefixes: prefixes)
        let number = (prefixes.rexB << 3) | (opcode & 0x07)
        let register = X86.Register(number: number, width: width)
        return Decoded(instruction: .push(.register(register)), length: cursor.consumed)
    }

    private static func decodePopRegisterShort(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectPushPopWidth(prefixes: prefixes)
        let number = (prefixes.rexB << 3) | (opcode & 0x07)
        let register = X86.Register(number: number, width: width)
        return Decoded(instruction: .pop(.register(register)), length: cursor.consumed)
    }

    private static func decodePushImm8(cursor: inout Cursor) throws -> Decoded {
        let imm = Int64(Int8(bitPattern: try cursor.takeByte()))
        return Decoded(instruction: .push(.immediate(imm)), length: cursor.consumed)
    }

    private static func decodePushImm32(cursor: inout Cursor) throws -> Decoded {
        let imm = Int64(Int32(bitPattern: try cursor.takeLE32()))
        return Decoded(instruction: .push(.immediate(imm)), length: cursor.consumed)
    }

    private static func decodePopMemory(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        try requireSlash0(modrm: modrm, opcode: 0x8F)
        let width = selectPushPopWidth(prefixes: prefixes)
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        return Decoded(instruction: .pop(target), length: cursor.consumed)
    }

    private static func decodeLea(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        guard X86.ModRM.mod.extract(modrm) != X86.ModRM.modRegister else {
            // LEA with a register source is an UD; gas/objdump report
            // `(bad)` here. We surface it as unknownEncoding.
            throw AssemblerError.unknownEncoding(0x8D)
        }
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let destination = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let memory = try decodeMemoryAddressing(modrm: modrm, prefixes: prefixes, cursor: &cursor)
        return Decoded(instruction: .lea(destination: destination, source: memory), length: cursor.consumed)
    }

    // MARK: - IMUL (2-op and 3-op)

    private static func decodeImulRegister(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let destination = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let source = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        return Decoded(instruction: .imulRegister(destination: destination, source: source), length: cursor.consumed)
    }

    private static func decodeImulImmediate(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let destination = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let source = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        let immediate: Int64
        if opcode == 0x6B {
            immediate = Int64(Int8(bitPattern: try cursor.takeByte()))
        } else {
            switch width {
            case .word:  immediate = Int64(try cursor.takeLE16())
            case .dword: immediate = Int64(try cursor.takeLE32())
            case .qword: immediate = Int64(Int32(bitPattern: try cursor.takeLE32()))
            case .byte:  throw AssemblerError.unknownEncoding(UInt32(opcode))
            }
        }
        return Decoded(
            instruction: .imulImmediate(destination: destination, source: source, immediate: immediate),
            length: cursor.consumed
        )
    }

    // MARK: - Shift / Rotate

    private static func decodeShift(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let isByte = (opcode & 0x01) == 0
        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let nField = X86.ModRM.reg.extract(modrm)
        guard let kind = X86.ShiftKind.decode(slashDigit: nField) else {
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        let count: X86.ShiftCount
        switch opcode {
        case 0xD0, 0xD1:
            count = .one
        case 0xD2, 0xD3:
            count = .cl
        case 0xC0, 0xC1:
            let imm = try cursor.takeByte()
            count = (imm == 1) ? .one : .immediate(imm)
        default:
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        return Decoded(instruction: .shift(kind, target: target, count: count), length: cursor.consumed)
    }

    private static func decodeDoubleShift(kind: X86.DoubleShiftKind, withImmediate: Bool, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let source = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        let count: X86.ShiftCount
        if withImmediate {
            let imm = try cursor.takeByte()
            count = (imm == 1) ? .one : .immediate(imm)
        } else {
            count = .cl
        }
        return Decoded(instruction: .doubleShift(kind, target: target, source: source, count: count), length: cursor.consumed)
    }

    // MARK: - TEST

    private static func decodeTestMR(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let isByte = (opcode == 0x84)
        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let regOperand = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
        let rmDestination = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        return Decoded(
            instruction: .test(left: rmDestination, right: .register(regOperand)),
            length: cursor.consumed
        )
    }

    private static func decodeTestAccumulator(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let isByte = (opcode == 0xA8)
        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)
        let imm: Int64
        switch width {
        case .byte:  imm = Int64(try cursor.takeByte())
        case .word:  imm = Int64(try cursor.takeLE16())
        case .dword: imm = Int64(try cursor.takeLE32())
        case .qword: imm = Int64(Int32(bitPattern: try cursor.takeLE32()))
        }
        let acc = X86.Register(number: 0, width: width)
        return Decoded(instruction: .test(left: .register(acc), right: .immediate(imm)), length: cursor.consumed)
    }

    // MARK: - F6 / F7 (TEST imm, NOT, NEG)

    private static func decodeF6F7(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let isByte = (opcode == 0xF6)
        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let nField = X86.ModRM.reg.extract(modrm)
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)

        switch nField {
        case 0, 1: // TEST r/m, imm
            let imm: Int64
            switch width {
            case .byte:  imm = Int64(try cursor.takeByte())
            case .word:  imm = Int64(try cursor.takeLE16())
            case .dword: imm = Int64(try cursor.takeLE32())
            case .qword: imm = Int64(Int32(bitPattern: try cursor.takeLE32()))
            }
            return Decoded(instruction: .test(left: target, right: .immediate(imm)), length: cursor.consumed)
        case 2, 3:
            let kind: X86.UnaryAluKind = (nField == 2) ? .not : .neg
            return Decoded(instruction: .unaryAlu(kind, target: target), length: cursor.consumed)
        case 4, 5, 6, 7:
            guard let kind = X86.MulDivKind.decode(slashDigit: nField) else {
                throw AssemblerError.unknownEncoding(UInt32(opcode))
            }
            return Decoded(instruction: .mulDiv(kind, target: target), length: cursor.consumed)
        default:
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
    }

    // MARK: - FE / FF (INC, DEC, indirect CALL / JMP)

    private static func decodeFEFF(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let isByte = (opcode == 0xFE)
        let modrm = try cursor.takeByte()
        let nField = X86.ModRM.reg.extract(modrm)

        // FF /2 = CALL r/m64; FF /4 = JMP r/m64. Long mode forces qword
        // regardless of REX.W, so the operand width is fixed here.
        if !isByte && (nField == 2 || nField == 4) {
            let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: .qword, cursor: &cursor)
            let instruction: X86.Instruction = (nField == 2)
                ? .callIndirect(target: target)
                : .jumpIndirect(target: target)
            return Decoded(instruction: instruction, length: cursor.consumed)
        }

        // FF /6 = PUSH r/m. Width is word (with 0x66) or qword (default);
        // REX.W is ignored.
        if !isByte && nField == 6 {
            let pushWidth = selectPushPopWidth(prefixes: prefixes)
            let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: pushWidth, cursor: &cursor)
            let operand: X86.Operand
            switch target {
            case .register(let r): operand = .register(r)
            case .memory(let m, let w): operand = .memory(m, width: w)
            }
            return Decoded(instruction: .push(operand), length: cursor.consumed)
        }

        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)
        guard let kind = X86.UnaryAluKind.decodeIncDec(slashDigit: nField) else {
            // /3 CALLF, /5 JMPF, /6 PUSH, /7 reserved — covered in later phases.
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        let target = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        return Decoded(instruction: .unaryAlu(kind, target: target), length: cursor.consumed)
    }

    // MARK: - Binary ALU

    /// Decode the MR/RM/I variants (sub-opcode 0..5) of the binary ALU
    /// family. The family is already resolved from the high opcode bits.
    private static func decodeBinaryAlu(
        kind: X86.BinaryAluKind,
        variant: UInt8,
        prefixes: Prefixes,
        cursor: inout Cursor
    ) throws -> Decoded {
        let isByte = (variant & 0x1) == 0
        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)

        switch variant {
        case 0, 1: // MR — destination is r/m, source is reg
            let modrm = try cursor.takeByte()
            let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
            let regOperand = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
            let destination = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
            return Decoded(
                instruction: .binaryAlu(kind, destination: destination, source: .register(regOperand)),
                length: cursor.consumed
            )

        case 2, 3: // RM — destination is reg, source is r/m
            let modrm = try cursor.takeByte()
            let regNum = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
            let regOperand = makeRegister(number: regNum, width: width, hasREX: prefixes.hasREX)
            let rmDestination = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
            let source: X86.Operand
            switch rmDestination {
            case .register(let r): source = .register(r)
            case .memory(let m, let w): source = .memory(m, width: w)
            }
            return Decoded(
                instruction: .binaryAlu(kind, destination: .register(regOperand), source: source),
                length: cursor.consumed
            )

        case 4: // I — implicit AL, imm8
            let imm = Int64(try cursor.takeByte())
            let al = X86.Register(number: 0, width: .byte)
            return Decoded(
                instruction: .binaryAlu(kind, destination: .register(al), source: .immediate(imm)),
                length: cursor.consumed
            )

        case 5: // I — implicit rAX, imm{16,32, sign-extended 32}
            let imm: Int64
            switch width {
            case .word:  imm = Int64(try cursor.takeLE16())
            case .dword: imm = Int64(try cursor.takeLE32())
            case .qword: imm = Int64(Int32(bitPattern: try cursor.takeLE32()))
            case .byte:  throw AssemblerError.unknownEncoding(UInt32(variant))
            }
            let rax = X86.Register(number: 0, width: width)
            return Decoded(
                instruction: .binaryAlu(kind, destination: .register(rax), source: .immediate(imm)),
                length: cursor.consumed
            )

        default:
            throw AssemblerError.unknownEncoding(UInt32(variant))
        }
    }

    /// Decode the MI variants (80/81/83 `/n` ib/iw/id). The family is
    /// carried by the ModR/M `reg` field, which doubles as the `/n`
    /// slash-digit.
    private static func decodeBinaryAluMI(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        let nField = X86.ModRM.reg.extract(modrm)
        guard let kind = X86.BinaryAluKind.decode(opcodeIndex: nField) else {
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        let width: X86.RegisterWidth = (opcode == 0x80) ? .byte : selectWidth(prefixes: prefixes)
        let destination = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        let imm: Int64
        switch opcode {
        case 0x80:
            imm = Int64(try cursor.takeByte())
        case 0x83:
            imm = Int64(Int8(bitPattern: try cursor.takeByte()))
        case 0x81:
            switch width {
            case .word:  imm = Int64(try cursor.takeLE16())
            case .dword: imm = Int64(try cursor.takeLE32())
            case .qword: imm = Int64(Int32(bitPattern: try cursor.takeLE32()))
            case .byte:  throw AssemblerError.unknownEncoding(UInt32(opcode))
            }
        default:
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        return Decoded(
            instruction: .binaryAlu(kind, destination: destination, source: .immediate(imm)),
            length: cursor.consumed
        )
    }

    /// Decode a `r/m` slot into either a register or a memory operand.
    private static func decodeRMDestination(
        modrm: UInt8,
        prefixes: Prefixes,
        width: X86.RegisterWidth,
        cursor: inout Cursor
    ) throws -> X86.RegisterOrMemory {
        if X86.ModRM.mod.extract(modrm) == X86.ModRM.modRegister {
            let number = (prefixes.rexB << 3) | X86.ModRM.rm.extract(modrm)
            return .register(makeRegister(number: number, width: width, hasREX: prefixes.hasREX))
        }
        let memory = try decodeMemoryAddressing(modrm: modrm, prefixes: prefixes, cursor: &cursor)
        return .memory(memory, width: width)
    }

    // MARK: - MOV r/m, r and MOV r, r/m

    /// Decode the 88/89 (MR) and 8A/8B (RM) families. The ModR/M `mod`
    /// field selects the register-direct path (`mod == 11`) or the memory
    /// path (`mod != 11`); the latter chains into `decodeMemoryAddressing`.
    private static func decodeMovRegisterMemory(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        let isByte = (opcode == 0x88 || opcode == 0x8A)
        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)
        let regNumber = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let regOperand = makeRegister(number: regNumber, width: width, hasREX: prefixes.hasREX)
        let mod = X86.ModRM.mod.extract(modrm)
        let isMR = (opcode == 0x88 || opcode == 0x89)

        if mod == X86.ModRM.modRegister {
            let rmNumber = (prefixes.rexB << 3) | X86.ModRM.rm.extract(modrm)
            let rmOperand = makeRegister(number: rmNumber, width: width, hasREX: prefixes.hasREX)
            let (destination, source) = isMR ? (rmOperand, regOperand) : (regOperand, rmOperand)
            return Decoded(
                instruction: .mov(destination: .register(destination), source: .register(source)),
                length: cursor.consumed
            )
        }

        let memory = try decodeMemoryAddressing(modrm: modrm, prefixes: prefixes, cursor: &cursor)
        let instruction: X86.Instruction = isMR
            ? .mov(destination: .memory(memory, width: width), source: .register(regOperand))
            : .mov(destination: .register(regOperand), source: .memory(memory, width: width))
        return Decoded(instruction: instruction, length: cursor.consumed)
    }

    /// Decode ModR/M + optional SIB + displacement into a `MemoryOperand`.
    /// Called only for `mod != 11`.
    private static func decodeMemoryAddressing(modrm: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> X86.MemoryOperand {
        let mod = X86.ModRM.mod.extract(modrm)
        let rm = X86.ModRM.rm.extract(modrm)

        // RIP-relative: mod=00, rm=5 (in 64-bit mode).
        if mod == X86.ModRM.modIndirect && rm == 0b101 {
            let disp = Int32(bitPattern: try cursor.takeLE32())
            return X86.MemoryOperand(displacement: Int64(disp), ripRelative: true)
        }

        // SIB escape: rm=4.
        if rm == 0b100 {
            let sib = try cursor.takeByte()
            let sibScaleField = X86.SIB.scale.extract(sib)
            let sibIndexField = X86.SIB.index.extract(sib)
            let sibBaseField  = X86.SIB.base.extract(sib)

            // Index: sibIndex==4 with REX.X==0 means "no index"; with REX.X==1
            // it is R12 (and a legitimate index).
            let index: X86.Register?
            if sibIndexField == X86.SIB.noIndex && prefixes.rexX == 0 {
                index = nil
            } else {
                let number = (prefixes.rexX << 3) | sibIndexField
                index = X86.Register(number: number, width: .qword)
            }
            let scale: UInt8 = 1 << sibScaleField

            // Base: sibBase==5 with mod==0 means "no base"; the displacement
            // is then a full disp32.
            let base: X86.Register?
            let displacement: Int64
            if mod == X86.ModRM.modIndirect && sibBaseField == X86.SIB.noBase {
                base = nil
                displacement = Int64(Int32(bitPattern: try cursor.takeLE32()))
            } else {
                let number = (prefixes.rexB << 3) | sibBaseField
                base = X86.Register(number: number, width: .qword)
                displacement = try readDisplacement(mod: mod, cursor: &cursor)
            }

            return X86.MemoryOperand(base: base, index: index, scale: scale, displacement: displacement)
        }

        // Plain `[base + disp]` form, no SIB.
        let baseNumber = (prefixes.rexB << 3) | rm
        let base = X86.Register(number: baseNumber, width: .qword)
        let displacement = try readDisplacement(mod: mod, cursor: &cursor)
        return X86.MemoryOperand(base: base, displacement: displacement)
    }

    private static func readDisplacement(mod: UInt8, cursor: inout Cursor) throws -> Int64 {
        switch mod {
        case X86.ModRM.modIndirect: return 0
        case X86.ModRM.modDisp8:    return Int64(Int8(bitPattern: try cursor.takeByte()))
        case X86.ModRM.modDisp32:   return Int64(Int32(bitPattern: try cursor.takeLE32()))
        default:
            // mod==11 is the register-direct path and should never reach here.
            throw AssemblerError.unknownEncoding(UInt32(mod))
        }
    }

    // MARK: - MOV r, imm short forms

    private static func decodeMovImm8(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let number = (prefixes.rexB << 3) | (opcode & 0x7)
        let destination = makeRegister(number: number, width: .byte, hasREX: prefixes.hasREX)
        let imm = Int64(try cursor.takeByte())
        return Decoded(instruction: .mov(destination: .register(destination), source: .immediate(imm)), length: cursor.consumed)
    }

    private static func decodeMovImmWord(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let number = (prefixes.rexB << 3) | (opcode & 0x7)
        let destination = makeRegister(number: number, width: width, hasREX: prefixes.hasREX)
        let imm: Int64
        switch width {
        case .word:  imm = Int64(try cursor.takeLE16())
        case .dword: imm = Int64(try cursor.takeLE32())
        case .qword: imm = Int64(bitPattern: try cursor.takeLE64())
        case .byte:  throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        return Decoded(instruction: .mov(destination: .register(destination), source: .immediate(imm)), length: cursor.consumed)
    }

    // MARK: - MOV r/m, imm (C6 / C7 /0)

    /// `C6 /0 ib`. Accepts both register-direct (`mod == 11`) and memory
    /// (`mod != 11`) destinations; the ModR/M `reg` field must be 0.
    private static func decodeMovMI8(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        try requireSlash0(modrm: modrm, opcode: 0xC6)
        let destination = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: .byte, cursor: &cursor)
        let imm = Int64(try cursor.takeByte())
        return Decoded(instruction: .mov(destination: destination, source: .immediate(imm)), length: cursor.consumed)
    }

    /// `C7 /0 i{w,d}`. The qword form sign-extends imm32 to Int64 so the
    /// encoder's "fits in Int32" canonical path round-trips.
    private static func decodeMovMIWord(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        try requireSlash0(modrm: modrm, opcode: 0xC7)
        let width = selectWidth(prefixes: prefixes)
        let destination = try decodeRMDestination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        let imm: Int64
        switch width {
        case .word:  imm = Int64(try cursor.takeLE16())
        case .dword: imm = Int64(try cursor.takeLE32())
        case .qword: imm = Int64(Int32(bitPattern: try cursor.takeLE32()))
        case .byte:  throw AssemblerError.unknownEncoding(0xC7)
        }
        return Decoded(instruction: .mov(destination: destination, source: .immediate(imm)), length: cursor.consumed)
    }

    // MARK: - Shared helpers

    private static func selectWidth(prefixes: Prefixes) -> X86.RegisterWidth {
        if prefixes.rexW == 1 { return .qword }
        if prefixes.operandSize { return .word }
        return .dword
    }

    private static func makeRegister(number: UInt8, width: X86.RegisterWidth, hasREX: Bool) -> X86.Register {
        if width == .byte, (4...7).contains(number) {
            if hasREX {
                return X86.Register(number: number, width: .byte, requiresREXForByte: true)
            } else {
                return X86.Register(number: number, width: .byte, isHighByte: true)
            }
        }
        return X86.Register(number: number, width: width)
    }

    private static func requireSlash0(modrm: UInt8, opcode: UInt8) throws {
        guard X86.ModRM.reg.extract(modrm) == 0 else {
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
    }
}
