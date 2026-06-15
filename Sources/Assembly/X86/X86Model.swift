import Foundation

/// The X86 / X86-64 instruction-model namespace, mirroring the layering of
/// `A64`. Domain types (registers, memory operands, instruction kinds) live
/// here; the byte-level format descriptors live in `X86InstructionFormats`.
internal enum X86 {
    /// General-purpose register width.
    enum RegisterWidth: Int, Equatable {
        case byte = 8
        case word = 16
        case dword = 32
        case qword = 64
    }

    /// A general-purpose register slot.
    ///
    /// `number` is the 4-bit encoding 0–15 (e.g. RAX=0, RCX=1, ..., R15=15).
    /// For the legacy high-byte registers (AH/CH/DH/BH) `isHighByte == true`;
    /// for SPL/BPL/SIL/DIL the encoder must emit a REX prefix even when
    /// otherwise unnecessary (`requiresREXForByte == true`).
    struct Register: Equatable {
        var number: UInt8
        var width: RegisterWidth
        /// One of AH/CH/DH/BH. These occupy `number` 4–7 with no REX prefix
        /// and become invalid the moment a REX prefix appears in the same
        /// instruction.
        var isHighByte: Bool
        /// One of SPL/BPL/SIL/DIL. These occupy `number` 4–7 *with* a REX
        /// prefix and require a REX byte even when no other field needs one.
        var requiresREXForByte: Bool

        init(number: UInt8, width: RegisterWidth, isHighByte: Bool = false, requiresREXForByte: Bool = false) {
            self.number = number
            self.width = width
            self.isHighByte = isHighByte
            self.requiresREXForByte = requiresREXForByte
        }

        /// Low 3 bits of `number`, fitted into a ModR/M `reg` or `rm` field.
        var lowBits: UInt8 { number & 0x7 }

        /// High bit of `number`, fitted into REX.R / REX.B / REX.X.
        var highBit: UInt8 { (number >> 3) & 0x1 }

        /// True iff the register is one of R8..R15 in any width.
        var isExtended: Bool { number >= 8 }

        /// The width tag used in human-readable diagnostics.
        var widthSuffix: String {
            switch width {
            case .byte:  return "byte"
            case .word:  return "word"
            case .dword: return "dword"
            case .qword: return "qword"
            }
        }
    }

    /// A memory operand in long mode.
    ///
    /// Long mode permits at most one base register, at most one index
    /// register scaled by 1/2/4/8, and an optional 32-bit (sign-extended)
    /// displacement. The `RIP+disp32` form is represented by `ripRelative
    /// == true` with no base or index. The `[disp32]` absolute form is
    /// represented by `base == nil && index == nil && ripRelative == false`.
    /// Registers must be 64-bit (the 32-bit `[esi+...]` form requires the
    /// `0x67` address-size override prefix and is deferred).
    struct MemoryOperand: Equatable {
        var base: Register?
        var index: Register?
        var scale: UInt8
        var displacement: Int64
        var ripRelative: Bool

        init(
            base: Register? = nil,
            index: Register? = nil,
            scale: UInt8 = 1,
            displacement: Int64 = 0,
            ripRelative: Bool = false
        ) {
            self.base = base
            self.index = index
            self.scale = scale
            self.displacement = displacement
            self.ripRelative = ripRelative
        }

        /// Encoded value of the SIB.scale field: 00 / 01 / 10 / 11 for scales
        /// 1 / 2 / 4 / 8 respectively.
        var scaleField: UInt8? {
            switch scale {
            case 1: return 0b00
            case 2: return 0b01
            case 4: return 0b10
            case 8: return 0b11
            default: return nil
            }
        }
    }

    /// An operand position that can be written: a register or a memory
    /// reference. Used as the destination of `MOV`, the left-hand side of
    /// binary ALU ops (ADD/SUB/...), and the target of unary ALU ops
    /// (INC/NEG/...).
    enum RegisterOrMemory: Equatable {
        case register(Register)
        case memory(MemoryOperand, width: RegisterWidth)

        var width: RegisterWidth {
            switch self {
            case .register(let r): return r.width
            case .memory(_, let w): return w
            }
        }
    }

    /// An operand position that can be read: register, memory, or
    /// immediate. Used as the right-hand side of `MOV` and binary ALU ops.
    enum Operand: Equatable {
        case register(Register)
        case memory(MemoryOperand, width: RegisterWidth)
        case immediate(Int64)
    }

