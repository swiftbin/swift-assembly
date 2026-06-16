import Foundation

/// The X86 / X86-64 instruction-model namespace, mirroring the layering of
/// `A64`. Domain types (registers, memory operands, instruction kinds) live
/// here; the byte-level format descriptors live in `X86InstructionFormats`.
internal enum X86 {
    /// Operand width tag. The first four cases are GPR widths; the
    /// remaining vector widths are used by SSE/AVX memory operands and
    /// SIMD-register types. (Registers themselves are GPR-only; SIMD
    /// register references go through dedicated types like `XMMRegister`.)
    enum RegisterWidth: Int, Equatable {
        case byte = 8
        case word = 16
        case dword = 32
        case qword = 64
        case xmmword = 128
    }

    /// A 128-bit SSE/AVX register (XMM0..XMM15). Distinct from `Register`
    /// because XMMs have no high-byte / REX-byte quirks and never share
    /// encoding slots with general-purpose registers.
    struct XMMRegister: Equatable {
        var number: UInt8

        var lowBits: UInt8 { number & 0x7 }
        var highBit: UInt8 { (number >> 3) & 0x1 }
    }

    /// SSE operand: a 128-bit XMM register or a memory reference. The
    /// memory operand's width depends on the instruction (m32 for MOVSS,
    /// m64 for MOVSD, m128 for the rest).
    enum XMMOrMemory: Equatable {
        case register(XMMRegister)
        case memory(MemoryOperand)
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
            case .byte:    return "byte"
            case .word:    return "word"
            case .dword:   return "dword"
            case .qword:   return "qword"
            case .xmmword: return "xmmword"
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
        case int1, int3, ud2
        case clc, stc, cmc, cld, std, cli, sti
        case lahf, sahf
        case pause, hlt, wait, xlatb
        case syscall, sysret, sysretq, swapgs
        case cpuid
        case rdtsc, rdtscp, rdmsr, wrmsr, rdpmc
        case monitor, mwait
        // Sign-extension into the accumulator. 0x98 / 0x99 are the same
        // opcode bytes; the operand-size prefix or REX.W selects which
        // mnemonic. CBW = AL→AX, CWDE = AX→EAX, CDQE = EAX→RAX;
        // CWD = AX→DX:AX, CDQ = EAX→EDX:EAX, CQO = RAX→RDX:RAX.
        case cbw, cwde, cdqe
        case cwd, cdq, cqo
        // Stack flag push/pop. In long mode the default operand size is
        // qword; the 0x66 prefix selects the 16-bit form.
        case pushfq, popfq
        case pushfw, popfw
        // Memory fences (0F AE with mod=11 sub-opcodes).
        case lfence, mfence, sfence
        // Cache / TLB / flag-control system ops.
        case invd, wbinvd
        case clts
        // x87 FPU zero-operand instructions. All ride the D8..DF opcode
        // range with a fixed mod=11 sub-encoding. Many of these come
        // in WAIT / no-WAIT pairs (e.g. FINIT = 9B DB E3 vs FNINIT =
        // DB E3); both forms get their own entry so longest-prefix
        // matching picks the right canonical mnemonic.
        case fchs, fabs, fsqrt, frndint
        case fld1, fldl2t, fldl2e, fldpi, fldlg2, fldln2, fldz
        case ftst, fxam
        case fnop, fdecstp, fincstp
        case fsin, fcos, fsincos, fptan, fpatan, f2xm1
        case fyl2x, fyl2xp1, fprem, fprem1, fscale, fxtract
        case fninit, finit, fnclex, fclex
        case fcompp, fucompp

