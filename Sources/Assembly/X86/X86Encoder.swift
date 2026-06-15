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

    /// Encode the register-direct forms of `MOV` (Phase 2 scope: no memory
    /// operands). Register/register uses the MR form (88/89 `/r`); register/
    /// immediate uses the short B0+rb / B8+rd forms, falling back to the
    /// C7 /0 sign-extended form for r64 immediates that fit in Int32.
    private static func encodeMov(destination: X86.Register, source: X86.MovSource) throws -> [UInt8] {
        switch source {
        case .register(let src):
            return try encodeMovRegister(destination: destination, source: src)
        case .immediate(let imm):
            return try encodeMovImmediate(destination: destination, immediate: imm)
        }
    }

    private static func encodeMovRegister(destination dst: X86.Register, source src: X86.Register) throws -> [UInt8] {
        try validateByteRegisterCompatibility([dst, src], mnemonic: "mov")
        let width = dst.width
        var bytes: [UInt8] = []
        if width == .word { bytes.append(X86.operandSizeOverride) }
        let rexW: UInt8 = width == .qword ? 1 : 0
        let forceREX = needsForcedREX([dst, src])
        if let rex = X86.REX.build(w: rexW, r: src.highBit, x: 0, b: dst.highBit, forceEmit: forceREX) {
            bytes.append(rex)
        }
        let opcode: UInt8 = width == .byte ? 0x88 : 0x89
        bytes.append(opcode)
        bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: src.lowBits, rm: dst.lowBits))
        return bytes
    }

    private static func encodeMovImmediate(destination dst: X86.Register, immediate imm: Int64) throws -> [UInt8] {
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
            appendLittleEndian(UInt16(truncatingIfNeeded: imm), into: &bytes)
            return bytes

        case .dword:
            var bytes: [UInt8] = []
            if let rex = X86.REX.build(b: dst.highBit) { bytes.append(rex) }
            bytes.append(0xB8 | dst.lowBits)
            appendLittleEndian(UInt32(truncatingIfNeeded: imm), into: &bytes)
            return bytes

        case .qword:
            let fitsInt32 = Int64(Int32(truncatingIfNeeded: imm)) == imm
            if fitsInt32 {
                // REX.W C7 /0 id (mod=11) — 7 bytes total.
                var bytes: [UInt8] = []
                bytes.append(X86.REX.build(w: 1, b: dst.highBit)!) // W=1 always emits REX
                bytes.append(0xC7)
                bytes.append(X86.ModRM.make(mod: X86.ModRM.modRegister, reg: 0, rm: dst.lowBits))
                appendLittleEndian(UInt32(truncatingIfNeeded: imm), into: &bytes)
                return bytes
            } else {
                // REX.W B8+rd io — 10 bytes total.
                var bytes: [UInt8] = []
                bytes.append(X86.REX.build(w: 1, b: dst.highBit)!)
                bytes.append(0xB8 | dst.lowBits)
                appendLittleEndian(UInt64(bitPattern: imm), into: &bytes)
                return bytes
            }
        }
    }

    // MARK: - Helpers

    /// Ensure a high-byte register (AH/CH/DH/BH) does not appear alongside
    /// any operand that would force a REX prefix (R8..R15 or SPL/BPL/SIL/DIL).
    private static func validateByteRegisterCompatibility(_ registers: [X86.Register], mnemonic: String) throws {
        let hasHighByte = registers.contains { $0.isHighByte }
        let needsREX = needsForcedREX(registers) || registers.contains { $0.isExtended }
        if hasHighByte && needsREX {
            throw AssemblerError.unsupportedOperand(
                "\(mnemonic): high-byte register (AH/BH/CH/DH) cannot be combined with R8..R15 or SPL/BPL/SIL/DIL"
            )
        }
    }

    /// True if any operand forces a REX prefix purely to disambiguate the
    /// byte register encoding (SPL/BPL/SIL/DIL).
    private static func needsForcedREX(_ registers: [X86.Register]) -> Bool {
        registers.contains { $0.requiresREXForByte }
    }

    private static func appendLittleEndian(_ value: UInt16, into bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func appendLittleEndian(_ value: UInt32, into bytes: inout [UInt8]) {
        for shift in stride(from: 0, to: 32, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }

    private static func appendLittleEndian(_ value: UInt64, into bytes: inout [UInt8]) {
        for shift in stride(from: 0, to: 64, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}