    /// Zero-operand instructions whose encoding is a single fixed byte
    /// sequence. See `X86_CHECKLIST.md` Phase 1.
    enum ZeroOperandKind: String, Equatable, CaseIterable {
        case nop
        case ret, retf
        case iret, iretd, iretq
        case leave
        case int3, ud2
        case clc, stc, cmc, cld, std, cli, sti
        case lahf, sahf
        case pause, hlt, wait, xlatb
        case syscall, sysret, sysretq, swapgs
        case cpuid
        case rdtsc, rdtscp, rdmsr, wrmsr, rdpmc
        case monitor, mwait

        var bytes: [UInt8] {
            switch self {
            case .nop:      return [0x90]
            case .ret:      return [0xC3]
            case .retf:     return [0xCB]
            case .iret:     return [0x66, 0xCF]
            case .iretd:    return [0xCF]
            case .iretq:    return [0x48, 0xCF]
            case .leave:    return [0xC9]
            case .int3:     return [0xCC]
            case .ud2:      return [0x0F, 0x0B]
            case .clc:      return [0xF8]
            case .stc:      return [0xF9]
            case .cmc:      return [0xF5]
            case .cld:      return [0xFC]
            case .std:      return [0xFD]
            case .cli:      return [0xFA]
            case .sti:      return [0xFB]
            case .lahf:     return [0x9F]
            case .sahf:     return [0x9E]
            case .pause:    return [0xF3, 0x90]
            case .hlt:      return [0xF4]
            case .wait:     return [0x9B]
            case .xlatb:    return [0xD7]
            case .syscall:  return [0x0F, 0x05]
            case .sysret:   return [0x0F, 0x07]
            case .sysretq:  return [0x48, 0x0F, 0x07]
            case .swapgs:   return [0x0F, 0x01, 0xF8]
            case .cpuid:    return [0x0F, 0xA2]
            case .rdtsc:    return [0x0F, 0x31]
            case .rdtscp:   return [0x0F, 0x01, 0xF9]
            case .rdmsr:    return [0x0F, 0x32]
            case .wrmsr:    return [0x0F, 0x30]
            case .rdpmc:    return [0x0F, 0x33]
            case .monitor:  return [0x0F, 0x01, 0xC8]
            case .mwait:    return [0x0F, 0x01, 0xC9]
            }
        }

        static func resolve(mnemonic: String) -> ZeroOperandKind? {
            switch mnemonic {
            case "fwait": return .wait
            case "xlat":  return .xlatb
            default:      return ZeroOperandKind(rawValue: mnemonic)
            }
        }
    }

    /// Two-operand integer ALU operations sharing the
    /// 00–3D opcode block. The mnemonic *is* the family index used by
    /// every encoding form:
    ///
    /// * MR  byte:     `0x00 + 8 * n` `/r`
    /// * MR  non-byte: `0x01 + 8 * n` `/r`
    /// * RM  byte:     `0x02 + 8 * n` `/r`
    /// * RM  non-byte: `0x03 + 8 * n` `/r`
    /// * I   AL:       `0x04 + 8 * n` `ib`
    /// * I   rAX:      `0x05 + 8 * n` `iw/id`
    /// * MI  byte:     `0x80 /n ib`
    /// * MI  non-byte: `0x81 /n iw/id`
    /// * MI  sign-ext: `0x83 /n ib`  (non-byte only)
    enum BinaryAluKind: String, Equatable, CaseIterable {
        case add, or, adc, sbb, and, sub, xor, cmp

        /// The family index `n` used as the `/n` ModR/M reg field and as
        /// the `8 * n` offset into the MR/RM/I opcode tables.
        var opcodeIndex: UInt8 {
            switch self {
            case .add: return 0
            case .or:  return 1
            case .adc: return 2
            case .sbb: return 3
            case .and: return 4
            case .sub: return 5
            case .xor: return 6
            case .cmp: return 7
            }
        }

        /// MR form opcode: `0x00 + 8n` for byte, `0x01 + 8n` otherwise.
        func mrOpcode(byte: Bool) -> UInt8 {
            (byte ? UInt8(0x00) : UInt8(0x01)) | (opcodeIndex << 3)
        }

        /// RM form opcode: `0x02 + 8n` for byte, `0x03 + 8n` otherwise.
        func rmOpcode(byte: Bool) -> UInt8 {
            (byte ? UInt8(0x02) : UInt8(0x03)) | (opcodeIndex << 3)
        }

