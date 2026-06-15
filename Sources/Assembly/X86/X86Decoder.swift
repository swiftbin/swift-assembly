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
        case 0x70...0x7F:
            return try decodeJccRel8(opcode: opcode, cursor: &cursor)
        case 0x80, 0x81, 0x83:
            return try decodeBinaryAluMI(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0x84, 0x85:
            return try decodeTestMR(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0x88, 0x89, 0x8A, 0x8B:
            return try decodeMovRegisterMemory(opcode: opcode, prefixes: prefixes, cursor: &cursor)
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

    // MARK: - 0F-escape two-byte opcodes

    private static func decodeTwoByteOpcode(opcode2: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        switch opcode2 {
        case 0x80...0x8F:
            return try decodeJccRel32(opcode2: opcode2, cursor: &cursor)
        case 0xA4: return try decodeDoubleShift(kind: .shld, withImmediate: true,  prefixes: prefixes, cursor: &cursor)
        case 0xA5: return try decodeDoubleShift(kind: .shld, withImmediate: false, prefixes: prefixes, cursor: &cursor)
        case 0xAC: return try decodeDoubleShift(kind: .shrd, withImmediate: true,  prefixes: prefixes, cursor: &cursor)
        case 0xAD: return try decodeDoubleShift(kind: .shrd, withImmediate: false, prefixes: prefixes, cursor: &cursor)
        default:
            throw AssemblerError.unknownEncoding(UInt32(opcode2))
        }
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
        default:
            // /4..7 are MUL/IMUL/DIV/IDIV — added in a later phase.
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
    }

    // MARK: - FE / FF (INC, DEC)

    private static func decodeFEFF(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let isByte = (opcode == 0xFE)
        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)
        let modrm = try cursor.takeByte()
        let nField = X86.ModRM.reg.extract(modrm)
        guard let kind = X86.UnaryAluKind.decodeIncDec(slashDigit: nField) else {
            // FE only accepts /0 and /1; FF /2..7 are CALL/JMP/PUSH (later phases).
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