        var bytes: [UInt8] {
            switch self {
            case .nop:      return [0x90]
            case .ret:      return [0xC3]
            case .retf:     return [0xCB]
            case .iret:     return [0x66, 0xCF]
            case .iretd:    return [0xCF]
            case .iretq:    return [0x48, 0xCF]
            case .leave:    return [0xC9]
            case .int1:     return [0xF1]
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
            case .cbw:      return [0x66, 0x98]
            case .cwde:     return [0x98]
            case .cdqe:     return [0x48, 0x98]
            case .cwd:      return [0x66, 0x99]
            case .cdq:      return [0x99]
            case .cqo:      return [0x48, 0x99]
            case .pushfq:   return [0x9C]
            case .popfq:    return [0x9D]
            case .pushfw:   return [0x66, 0x9C]
            case .popfw:    return [0x66, 0x9D]
            case .lfence:   return [0x0F, 0xAE, 0xE8]
            case .mfence:   return [0x0F, 0xAE, 0xF0]
            case .sfence:   return [0x0F, 0xAE, 0xF8]
            case .invd:     return [0x0F, 0x08]
            case .wbinvd:   return [0x0F, 0x09]
            case .clts:     return [0x0F, 0x06]
            // x87 — D9 E0..FF block (unary FP ops and constants).
            case .fchs:     return [0xD9, 0xE0]
            case .fabs:     return [0xD9, 0xE1]
            case .ftst:     return [0xD9, 0xE4]
            case .fxam:     return [0xD9, 0xE5]
            case .fld1:     return [0xD9, 0xE8]
            case .fldl2t:   return [0xD9, 0xE9]
            case .fldl2e:   return [0xD9, 0xEA]
            case .fldpi:    return [0xD9, 0xEB]
            case .fldlg2:   return [0xD9, 0xEC]
            case .fldln2:   return [0xD9, 0xED]
            case .fldz:     return [0xD9, 0xEE]
            case .f2xm1:    return [0xD9, 0xF0]
            case .fyl2x:    return [0xD9, 0xF1]
            case .fptan:    return [0xD9, 0xF2]
            case .fpatan:   return [0xD9, 0xF3]
            case .fxtract:  return [0xD9, 0xF4]
            case .fprem1:   return [0xD9, 0xF5]
            case .fdecstp:  return [0xD9, 0xF6]
            case .fincstp:  return [0xD9, 0xF7]
            case .fprem:    return [0xD9, 0xF8]
            case .fyl2xp1:  return [0xD9, 0xF9]
            case .fsqrt:    return [0xD9, 0xFA]
            case .fsincos:  return [0xD9, 0xFB]
            case .frndint:  return [0xD9, 0xFC]
            case .fscale:   return [0xD9, 0xFD]
            case .fsin:     return [0xD9, 0xFE]
            case .fcos:     return [0xD9, 0xFF]
            case .fnop:     return [0xD9, 0xD0]
            // Compare-and-pop pairs.
            case .fcompp:   return [0xDE, 0xD9]
            case .fucompp:  return [0xDA, 0xE9]
            // Control-word ops: WAIT (0x9B) and no-WAIT variants.
            case .fnclex:   return [0xDB, 0xE2]
            case .fninit:   return [0xDB, 0xE3]
            case .fclex:    return [0x9B, 0xDB, 0xE2]
            case .finit:    return [0x9B, 0xDB, 0xE3]
            }
        }