        /// I (accumulator) form opcode: `0x04 + 8n` for byte, `0x05 + 8n` otherwise.
        func accumulatorOpcode(byte: Bool) -> UInt8 {
            (byte ? UInt8(0x04) : UInt8(0x05)) | (opcodeIndex << 3)
        }

        static func decode(opcodeIndex: UInt8) -> BinaryAluKind? {
            allCases.first { $0.opcodeIndex == opcodeIndex }
        }
    }

    /// Single-operand integer ALU operations. The /n field that lives in
    /// the ModR/M `reg` slot selects the operation, and the opcode byte
    /// selects the operand width:
    ///
    /// * INC / DEC use 0xFE (byte) / 0xFF (non-byte) with `/0` and `/1`.
    /// * NOT / NEG use 0xF6 (byte) / 0xF7 (non-byte) with `/2` and `/3`.
    enum UnaryAluKind: String, Equatable, CaseIterable {
        case inc, dec, not, neg

        /// The `/n` slash-digit placed in ModR/M.reg.
        var slashDigit: UInt8 {
            switch self {
            case .inc: return 0
            case .dec: return 1
            case .not: return 2
            case .neg: return 3
            }
        }

        /// INC/DEC ride the FE/FF opcode group; NOT/NEG ride F6/F7.
        var usesIncDecGroup: Bool {
            switch self {
            case .inc, .dec: return true
            case .not, .neg: return false
            }
        }

        /// Opcode byte for the chosen width.
        func opcode(byte: Bool) -> UInt8 {
            if usesIncDecGroup {
                return byte ? 0xFE : 0xFF
            } else {
                return byte ? 0xF6 : 0xF7
            }
        }

        static func decodeIncDec(slashDigit: UInt8) -> UnaryAluKind? {
            switch slashDigit {
            case 0: return .inc
            case 1: return .dec
            default: return nil
            }
        }

        static func decodeNotNeg(slashDigit: UInt8) -> UnaryAluKind? {
            switch slashDigit {
            case 2: return .not
            case 3: return .neg
            default: return nil
            }
        }
    }

    /// Single-operand shift and rotate instructions. The /n slash-digit
    /// in ModR/M.reg selects the operation:
    ///
    /// * /0 ROL    /1 ROR    /2 RCL    /3 RCR
    /// * /4 SHL    /5 SHR              /7 SAR
    ///
    /// SAL is a synonym for SHL and folds onto `.shl` on parse.
    enum ShiftKind: String, Equatable, CaseIterable {
        case rol, ror, rcl, rcr, shl, shr, sar

        var slashDigit: UInt8 {
            switch self {
            case .rol: return 0
            case .ror: return 1
            case .rcl: return 2
            case .rcr: return 3
            case .shl: return 4
            case .shr: return 5
            case .sar: return 7
            }
        }

        static func decode(slashDigit: UInt8) -> ShiftKind? {
            allCases.first { $0.slashDigit == slashDigit }
        }

        static func resolve(mnemonic: String) -> ShiftKind? {
            if mnemonic == "sal" { return .shl }
            return ShiftKind(rawValue: mnemonic)
        }
    }

    /// Shift count: by literal 1 (the D0/D1 implicit form), by CL
    /// (D2/D3), or by an 8-bit immediate (C0/C1 ib). The parser folds
    /// a numeric `1` literal onto `.one` so the encoder always picks
    /// the shorter implicit form.
    enum ShiftCount: Equatable {
        case one
        case cl
        case immediate(UInt8)
    }

    /// Three-operand double-precision shifts `SHLD` / `SHRD`. The count
    /// is either CL (`0F A5 / AD`) or an 8-bit immediate
    /// (`0F A4 / AC ib`); there is no by-1 implicit form.
    enum DoubleShiftKind: String, Equatable, CaseIterable {
        case shld, shrd

        /// Second-byte opcode for the imm8 form (A4 / AC).
        var immediateOpcode: UInt8 { self == .shld ? 0xA4 : 0xAC }
        /// Second-byte opcode for the CL form (A5 / AD).
        var clOpcode: UInt8 { self == .shld ? 0xA5 : 0xAD }
    }

    /// Where a conditional or unconditional jump (or CALL) sends control.
    /// `offset` is the byte delta from the end of the instruction — the
    /// value that lives directly in the rel field. `label` carries a
    /// name that the assembler resolves against the program's label map.
    enum BranchTarget: Equatable {
        case offset(Int64)
        case label(String)
    }

