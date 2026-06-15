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

        switch opcode {
        case 0x88, 0x89, 0x8A, 0x8B:
            return try decodeMovRegisterMemory(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xB0...0xB7:
            return try decodeMovImm8(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xB8...0xBF:
            return try decodeMovImmWord(opcode: opcode, prefixes: prefixes, cursor: &cursor)
        case 0xC6:
            return try decodeMovMI8(prefixes: prefixes, cursor: &cursor)
        case 0xC7:
            return try decodeMovMIWord(prefixes: prefixes, cursor: &cursor)
        default:
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
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
        let destination = try decodeSlash0Destination(modrm: modrm, prefixes: prefixes, width: .byte, cursor: &cursor)
        let imm = Int64(try cursor.takeByte())
        return Decoded(instruction: .mov(destination: destination, source: .immediate(imm)), length: cursor.consumed)
    }

    /// `C7 /0 i{w,d}`. The qword form sign-extends imm32 to Int64 so the
    /// encoder's "fits in Int32" canonical path round-trips.
    private static func decodeMovMIWord(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        try requireSlash0(modrm: modrm, opcode: 0xC7)
        let width = selectWidth(prefixes: prefixes)
        let destination = try decodeSlash0Destination(modrm: modrm, prefixes: prefixes, width: width, cursor: &cursor)
        let imm: Int64
        switch width {
        case .word:  imm = Int64(try cursor.takeLE16())
        case .dword: imm = Int64(try cursor.takeLE32())
        case .qword: imm = Int64(Int32(bitPattern: try cursor.takeLE32()))
        case .byte:  throw AssemblerError.unknownEncoding(0xC7)
        }
        return Decoded(instruction: .mov(destination: destination, source: .immediate(imm)), length: cursor.consumed)
    }

    /// Decode the destination of a `/0` instruction whose ModR/M may be
    /// either register-direct or memory.
    private static func decodeSlash0Destination(
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
