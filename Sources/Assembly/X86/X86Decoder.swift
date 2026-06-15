import Foundation

internal enum X86InstructionDecoder {
    /// One decoded instruction plus the number of bytes it consumed.
    struct Decoded {
        var instruction: X86.Instruction
        var length: Int
    }

    /// Zero-operand kinds in *descending* length order. Longest-prefix-wins
    /// matching is required because several encodings share a leading byte
    /// with shorter ones (`F3 90 pause` vs `90 nop`, `66 CF iret` /
    /// `48 CF iretq` vs `CF iretd`, `48 0F 07 sysretq` vs `0F 07 sysret`).
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

    /// Prefix state extracted from the byte stream before the opcode.
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
            guard offset < bytes.count else {
                throw AssemblerError.invalidByteCount(bytes.count)
            }
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
            return try decodeMovRegisterDirection(opcode: opcode, prefixes: prefixes, cursor: &cursor)
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

    // MARK: - MOV variants

    /// Decode MR (88/89) and RM (8A/8B) forms. Phase 2 restricts the operand
    /// to register-direct (`mod == 11`); a memory operand raises
    /// `unknownEncoding` until Phase 3 introduces the memory addressing
    /// vocabulary.
    private static func decodeMovRegisterDirection(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        guard X86.ModRM.mod.extract(modrm) == X86.ModRM.modRegister else {
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        let isByte = (opcode == 0x88 || opcode == 0x8A)
        let width = isByte ? X86.RegisterWidth.byte : selectWidth(prefixes: prefixes)
        let regNumber = (prefixes.rexR << 3) | X86.ModRM.reg.extract(modrm)
        let rmNumber  = (prefixes.rexB << 3) | X86.ModRM.rm.extract(modrm)
        let regOperand = makeRegister(number: regNumber, width: width, hasREX: prefixes.hasREX)
        let rmOperand  = makeRegister(number: rmNumber,  width: width, hasREX: prefixes.hasREX)
        let (destination, source) = (opcode == 0x88 || opcode == 0x89) ? (rmOperand, regOperand) : (regOperand, rmOperand)
        return Decoded(instruction: .mov(destination: destination, source: .register(source)), length: cursor.consumed)
    }

    /// Decode `B0+rb ib`: MOV r8, imm8.
    private static func decodeMovImm8(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let number = (prefixes.rexB << 3) | (opcode & 0x7)
        let destination = makeRegister(number: number, width: .byte, hasREX: prefixes.hasREX)
        let imm = Int64(try cursor.takeByte())
        return Decoded(instruction: .mov(destination: destination, source: .immediate(imm)), length: cursor.consumed)
    }

    /// Decode `B8+r{w,d,o}`: MOV r16/32/64, imm16/32/64.
    private static func decodeMovImmWord(opcode: UInt8, prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let width = selectWidth(prefixes: prefixes)
        let number = (prefixes.rexB << 3) | (opcode & 0x7)
        let destination = makeRegister(number: number, width: width, hasREX: prefixes.hasREX)
        let imm: Int64
        switch width {
        case .word:  imm = Int64(try cursor.takeLE16())
        case .dword: imm = Int64(try cursor.takeLE32())
        case .qword: imm = Int64(bitPattern: try cursor.takeLE64())
        case .byte:
            // Unreachable: B8..BF is non-byte; byte form is B0..B7.
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        return Decoded(instruction: .mov(destination: destination, source: .immediate(imm)), length: cursor.consumed)
    }

    /// Decode `C6 /0 ib`: MOV r/m8, imm8 (Phase 2: register-direct only).
    private static func decodeMovMI8(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        try requireSlash0RegisterDirect(modrm: modrm, opcode: 0xC6)
        let number = (prefixes.rexB << 3) | X86.ModRM.rm.extract(modrm)
        let destination = makeRegister(number: number, width: .byte, hasREX: prefixes.hasREX)
        let imm = Int64(try cursor.takeByte())
        return Decoded(instruction: .mov(destination: destination, source: .immediate(imm)), length: cursor.consumed)
    }

    /// Decode `C7 /0 i{w,d}`: MOV r/m16/32/64, imm{16,32,32 sign-extended}
    /// (Phase 2: register-direct only). The qword form sign-extends imm32
    /// to Int64 so the encoder's "fits in Int32" canonical path round-trips
    /// (`mov rax, -1` → `48 C7 C0 FF FF FF FF` ↔ `imm = -1`).
    private static func decodeMovMIWord(prefixes: Prefixes, cursor: inout Cursor) throws -> Decoded {
        let modrm = try cursor.takeByte()
        try requireSlash0RegisterDirect(modrm: modrm, opcode: 0xC7)
        let width = selectWidth(prefixes: prefixes)
        let number = (prefixes.rexB << 3) | X86.ModRM.rm.extract(modrm)
        let destination = makeRegister(number: number, width: width, hasREX: prefixes.hasREX)
        let imm: Int64
        switch width {
        case .word:  imm = Int64(try cursor.takeLE16())
        case .dword: imm = Int64(try cursor.takeLE32())
        case .qword:
            let raw = try cursor.takeLE32()
            imm = Int64(Int32(bitPattern: raw))
        case .byte:
            throw AssemblerError.unknownEncoding(0xC7)
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

    private static func requireSlash0RegisterDirect(modrm: UInt8, opcode: UInt8) throws {
        guard X86.ModRM.mod.extract(modrm) == X86.ModRM.modRegister else {
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
        guard X86.ModRM.reg.extract(modrm) == 0 else {
            throw AssemblerError.unknownEncoding(UInt32(opcode))
        }
    }
}