        static func resolve(mnemonic: String) -> ZeroOperandKind? {
            switch mnemonic {
            case "fwait": return .wait
            case "xlat":  return .xlatb
            // In long mode `pushf`/`popf` default to qword.
            case "pushf": return .pushfq
            case "popf":  return .popfq
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

    /// 1-operand multiply / divide. The `/n` slash-digit (4..7 in the
    /// F6/F7 opcode group) selects the operation:
    ///
    /// * `/4` MUL — unsigned multiply
    /// * `/5` IMUL — signed multiply
    /// * `/6` DIV — unsigned divide
    /// * `/7` IDIV — signed divide
    ///
    /// All four share the same operand shape: a single r/m of any width.
    /// The implicit accumulator pair (AX, DX:AX, EDX:EAX, RDX:RAX) is
    /// determined by the operand width.
    enum MulDivKind: String, Equatable, CaseIterable {
        case mul, imul, div, idiv

        var slashDigit: UInt8 {
            switch self {
            case .mul:  return 4
            case .imul: return 5
            case .div:  return 6
            case .idiv: return 7
            }
        }

        static func decode(slashDigit: UInt8) -> MulDivKind? {
            allCases.first { $0.slashDigit == slashDigit }
        }
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
        case jumpIndirect(target: RegisterOrMemory)
        case callIndirect(target: RegisterOrMemory)
        case enter(allocation: UInt16, nestingLevel: UInt8)
        case mulDiv(MulDivKind, target: RegisterOrMemory)
        /// 2-operand IMUL (`0F AF /r`): r = r × r/m, signed.
        case imulRegister(destination: Register, source: RegisterOrMemory)
        /// 3-operand IMUL (`69 /r iw/id`, `6B /r ib`): r = r/m × imm, signed.
        case imulImmediate(destination: Register, source: RegisterOrMemory, immediate: Int64)
        /// PUSH r/m/imm. Operand width must be word or qword in long mode.
        case push(Operand)
        /// POP r/m. No immediate form.
        case pop(RegisterOrMemory)
        /// LEA r, m — load effective address. The source is treated as
        /// an address expression, not a memory access; its width is the
        /// destination register's width.
        case lea(destination: Register, source: MemoryOperand)
        /// Sign- or zero-extending move. The destination's width is the
        /// instruction operand size; the source's width determines the
        /// 0F BE / BF / B6 / B7 opcode byte (or 63 for MOVSXD).
        case extendingMove(ExtendingMoveKind, destination: Register, source: RegisterOrMemory)
        /// BSWAP r32 / r64 — reverse the byte order of a register.
        case bswap(Register)
        /// XCHG r/m, r. Symmetric in semantics; the encoder picks the
        /// short form when exactly one operand is rAX.
        case xchg(target: RegisterOrMemory, register: Register)
        /// XADD r/m, r — atomic exchange-add.
        case xadd(target: RegisterOrMemory, source: Register)
        /// CMPXCHG r/m, r — atomic compare-and-swap against rAX.
        case cmpxchg(target: RegisterOrMemory, source: Register)
        /// CMPXCHG8B / CMPXCHG16B — wide compare-and-swap whose width
        /// is intrinsic to the mnemonic (8 or 16 bytes).
        case cmpxchgWide(CmpxchgWideKind, MemoryOperand)
        /// CMOVcc r, r/m — conditional move (16 condition codes, RM form,
        /// no byte form).
        case cmovcc(Condition, destination: Register, source: RegisterOrMemory)
        /// SETcc r/m8 — set byte on condition. The ModR/M `reg` field is
        /// don't-care and the encoder writes `/0` by convention.
        case setcc(Condition, target: RegisterOrMemory)
        /// BT / BTS / BTR / BTC — bit test (and optionally set/reset/
        /// complement). Two operand shapes: `r/m, r` (`0F A3/AB/B3/BB
        /// /r`) and `r/m, imm8` (`0F BA /n ib`).
        case bitTest(BitTestKind, target: RegisterOrMemory, source: BitTestSource)
        /// BSF / BSR — bit scan forward / reverse (`0F BC/BD /r`).
        case bitScan(BitScanKind, destination: Register, source: RegisterOrMemory)
        /// POPCNT / LZCNT / TZCNT — population/leading-zero/trailing-zero
        /// counts (`F3 0F B8/BD/BC /r`). The F3 prefix is mandatory and
        /// distinguishes LZCNT/TZCNT from BSR/BSF at the same opcode.
        case bitCount(BitCountKind, destination: Register, source: RegisterOrMemory)
        /// String operation (MOVS/CMPS/SCAS/LODS/STOS/INS/OUTS) with an
        /// optional REP/REPE/REPNE prefix. The operands (RSI/RDI/RAX/DX)
        /// are implicit so the model only carries the kind + prefix.
        case stringOp(StringOpKind, prefix: StringPrefix?)
        /// IN — read from a port into the AL/AX/EAX accumulator.
        case inFromPort(target: Register, port: PortSource)
        /// OUT — write the AL/AX/EAX accumulator out to a port.
        case outToPort(source: Register, port: PortSource)
        /// `INT imm8` — software interrupt with an 8-bit vector. INT3
        /// and INT1 live in `ZeroOperandKind` because they have fixed
        /// opcodes; this case covers the general `CD ib` form.
        case interrupt(vector: UInt8)
        /// `CLFLUSH m` — flush a cache line containing `m` (`0F AE /7`,
        /// `mod != 11`).
        case clflush(MemoryOperand)
        /// `INVLPG m` — invalidate the TLB entry for `m` (`0F 01 /7`,
        /// `mod != 11`). The mod=11 sub-encodings of `/7` (`SWAPGS`,
        /// `RDTSCP`) live in `ZeroOperandKind`.
        case invlpg(MemoryOperand)
        /// Descriptor-table load/store with a 10-byte memory operand:
        /// SGDT, SIDT, LGDT, LIDT (`0F 01 /0..3`).
        case descriptorTable(DescriptorTableKind, memory: MemoryOperand)
        /// System r/m instructions (SLDT/STR/LLDT/LTR/VERR/VERW,
        /// SMSW/LMSW). Most are r/m16-only; the read variants
        /// (SLDT/STR/SMSW) also accept r32/r64 destinations.
        case systemRM(SystemRMKind, target: RegisterOrMemory)
        /// `MOV r64, CRn/DRn` — read a control or debug register.
        case movFromSystemRegister(SystemRegisterKind, destination: Register, number: UInt8)
        /// `MOV CRn/DRn, r64` — write a control or debug register.
        case movToSystemRegister(SystemRegisterKind, number: UInt8, source: Register)
        /// `LAR r, r/m` — load access rights (`0F 02 /r`).
        case lar(destination: Register, source: RegisterOrMemory)
        /// `LSL r, r/m` — load segment limit (`0F 03 /r`).
        case lsl(destination: Register, source: RegisterOrMemory)
        /// SSE/SSE2 MOV family: MOVAPS/MOVUPS/MOVAPD/MOVUPD/MOVDQA/
        /// MOVDQU/MOVSS/MOVSD. The kind determines the mandatory prefix
        /// (none/66/F3/F2) and the load/store opcode pair.
        case sseMov(SSEMovKind, destination: XMMOrMemory, source: XMMOrMemory)
        /// SSE arithmetic: ADD/SUB/MUL/DIV/MIN/MAX/SQRT in PS/PD/SS/SD
        /// variants. All ride `0F 5x /r` with a mandatory prefix
        /// selecting the variant (none for PS, 66 for PD, F3 for SS,
        /// F2 for SD).
        case sseArithmetic(SSEArithmeticKind, destination: XMMRegister, source: XMMOrMemory)
        /// `CVTSI2SS` / `CVTSI2SD` — convert signed integer from a
        /// general-purpose register (or memory) into a scalar
        /// single/double-precision float in an XMM register
        /// (`F3 0F 2A /r` / `F2 0F 2A /r`).
        case sseIntToFloat(SSEIntToFloatKind, destination: XMMRegister, source: RegisterOrMemory)
        /// `CVTSS2SI` / `CVTSD2SI` (rounded) and `CVTTSS2SI` /
        /// `CVTTSD2SI` (truncated) — convert a scalar single/double
        /// from XMM (or memory) into a signed integer in a GPR
        /// (`F3/F2 0F 2D /r` and `F3/F2 0F 2C /r`).
        case sseFloatToInt(SSEFloatToIntKind, destination: Register, source: XMMOrMemory)
        /// MOVD / MOVQ — move 32 or 64 bits between an XMM register and
        /// a GPR or memory operand. The two mnemonics share opcodes
        /// `66 0F 6E /r` (load) and `66 0F 7E /r` (store); REX.W
        /// distinguishes MOVD (dword) from MOVQ (qword).
        case movDQ(MovDQKind, direction: MovDQDirection, xmm: XMMRegister, gpr: RegisterOrMemory)
        /// SSE2 packed-integer arithmetic and bit-wise logic.
        /// Operand shape is `xmm, xmm/m128`; all ride `66 0F xx /r`
        /// with the opcode picking the operation.
        case ssePackedInteger(SSEPackedIntegerKind, destination: XMMRegister, source: XMMOrMemory)
    }

    /// SSE2 packed integer operations on 128-bit XMM operands.
    /// Width suffixes (`b`/`w`/`d`/`q`) indicate the element size
    /// (8/16/32/64 bits) within the packed vector. Saturating variants
    /// use `s` (signed) or `us` (unsigned). All ride `66 0F xx /r`.
    enum SSEPackedIntegerKind: String, Equatable, CaseIterable {
        // Unsaturated add / sub by element width
        case paddb, paddw, paddd, paddq
        case psubb, psubw, psubd, psubq
        // Saturating add / sub
        case paddsb, paddsw, paddusb, paddusw
        case psubsb, psubsw, psubusb, psubusw
        // Bit-wise logic
        case pand, pandn, por, pxor
        // Compare for equal / greater-than (byte / word / dword lanes)
        case pcmpeqb, pcmpeqw, pcmpeqd
        case pcmpgtb, pcmpgtw, pcmpgtd
        // Multiplies and multiply-add
        case pmullw          // low 16 of 16x16 → 16
        case pmulhw          // high 16 of 16x16 (signed)
        case pmulhuw         // high 16 of 16x16 (unsigned)
        case pmuludq         // 32x32 → 64 (low 32 of each qword)
        case pmaddwd         // multiply-then-add adjacent pairs
        // Per-lane min / max
        case pminub, pminsw
        case pmaxub, pmaxsw
        // Rounded average and sum-of-absolute-differences
        case pavgb, pavgw
        case psadbw
        // Interleave low / high lanes of two vectors
        case punpcklbw, punpcklwd, punpckldq, punpcklqdq
        case punpckhbw, punpckhwd, punpckhdq, punpckhqdq
        // Pack with saturation: word → byte and dword → word
        case packsswb, packssdw    // signed
        case packuswb              // unsigned
        // Variable shifts (count taken from xmm/m128). The imm8 forms
        // ride a different opcode group and live in their own case.
        case psllw, pslld, psllq
        case psrlw, psrld, psrlq
        case psraw, psrad

        var opcode2: UInt8 {
            switch self {
            case .punpcklbw: return 0x60
            case .punpcklwd: return 0x61
            case .punpckldq: return 0x62
            case .packsswb:  return 0x63
            case .pcmpgtb:  return 0x64
            case .pcmpgtw:  return 0x65
            case .pcmpgtd:  return 0x66
            case .packuswb: return 0x67
            case .punpckhbw: return 0x68
            case .punpckhwd: return 0x69
            case .punpckhdq: return 0x6A
            case .packssdw:  return 0x6B
            case .punpcklqdq: return 0x6C
            case .punpckhqdq: return 0x6D
            case .pcmpeqb:  return 0x74
            case .pcmpeqw:  return 0x75
            case .pcmpeqd:  return 0x76
            case .psrlw:    return 0xD1
            case .psrld:    return 0xD2
            case .psrlq:    return 0xD3
            case .paddq:    return 0xD4
            case .pmullw:   return 0xD5
            case .psubusb:  return 0xD8
            case .psubusw:  return 0xD9
            case .pminub:   return 0xDA
            case .pand:     return 0xDB
            case .paddusb:  return 0xDC
            case .paddusw:  return 0xDD
            case .pmaxub:   return 0xDE
            case .pandn:    return 0xDF
            case .pavgb:    return 0xE0
            case .psraw:    return 0xE1
            case .psrad:    return 0xE2
            case .pavgw:    return 0xE3
            case .pmulhuw:  return 0xE4
            case .pmulhw:   return 0xE5
            case .psubsb:   return 0xE8
            case .psubsw:   return 0xE9
            case .pminsw:   return 0xEA
            case .por:      return 0xEB
            case .paddsb:   return 0xEC
            case .paddsw:   return 0xED
            case .pmaxsw:   return 0xEE
            case .pxor:     return 0xEF
            case .psllw:    return 0xF1
            case .pslld:    return 0xF2
            case .psllq:    return 0xF3
            case .pmuludq:  return 0xF4
            case .pmaddwd:  return 0xF5
            case .psadbw:   return 0xF6
            case .psubb:    return 0xF8
            case .psubw:    return 0xF9
            case .psubd:    return 0xFA
            case .psubq:    return 0xFB
            case .paddb:    return 0xFC
            case .paddw:    return 0xFD
            case .paddd:    return 0xFE
            }
        }

        static func decode(opcode2: UInt8) -> SSEPackedIntegerKind? {
            allCases.first { $0.opcode2 == opcode2 }
        }
    }

    enum MovDQKind: String, Equatable, CaseIterable {
        case movd, movq

        var gprWidth: RegisterWidth {
            switch self {
            case .movd: return .dword
            case .movq: return .qword
            }
        }
    }

    enum MovDQDirection: Equatable {
        case load   // xmm <- r/m
        case store  // r/m <- xmm
    }

    enum SSEIntToFloatKind: String, Equatable, CaseIterable {
        case cvtsi2ss, cvtsi2sd

        var mandatoryPrefix: UInt8 {
            switch self {
            case .cvtsi2ss: return 0xF3
            case .cvtsi2sd: return 0xF2
            }
        }

        static func decode(mandatoryPrefix: UInt8) -> SSEIntToFloatKind? {
            allCases.first { $0.mandatoryPrefix == mandatoryPrefix }
        }
    }

    enum SSEFloatToIntKind: String, Equatable, CaseIterable {
        case cvtss2si, cvtsd2si     // rounded (uses MXCSR rounding mode)
        case cvttss2si, cvttsd2si   // truncated

        /// Opcode2: `0x2D` for the rounded variants, `0x2C` for
        /// the truncating ones.
        var opcode2: UInt8 {
            switch self {
            case .cvtss2si, .cvtsd2si:   return 0x2D
            case .cvttss2si, .cvttsd2si: return 0x2C
            }
        }

        var mandatoryPrefix: UInt8 {
            switch self {
            case .cvtss2si, .cvttss2si: return 0xF3
            case .cvtsd2si, .cvttsd2si: return 0xF2
            }
        }

        /// Memory operand width when the source is a memory reference.
        /// Scalar single → m32; scalar double → m64.
        var sourceMemoryWidth: RegisterWidth {
            switch self {
            case .cvtss2si, .cvttss2si: return .dword
            case .cvtsd2si, .cvttsd2si: return .qword
            }
        }

        static func decode(mandatoryPrefix: UInt8, opcode2: UInt8) -> SSEFloatToIntKind? {
            allCases.first { $0.mandatoryPrefix == mandatoryPrefix && $0.opcode2 == opcode2 }
        }
    }

    /// SSE/SSE2 arithmetic variants. The opcode byte at `0F xx`
    /// selects the operation (ADD/SUB/MUL/DIV/MIN/MAX/SQRT); the
    /// mandatory prefix (none / 0x66 / 0xF3 / 0xF2) selects the
    /// PS/PD/SS/SD precision form, which also determines the memory
    /// operand width (m128 for PS/PD, m32 for SS, m64 for SD).
    enum SSEArithmeticKind: String, Equatable, CaseIterable {
        case addps, addpd, addss, addsd
        case subps, subpd, subss, subsd
        case mulps, mulpd, mulss, mulsd
        case divps, divpd, divss, divsd
        case minps, minpd, minss, minsd
        case maxps, maxpd, maxss, maxsd
        case sqrtps, sqrtpd, sqrtss, sqrtsd
        // Reciprocal / reciprocal square-root — single-precision only
        // (no PD/SD variants exist).
        case rcpps, rcpss
        case rsqrtps, rsqrtss
        // Bit-wise logic — PS/PD only (no SS/SD).
        case andps, andpd
        case andnps, andnpd
        case orps, orpd
        case xorps, xorpd
        // Compare-with-flags (sets EFLAGS, doesn't write back to dst).
        // COMI signals invalid on QNaN; UCOMI doesn't.
        case ucomiss, ucomisd
        case comiss, comisd
        // Floating-point format conversions (XMM ↔ XMM). All ride the
        // `0F 5A` (precision change) and `0F 5B` (FP ↔ int) opcodes
        // with mandatory prefixes selecting the source/destination
        // type pair.
        case cvtss2sd, cvtsd2ss   // scalar single ↔ scalar double
        case cvtps2pd, cvtpd2ps   // packed
        case cvtdq2ps, cvtps2dq, cvttps2dq   // integer ↔ packed single

        /// Second-byte opcode (operation selector).
        var opcode2: UInt8 {
            switch self {
            case .ucomiss, .ucomisd:                 return 0x2E
            case .comiss,  .comisd:                  return 0x2F
            case .cvtss2sd, .cvtsd2ss,
                 .cvtps2pd, .cvtpd2ps:               return 0x5A
            case .cvtdq2ps, .cvtps2dq, .cvttps2dq:   return 0x5B
            case .sqrtps, .sqrtpd, .sqrtss, .sqrtsd: return 0x51
            case .rsqrtps, .rsqrtss:                 return 0x52
            case .rcpps, .rcpss:                     return 0x53
            case .andps, .andpd:                     return 0x54
            case .andnps, .andnpd:                   return 0x55
            case .orps, .orpd:                       return 0x56
            case .xorps, .xorpd:                     return 0x57
            case .addps,  .addpd,  .addss,  .addsd:  return 0x58
            case .mulps,  .mulpd,  .mulss,  .mulsd:  return 0x59
            case .subps,  .subpd,  .subss,  .subsd:  return 0x5C
            case .minps,  .minpd,  .minss,  .minsd:  return 0x5D
            case .divps,  .divpd,  .divss,  .divsd:  return 0x5E
            case .maxps,  .maxpd,  .maxss,  .maxsd:  return 0x5F
            }
        }

        /// Mandatory prefix byte (variant selector).
        var mandatoryPrefix: UInt8? {
            switch self {
            case .addps, .subps, .mulps, .divps, .minps, .maxps, .sqrtps,
                 .rcpps, .rsqrtps,
                 .andps, .andnps, .orps, .xorps,
                 .ucomiss, .comiss,
                 .cvtps2pd, .cvtdq2ps:
                return nil
            case .addpd, .subpd, .mulpd, .divpd, .minpd, .maxpd, .sqrtpd,
                 .andpd, .andnpd, .orpd, .xorpd,
                 .ucomisd, .comisd,
                 .cvtpd2ps, .cvtps2dq:
                return 0x66
            case .addss, .subss, .mulss, .divss, .minss, .maxss, .sqrtss,
                 .rcpss, .rsqrtss,
                 .cvtss2sd, .cvttps2dq:
                return 0xF3
            case .addsd, .subsd, .mulsd, .divsd, .minsd, .maxsd, .sqrtsd,
                 .cvtsd2ss:
                return 0xF2
            }
        }

        /// Memory operand width when the source is a memory reference.
        /// Most variants follow the prefix-based rule (66/none → m128,
        /// F3 → m32, F2 → m64), but COMI/UCOMI and several conversions
        /// have intrinsic widths that disagree with the prefix shortcut.
        var memoryWidth: RegisterWidth {
            switch self {
            case .ucomiss, .comiss,
                 .cvtss2sd:                     // src: m32 (single)
                return .dword
            case .ucomisd, .comisd,
                 .cvtsd2ss,                     // src: m64 (double)
                 .cvtps2pd:                     // src: m64 (two singles in low half)
                return .qword
            case .cvtpd2ps, .cvtdq2ps,
                 .cvtps2dq, .cvttps2dq:         // src: m128 (packed)
                return .xmmword
            default:
                switch self.mandatoryPrefix {
                case 0xF3: return .dword   // SS: scalar single
                case 0xF2: return .qword   // SD: scalar double
                default:   return .xmmword // PS/PD: packed
                }
            }
        }

        static func decode(mandatoryPrefix: UInt8?, opcode2: UInt8) -> SSEArithmeticKind? {
            allCases.first { $0.mandatoryPrefix == mandatoryPrefix && $0.opcode2 == opcode2 }
        }
    }

    /// SSE/SSE2 data movement variants. Each kind owns its mandatory
    /// prefix (none/66/F3/F2) and the two 0F-escape opcodes that
    /// implement the load (xmm ← r/m) and store (r/m ← xmm) directions.
    enum SSEMovKind: String, Equatable, CaseIterable {
        case movaps, movups, movapd, movupd
        case movdqa, movdqu
        case movss, movsd

        /// Mandatory legacy prefix byte (or nil for the no-prefix forms).
        var mandatoryPrefix: UInt8? {
            switch self {
            case .movaps, .movups:                  return nil
            case .movapd, .movupd, .movdqa:         return 0x66
            case .movdqu, .movss:                   return 0xF3
            case .movsd:                            return 0xF2
            }
        }

        /// Second-byte opcode for the load direction (RM, xmm ← r/m).
        var loadOpcode: UInt8 {
            switch self {
            case .movaps, .movapd:                   return 0x28
            case .movups, .movupd, .movss, .movsd:   return 0x10
            case .movdqa, .movdqu:                   return 0x6F
            }
        }

        /// Second-byte opcode for the store direction (MR, r/m ← xmm).
        var storeOpcode: UInt8 {
            switch self {
            case .movaps, .movapd:                   return 0x29
            case .movups, .movupd, .movss, .movsd:   return 0x11
            case .movdqa, .movdqu:                   return 0x7F
            }
        }

        /// Memory operand width. MOVSS / MOVSD touch a single scalar
        /// (32 / 64 bits); everything else moves a full 128-bit vector.
        var memoryWidth: RegisterWidth {
            switch self {
            case .movss: return .dword
            case .movsd: return .qword
            default:     return .xmmword
            }
        }

        /// Decode the kind from (mandatory prefix, opcode2). Returns
        /// `nil` if the combination doesn't name an SSE MOV variant.
        static func decode(mandatoryPrefix: UInt8?, opcode2: UInt8) -> (kind: SSEMovKind, isLoad: Bool)? {
            for kind in allCases {
                guard kind.mandatoryPrefix == mandatoryPrefix else { continue }
                if kind.loadOpcode == opcode2  { return (kind, true) }
                if kind.storeOpcode == opcode2 { return (kind, false) }
            }
            return nil
        }
    }

    enum SystemRegisterKind: String, Equatable, CaseIterable {
        case cr, dr

        /// `MOV r, <sysreg>` opcode (read direction): `0F 20` for CR,
        /// `0F 21` for DR.
        var readOpcode2: UInt8 {
            switch self {
            case .cr: return 0x20
            case .dr: return 0x21
            }
        }

        /// `MOV <sysreg>, r` opcode (write direction): `0F 22` for CR,
        /// `0F 23` for DR.
        var writeOpcode2: UInt8 {
            switch self {
            case .cr: return 0x22
            case .dr: return 0x23
            }
        }

        static func decode(opcode2: UInt8) -> (kind: SystemRegisterKind, isRead: Bool)? {
            switch opcode2 {
            case 0x20: return (.cr, true)
            case 0x21: return (.dr, true)
            case 0x22: return (.cr, false)
            case 0x23: return (.dr, false)
            default:   return nil
            }
        }
    }

    enum DescriptorTableKind: String, Equatable, CaseIterable {
        case sgdt, sidt, lgdt, lidt

        var slashDigit: UInt8 {
            switch self {
            case .sgdt: return 0
            case .sidt: return 1
            case .lgdt: return 2
            case .lidt: return 3
            }
        }

        static func decode(slashDigit: UInt8) -> DescriptorTableKind? {
            allCases.first { $0.slashDigit == slashDigit }
        }
    }

    enum SystemRMKind: String, Equatable, CaseIterable {
        case sldt, str, lldt, ltr, verr, verw   // 0F 00 /0..5
        case smsw, lmsw                          // 0F 01 /4 and /6

        /// Second-byte opcode (the 0F-escape sub-table).
        var escape2: UInt8 {
            switch self {
            case .smsw, .lmsw: return 0x01
            default:           return 0x00
            }
        }

        /// `/n` slash-digit placed in ModR/M.reg.
        var slashDigit: UInt8 {
            switch self {
            case .sldt: return 0
            case .str:  return 1
            case .lldt: return 2
            case .ltr:  return 3
            case .verr: return 4
            case .verw: return 5
            case .smsw: return 4
            case .lmsw: return 6
            }
        }

        /// SLDT/STR/SMSW are "store" variants that can write into a
        /// wider register (r32/r64), zero-extending the 16-bit source.
        /// The "load/verify" variants are r/m16 only.
        var allowsWideRegister: Bool {
            switch self {
            case .sldt, .str, .smsw: return true
            default:                 return false
            }
        }

        static func decode(escape2: UInt8, slashDigit: UInt8) -> SystemRMKind? {
            allCases.first { $0.escape2 == escape2 && $0.slashDigit == slashDigit }
        }
    }

    /// The port specifier of IN/OUT: an 8-bit immediate (E4/E5/E6/E7)
    /// or the DX register (EC/ED/EE/EF).
    enum PortSource: Equatable {
        case immediate(UInt8)
        case dx
    }

    /// Identifies one of the implicit-operand string operations. The
    /// raw value is the canonical mnemonic; surface aliases (e.g. the
    /// rare `cmpsd` collision with the SSE form) are handled by the
    /// parser when more context is available.
    enum StringOpKind: String, Equatable, CaseIterable {
        case movsb, movsw, movsd, movsq
        case cmpsb, cmpsw, cmpsd, cmpsq
        case scasb, scasw, scasd, scasq
        case lodsb, lodsw, lodsd, lodsq
        case stosb, stosw, stosd, stosq
        case insb,  insw,  insd
        case outsb, outsw, outsd

        /// The full base byte sequence (including the operand-size
        /// prefix or REX.W for word/qword forms), excluding any REP /
        /// REPE / REPNE prefix.
        var baseBytes: [UInt8] {
            switch self {
            case .movsb: return [0xA4]
            case .movsw: return [0x66, 0xA5]
            case .movsd: return [0xA5]
            case .movsq: return [0x48, 0xA5]

            case .cmpsb: return [0xA6]
            case .cmpsw: return [0x66, 0xA7]
            case .cmpsd: return [0xA7]
            case .cmpsq: return [0x48, 0xA7]

            case .scasb: return [0xAE]
            case .scasw: return [0x66, 0xAF]
            case .scasd: return [0xAF]
            case .scasq: return [0x48, 0xAF]

            case .lodsb: return [0xAC]
            case .lodsw: return [0x66, 0xAD]
            case .lodsd: return [0xAD]
            case .lodsq: return [0x48, 0xAD]

            case .stosb: return [0xAA]
            case .stosw: return [0x66, 0xAB]
            case .stosd: return [0xAB]
            case .stosq: return [0x48, 0xAB]

            case .insb:  return [0x6C]
            case .insw:  return [0x66, 0x6D]
            case .insd:  return [0x6D]

            case .outsb: return [0x6E]
            case .outsw: return [0x66, 0x6F]
            case .outsd: return [0x6F]
            }
        }

        /// True for CMPS / SCAS, which use the F3 prefix as REPE rather
        /// than REP and accept F2 (REPNE).
        var isComparison: Bool {
            switch self {
            case .cmpsb, .cmpsw, .cmpsd, .cmpsq,
                 .scasb, .scasw, .scasd, .scasq:
                return true
            default:
                return false
            }
        }

        /// Decode the kind from a base opcode byte plus width info.
        /// Returns `nil` if the byte isn't a string-op opcode.
        static func decode(opcode: UInt8, operandSize: Bool, rexW: Bool) -> StringOpKind? {
            let isByteOpcode = (opcode & 0x01) == 0
            let widthVariant: StringOpKind?
            switch opcode {
            case 0xA4, 0xA5:
                widthVariant = isByteOpcode ? .movsb : (rexW ? .movsq : (operandSize ? .movsw : .movsd))
            case 0xA6, 0xA7:
                widthVariant = isByteOpcode ? .cmpsb : (rexW ? .cmpsq : (operandSize ? .cmpsw : .cmpsd))
            case 0xAA, 0xAB:
                widthVariant = isByteOpcode ? .stosb : (rexW ? .stosq : (operandSize ? .stosw : .stosd))
            case 0xAC, 0xAD:
                widthVariant = isByteOpcode ? .lodsb : (rexW ? .lodsq : (operandSize ? .lodsw : .lodsd))
            case 0xAE, 0xAF:
                widthVariant = isByteOpcode ? .scasb : (rexW ? .scasq : (operandSize ? .scasw : .scasd))
            case 0x6C, 0x6D:
                widthVariant = isByteOpcode ? .insb : (operandSize ? .insw : .insd)
            case 0x6E, 0x6F:
                widthVariant = isByteOpcode ? .outsb : (operandSize ? .outsw : .outsd)
            default:
                widthVariant = nil
            }
            return widthVariant
        }
    }

    /// The mandatory prefix on a REP / REPE / REPNE string op. The
    /// formatter resolves the mnemonic by looking at the paired
    /// `StringOpKind.isComparison` (REP vs REPE for the same F3 byte).
    enum StringPrefix: Equatable {
        case f3   // REP (moving ops) / REPE (comparing ops)
        case f2   // REPNE (comparing ops only)

        var byte: UInt8 {
            switch self {
            case .f3: return 0xF3
            case .f2: return 0xF2
            }
        }
    }

    enum BitCountKind: String, Equatable, CaseIterable {
        case popcnt, lzcnt, tzcnt

        /// Second-byte opcode after the mandatory F3 prefix.
        var opcode2: UInt8 {
            switch self {
            case .popcnt: return 0xB8
            case .tzcnt:  return 0xBC
            case .lzcnt:  return 0xBD
            }
        }
    }

    enum BitTestKind: String, Equatable, CaseIterable {
        case bt, bts, btr, btc

        /// `/n` slash-digit in the imm8 form (`0F BA /n ib`).
        var slashDigit: UInt8 {
            switch self {
            case .bt:  return 4
            case .bts: return 5
            case .btr: return 6
            case .btc: return 7
            }
        }

        /// Second-byte opcode for the `r/m, r` form.
        var registerFormOpcode: UInt8 {
            switch self {
            case .bt:  return 0xA3
            case .bts: return 0xAB
            case .btr: return 0xB3
            case .btc: return 0xBB
            }
        }

        static func decode(slashDigit: UInt8) -> BitTestKind? {
            allCases.first { $0.slashDigit == slashDigit }
        }

        static func decodeRegisterForm(opcode2: UInt8) -> BitTestKind? {
            allCases.first { $0.registerFormOpcode == opcode2 }
        }
    }

    enum BitTestSource: Equatable {
        case register(Register)
        case immediate(UInt8)
    }

    enum BitScanKind: String, Equatable, CaseIterable {
        case bsf, bsr

        var opcode2: UInt8 {
            switch self {
            case .bsf: return 0xBC
            case .bsr: return 0xBD
            }
        }
    }

    enum ExtendingMoveKind: String, Equatable, CaseIterable {
        case movsx, movzx, movsxd
    }

    enum CmpxchgWideKind: String, Equatable, CaseIterable {
        case cmpxchg8b, cmpxchg16b
    }
}