    /// The 16 single-byte condition codes that drive Jcc, CMOVcc, and
    /// SETcc. The raw value is the canonical mnemonic suffix; surface
    /// aliases (`jc`/`jnae`/...) are folded onto the canonical via
    /// `Condition.resolve(suffix:)`.
    enum Condition: String, Equatable, CaseIterable {
        case o, no, b, ae, e, ne, be, a, s, ns, p, np, l, ge, le, g

        /// The 4-bit code (0..15) used by Jcc / CMOVcc / SETcc opcodes.
        var encoding: UInt8 {
            switch self {
            case .o:  return 0x0
            case .no: return 0x1
            case .b:  return 0x2
            case .ae: return 0x3
            case .e:  return 0x4
            case .ne: return 0x5
            case .be: return 0x6
            case .a:  return 0x7
            case .s:  return 0x8
            case .ns: return 0x9
            case .p:  return 0xA
            case .np: return 0xB
            case .l:  return 0xC
            case .ge: return 0xD
            case .le: return 0xE
            case .g:  return 0xF
            }
        }

        static func decode(_ code: UInt8) -> Condition? {
            allCases.first { $0.encoding == code }
        }

        /// Resolve a mnemonic suffix (the text after the leading `j` /
        /// `cmov` / `set`) into a canonical condition. Surface aliases
        /// `c`/`nc`/`z`/`nz`/`na`/`nbe`/`pe`/`po`/`nl`/`nge`/`ng`/`nle`
        /// and the redundant `nae`/`nb` forms all fold here.
        static func resolve(suffix: String) -> Condition? {
            switch suffix {
            case "o":            return .o
            case "no":           return .no
            case "b", "nae", "c": return .b
            case "ae", "nb", "nc": return .ae
            case "e", "z":       return .e
            case "ne", "nz":     return .ne
            case "be", "na":     return .be
            case "a", "nbe":     return .a
            case "s":            return .s
            case "ns":           return .ns
            case "p", "pe":      return .p
            case "np", "po":     return .np
            case "l", "nge":     return .l
            case "ge", "nl":     return .ge
            case "le", "ng":     return .le
            case "g", "nle":     return .g
            default:             return nil
            }
        }
    }

    /// The `LOOP` family plus `JECXZ`/`JRCXZ`. All five share the
    /// `E0..E3 ib` opcode space; `JECXZ` is `JRCXZ` with the 0x67
    /// address-size override in long mode.
    enum LoopKind: String, Equatable, CaseIterable {
        case loop, loope, loopne, jecxz, jrcxz

        var opcode: UInt8 {
            switch self {
            case .loopne:        return 0xE0
            case .loope:         return 0xE1
            case .loop:          return 0xE2
            case .jecxz, .jrcxz: return 0xE3
            }
        }

        /// `JECXZ` needs the 0x67 address-size override in 64-bit mode
        /// to select ECX rather than the default RCX.
        var needsAddressSize: Bool { self == .jecxz }

        static func resolve(mnemonic: String) -> LoopKind? {
            switch mnemonic {
            case "loopz":  return .loope
            case "loopnz": return .loopne
            default:       return LoopKind(rawValue: mnemonic)
            }
        }

        static func decode(opcode: UInt8, addressOverride: Bool) -> LoopKind? {
            switch opcode {
            case 0xE0: return .loopne
            case 0xE1: return .loope
            case 0xE2: return .loop
            case 0xE3: return addressOverride ? .jecxz : .jrcxz
            default:   return nil
            }
        }
    }

    /// The set of instructions recognised by the current implementation.
    enum Instruction: Equatable {
        case zeroOperand(ZeroOperandKind)
        case mov(destination: RegisterOrMemory, source: Operand)
        case binaryAlu(BinaryAluKind, destination: RegisterOrMemory, source: Operand)
        case unaryAlu(UnaryAluKind, target: RegisterOrMemory)
        case test(left: RegisterOrMemory, right: Operand)
        case shift(ShiftKind, target: RegisterOrMemory, count: ShiftCount)
        case doubleShift(DoubleShiftKind, target: RegisterOrMemory, source: Register, count: ShiftCount)
        case jump(BranchTarget)
        case conditionalJump(Condition, BranchTarget)
        case call(BranchTarget)
        case loop(LoopKind, BranchTarget)
    }
}
