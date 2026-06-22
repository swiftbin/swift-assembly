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
        case ymmword = 256
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

    /// A 256-bit YMM register. The number space is identical to XMM
    /// (0–15) — the vector width is encoded by the VEX.L bit, not the
    /// register identity.
    struct YMMRegister: Equatable {
        var number: UInt8

        var lowBits: UInt8 { number & 0x7 }
        var highBit: UInt8 { (number >> 3) & 0x1 }
    }

    /// AVX vector size selector. `xmm` (128-bit, VEX.L=0) and `ymm`
    /// (256-bit, VEX.L=1) cover the bulk of the AVX/AVX2 surface area.
    enum AVXVectorSize: Equatable {
        case xmm        // 128-bit, VEX.L=0
        case ymm        // 256-bit, VEX.L=1

        var lBit: UInt8 { self == .ymm ? 1 : 0 }

        /// Memory operand width for a `xmm/m128` or `ymm/m256` source.
        var packedMemoryWidth: RegisterWidth { self == .ymm ? .ymmword : .xmmword }
    }

    /// AVX vector operand: an XMM/YMM register (encoded as a 4-bit
    /// register number, vector size dictated by the instruction
    /// context) or a memory reference.
    enum VectorOrMemory: Equatable {
        case register(UInt8)        // 0–15
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
            case .ymmword: return "ymmword"
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
        /// SSE2 imm8-controlled shifts. The mnemonic overlaps with the
        /// variable-shift forms (PSLLW/PSRLW/...) but the encoding is
        /// different: `66 0F 71-73 /n ib`, with the group opcode
        /// selecting the lane width and `/n` selecting the operation.
        case sseShiftImmediate(SSEImmediateShiftKind, target: XMMRegister, immediate: UInt8)
        /// SSE/SSE2 imm8-controlled lane shuffles. Operand shape is
        /// `xmm, xmm/m128, imm8`; the kind picks the mandatory prefix
        /// and second opcode byte. PSHUFD/PSHUFLW/PSHUFHW ride `0F 70`
        /// (with `66`/`F2`/`F3`); SHUFPS/SHUFPD ride `0F C6` (no prefix
        /// or `66`).
        case sseShuffle(SSEShuffleKind, destination: XMMRegister, source: XMMOrMemory, immediate: UInt8)
        /// SSE/SSE2 packed/scalar compare with imm8 predicate. Operand
        /// shape is `xmm, xmm/m128, imm8`; the kind picks the mandatory
        /// prefix while the opcode is fixed at `0F C2`.
        case sseCompare(SSECompareKind, destination: XMMRegister, source: XMMOrMemory, predicate: UInt8)
        /// Half-vector moves: MOVLPS/MOVHPS/MOVLPD/MOVHPD shuttle a
        /// 64-bit lane between an XMM register and memory; MOVHLPS and
        /// MOVLHPS shuttle a lane between two XMM registers. The same
        /// opcode (0F 12 or 0F 16) covers a memory pair and its
        /// register-only sibling, disambiguated by ModR/M.mod.
        case sseHalfMove(SSEHalfMoveKind, destination: XMMOrMemory, source: XMMOrMemory)
        /// PMOVMSKB / MOVMSKPS / MOVMSKPD — extract a per-lane sign-bit
        /// mask from an XMM register into a GPR. Encoded as
        /// `[66] 0F D7/50 /r` with `reg` = GPR and `rm` = XMM.
        case sseMaskExtract(SSEMaskExtractKind, destination: Register, source: XMMRegister)
        /// MASKMOVDQU — selectively store bytes from `source` to memory
        /// at `[RDI]` using the per-byte sign-bit mask from `mask`.
        /// `66 0F F7 /r` with `reg` = source and `rm` = mask.
        case maskMovDqu(source: XMMRegister, mask: XMMRegister)
        /// LDMXCSR / STMXCSR — load or store the SSE MXCSR control
        /// register against an m32 operand. Encoded as `0F AE /2` and
        /// `0F AE /3` respectively.
        case mxcsr(MXCSRKind, memory: MemoryOperand)
        /// MOVNTPS / MOVNTPD / MOVNTDQ — non-temporal store of an XMM
        /// register to memory. Encoded as `[66] 0F 2B/E7 /r` with
        /// `reg` = source XMM, `rm` = m128.
        case sseNonTemporalStore(SSENonTemporalKind, memory: MemoryOperand, source: XMMRegister)
        /// MOVNTI — non-temporal store of a GPR to memory. Encoded as
        /// `0F C3 /r` with the destination memory in `rm` and the
        /// source register in `reg`.
        case movnti(memory: MemoryOperand, source: Register)
        /// PREFETCH hints — single byte-pointer memory operand. All
        /// SSE-era variants ride `0F 18 /n`; PREFETCHW (3DNow!/PRFCHW
        /// extension) rides `0F 0D /1`.
        case prefetch(PrefetchKind, memory: MemoryOperand)
        /// SSE3 packed/scalar instructions sharing a single shape:
        /// `xmm, xmm/m128` (or `xmm/m64` for MOVDDUP). The mandatory
        /// prefix (66/F2/F3) and opcode2 together pick the operation.
        case sse3(SSE3Kind, destination: XMMRegister, source: XMMOrMemory)
        /// SSSE3 `xmm, xmm/m128` operations. All ride `66 0F 38 xx /r`
        /// with the opcode picking the operation. PALIGNR has its own
        /// case because it adds an imm8 lane shift.
        case ssse3(SSSE3Kind, destination: XMMRegister, source: XMMOrMemory)
        /// PALIGNR — `66 0F 3A 0F /r ib`. Concatenates the destination
        /// and source and shifts the result right by the imm8 byte
        /// count, taking the low 16 bytes as the new destination.
        case palignr(destination: XMMRegister, source: XMMOrMemory, immediate: UInt8)
        /// SSE4.1 PMOVSX* / PMOVZX* — sign- or zero-extend a packed
        /// vector by widening each lane. Encoded as `66 0F 38 2x|3x /r`
        /// with the source operand width determined by the kind.
        case ssePackExtend(SSEPackExtendKind, destination: XMMRegister, source: XMMOrMemory)
        /// SSE4.1 `xmm, xmm/m128` operations on the 0F 38 escape:
        /// PMUL/PMIN/PMAX/PACKUSDW/PCMPEQQ/PHMINPOSUW/PTEST.
        case sse41Packed(SSE41PackedKind, destination: XMMRegister, source: XMMOrMemory)
        /// MOVNTDQA — non-temporal aligned dqword load from memory.
        /// `66 0F 38 2A /r` with memory-only `rm` operand.
        case movntdqa(destination: XMMRegister, memory: MemoryOperand)
        /// SSE4.1 imm8 instructions on the 0F 3A escape:
        /// ROUNDPS/PD/SS/SD, BLENDPS/PD, PBLENDW, DPPS/DPPD, MPSADBW.
        case sse41Imm(SSE41ImmediateKind, destination: XMMRegister, source: XMMOrMemory, immediate: UInt8)
        /// PINSR{B,W,D,Q} — insert a GPR or memory lane into an XMM
        /// register, controlled by an imm8 lane index.
        case sseInsertLane(SSEInsertLaneKind, destination: XMMRegister, source: RegisterOrMemory, immediate: UInt8)
        /// PEXTR{B,W,D,Q} — extract a lane from an XMM register into a
        /// GPR or memory operand, controlled by an imm8 lane index.
        case sseExtractLane(SSEExtractLaneKind, destination: RegisterOrMemory, source: XMMRegister, immediate: UInt8)
        /// INSERTPS — insert a single-precision lane (XMM ↔ XMM/m32)
        /// with an imm8 control byte.
        case insertps(destination: XMMRegister, source: XMMOrMemory, immediate: UInt8)
        /// EXTRACTPS — extract one single from an XMM into a GPR or
        /// m32 destination.
        case extractps(destination: RegisterOrMemory, source: XMMRegister, immediate: UInt8)
        /// BLENDVPS / BLENDVPD / PBLENDVB — blend two XMM operands
        /// using the implicit XMM0 mask register.
        case sseBlendv(SSEBlendvKind, destination: XMMRegister, source: XMMOrMemory)
        /// SSE4.2 CRC32 — accumulate a CRC32 (polynomial 11EDC6F41h) on
        /// a byte/word/dword/qword source into a 32- or 64-bit GPR.
        /// Encoded as `F2 [66] [REX] 0F 38 F0|F1 /r`: F0 with a byte
        /// source, F1 otherwise; 0x66 narrows the source to word.
        case crc32(destination: Register, source: RegisterOrMemory)
        /// AVX packed/scalar three-operand FP arithmetic: VADD/VSUB/
        /// VMUL/VDIV PS/PD/SS/SD. The packed forms can be either 128 or
        /// 256 bits (xmm vs ymm); the scalar forms (SS/SD) are
        /// 128-bit only. Encoded with a VEX prefix; the kind picks the
        /// mandatory prefix and 0F-escape, and `size` picks VEX.L.
        case vexArithmetic(VexArithmeticKind, size: AVXVectorSize, destination: UInt8, source1: UInt8, source2: VectorOrMemory)
        /// AVX/AVX2 VEX-encoded packed integer 3-operand instructions
        /// — all ride `VEX.128/256 66 0F xx /r` with `xmm/ymm` operands
        /// and `xmm/m128 (or ymm/m256)` source.
        case vexPackedInteger(VexPackedIntegerKind, size: AVXVectorSize, destination: UInt8, source1: UInt8, source2: VectorOrMemory)
        /// AVX 2-operand FP transforms: VSQRTPS/PD, VRSQRTPS, VRCPPS.
        /// Source is `xmm/ymm/m128/m256`; VEX.vvvv must be all-ones.
        case vexUnary(VexUnaryKind, size: AVXVectorSize, destination: UInt8, source: VectorOrMemory)
        /// VMOVAPS/VMOVAPD/VMOVUPS/VMOVUPD/VMOVDQA/VMOVDQU. The opcode
        /// pair (load/store) is selected by which side is memory.
        case vexMov(VexMovKind, size: AVXVectorSize, destination: VectorOrMemory, source: VectorOrMemory)
        /// AVX/AVX2 imm8-controlled SIMD shifts. The destination goes
        /// into VEX.vvvv (the "non-destructive source" slot), the
        /// source register into ModR/M.rm, and the slash-digit selects
        /// the operation in ModR/M.reg.
        case vexShiftImmediate(VexImmediateShiftKind, size: AVXVectorSize, destination: UInt8, source: UInt8, immediate: UInt8)
        /// VPSHUFD/LW/HW — 2-operand `xmm/ymm, xmm/ymm/m, imm8`
        /// (vvvv reserved).
        case vexShuffleImm(VexShuffleImmKind, size: AVXVectorSize, destination: UInt8, source: VectorOrMemory, immediate: UInt8)
        /// VSHUFPS/PD and VPALIGNR — 3-operand
        /// `xmm/ymm, xmm/ymm, xmm/ymm/m, imm8` (first source in vvvv).
        case vexThreeOpImm(VexThreeOpImmKind, size: AVXVectorSize, destination: UInt8, source1: UInt8, source2: VectorOrMemory, immediate: UInt8)
        /// VMOVMSKPS/PD and VPMOVMSKB — extract a per-lane sign-bit
        /// mask from an XMM/YMM register into a GPR.
        case vexMaskExtract(VexMaskExtractKind, size: AVXVectorSize, destination: Register, source: UInt8)
        /// BMI1 ANDN — `r32/64, r32/64, r/m32/64`. Encoded as
        /// VEX.LZ.0F38 F2 /r with the first source in VEX.vvvv and
        /// the second in ModR/M.rm.
        case bmiAndn(destination: Register, source1: Register, source2: RegisterOrMemory)
        /// BMI1 unary ops on `r32/64, r/m32/64` — BLSI/BLSMSK/BLSR.
        /// All ride VEX.LZ.0F38 F3 with the slash-digit picking the
        /// op; the destination goes into VEX.vvvv.
        case bmiUnary(BMI1UnaryKind, destination: Register, source: RegisterOrMemory)
        /// BMI1 BEXTR and BMI2 BZHI/SARX/SHLX/SHRX — `dst, src1, src2`
        /// where src1 carries the value and src2 the control field
        /// (in VEX.vvvv). All ride VEX.LZ.[pp].0F38 [opcode] /r.
        case bmiShiftLike(BMI2ShiftLikeKind, destination: Register, source1: RegisterOrMemory, source2: Register)
        /// RORX — rotate right by imm8 without affecting flags.
        /// Encoded as VEX.LZ.F2.0F3A F0 /r ib (W picks 32/64).
        case rorx(destination: Register, source: RegisterOrMemory, immediate: UInt8)
        /// BMI2 PDEP/PEXT — parallel deposit/extract. Same operand
        /// layout as ANDN: dst in ModR/M.reg, src1 in VEX.vvvv, src2
        /// in ModR/M.rm. PDEP rides pp=F2, PEXT rides pp=F3.
        case bmi2PextDep(BMI2PextDepKind, destination: Register, source1: Register, source2: RegisterOrMemory)
        /// BMI2 MULX — unsigned multiply without affecting flags. The
        /// implicit second multiplicand is RDX/EDX. Encoded with the
        /// high half destination in ModR/M.reg and the low half in
        /// VEX.vvvv; the source is in ModR/M.rm.
        case mulx(destinationHigh: Register, destinationLow: Register, source: RegisterOrMemory)
        /// ADX — ADCX and ADOX. Two-operand carry chain operations
        /// encoded as `[66|F3] 0F 38 F6 /r`. ADCX feeds the CF chain;
        /// ADOX feeds the OF chain.
        case adx(AdxKind, destination: Register, source: RegisterOrMemory)
        /// VMOVD / VMOVQ — move between an XMM register and a GPR or
        /// memory operand. Encoded as VEX.128.66.0F.W0|W1 6E (load) or
        /// 7E (store). W=1 selects MOVQ over MOVD.
        case vexMovDQ(MovDQKind, direction: MovDQDirection, xmm: XMMRegister, gpr: RegisterOrMemory)
    }

    enum SSEImmediateShiftKind: String, Equatable, CaseIterable {
        // Word / dword / qword logical shifts
        case psrlw, psrld, psrlq
        case psllw, pslld, psllq
        // Word / dword arithmetic shifts (no PSRAQ)
        case psraw, psrad
        // Byte-shift the entire 128-bit register
        case psrldq, pslldq

        /// `66 0F 71/72/73 /n ib` — the opcode picks the element width.
        var opcode2: UInt8 {
            switch self {
            case .psrlw, .psraw, .psllw:                     return 0x71  // word lanes
            case .psrld, .psrad, .pslld:                     return 0x72  // dword lanes
            case .psrlq, .psllq, .psrldq, .pslldq:           return 0x73  // qword + 128-bit byte-shift
            }
        }

        /// `/n` slash-digit in ModR/M.reg.
        var slashDigit: UInt8 {
            switch self {
            case .psrlw, .psrld, .psrlq: return 2
            case .psrldq:                return 3
            case .psraw, .psrad:         return 4
            case .psllw, .pslld, .psllq: return 6
            case .pslldq:                return 7
            }
        }

        static func decode(opcode2: UInt8, slashDigit: UInt8) -> SSEImmediateShiftKind? {
            allCases.first { $0.opcode2 == opcode2 && $0.slashDigit == slashDigit }
        }
    }

    /// SSE/SSE2 imm8-controlled lane shuffles. All ride a two-byte
    /// opcode after the mandatory prefix; the immediate selects the
    /// source lane for each destination lane.
    enum SSEShuffleKind: String, Equatable, CaseIterable {
        case pshufd         // 66 0F 70 /r ib — shuffle 4 dwords
        case pshuflw        // F2 0F 70 /r ib — shuffle low 4 words
        case pshufhw        // F3 0F 70 /r ib — shuffle high 4 words
        case shufps         //    0F C6 /r ib — interleave 2 dst + 2 src singles
        case shufpd         // 66 0F C6 /r ib — pick one of 2 doubles per lane

        /// Mandatory prefix preceding `0F`. Returns nil when there is
        /// none (only SHUFPS).
        var mandatoryPrefix: UInt8? {
            switch self {
            case .pshufd, .shufpd: return 0x66
            case .pshuflw:         return 0xF2
            case .pshufhw:         return 0xF3
            case .shufps:          return nil
            }
        }

        /// The byte that follows `0F`.
        var opcode2: UInt8 {
            switch self {
            case .pshufd, .pshuflw, .pshufhw: return 0x70
            case .shufps, .shufpd:            return 0xC6
            }
        }

        static func decode(mandatoryPrefix: UInt8?, opcode2: UInt8) -> SSEShuffleKind? {
            allCases.first { $0.mandatoryPrefix == mandatoryPrefix && $0.opcode2 == opcode2 }
        }
    }

    /// SSE/SSE2 packed/scalar compare with imm8 predicate
    /// (CMPPS/CMPPD/CMPSS/CMPSD). All ride `[prefix] 0F C2 /r ib` with
    /// the mandatory prefix selecting precision (single/double) and
    /// vector vs scalar.
    enum SSECompareKind: String, Equatable, CaseIterable {
        case cmpps          //    0F C2 /r ib — packed single
        case cmppd          // 66 0F C2 /r ib — packed double
        case cmpss          // F3 0F C2 /r ib — scalar single
        case cmpsd          // F2 0F C2 /r ib — scalar double

        var mandatoryPrefix: UInt8? {
            switch self {
            case .cmpps: return nil
            case .cmppd: return 0x66
            case .cmpss: return 0xF3
            case .cmpsd: return 0xF2
            }
        }

        /// `xmm/m128` for packed; `xmm/m32` or `xmm/m64` for scalar.
        /// We model memory width as xmmword everywhere since the parser
        /// already accepts size-hint-less memory.
        var sourceWidth: RegisterWidth { .xmmword }

        static func decode(mandatoryPrefix: UInt8?) -> SSECompareKind? {
            allCases.first { $0.mandatoryPrefix == mandatoryPrefix }
        }
    }

    /// MOV*PS/MOV*PD half-vector moves and their register-only
    /// siblings (MOVHLPS/MOVLHPS). The load opcode is 0F 12 (low half)
    /// or 0F 16 (high half); the store opcode is one higher (13/17)
    /// and only applies to the memory-form mnemonics.
    enum SSEHalfMoveKind: String, Equatable, CaseIterable {
        case movlps         //    0F 12/13 m64 — low quad load/store
        case movhlps        //    0F 12 reg-only — src.high → dst.low
        case movhps         //    0F 16/17 m64 — high quad load/store
        case movlhps        //    0F 16 reg-only — src.low → dst.high
        case movlpd         // 66 0F 12/13 m64
        case movhpd         // 66 0F 16/17 m64

        var mandatoryPrefix: UInt8? {
            switch self {
            case .movlpd, .movhpd: return 0x66
            default:               return nil
            }
        }

        /// Load opcode (memory → xmm or reg-only form). Store opcode is
        /// one higher.
        var loadOpcode: UInt8 {
            switch self {
            case .movlps, .movhlps, .movlpd: return 0x12
            case .movhps, .movlhps, .movhpd: return 0x16
            }
        }

        var allowsMemory: Bool {
            switch self {
            case .movhlps, .movlhps: return false
            default:                 return true
            }
        }

        var allowsRegister: Bool {
            switch self {
            case .movhlps, .movlhps: return true
            default:                 return false
            }
        }

        /// The partner operand is a 64-bit lane.
        var partnerWidth: RegisterWidth { .qword }
    }

    /// Extract a per-lane sign-bit mask from an XMM register into a
    /// GPR. The width (PD/PS/byte) selects how many bits are written.
    enum SSEMaskExtractKind: String, Equatable, CaseIterable {
        case pmovmskb       // 66 0F D7 — 16 byte-mask bits
        case movmskps       //    0F 50 — 4 single-mask bits
        case movmskpd       // 66 0F 50 — 2 double-mask bits

        var mandatoryPrefix: UInt8? {
            switch self {
            case .pmovmskb, .movmskpd: return 0x66
            case .movmskps:            return nil
            }
        }

        var opcode2: UInt8 {
            switch self {
            case .pmovmskb:           return 0xD7
            case .movmskps, .movmskpd: return 0x50
            }
        }

        static func decode(mandatoryPrefix: UInt8?, opcode2: UInt8) -> SSEMaskExtractKind? {
            allCases.first { $0.mandatoryPrefix == mandatoryPrefix && $0.opcode2 == opcode2 }
        }
    }

    /// LDMXCSR / STMXCSR — both ride `0F AE` with the slash-digit
    /// selecting the direction.
    enum MXCSRKind: String, Equatable, CaseIterable {
        case ldmxcsr        // 0F AE /2 — m32 → MXCSR
        case stmxcsr        // 0F AE /3 — MXCSR → m32

        var slashDigit: UInt8 {
            switch self {
            case .ldmxcsr: return 2
            case .stmxcsr: return 3
            }
        }

        static func decode(slashDigit: UInt8) -> MXCSRKind? {
            allCases.first { $0.slashDigit == slashDigit }
        }
    }

    /// Non-temporal stores from an XMM register to a 128-bit memory
    /// location. All ride a two-byte opcode after the mandatory prefix.
    enum SSENonTemporalKind: String, Equatable, CaseIterable {
        case movntps        //    0F 2B — packed single
        case movntpd        // 66 0F 2B — packed double
        case movntdq        // 66 0F E7 — packed dqword

        var mandatoryPrefix: UInt8? {
            switch self {
            case .movntps: return nil
            case .movntpd, .movntdq: return 0x66
            }
        }

        var opcode2: UInt8 {
            switch self {
            case .movntps, .movntpd: return 0x2B
            case .movntdq:           return 0xE7
            }
        }

        static func decode(mandatoryPrefix: UInt8?, opcode2: UInt8) -> SSENonTemporalKind? {
            allCases.first { $0.mandatoryPrefix == mandatoryPrefix && $0.opcode2 == opcode2 }
        }
    }

    /// PREFETCH hint variants. All take a single byte-pointer memory
    /// operand. The first four ride `0F 18 /n`; PREFETCHW rides
    /// `0F 0D /1`.
    enum PrefetchKind: String, Equatable, CaseIterable {
        case prefetchnta    // 0F 18 /0
        case prefetcht0     // 0F 18 /1
        case prefetcht1     // 0F 18 /2
        case prefetcht2     // 0F 18 /3
        case prefetchw      // 0F 0D /1

        var opcode2: UInt8 {
            switch self {
            case .prefetchw: return 0x0D
            default:         return 0x18
            }
        }

        var slashDigit: UInt8 {
            switch self {
            case .prefetchnta: return 0
            case .prefetcht0:  return 1
            case .prefetcht1:  return 2
            case .prefetcht2:  return 3
            case .prefetchw:   return 1
            }
        }

        static func decode(opcode2: UInt8, slashDigit: UInt8) -> PrefetchKind? {
            allCases.first { $0.opcode2 == opcode2 && $0.slashDigit == slashDigit }
        }
    }

    /// SSE3 `xmm, xmm/m128` instructions. MOVDDUP's source is m64 in
    /// the memory form, which only affects the formatter — the
    /// underlying `/r` encoding is identical.
    enum SSE3Kind: String, Equatable, CaseIterable {
        case addsubps       // F2 0F D0
        case addsubpd       // 66 0F D0
        case haddps         // F2 0F 7C
        case haddpd         // 66 0F 7C
        case hsubps         // F2 0F 7D
        case hsubpd         // 66 0F 7D
        case movshdup       // F3 0F 16 — duplicate odd-indexed singles
        case movsldup       // F3 0F 12 — duplicate even-indexed singles
        case movddup        // F2 0F 12 — duplicate one double into both lanes
        case lddqu          // F2 0F F0 — unaligned dqword load

        var mandatoryPrefix: UInt8 {
            switch self {
            case .addsubpd, .haddpd, .hsubpd:           return 0x66
            case .addsubps, .haddps, .hsubps,
                 .movddup, .lddqu:                       return 0xF2
            case .movshdup, .movsldup:                  return 0xF3
            }
        }

        var opcode2: UInt8 {
            switch self {
            case .addsubps, .addsubpd: return 0xD0
            case .haddps, .haddpd:     return 0x7C
            case .hsubps, .hsubpd:     return 0x7D
            case .movshdup:            return 0x16
            case .movsldup, .movddup:  return 0x12
            case .lddqu:               return 0xF0
            }
        }

        /// MOVDDUP's memory form is m64; the rest are m128.
        var sourceWidth: RegisterWidth {
            self == .movddup ? .qword : .xmmword
        }

        static func decode(mandatoryPrefix: UInt8, opcode2: UInt8) -> SSE3Kind? {
            allCases.first { $0.mandatoryPrefix == mandatoryPrefix && $0.opcode2 == opcode2 }
        }
    }

    /// AVX VEX-encoded 3-operand FP arithmetic. The kind picks the
    /// mandatory prefix (in VEX.pp) and the opcode byte; the size
    /// (xmm/ymm) picks VEX.L.
    enum VexArithmeticKind: String, Equatable, CaseIterable {
        case vaddps         // VEX.128/256 0F 58 — packed singles
        case vaddpd         // VEX.128/256 66 0F 58 — packed doubles
        case vaddss         // VEX.LIG F3 0F 58 — scalar single
        case vaddsd         // VEX.LIG F2 0F 58 — scalar double
        case vsubps         // 0F 5C
        case vsubpd         // 66 0F 5C
        case vsubss         // F3 0F 5C
        case vsubsd         // F2 0F 5C
        case vmulps         // 0F 59
        case vmulpd         // 66 0F 59
        case vmulss         // F3 0F 59
        case vmulsd         // F2 0F 59
        case vdivps         // 0F 5E
        case vdivpd         // 66 0F 5E
        case vdivss         // F3 0F 5E
        case vdivsd         // F2 0F 5E
        case vminps         // 0F 5D
        case vminpd         // 66 0F 5D
        case vminss         // F3 0F 5D
        case vminsd         // F2 0F 5D
        case vmaxps         // 0F 5F
        case vmaxpd         // 66 0F 5F
        case vmaxss         // F3 0F 5F
        case vmaxsd         // F2 0F 5F
        // Scalar reciprocal / sqrt. Three-operand form (vvvv carries the
        // first source); no PD variants for RSQRT/RCP.
        case vsqrtss        // F3 0F 51
        case vsqrtsd        // F2 0F 51
        case vrsqrtss       // F3 0F 52
        case vrcpss         // F3 0F 53
        // Bit-wise logic on packed singles/doubles. No scalar form.
        case vandps         // 0F 54
        case vandpd         // 66 0F 54
        case vandnps        // 0F 55
        case vandnpd        // 66 0F 55
        case vorps          // 0F 56
        case vorpd          // 66 0F 56
        case vxorps         // 0F 57
        case vxorpd         // 66 0F 57
        // SSE3 V-prefixed packed FP
        case vhaddps        // F2 0F 7C
        case vhaddpd        // 66 0F 7C
        case vhsubps        // F2 0F 7D
        case vhsubpd        // 66 0F 7D
        case vaddsubps      // F2 0F D0
        case vaddsubpd      // 66 0F D0

        /// `pp` bits for the VEX prefix: 0=none, 1=66, 2=F3, 3=F2.
        var ppBits: UInt8 {
            switch self {
            case .vaddps, .vsubps, .vmulps, .vdivps,
                 .vminps, .vmaxps, .vandps, .vandnps,
                 .vorps,  .vxorps: return 0b00
            case .vaddpd, .vsubpd, .vmulpd, .vdivpd,
                 .vminpd, .vmaxpd, .vandpd, .vandnpd,
                 .vorpd,  .vxorpd,
                 .vhaddpd, .vhsubpd, .vaddsubpd: return 0b01
            case .vaddss, .vsubss, .vmulss, .vdivss,
                 .vminss, .vmaxss, .vsqrtss, .vrsqrtss,
                 .vrcpss: return 0b10
            case .vaddsd, .vsubsd, .vmulsd, .vdivsd,
                 .vminsd, .vmaxsd, .vsqrtsd,
                 .vhaddps, .vhsubps, .vaddsubps: return 0b11
            }
        }

        /// Single-byte opcode after the VEX prefix.
        var opcode: UInt8 {
            switch self {
            case .vaddps, .vaddpd, .vaddss, .vaddsd: return 0x58
            case .vsubps, .vsubpd, .vsubss, .vsubsd: return 0x5C
            case .vmulps, .vmulpd, .vmulss, .vmulsd: return 0x59
            case .vdivps, .vdivpd, .vdivss, .vdivsd: return 0x5E
            case .vminps, .vminpd, .vminss, .vminsd: return 0x5D
            case .vmaxps, .vmaxpd, .vmaxss, .vmaxsd: return 0x5F
            case .vandps, .vandpd:                    return 0x54
            case .vandnps, .vandnpd:                  return 0x55
            case .vorps,  .vorpd:                     return 0x56
            case .vxorps, .vxorpd:                    return 0x57
            case .vsqrtss, .vsqrtsd:                  return 0x51
            case .vrsqrtss:                            return 0x52
            case .vrcpss:                              return 0x53
            case .vhaddps, .vhaddpd:                  return 0x7C
            case .vhsubps, .vhsubpd:                  return 0x7D
            case .vaddsubps, .vaddsubpd:              return 0xD0
            }
        }

        /// True when only the 128-bit form is defined (scalar SS/SD
        /// variants — VEX.L is ignored, but we still emit L=0).
        var isScalar: Bool {
            switch self {
            case .vaddss, .vaddsd, .vsubss, .vsubsd,
                 .vmulss, .vmulsd, .vdivss, .vdivsd,
                 .vminss, .vminsd, .vmaxss, .vmaxsd,
                 .vsqrtss, .vsqrtsd, .vrsqrtss, .vrcpss: return true
            default:                                      return false
            }
        }

        /// Memory operand width for the third operand: m128 / m256 for
        /// packed; m32 for SS; m64 for SD.
        func memoryWidth(size: AVXVectorSize) -> RegisterWidth {
            switch self {
            case .vaddss, .vsubss, .vmulss, .vdivss,
                 .vminss, .vmaxss, .vsqrtss, .vrsqrtss, .vrcpss: return .dword
            case .vaddsd, .vsubsd, .vmulsd, .vdivsd,
                 .vminsd, .vmaxsd, .vsqrtsd:               return .qword
            default:               return size.packedMemoryWidth
            }
        }

        static func decode(ppBits: UInt8, opcode: UInt8) -> VexArithmeticKind? {
            allCases.first { $0.ppBits == ppBits && $0.opcode == opcode }
        }
    }

    /// AVX/AVX2 VEX-encoded packed integer operations. All ride
    /// `VEX.128/256 66 0F xx /r` with a single-byte opcode — pp is
    /// fixed at 01 and the escape is 0F.
    enum VexPackedIntegerKind: String, Equatable, CaseIterable {
        // Unsaturated add by lane width
        case vpaddb         // 66 0F FC
        case vpaddw         // 66 0F FD
        case vpaddd         // 66 0F FE
        case vpaddq         // 66 0F D4
        // Unsaturated sub by lane width
        case vpsubb         // 66 0F F8
        case vpsubw         // 66 0F F9
        case vpsubd         // 66 0F FA
        case vpsubq         // 66 0F FB
        // Bit-wise logic
        case vpand          // 66 0F DB
        case vpandn         // 66 0F DF
        case vpor           // 66 0F EB
        case vpxor          // 66 0F EF
        // Saturating add / sub
        case vpaddsb        // 66 0F EC
        case vpaddsw        // 66 0F ED
        case vpaddusb       // 66 0F DC
        case vpaddusw       // 66 0F DD
        case vpsubsb        // 66 0F E8
        case vpsubsw        // 66 0F E9
        case vpsubusb       // 66 0F D8
        case vpsubusw       // 66 0F D9
        // Compare (equal / greater-than) by lane width
        case vpcmpeqb       // 66 0F 74
        case vpcmpeqw       // 66 0F 75
        case vpcmpeqd       // 66 0F 76
        case vpcmpgtb       // 66 0F 64
        case vpcmpgtw       // 66 0F 65
        case vpcmpgtd       // 66 0F 66
        // Multiplies and multiply-add
        case vpmullw        // 66 0F D5
        case vpmulhw        // 66 0F E5
        case vpmulhuw       // 66 0F E4
        case vpmuludq       // 66 0F F4
        case vpmaddwd       // 66 0F F5
        // Min / max
        case vpminub        // 66 0F DA
        case vpminsw        // 66 0F EA
        case vpmaxub        // 66 0F DE
        case vpmaxsw        // 66 0F EE
        // Average and sum-of-absolute-differences
        case vpavgb         // 66 0F E0
        case vpavgw         // 66 0F E3
        case vpsadbw        // 66 0F F6
        // Interleave lanes
        case vpunpcklbw     // 66 0F 60
        case vpunpcklwd     // 66 0F 61
        case vpunpckldq     // 66 0F 62
        case vpunpcklqdq    // 66 0F 6C
        case vpunpckhbw     // 66 0F 68
        case vpunpckhwd     // 66 0F 69
        case vpunpckhdq     // 66 0F 6A
        case vpunpckhqdq    // 66 0F 6D
        // Pack with saturation
        case vpacksswb      // 66 0F 63
        case vpackssdw      // 66 0F 6B
        case vpackuswb      // 66 0F 67
        // Variable shifts (count from xmm/m128)
        case vpsrlw         // 66 0F D1
        case vpsrld         // 66 0F D2
        case vpsrlq         // 66 0F D3
        case vpsllw         // 66 0F F1
        case vpslld         // 66 0F F2
        case vpsllq         // 66 0F F3
        case vpsraw         // 66 0F E1
        case vpsrad         // 66 0F E2

        var opcode: UInt8 {
            switch self {
            case .vpaddb:    return 0xFC
            case .vpaddw:    return 0xFD
            case .vpaddd:    return 0xFE
            case .vpaddq:    return 0xD4
            case .vpsubb:    return 0xF8
            case .vpsubw:    return 0xF9
            case .vpsubd:    return 0xFA
            case .vpsubq:    return 0xFB
            case .vpand:     return 0xDB
            case .vpandn:    return 0xDF
            case .vpor:      return 0xEB
            case .vpxor:     return 0xEF
            case .vpaddsb:   return 0xEC
            case .vpaddsw:   return 0xED
            case .vpaddusb:  return 0xDC
            case .vpaddusw:  return 0xDD
            case .vpsubsb:   return 0xE8
            case .vpsubsw:   return 0xE9
            case .vpsubusb:  return 0xD8
            case .vpsubusw:  return 0xD9
            case .vpcmpeqb:  return 0x74
            case .vpcmpeqw:  return 0x75
            case .vpcmpeqd:  return 0x76
            case .vpcmpgtb:  return 0x64
            case .vpcmpgtw:  return 0x65
            case .vpcmpgtd:  return 0x66
            case .vpmullw:   return 0xD5
            case .vpmulhw:   return 0xE5
            case .vpmulhuw:  return 0xE4
            case .vpmuludq:  return 0xF4
            case .vpmaddwd:  return 0xF5
            case .vpminub:   return 0xDA
            case .vpminsw:   return 0xEA
            case .vpmaxub:   return 0xDE
            case .vpmaxsw:   return 0xEE
            case .vpavgb:    return 0xE0
            case .vpavgw:    return 0xE3
            case .vpsadbw:   return 0xF6
            case .vpunpcklbw:  return 0x60
            case .vpunpcklwd:  return 0x61
            case .vpunpckldq:  return 0x62
            case .vpunpcklqdq: return 0x6C
            case .vpunpckhbw:  return 0x68
            case .vpunpckhwd:  return 0x69
            case .vpunpckhdq:  return 0x6A
            case .vpunpckhqdq: return 0x6D
            case .vpacksswb:   return 0x63
            case .vpackssdw:   return 0x6B
            case .vpackuswb:   return 0x67
            case .vpsrlw:      return 0xD1
            case .vpsrld:      return 0xD2
            case .vpsrlq:      return 0xD3
            case .vpsllw:      return 0xF1
            case .vpslld:      return 0xF2
            case .vpsllq:      return 0xF3
            case .vpsraw:      return 0xE1
            case .vpsrad:      return 0xE2
            }
        }

        static func decode(opcode: UInt8) -> VexPackedIntegerKind? {
            allCases.first { $0.opcode == opcode }
        }
    }

    /// AVX 2-operand packed FP transforms (no vvvv source).
    enum VexUnaryKind: String, Equatable, CaseIterable {
        case vsqrtps        //    0F 51 — packed single
        case vsqrtpd        // 66 0F 51 — packed double
        case vrsqrtps       //    0F 52 — packed single only
        case vrcpps         //    0F 53 — packed single only
        // SSE3 V-prefixed 2-op moves / loads
        case vmovsldup      // F3 0F 12 — duplicate even-indexed singles
        case vmovshdup      // F3 0F 16 — duplicate odd-indexed singles
        case vmovddup       // F2 0F 12 — duplicate one double per lane
        case vlddqu         // F2 0F F0 — unaligned dqword load

        var ppBits: UInt8 {
            switch self {
            case .vsqrtps, .vrsqrtps, .vrcpps: return 0b00
            case .vsqrtpd:                       return 0b01
            case .vmovsldup, .vmovshdup:         return 0b10
            case .vmovddup, .vlddqu:             return 0b11
            }
        }

        var opcode: UInt8 {
            switch self {
            case .vsqrtps, .vsqrtpd: return 0x51
            case .vrsqrtps:           return 0x52
            case .vrcpps:             return 0x53
            case .vmovsldup, .vmovddup: return 0x12
            case .vmovshdup:           return 0x16
            case .vlddqu:              return 0xF0
            }
        }

        /// VMOVDDUP narrows the memory operand to m64 in the 128-bit
        /// form. The 256-bit form uses m256.
        func memoryWidth(size: AVXVectorSize) -> RegisterWidth {
            if self == .vmovddup && size == .xmm { return .qword }
            return size.packedMemoryWidth
        }

        static func decode(ppBits: UInt8, opcode: UInt8) -> VexUnaryKind? {
            allCases.first { $0.ppBits == ppBits && $0.opcode == opcode }
        }
    }

    /// VEX move family. Each kind ships a load opcode (xmm/ymm <- src)
    /// and a store opcode (load + 1, dst <- xmm/ymm).
    enum VexMovKind: String, Equatable, CaseIterable {
        case vmovups        //    0F 10 / 11 — unaligned packed single
        case vmovupd        // 66 0F 10 / 11 — unaligned packed double
        case vmovaps        //    0F 28 / 29 — aligned packed single
        case vmovapd        // 66 0F 28 / 29 — aligned packed double
        case vmovdqu        // F3 0F 6F / 7F — unaligned packed dqword
        case vmovdqa        // 66 0F 6F / 7F — aligned packed dqword

        var ppBits: UInt8 {
            switch self {
            case .vmovups, .vmovaps: return 0b00
            case .vmovupd, .vmovapd, .vmovdqa: return 0b01
            case .vmovdqu: return 0b10
            }
        }

        var loadOpcode: UInt8 {
            switch self {
            case .vmovups, .vmovupd: return 0x10
            case .vmovaps, .vmovapd: return 0x28
            case .vmovdqu, .vmovdqa: return 0x6F
            }
        }

        /// VMOVAPS/UPS/APD/UPD use load+1 for the store opcode; VMOVDQA
        /// and VMOVDQU jump to 0x7F (load was 0x6F).
        var storeOpcode: UInt8 {
            switch self {
            case .vmovdqu, .vmovdqa: return 0x7F
            default:                 return loadOpcode + 1
            }
        }

        static func decode(ppBits: UInt8, opcode: UInt8) -> (kind: VexMovKind, isStore: Bool)? {
            for kind in allCases where kind.ppBits == ppBits {
                if kind.loadOpcode == opcode  { return (kind, false) }
                if kind.storeOpcode == opcode { return (kind, true) }
            }
            return nil
        }
    }

    /// VEX imm8-controlled SIMD shifts. Same opcode/slash-digit
    /// mapping as the SSE2 versions; just the encoding form differs.
    enum VexImmediateShiftKind: String, Equatable, CaseIterable {
        case vpsrlw, vpsrld, vpsrlq
        case vpsllw, vpslld, vpsllq
        case vpsraw, vpsrad
        case vpsrldq, vpslldq

        var opcode: UInt8 {
            switch self {
            case .vpsrlw, .vpsraw, .vpsllw:                return 0x71
            case .vpsrld, .vpsrad, .vpslld:                return 0x72
            case .vpsrlq, .vpsllq, .vpsrldq, .vpslldq:     return 0x73
            }
        }

        var slashDigit: UInt8 {
            switch self {
            case .vpsrlw, .vpsrld, .vpsrlq: return 2
            case .vpsrldq:                  return 3
            case .vpsraw, .vpsrad:          return 4
            case .vpsllw, .vpslld, .vpsllq: return 6
            case .vpslldq:                  return 7
            }
        }

        static func decode(opcode: UInt8, slashDigit: UInt8) -> VexImmediateShiftKind? {
            allCases.first { $0.opcode == opcode && $0.slashDigit == slashDigit }
        }
    }

    /// VPSHUFD/LW/HW — 2-operand imm8 shuffles. All ride `[prefix] 0F
    /// 70 /r ib` with the mandatory prefix selecting the kind.
    enum VexShuffleImmKind: String, Equatable, CaseIterable {
        case vpshufd    // 66 0F 70
        case vpshuflw   // F2 0F 70
        case vpshufhw   // F3 0F 70

        var ppBits: UInt8 {
            switch self {
            case .vpshufd:  return 0b01
            case .vpshuflw: return 0b11
            case .vpshufhw: return 0b10
            }
        }

        static func decode(ppBits: UInt8) -> VexShuffleImmKind? {
            allCases.first { $0.ppBits == ppBits }
        }
    }

    /// VSHUFPS/PD and VPALIGNR — 3-operand imm8 instructions.
    /// VSHUFPS/PD ride `0F C6`; VPALIGNR rides `66 0F 3A 0F`. VCMP*
    /// ride `[prefix] 0F C2` with imm8 picking the predicate.
    enum VexThreeOpImmKind: String, Equatable, CaseIterable {
        case vshufps    //    0F   C6
        case vshufpd    // 66 0F   C6
        case vpalignr   // 66 0F3A 0F
        case vcmpps     //    0F   C2
        case vcmppd     // 66 0F   C2
        case vcmpss     // F3 0F   C2
        case vcmpsd     // F2 0F   C2

        var ppBits: UInt8 {
            switch self {
            case .vshufps, .vcmpps:                 return 0b00
            case .vshufpd, .vpalignr, .vcmppd:      return 0b01
            case .vcmpss:                           return 0b10
            case .vcmpsd:                           return 0b11
            }
        }

        var escape: UInt8 {
            switch self {
            case .vshufps, .vshufpd,
                 .vcmpps, .vcmppd, .vcmpss, .vcmpsd: return 0b00001     // 0F
            case .vpalignr:                            return 0b00011    // 0F 3A
            }
        }

        var opcode: UInt8 {
            switch self {
            case .vshufps, .vshufpd: return 0xC6
            case .vpalignr:           return 0x0F
            case .vcmpps, .vcmppd, .vcmpss, .vcmpsd: return 0xC2
            }
        }

        /// VCMPSS reads a 32-bit memory source; VCMPSD reads 64-bit;
        /// the rest take the size-driven packed width.
        func memoryWidth(size: AVXVectorSize) -> RegisterWidth {
            switch self {
            case .vcmpss: return .dword
            case .vcmpsd: return .qword
            default:      return size.packedMemoryWidth
            }
        }

        var isScalar: Bool {
            self == .vcmpss || self == .vcmpsd
        }

        static func decode(escape: UInt8, ppBits: UInt8, opcode: UInt8) -> VexThreeOpImmKind? {
            allCases.first { $0.escape == escape && $0.ppBits == ppBits && $0.opcode == opcode }
        }
    }

    /// VEX-encoded mask extract — GPR <- per-lane sign-bit mask.
    enum VexMaskExtractKind: String, Equatable, CaseIterable {
        case vmovmskps      //    0F 50 — packed singles
        case vmovmskpd      // 66 0F 50 — packed doubles
        case vpmovmskb      // 66 0F D7 — bytes

        var ppBits: UInt8 {
            switch self {
            case .vmovmskps: return 0b00
            case .vmovmskpd, .vpmovmskb: return 0b01
            }
        }

        var opcode: UInt8 {
            switch self {
            case .vmovmskps, .vmovmskpd: return 0x50
            case .vpmovmskb:             return 0xD7
            }
        }

        static func decode(ppBits: UInt8, opcode: UInt8) -> VexMaskExtractKind? {
            allCases.first { $0.ppBits == ppBits && $0.opcode == opcode }
        }
    }

    /// BMI1 unary operations: dst (in VEX.vvvv) <- f(src in ModR/M.rm).
    /// All ride VEX.LZ.0F38 F3 with `/n` picking the operation.
    enum BMI1UnaryKind: String, Equatable, CaseIterable {
        case blsr           // /1 — reset lowest set bit
        case blsmsk         // /2 — mask up to lowest set bit
        case blsi           // /3 — isolate lowest set bit

        var slashDigit: UInt8 {
            switch self {
            case .blsr:   return 1
            case .blsmsk: return 2
            case .blsi:   return 3
            }
        }

        static func decode(slashDigit: UInt8) -> BMI1UnaryKind? {
            allCases.first { $0.slashDigit == slashDigit }
        }
    }

    /// BMI1 BEXTR + BMI2 BZHI/SARX/SHLX/SHRX. All ride
    /// `VEX.LZ.[pp].0F38.[W] [opcode] /r` with dst in ModR/M.reg, the
    /// shifted value in ModR/M.rm, and the control in VEX.vvvv.
    enum BMI2ShiftLikeKind: String, Equatable, CaseIterable {
        case bextr          // pp=0,  opcode F7  (BMI1)
        case bzhi           // pp=0,  opcode F5
        case shlx           // pp=66, opcode F7
        case sarx           // pp=F3, opcode F7
        case shrx           // pp=F2, opcode F7

        var ppBits: UInt8 {
            switch self {
            case .bextr, .bzhi: return 0b00
            case .shlx:         return 0b01
            case .sarx:         return 0b10
            case .shrx:         return 0b11
            }
        }

        var opcode: UInt8 {
            switch self {
            case .bzhi: return 0xF5
            default:    return 0xF7
            }
        }

        static func decode(ppBits: UInt8, opcode: UInt8) -> BMI2ShiftLikeKind? {
            allCases.first { $0.ppBits == ppBits && $0.opcode == opcode }
        }
    }

    /// BMI2 parallel-bit deposit/extract. Both ride VEX.LZ.[pp].0F38
    /// F5 /r with the same operand layout as ANDN.
    enum BMI2PextDepKind: String, Equatable, CaseIterable {
        case pdep       // pp = F2
        case pext       // pp = F3

        var ppBits: UInt8 {
            switch self {
            case .pdep: return 0b11
            case .pext: return 0b10
            }
        }

        static func decode(ppBits: UInt8) -> BMI2PextDepKind? {
            allCases.first { $0.ppBits == ppBits }
        }
    }

    /// ADCX and ADOX — share opcode 0F 38 F6 and differ in the
    /// mandatory prefix (66 for ADCX feeding CF, F3 for ADOX feeding
    /// OF).
    enum AdxKind: String, Equatable, CaseIterable {
        case adcx           // 66 0F 38 F6 — feeds the CF chain
        case adox           // F3 0F 38 F6 — feeds the OF chain

        var prefix: UInt8 {
            switch self {
            case .adcx: return 0x66
            case .adox: return 0xF3
            }
        }
    }

    /// SSSE3 `xmm, xmm/m128` instructions. All ride `66 0F 38 xx /r`.
    enum SSSE3Kind: String, Equatable, CaseIterable {
        // Byte-shuffle controlled by a byte mask in the source
        case pshufb         // 66 0F 38 00 — shuffle bytes
        // Horizontal add/sub
        case phaddw         // 66 0F 38 01
        case phaddd         // 66 0F 38 02
        case phaddsw        // 66 0F 38 03 — saturating
        case pmaddubsw      // 66 0F 38 04 — unsigned×signed, saturating
        case phsubw         // 66 0F 38 05
        case phsubd         // 66 0F 38 06
        case phsubsw        // 66 0F 38 07
        // Conditional sign-flip
        case psignb         // 66 0F 38 08
        case psignw         // 66 0F 38 09
        case psignd         // 66 0F 38 0A
        // Multiply high with rounding and scaling
        case pmulhrsw       // 66 0F 38 0B
        // Absolute value
        case pabsb          // 66 0F 38 1C
        case pabsw          // 66 0F 38 1D
        case pabsd          // 66 0F 38 1E

        var opcode3: UInt8 {
            switch self {
            case .pshufb:     return 0x00
            case .phaddw:     return 0x01
            case .phaddd:     return 0x02
            case .phaddsw:    return 0x03
            case .pmaddubsw:  return 0x04
            case .phsubw:     return 0x05
            case .phsubd:     return 0x06
            case .phsubsw:    return 0x07
            case .psignb:     return 0x08
            case .psignw:     return 0x09
            case .psignd:     return 0x0A
            case .pmulhrsw:   return 0x0B
            case .pabsb:      return 0x1C
            case .pabsw:      return 0x1D
            case .pabsd:      return 0x1E
            }
        }

        static func decode(opcode3: UInt8) -> SSSE3Kind? {
            allCases.first { $0.opcode3 == opcode3 }
        }
    }

    /// SSE4.1 widening pack moves. `66 0F 38 2x` are sign-extending,
    /// `3x` are zero-extending; the low nibble selects the lane widen.
    enum SSEPackExtendKind: String, Equatable, CaseIterable {
        // Sign-extending forms
        case pmovsxbw       // 66 0F 38 20 — m64 → 8 words
        case pmovsxbd       // 66 0F 38 21 — m32 → 4 dwords
        case pmovsxbq       // 66 0F 38 22 — m16 → 2 qwords
        case pmovsxwd       // 66 0F 38 23 — m64 → 4 dwords
        case pmovsxwq       // 66 0F 38 24 — m32 → 2 qwords
        case pmovsxdq       // 66 0F 38 25 — m64 → 2 qwords
        // Zero-extending forms
        case pmovzxbw       // 66 0F 38 30
        case pmovzxbd       // 66 0F 38 31
        case pmovzxbq       // 66 0F 38 32
        case pmovzxwd       // 66 0F 38 33
        case pmovzxwq       // 66 0F 38 34
        case pmovzxdq       // 66 0F 38 35

        var opcode3: UInt8 {
            switch self {
            case .pmovsxbw: return 0x20
            case .pmovsxbd: return 0x21
            case .pmovsxbq: return 0x22
            case .pmovsxwd: return 0x23
            case .pmovsxwq: return 0x24
            case .pmovsxdq: return 0x25
            case .pmovzxbw: return 0x30
            case .pmovzxbd: return 0x31
            case .pmovzxbq: return 0x32
            case .pmovzxwd: return 0x33
            case .pmovzxwq: return 0x34
            case .pmovzxdq: return 0x35
            }
        }

        /// Source operand width when in memory form. The packed XMM
        /// register source always provides the full 16 bytes; only the
        /// low N bytes are read.
        var sourceWidth: RegisterWidth {
            switch self {
            case .pmovsxbw, .pmovsxwd, .pmovsxdq,
                 .pmovzxbw, .pmovzxwd, .pmovzxdq: return .qword
            case .pmovsxbd, .pmovsxwq,
                 .pmovzxbd, .pmovzxwq:            return .dword
            case .pmovsxbq, .pmovzxbq:            return .word
            }
        }

        static func decode(opcode3: UInt8) -> SSEPackExtendKind? {
            allCases.first { $0.opcode3 == opcode3 }
        }
    }

    /// SSE4.1 packed-integer operations on the 0F 38 escape that share
    /// the `xmm, xmm/m128` shape.
    enum SSE41PackedKind: String, Equatable, CaseIterable {
        case ptest          // 66 0F 38 17 — set EFLAGS from AND / ANDN
        case pmuldq         // 66 0F 38 28 — packed signed dword × dword → qword
        case pcmpeqq        // 66 0F 38 29 — packed compare equal qword
        case packusdw       // 66 0F 38 2B — pack with unsigned saturation (d→w)
        case pminsb         // 66 0F 38 38
        case pminsd         // 66 0F 38 39
        case pminuw         // 66 0F 38 3A
        case pminud         // 66 0F 38 3B
        case pmaxsb         // 66 0F 38 3C
        case pmaxsd         // 66 0F 38 3D
        case pmaxuw         // 66 0F 38 3E
        case pmaxud         // 66 0F 38 3F
        case pmulld         // 66 0F 38 40 — packed mul low dword
        case phminposuw     // 66 0F 38 41 — packed horizontal min unsigned word
        case pcmpgtq        // 66 0F 38 37 — SSE4.2 packed compare gt qword
        // AES-NI 0F 38 family
        case aesimc         // 66 0F 38 DB — AES inverse mix-columns
        case aesenc         // 66 0F 38 DC — AES encrypt round
        case aesenclast     // 66 0F 38 DD — AES encrypt last round
        case aesdec         // 66 0F 38 DE — AES decrypt round
        case aesdeclast     // 66 0F 38 DF — AES decrypt last round

        var opcode3: UInt8 {
            switch self {
            case .ptest:       return 0x17
            case .pmuldq:      return 0x28
            case .pcmpeqq:     return 0x29
            case .packusdw:    return 0x2B
            case .pcmpgtq:     return 0x37
            case .pminsb:      return 0x38
            case .pminsd:      return 0x39
            case .pminuw:      return 0x3A
            case .pminud:      return 0x3B
            case .pmaxsb:      return 0x3C
            case .pmaxsd:      return 0x3D
            case .pmaxuw:      return 0x3E
            case .pmaxud:      return 0x3F
            case .pmulld:      return 0x40
            case .phminposuw:  return 0x41
            case .aesimc:      return 0xDB
            case .aesenc:      return 0xDC
            case .aesenclast:  return 0xDD
            case .aesdec:      return 0xDE
            case .aesdeclast:  return 0xDF
            }
        }

        static func decode(opcode3: UInt8) -> SSE41PackedKind? {
            allCases.first { $0.opcode3 == opcode3 }
        }
    }

    /// SSE4.1 imm8 operations on the 0F 3A escape. ROUNDSS/ROUNDSD
    /// narrow the memory source to m32/m64; everything else is m128.
    enum SSE41ImmediateKind: String, Equatable, CaseIterable {
        case roundps        // 66 0F 3A 08 — packed single round
        case roundpd        // 66 0F 3A 09 — packed double round
        case roundss        // 66 0F 3A 0A — scalar single round (m32 src)
        case roundsd        // 66 0F 3A 0B — scalar double round (m64 src)
        case blendps        // 66 0F 3A 0C — blend singles
        case blendpd        // 66 0F 3A 0D — blend doubles
        case pblendw        // 66 0F 3A 0E — blend words
        case dpps           // 66 0F 3A 40 — dot product singles
        case dppd           // 66 0F 3A 41 — dot product doubles
        case mpsadbw        // 66 0F 3A 42 — multiple packed SAD bytes
        // SSE4.2 string comparison family — same shape, distinct opcodes.
        case pcmpestrm      // 66 0F 3A 60 — explicit length, mask result
        case pcmpestri      // 66 0F 3A 61 — explicit length, index result
        case pcmpistrm      // 66 0F 3A 62 — implicit length, mask result
        case pcmpistri      // 66 0F 3A 63 — implicit length, index result
        // PCLMULQDQ + AES-NI key-schedule helper
        case pclmulqdq          // 66 0F 3A 44
        case aeskeygenassist    // 66 0F 3A DF

        var opcode3: UInt8 {
            switch self {
            case .roundps: return 0x08
            case .roundpd: return 0x09
            case .roundss: return 0x0A
            case .roundsd: return 0x0B
            case .blendps: return 0x0C
            case .blendpd: return 0x0D
            case .pblendw: return 0x0E
            case .dpps:    return 0x40
            case .dppd:    return 0x41
            case .mpsadbw: return 0x42
            case .pcmpestrm: return 0x60
            case .pcmpestri: return 0x61
            case .pcmpistrm: return 0x62
            case .pcmpistri: return 0x63
            case .pclmulqdq:       return 0x44
            case .aeskeygenassist: return 0xDF
            }
        }

        var sourceWidth: RegisterWidth {
            switch self {
            case .roundss: return .dword
            case .roundsd: return .qword
            default:       return .xmmword
            }
        }

        static func decode(opcode3: UInt8) -> SSE41ImmediateKind? {
            allCases.first { $0.opcode3 == opcode3 }
        }
    }

    /// PINSR family. PINSRW uses the 66 0F C4 two-byte form; the
    /// others ride 66 0F 3A 20|22 ib. PINSRQ shares opcode 22 with
    /// PINSRD and is distinguished by REX.W.
    enum SSEInsertLaneKind: String, Equatable, CaseIterable {
        case pinsrb         // 66 0F 3A 20 — r32/m8  → byte lane
        case pinsrw         // 66 0F C4    — r32/m16 → word lane
        case pinsrd         // 66 0F 3A 22 — r/m32   → dword lane
        case pinsrq         // 66 REX.W 0F 3A 22 — r/m64 → qword lane

        /// Width of the GPR source. PINSRB/PINSRW take r32 (low bits
        /// used); PINSRD/PINSRQ take the natural width.
        var gprWidth: RegisterWidth {
            switch self {
            case .pinsrb, .pinsrw, .pinsrd: return .dword
            case .pinsrq:                   return .qword
            }
        }

        /// Width of the memory operand.
        var memoryWidth: RegisterWidth {
            switch self {
            case .pinsrb: return .byte
            case .pinsrw: return .word
            case .pinsrd: return .dword
            case .pinsrq: return .qword
            }
        }
    }

    /// PEXTR family. PEXTRW is encoded here using the SSE4.1 form
    /// (66 0F 3A 15 /r ib) which accepts either a register or memory
    /// destination; the SSE2 register-only form (66 0F C5) is not
    /// emitted, but the decoder accepts it.
    enum SSEExtractLaneKind: String, Equatable, CaseIterable {
        case pextrb         // 66 0F 3A 14 — byte  lane → r32/m8
        case pextrw         // 66 0F 3A 15 — word  lane → r32/m16 (SSE4.1 form)
        case pextrd         // 66 0F 3A 16 — dword lane → r/m32
        case pextrq         // 66 REX.W 0F 3A 16 — qword lane → r/m64

        var gprWidth: RegisterWidth {
            switch self {
            case .pextrb, .pextrw, .pextrd: return .dword
            case .pextrq:                   return .qword
            }
        }

        var memoryWidth: RegisterWidth {
            switch self {
            case .pextrb: return .byte
            case .pextrw: return .word
            case .pextrd: return .dword
            case .pextrq: return .qword
            }
        }
    }

    /// BLENDV* — implicit XMM0 mask. The two-operand mnemonic in
    /// the source still expects three operands at the assembler level
    /// (the third must be `xmm0`); the encoding doesn't carry it.
    enum SSEBlendvKind: String, Equatable, CaseIterable {
        case blendvps       // 66 0F 38 14
        case blendvpd       // 66 0F 38 15
        case pblendvb       // 66 0F 38 10

        var opcode3: UInt8 {
            switch self {
            case .blendvps: return 0x14
            case .blendvpd: return 0x15
            case .pblendvb: return 0x10
            }
        }

        static func decode(opcode3: UInt8) -> SSEBlendvKind? {
            allCases.first { $0.opcode3 == opcode3 }
        }
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
