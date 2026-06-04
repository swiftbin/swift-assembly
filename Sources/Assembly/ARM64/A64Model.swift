import Foundation

internal enum A64 {
    enum RegisterKind: Equatable {
        case general
        case zero
        case stackPointer
    }

    struct Register: Equatable {
        var number: UInt32
        var width: Int
        var kind: RegisterKind

        var encodedNumber: UInt32 { number & 0x1f }
        var is64Bit: Bool { width == 64 }
    }

    struct FPRegister: Equatable {
        var number: UInt32
        var width: Int

        var encodedNumber: UInt32 { number & 0x1f }

        /// The `ptype`/`type` field used by scalar floating-point encodings.
        var ptype: UInt32? {
            switch width {
            case 32: return 0b00
            case 64: return 0b01
            case 16: return 0b11
            default: return nil
            }
        }
    }

    enum VectorArrangement: String, Equatable {
        case b8 = "8b"
        case b16 = "16b"
        case h2 = "2h"
        case h4 = "4h"
        case h8 = "8h"
        case s2 = "2s"
        case s4 = "4s"
        case d1 = "1d"
        case d2 = "2d"
        /// A single 128-bit (quadword) element, used only by the `PMULL`/`PMULL2`
        /// 64→128 polynomial multiply. `Q` is supplied by the `1d`/`2d` source, so
        /// this destination arrangement reports `q = 0`.
        case q1 = "1q"

        /// The `size` field (element size code: B=0, H=1, S=2, D=3).
        var elementSize: UInt32 {
            switch self {
            case .b8, .b16: return 0b00
            case .h2, .h4, .h8: return 0b01
            case .s2, .s4: return 0b10
            case .d1, .d2, .q1: return 0b11
            }
        }

        /// The element width in bits.
        var elementWidth: Int {
            switch self {
            case .b8, .b16: return 8
            case .h2, .h4, .h8: return 16
            case .s2, .s4: return 32
            case .d1, .d2: return 64
            case .q1: return 128
            }
        }

        /// The `Q` bit (1 for 128-bit / fully populated arrangements).
        var q: UInt32 {
            switch self {
            case .b16, .h8, .s4, .d2: return 1
            case .b8, .h2, .h4, .s2, .d1, .q1: return 0
            }
        }
    }

    struct VectorRegister: Equatable {
        var number: UInt32
        var arrangement: VectorArrangement

        var encodedNumber: UInt32 { number & 0x1f }
    }

    /// A brace-delimited list of consecutively numbered vector registers sharing a single
    /// arrangement, e.g. `{v0.16b, v1.16b}` used by the structured load/store instructions.
    struct VectorRegisterList: Equatable {
        var firstNumber: UInt32
        var count: Int
        var arrangement: VectorArrangement

        var encodedNumber: UInt32 { firstNumber & 0x1f }
    }

    /// A brace-delimited list of consecutively numbered vector registers sharing an element
    /// width, together with a single lane index, e.g. `{v0.s, v1.s}[1]` used by the
    /// load/store single-structure instructions.
    struct VectorLaneList: Equatable {
        var firstNumber: UInt32
        var count: Int
        var width: VectorElementWidth
        var index: Int

        var encodedNumber: UInt32 { firstNumber & 0x1f }
    }

    /// Addressing forms used by the Advanced SIMD structured load/store instructions.
    enum VectorMemoryOperand: Equatable {
        case base(Register)                         // [Xn]
        case postImmediate(Register)                // [Xn], #imm  (imm is implicit = bytes transferred)
        case postRegister(Register, offset: Register) // [Xn], Xm
    }

    enum Condition: UInt32 {
        case eq = 0x0, ne = 0x1, hs = 0x2, lo = 0x3
        case mi = 0x4, pl = 0x5, vs = 0x6, vc = 0x7
        case hi = 0x8, ls = 0x9, ge = 0xa, lt = 0xb
        case gt = 0xc, le = 0xd, al = 0xe, nv = 0xf
    }

    enum ShiftKind: UInt32 {
        case lsl = 0
        case lsr = 1
        case asr = 2
        case ror = 3
    }

    enum ExtendKind: UInt32 {
        case uxtb = 0
        case uxth = 1
        case uxtw = 2
        case uxtx = 3
        case sxtb = 4
        case sxth = 5
        case sxtw = 6
        case sxtx = 7
    }

    enum MemoryOperand: Equatable {
        case unsignedOffset(base: Register, offset: Int64)
        case signedUnscaled(base: Register, offset: Int64)
        case preIndexed(base: Register, offset: Int64)
        case postIndexed(base: Register, offset: Int64)
        case registerOffset(base: Register, offset: Register, extend: ExtendKind?, shift: Int)
    }

    enum BranchRegisterKind: Equatable {
        case ret
        case br
        case blr
    }

    enum ExceptionKind: Equatable {
        case supervisorCall
        case breakpoint
        case halt
    }

    enum BarrierKind: Equatable {
        case instructionSynchronization
        case dataSynchronization
        case dataMemory
    }

    /// Named `HINT #imm` instructions. Unrecognised immediates round-trip
    /// through the generic `hint #imm` form.
    enum HintKind: String, Equatable, CaseIterable {
        case yield, wfe, wfi, sev, sevl, esb, csdb

        /// The 7-bit `CRm:op2` immediate.
        var immediate: UInt32 {
            switch self {
            case .yield: return 1
            case .wfe: return 2
            case .wfi: return 3
            case .sev: return 4
            case .sevl: return 5
            case .esb: return 16
            case .csdb: return 20
            }
        }

        static func decode(immediate: UInt32) -> HintKind? {
            allCases.first { $0.immediate == immediate }
        }
    }

    struct Shift: Equatable {
        var kind: ShiftKind
        var amount: Int
    }

    enum MoveWideKind: String, Equatable {
        case movz, movn, movk
    }

    enum AddSubKind: String, Equatable {
        case add, adds, sub, subs
    }

    enum CompareAliasKind: String, Equatable {
        case cmp, cmn
    }

    enum LogicalKind: String, Equatable {
        case and, ands, orr, eor, bic, bics, orn, eon
    }

    enum ShiftAliasKind: String, Equatable {
        case lsl, lsr, asr
    }

    enum ExtractKind: String, Equatable {
        case extr, ror
    }

    enum MultiplyKind: String, Equatable {
        case mul, mneg, madd, msub
    }

    enum DivideKind: String, Equatable {
        case udiv, sdiv
    }

    /// Add/subtract with carry (`adc`/`adcs`/`sbc`/`sbcs`). The `ngc`/`ngcs`
    /// aliases lower to `sbc`/`sbcs` with the zero register as first source.
    enum AddSubCarryKind: String, Equatable {
        case adc, adcs, sbc, sbcs

        /// The `op` field at bit 30 (1 for the subtract variants).
        var op: UInt32 { (self == .sbc || self == .sbcs) ? 1 : 0 }

        /// The `S` (set-flags) field at bit 29.
        var setsFlags: UInt32 { (self == .adcs || self == .sbcs) ? 1 : 0 }

        static func decode(op: UInt32, setsFlags: UInt32) -> AddSubCarryKind {
            switch (op, setsFlags) {
            case (0, 0): return .adc
            case (0, _): return .adcs
            case (_, 0): return .sbc
            default: return .sbcs
            }
        }
    }

    /// Bitfield move family (`sbfm`/`bfm`/`ubfm`). The many aliases
    /// (sbfx/ubfx/sbfiz/ubfiz/bfi/bfxil/bfc/sxtb/sxth/sxtw/uxtb/uxth and
    /// asr/lsl/lsr) all lower to one of these three with computed
    /// `immr`/`imms` fields.
    enum BitfieldKind: String, Equatable, CaseIterable {
        case sbfm, bfm, ubfm

        /// The `opc` field at [30:29].
        var opc: UInt32 {
            switch self {
            case .sbfm: return 0b00
            case .bfm: return 0b01
            case .ubfm: return 0b10
            }
        }

        static func decode(opc: UInt32) -> BitfieldKind? {
            allCases.first { $0.opc == opc }
        }
    }

    /// Wide multiply: 32x32→64 multiply-long variants and 64x64→64 high-half
    /// multiplies (data-processing 3 source).
    enum MultiplyWideKind: String, Equatable, CaseIterable {
        case smull, umull, smaddl, umaddl, smsubl, umsubl, smnegl, umnegl
        case smulh, umulh

        /// The `op31` field at [23:21].
        var op31: UInt32 {
            switch self {
            case .smull, .smaddl, .smsubl, .smnegl: return 0b001
            case .umull, .umaddl, .umsubl, .umnegl: return 0b101
            case .smulh: return 0b010
            case .umulh: return 0b110
            }
        }

        /// The `o0` bit at [15] (set for the subtracting variants).
        var o0: UInt32 {
            switch self {
            case .smsubl, .umsubl, .smnegl, .umnegl: return 1
            default: return 0
            }
        }

        /// Whether this is a 64x64→64 high-half multiply (all operands 64-bit,
        /// three operands, no accumulator).
        var isHigh: Bool { self == .smulh || self == .umulh }

        /// Whether the mnemonic takes an explicit accumulator operand (the
        /// `maddl`/`msubl` forms). The `mull`/`negl`/`mulh` forms use XZR.
        var hasAccumulator: Bool {
            switch self {
            case .smaddl, .umaddl, .smsubl, .umsubl: return true
            default: return false
            }
        }

        static func decode(op31: UInt32, o0: UInt32, hasAccumulator: Bool) -> MultiplyWideKind? {
            switch (op31, o0) {
            case (0b010, 0): return .smulh
            case (0b110, 0): return .umulh
            case (0b001, 0): return hasAccumulator ? .smaddl : .smull
            case (0b001, 1): return hasAccumulator ? .smsubl : .smnegl
            case (0b101, 0): return hasAccumulator ? .umaddl : .umull
            case (0b101, 1): return hasAccumulator ? .umsubl : .umnegl
            default: return nil
            }
        }
    }

    /// CRC32 / CRC32C checksum accumulation (data-processing 2 source).
    enum CRC32Kind: String, Equatable, CaseIterable {
        case crc32b, crc32h, crc32w, crc32x
        case crc32cb, crc32ch, crc32cw, crc32cx

        /// Whether the data source register `Rm` is 64-bit (the `x` variants).
        var usesDoubleWordSource: Bool { self == .crc32x || self == .crc32cx }

        /// The `sf` bit at [31] (set for the 64-bit-source variants).
        var sf: UInt32 { usesDoubleWordSource ? 1 : 0 }

        /// The `opcode` field at [15:10].
        var opcode: UInt32 {
            switch self {
            case .crc32b: return 0b010000
            case .crc32h: return 0b010001
            case .crc32w: return 0b010010
            case .crc32x: return 0b010011
            case .crc32cb: return 0b010100
            case .crc32ch: return 0b010101
            case .crc32cw: return 0b010110
            case .crc32cx: return 0b010111
            }
        }

        static func decode(opcode: UInt32) -> CRC32Kind? {
            allCases.first { $0.opcode == opcode }
        }
    }

    /// Data-processing (1 source): bit/byte reversals and count operations.
    enum DataProcessingOneSourceKind: String, Equatable, CaseIterable {
        case rbit, rev16, rev32, rev, clz, cls

        /// Whether the operation is only defined on 64-bit registers.
        var is64BitOnly: Bool { self == .rev32 }

        /// The `opcode` field at [15:10] for the given operand width.
        func opcode(is64Bit: Bool) -> UInt32 {
            switch self {
            case .rbit: return 0b000000
            case .rev16: return 0b000001
            case .rev32: return 0b000010
            // `rev` shares opcode 2 with `rev32` but selects it only when 32-bit;
            // the 64-bit form uses opcode 3.
            case .rev: return is64Bit ? 0b000011 : 0b000010
            case .clz: return 0b000100
            case .cls: return 0b000101
            }
        }

        /// Reconstruct the operation from the encoded `opcode` and `sf` bits.
        static func decode(opcode: UInt32, is64Bit: Bool) -> DataProcessingOneSourceKind? {
            switch opcode {
            case 0b000000: return .rbit
            case 0b000001: return .rev16
            case 0b000010: return is64Bit ? .rev32 : .rev
            case 0b000011: return is64Bit ? .rev : nil
            case 0b000100: return .clz
            case 0b000101: return .cls
            default: return nil
            }
        }
    }

    /// Conditional select family (`csel`/`csinc`/`csinv`/`csneg`).
    enum ConditionalSelectKind: String, Equatable, CaseIterable {
        case csel, csinc, csinv, csneg

        /// The `op` bit at [30].
        var op: UInt32 { (self == .csinv || self == .csneg) ? 1 : 0 }
        /// The `o2` bit at [10].
        var o2: UInt32 { (self == .csinc || self == .csneg) ? 1 : 0 }

        static func decode(op: UInt32, o2: UInt32) -> ConditionalSelectKind? {
            allCases.first { $0.op == op && $0.o2 == o2 }
        }
    }

    /// Conditional compare family (`ccmn`/`ccmp`).
    enum ConditionalCompareKind: String, Equatable, CaseIterable {
        case ccmn, ccmp

        /// The `op` bit at [30].
        var op: UInt32 { self == .ccmp ? 1 : 0 }
    }

    /// The second operand of a conditional compare: either a register or a
    /// 5-bit immediate.
    enum ConditionalCompareOperand: Equatable {
        case register(Register)
        case immediate(UInt32)
    }

    /// Conditional-set aliases that take only a destination and a condition
    /// (`cset`/`csetm`), lowering to `csinc`/`csinv` of the zero register with
    /// the inverted condition.
    enum ConditionalSetKind: String, Equatable, CaseIterable {
        case cset, csetm

        /// The underlying conditional-select operation.
        var base: ConditionalSelectKind { self == .cset ? .csinc : .csinv }
    }

    /// Conditional-select aliases that take a destination and a single source
    /// register (`cinc`/`cinv`/`cneg`), lowering to `csinc`/`csinv`/`csneg`
    /// with that register in both source positions and the inverted condition.
    enum ConditionalSelectAliasKind: String, Equatable, CaseIterable {
        case cinc, cinv, cneg

        /// The underlying conditional-select operation.
        var base: ConditionalSelectKind {
            switch self {
            case .cinc: return .csinc
            case .cinv: return .csinv
            case .cneg: return .csneg
            }
        }
    }

    enum LoadStoreSingleKind: String, Equatable {
        case ldr, ldrb, ldrh, ldrsb, ldrsh, ldrsw
        case str, strb, strh
        case ldur, ldurb, ldurh, ldursb, ldursh, ldursw
        case stur, sturb, sturh
    }

    enum LoadStorePairKind: String, Equatable {
        case ldp, stp
    }

    /// Load/store exclusive and load-acquire/store-release instructions.
    /// Covers the exclusive single (`ldxr`/`stxr`), acquiring exclusive
    /// (`ldaxr`/`stlxr`), non-exclusive ordered (`ldar`/`stlr`), and the
    /// exclusive pair (`ldxp`/`stxp`/`ldaxp`/`stlxp`) forms.
    enum LoadStoreExclusiveKind: String, Equatable, CaseIterable {
        case ldxrb, ldxrh, ldxr
        case stxrb, stxrh, stxr
        case ldaxrb, ldaxrh, ldaxr
        case stlxrb, stlxrh, stlxr
        case ldarb, ldarh, ldar
        case stlrb, stlrh, stlr
        case ldxp, ldaxp
        case stxp, stlxp

        var isPair: Bool {
            switch self {
            case .ldxp, .ldaxp, .stxp, .stlxp: return true
            default: return false
            }
        }

        /// True for the store-exclusive forms taking a `Ws` status register.
        var hasStatusRegister: Bool {
            switch self {
            case .stxrb, .stxrh, .stxr, .stlxrb, .stlxrh, .stlxr, .stxp, .stlxp: return true
            default: return false
            }
        }

        /// The `o2` field at bit 23 (set for the non-exclusive ordered forms).
        var o2: UInt32 {
            switch self {
            case .ldarb, .ldarh, .ldar, .stlrb, .stlrh, .stlr: return 1
            default: return 0
            }
        }

        /// The `L` (load) field at bit 22.
        var l: UInt32 {
            switch self {
            case .ldxrb, .ldxrh, .ldxr, .ldaxrb, .ldaxrh, .ldaxr, .ldarb, .ldarh, .ldar, .ldxp, .ldaxp:
                return 1
            default:
                return 0
            }
        }

        /// The `o0` field at bit 15 (acquire/release ordering).
        var o0: UInt32 {
            switch self {
            case .ldaxrb, .ldaxrh, .ldaxr, .stlxrb, .stlxrh, .stlxr,
                 .ldarb, .ldarh, .ldar, .stlrb, .stlrh, .stlr, .ldaxp, .stlxp:
                return 1
            default:
                return 0
            }
        }

        /// Fixed `size` field for byte/half forms; `nil` selects the
        /// width-dependent word/doubleword encoding.
        var fixedSize: UInt32? {
            switch self {
            case .ldxrb, .stxrb, .ldaxrb, .stlxrb, .ldarb, .stlrb: return 0b00
            case .ldxrh, .stxrh, .ldaxrh, .stlxrh, .ldarh, .stlrh: return 0b01
            default: return nil
            }
        }

        static func decode(o2: UInt32, l: UInt32, o1: UInt32, o0: UInt32, fixedSize: UInt32?) -> LoadStoreExclusiveKind? {
            allCases.first {
                $0.o2 == o2 && $0.l == l && ($0.isPair ? 1 : 0) == o1 && $0.o0 == o0 && $0.fixedSize == fixedSize
            }
        }
    }

    /// Compare and swap (`CAS` and its acquire/release/byte/half variants).
    enum CompareAndSwapKind: String, Equatable, CaseIterable {
        case cas, casa, casl, casal
        case casb, casab, caslb, casalb
        case cash, casah, caslh, casalh

        /// The `A` (acquire) field at bit 22.
        var acquire: UInt32 {
            switch self {
            case .casa, .casal, .casab, .casalb, .casah, .casalh: return 1
            default: return 0
            }
        }

        /// The `R` (release) field at bit 15.
        var release: UInt32 {
            switch self {
            case .casl, .casal, .caslb, .casalb, .caslh, .casalh: return 1
            default: return 0
            }
        }

        /// Fixed `size` field for byte/half forms; `nil` selects the
        /// width-dependent word/doubleword encoding.
        var fixedSize: UInt32? {
            switch self {
            case .casb, .casab, .caslb, .casalb: return 0b00
            case .cash, .casah, .caslh, .casalh: return 0b01
            default: return nil
            }
        }

        static func decode(acquire: UInt32, release: UInt32, fixedSize: UInt32?) -> CompareAndSwapKind? {
            allCases.first { $0.acquire == acquire && $0.release == release && $0.fixedSize == fixedSize }
        }
    }

    /// Compare and swap pair (`CASP` and its acquire/release variants).
    enum CompareAndSwapPairKind: String, Equatable, CaseIterable {
        case casp, caspa, caspl, caspal

        /// The `A` (acquire) field at bit 22.
        var acquire: UInt32 {
            switch self {
            case .caspa, .caspal: return 1
            default: return 0
            }
        }

        /// The `R` (release) field at bit 15.
        var release: UInt32 {
            switch self {
            case .caspl, .caspal: return 1
            default: return 0
            }
        }

        static func decode(acquire: UInt32, release: UInt32) -> CompareAndSwapPairKind? {
            allCases.first { $0.acquire == acquire && $0.release == release }
        }
    }

    /// Prefetch memory (`PRFM` scaled/register, `PRFUM` unscaled).
    enum PrefetchKind: String, Equatable, CaseIterable {
        case prfm, prfum
    }

    /// A named alias of a `SYS` instruction (`DC`, `IC`, `AT`, `TLBI`).
    struct SystemInstructionAlias: Equatable {
        var family: String
        var name: String
        var op1: UInt32
        var crn: UInt32
        var crm: UInt32
        var op2: UInt32
        var needsRegister: Bool

        static let all: [SystemInstructionAlias] = [
            // Data cache (DC), CRn=c7.
            SystemInstructionAlias(family: "dc", name: "ivac", op1: 0, crn: 7, crm: 6, op2: 1, needsRegister: true),
            SystemInstructionAlias(family: "dc", name: "isw", op1: 0, crn: 7, crm: 6, op2: 2, needsRegister: true),
            SystemInstructionAlias(family: "dc", name: "csw", op1: 0, crn: 7, crm: 10, op2: 2, needsRegister: true),
            SystemInstructionAlias(family: "dc", name: "cisw", op1: 0, crn: 7, crm: 14, op2: 2, needsRegister: true),
            SystemInstructionAlias(family: "dc", name: "zva", op1: 3, crn: 7, crm: 4, op2: 1, needsRegister: true),
            SystemInstructionAlias(family: "dc", name: "cvac", op1: 3, crn: 7, crm: 10, op2: 1, needsRegister: true),
            SystemInstructionAlias(family: "dc", name: "cvau", op1: 3, crn: 7, crm: 11, op2: 1, needsRegister: true),
            SystemInstructionAlias(family: "dc", name: "cvap", op1: 3, crn: 7, crm: 12, op2: 1, needsRegister: true),
            SystemInstructionAlias(family: "dc", name: "civac", op1: 3, crn: 7, crm: 14, op2: 1, needsRegister: true),
            // Instruction cache (IC), CRn=c7.
            SystemInstructionAlias(family: "ic", name: "ialluis", op1: 0, crn: 7, crm: 1, op2: 0, needsRegister: false),
            SystemInstructionAlias(family: "ic", name: "iallu", op1: 0, crn: 7, crm: 5, op2: 0, needsRegister: false),
            SystemInstructionAlias(family: "ic", name: "ivau", op1: 3, crn: 7, crm: 5, op2: 1, needsRegister: true),
            // Address translation (AT), CRn=c7.
            SystemInstructionAlias(family: "at", name: "s1e1r", op1: 0, crn: 7, crm: 8, op2: 0, needsRegister: true),
            SystemInstructionAlias(family: "at", name: "s1e1w", op1: 0, crn: 7, crm: 8, op2: 1, needsRegister: true),
            SystemInstructionAlias(family: "at", name: "s1e0r", op1: 0, crn: 7, crm: 8, op2: 2, needsRegister: true),
            SystemInstructionAlias(family: "at", name: "s1e0w", op1: 0, crn: 7, crm: 8, op2: 3, needsRegister: true),
            // TLB invalidate (TLBI), CRn=c8.
            SystemInstructionAlias(family: "tlbi", name: "vmalle1is", op1: 0, crn: 8, crm: 3, op2: 0, needsRegister: false),
            SystemInstructionAlias(family: "tlbi", name: "vae1is", op1: 0, crn: 8, crm: 3, op2: 1, needsRegister: true),
            SystemInstructionAlias(family: "tlbi", name: "aside1is", op1: 0, crn: 8, crm: 3, op2: 2, needsRegister: true),
            SystemInstructionAlias(family: "tlbi", name: "vaae1is", op1: 0, crn: 8, crm: 3, op2: 3, needsRegister: true),
            SystemInstructionAlias(family: "tlbi", name: "vale1is", op1: 0, crn: 8, crm: 3, op2: 5, needsRegister: true),
            SystemInstructionAlias(family: "tlbi", name: "vaale1is", op1: 0, crn: 8, crm: 3, op2: 7, needsRegister: true),
            SystemInstructionAlias(family: "tlbi", name: "vmalle1", op1: 0, crn: 8, crm: 7, op2: 0, needsRegister: false),
            SystemInstructionAlias(family: "tlbi", name: "vae1", op1: 0, crn: 8, crm: 7, op2: 1, needsRegister: true),
            SystemInstructionAlias(family: "tlbi", name: "aside1", op1: 0, crn: 8, crm: 7, op2: 2, needsRegister: true),
            SystemInstructionAlias(family: "tlbi", name: "vaae1", op1: 0, crn: 8, crm: 7, op2: 3, needsRegister: true),
            SystemInstructionAlias(family: "tlbi", name: "vale1", op1: 0, crn: 8, crm: 7, op2: 5, needsRegister: true),
            SystemInstructionAlias(family: "tlbi", name: "vaale1", op1: 0, crn: 8, crm: 7, op2: 7, needsRegister: true),
        ]

        /// Look up an alias by its family (`dc`/`ic`/`at`/`tlbi`) and operation name.
        static func find(family: String, name: String) -> SystemInstructionAlias? {
            all.first { $0.family == family && $0.name == name }
        }

        /// Look up an alias by its encoded `op1`/`CRn`/`CRm`/`op2` fields.
        static func find(op1: UInt32, crn: UInt32, crm: UInt32, op2: UInt32) -> SystemInstructionAlias? {
            all.first { $0.op1 == op1 && $0.crn == crn && $0.crm == crm && $0.op2 == op2 }
        }
    }

    /// A no-operand PSTATE flag manipulation instruction (`CFINV`, `AXFLAG`,
    /// `XAFLAG`). These occupy the MSR-immediate space with a fixed encoding.
    enum PStateFlagKind: String, Equatable, CaseIterable {
        case cfinv, axflag, xaflag

        var word: UInt32 {
            switch self {
            case .cfinv: return 0xd500_401f
            case .xaflag: return 0xd500_403f
            case .axflag: return 0xd500_405f
            }
        }
    }

    /// A PSTATE field written by `MSR <field>, #imm` (MSR immediate).
    enum PStateField: String, Equatable, CaseIterable {
        case spsel, daifset, daifclr, uao, pan, dit, ssbs

        /// The `op1` field at bits [18:16].
        var op1: UInt32 {
            switch self {
            case .spsel, .uao, .pan: return 0
            case .daifset, .daifclr, .dit, .ssbs: return 3
            }
        }

        /// The `op2` field at bits [7:5].
        var op2: UInt32 {
            switch self {
            case .ssbs: return 1
            case .dit: return 2
            case .uao: return 3
            case .pan: return 4
            case .spsel: return 5
            case .daifset: return 6
            case .daifclr: return 7
            }
        }

        static func decode(op1: UInt32, op2: UInt32) -> PStateField? {
            allCases.first { $0.op1 == op1 && $0.op2 == op2 }
        }
    }

    /// A system register accessed via `MRS` / `MSR` (register).
    ///
    /// Encoded as the `o0` (`op0 - 2`), `op1`, `CRn`, `CRm`, and `op2` fields.
    struct SystemRegister: Equatable {
        var op0: UInt32
        var op1: UInt32
        var crn: UInt32
        var crm: UInt32
        var op2: UInt32

        init(op0: UInt32, op1: UInt32, crn: UInt32, crm: UInt32, op2: UInt32) {
            self.op0 = op0
            self.op1 = op1
            self.crn = crn
            self.crm = crm
            self.op2 = op2
        }

        /// Common named system registers recognised by the assembler.
        static let named: [(name: String, register: SystemRegister)] = [
            ("nzcv", SystemRegister(op0: 3, op1: 3, crn: 4, crm: 2, op2: 0)),
            ("daif", SystemRegister(op0: 3, op1: 3, crn: 4, crm: 2, op2: 1)),
            ("fpcr", SystemRegister(op0: 3, op1: 3, crn: 4, crm: 4, op2: 0)),
            ("fpsr", SystemRegister(op0: 3, op1: 3, crn: 4, crm: 4, op2: 1)),
            ("tpidr_el0", SystemRegister(op0: 3, op1: 3, crn: 13, crm: 0, op2: 2)),
            ("tpidrro_el0", SystemRegister(op0: 3, op1: 3, crn: 13, crm: 0, op2: 3)),
            ("tpidr_el1", SystemRegister(op0: 3, op1: 0, crn: 13, crm: 0, op2: 4)),
            ("midr_el1", SystemRegister(op0: 3, op1: 0, crn: 0, crm: 0, op2: 0)),
            ("mpidr_el1", SystemRegister(op0: 3, op1: 0, crn: 0, crm: 0, op2: 5)),
            ("ctr_el0", SystemRegister(op0: 3, op1: 3, crn: 0, crm: 0, op2: 1)),
            ("dczid_el0", SystemRegister(op0: 3, op1: 3, crn: 0, crm: 0, op2: 7)),
            ("sp_el0", SystemRegister(op0: 3, op1: 0, crn: 4, crm: 1, op2: 0)),
            ("elr_el1", SystemRegister(op0: 3, op1: 0, crn: 4, crm: 0, op2: 1)),
            ("spsr_el1", SystemRegister(op0: 3, op1: 0, crn: 4, crm: 0, op2: 0)),
            ("vbar_el1", SystemRegister(op0: 3, op1: 0, crn: 12, crm: 0, op2: 0)),
            ("ttbr0_el1", SystemRegister(op0: 3, op1: 0, crn: 2, crm: 0, op2: 0)),
            ("ttbr1_el1", SystemRegister(op0: 3, op1: 0, crn: 2, crm: 0, op2: 1)),
            ("sctlr_el1", SystemRegister(op0: 3, op1: 0, crn: 1, crm: 0, op2: 0)),
            ("esr_el1", SystemRegister(op0: 3, op1: 0, crn: 5, crm: 2, op2: 0)),
            ("far_el1", SystemRegister(op0: 3, op1: 0, crn: 6, crm: 0, op2: 0)),
            ("cntvct_el0", SystemRegister(op0: 3, op1: 3, crn: 14, crm: 0, op2: 2)),
            ("cntfrq_el0", SystemRegister(op0: 3, op1: 3, crn: 14, crm: 0, op2: 0)),
            ("pmccntr_el0", SystemRegister(op0: 3, op1: 3, crn: 9, crm: 13, op2: 0)),
        ]

        /// The canonical name (a known register name, or the generic
        /// `S<op0>_<op1>_C<n>_C<m>_<op2>` form).
        var name: String {
            if let match = SystemRegister.named.first(where: { $0.register == self }) {
                return match.name
            }
            return "s\(op0)_\(op1)_c\(crn)_c\(crm)_\(op2)"
        }

        /// Parse a register name (named or the generic `S` form).
        static func parse(_ text: String) -> SystemRegister? {
            let lower = text.lowercased()
            if let match = named.first(where: { $0.name == lower }) {
                return match.register
            }
            // Generic form: s<op0>_<op1>_c<n>_c<m>_<op2>
            guard lower.hasPrefix("s") else { return nil }
            let parts = lower.dropFirst().split(separator: "_", omittingEmptySubsequences: false)
            guard parts.count == 5 else { return nil }
            guard let op0 = UInt32(parts[0]), let op1 = UInt32(parts[1]),
                  parts[2].hasPrefix("c"), parts[3].hasPrefix("c"),
                  let crn = UInt32(parts[2].dropFirst()),
                  let crm = UInt32(parts[3].dropFirst()),
                  let op2 = UInt32(parts[4]) else { return nil }
            guard op0 <= 3, op1 <= 7, crn <= 15, crm <= 15, op2 <= 7 else { return nil }
            return SystemRegister(op0: op0, op1: op1, crn: crn, crm: crm, op2: op2)
        }
    }

    /// Load-acquire / store-release RCpc with an unscaled immediate offset
    /// (`LDAPUR` / `STLUR` family, FEAT_LRCPC2).
    enum RCpcUnscaledKind: String, Equatable, CaseIterable {
        case stlurb, stlurh, stlur
        case ldapurb, ldapurh, ldapur
        case ldapursb, ldapursh, ldapursw

        /// The `size` (bits [31:30]) and `opc` (bits [23:22]) fields for the
        /// given target register width.
        func fields(is64Bit: Bool) -> (size: UInt32, opc: UInt32) {
            switch self {
            case .stlurb: return (0, 0)
            case .stlurh: return (1, 0)
            case .stlur: return (is64Bit ? 3 : 2, 0)
            case .ldapurb: return (0, 1)
            case .ldapurh: return (1, 1)
            case .ldapur: return (is64Bit ? 3 : 2, 1)
            case .ldapursb: return (0, is64Bit ? 2 : 3)
            case .ldapursh: return (1, is64Bit ? 2 : 3)
            case .ldapursw: return (2, 2)
            }
        }

        /// The required target register width, or `nil` if either is allowed.
        var requiredWidth: Int? {
            switch self {
            case .stlurb, .stlurh, .ldapurb, .ldapurh: return 32
            case .ldapursw: return 64
            case .stlur, .ldapur, .ldapursb, .ldapursh: return nil
            }
        }

        /// Recover the mnemonic and target register width from the encoded
        /// `size`/`opc` fields.
        static func decode(size: UInt32, opc: UInt32) -> (kind: RCpcUnscaledKind, width: Int)? {
            switch (opc, size) {
            case (0, 0): return (.stlurb, 32)
            case (0, 1): return (.stlurh, 32)
            case (0, 2): return (.stlur, 32)
            case (0, 3): return (.stlur, 64)
            case (1, 0): return (.ldapurb, 32)
            case (1, 1): return (.ldapurh, 32)
            case (1, 2): return (.ldapur, 32)
            case (1, 3): return (.ldapur, 64)
            case (2, 0): return (.ldapursb, 64)
            case (2, 1): return (.ldapursh, 64)
            case (2, 2): return (.ldapursw, 64)
            case (3, 0): return (.ldapursb, 32)
            case (3, 1): return (.ldapursh, 32)
            default: return nil
            }
        }
    }

    /// Load-acquire RCpc register (`LDAPR` / `LDAPRB` / `LDAPRH`).
    enum LoadAcquireRCpcKind: String, Equatable, CaseIterable {
        case ldaprb, ldaprh, ldapr

        /// Fixed `size` field for byte/half forms; `nil` selects the
        /// width-dependent word/doubleword encoding.
        var fixedSize: UInt32? {
            switch self {
            case .ldaprb: return 0b00
            case .ldaprh: return 0b01
            case .ldapr: return nil
            }
        }
    }

    /// The base operation of an atomic memory instruction (LSE).
    enum AtomicMemoryOperation: String, Equatable, CaseIterable {
        case add, clr, eor, set, smax, smin, umax, umin, swp

        /// The `opc` field at bits [14:12].
        var opc: UInt32 {
            switch self {
            case .add: return 0b000
            case .clr: return 0b001
            case .eor: return 0b010
            case .set: return 0b011
            case .smax: return 0b100
            case .smin: return 0b101
            case .umax: return 0b110
            case .umin: return 0b111
            case .swp: return 0b000
            }
        }

        /// The `o3` field at bit 15 (set for `swp`).
        var o3: UInt32 { self == .swp ? 1 : 0 }

        /// Whether a store-form alias (`st<op>`) exists for this operation.
        var hasStoreAlias: Bool { self != .swp }
    }

    /// An atomic memory operation (`LDADD`, `SWP`, the `ST<op>` aliases, …).
    struct AtomicMemoryKind: Equatable {
        var operation: AtomicMemoryOperation
        var acquire: Bool
        var release: Bool
        /// Fixed `size` field for byte/half forms; `nil` selects the
        /// width-dependent word/doubleword encoding.
        var fixedSize: UInt32?
        /// `true` for the `ST<op>` aliases (`Rt` is `wzr`/`xzr` and never acquires).
        var isStore: Bool

        var mnemonic: String {
            let order = (acquire ? "a" : "") + (release ? "l" : "")
            let suffix = fixedSize == nil ? "" : (fixedSize == 0 ? "b" : "h")
            if operation == .swp { return "swp" + order + suffix }
            return (isStore ? "st" : "ld") + operation.rawValue + order + suffix
        }

        static func parse(_ mnemonic: String) -> AtomicMemoryKind? {
            var rest: Substring
            var isStore = false
            var operation: AtomicMemoryOperation
            if mnemonic.hasPrefix("swp") {
                operation = .swp
                rest = mnemonic.dropFirst(3)
            } else if mnemonic.hasPrefix("ld") || mnemonic.hasPrefix("st") {
                isStore = mnemonic.hasPrefix("st")
                let afterPrefix = mnemonic.dropFirst(2)
                guard let op = AtomicMemoryOperation.allCases.first(where: {
                    $0 != .swp && afterPrefix.hasPrefix($0.rawValue)
                }) else { return nil }
                operation = op
                rest = afterPrefix.dropFirst(op.rawValue.count)
            } else {
                return nil
            }

            var acquire = false
            var release = false
            if rest.hasPrefix("a") { acquire = true; rest = rest.dropFirst() }
            if rest.hasPrefix("l") { release = true; rest = rest.dropFirst() }

            var fixedSize: UInt32?
            if rest == "b" { fixedSize = 0; rest = "" }
            else if rest == "h" { fixedSize = 1; rest = "" }
            guard rest.isEmpty else { return nil }

            // `swp` has no store form, and store aliases never acquire.
            if operation == .swp && isStore { return nil }
            if isStore && acquire { return nil }

            return AtomicMemoryKind(
                operation: operation, acquire: acquire, release: release,
                fixedSize: fixedSize, isStore: isStore
            )
        }
    }

    /// Advanced SIMD load/store multiple structures (`LD1`–`LD4` / `ST1`–`ST4`).
    enum LoadStoreMultipleKind: String, Equatable, CaseIterable {
        case st1, ld1, st2, ld2, st3, ld3, st4, ld4

        var isLoad: Bool { rawValue.hasPrefix("ld") }

        /// The structure size (1 for LD1/ST1 … 4 for LD4/ST4).
        var structure: Int { Int(String(rawValue.dropFirst(2)))! }

        /// Whether the given register count is valid for this kind.
        func allows(count: Int) -> Bool {
            structure == 1 ? (1...4).contains(count) : count == structure
        }

        /// The `opcode` field (bits[15:12]) for the given register count.
        func opcode(count: Int) -> UInt32? {
            switch (structure, count) {
            case (1, 1): return 0b0111
            case (1, 2): return 0b1010
            case (1, 3): return 0b0110
            case (1, 4): return 0b0010
            case (2, 2): return 0b1000
            case (3, 3): return 0b0100
            case (4, 4): return 0b0000
            default: return nil
            }
        }

        /// Reverse mapping from a decoded `opcode` to (structure, register count).
        static func decode(opcode: UInt32) -> (structure: Int, count: Int)? {
            switch opcode {
            case 0b0111: return (1, 1)
            case 0b1010: return (1, 2)
            case 0b0110: return (1, 3)
            case 0b0010: return (1, 4)
            case 0b1000: return (2, 2)
            case 0b0100: return (3, 3)
            case 0b0000: return (4, 4)
            default: return nil
            }
        }

        static func forStructure(_ structure: Int, isLoad: Bool) -> LoadStoreMultipleKind? {
            switch (structure, isLoad) {
            case (1, false): return .st1
            case (1, true):  return .ld1
            case (2, false): return .st2
            case (2, true):  return .ld2
            case (3, false): return .st3
            case (3, true):  return .ld3
            case (4, false): return .st4
            case (4, true):  return .ld4
            default: return nil
            }
        }
    }

    /// Advanced SIMD load single structure and replicate (`LD1R`–`LD4R`).
    enum LoadStoreReplicateKind: String, Equatable, CaseIterable {
        case ld1r, ld2r, ld3r, ld4r

        /// The structure size / number of registers (1 for LD1R … 4 for LD4R).
        var structure: Int { Int(String(rawValue.dropFirst(2).dropLast()))! }

        static func forStructure(_ structure: Int) -> LoadStoreReplicateKind? {
            switch structure {
            case 1: return .ld1r
            case 2: return .ld2r
            case 3: return .ld3r
            case 4: return .ld4r
            default: return nil
            }
        }
    }

    enum PointerAuthenticationKind: String, Equatable {
        case paciasp, autiasp, pacibsp, autibsp, xpaci, xpacd
    }

    enum FPDataProcessing2Kind: String, Equatable {
        case fmul, fdiv, fadd, fsub, fmax, fmin, fmaxnm, fminnm, fnmul
    }

    enum FPDataProcessing1Kind: String, Equatable {
        case fmov, fabs, fneg, fsqrt
        case frintn, frintp, frintm, frintz, frinta, frintx, frinti
        case frint32z, frint32x, frint64z, frint64x

        /// The 6-bit opcode field at [20:15].
        var opcode: UInt32 {
            switch self {
            case .fmov:     return 0b000000
            case .fabs:     return 0b000001
            case .fneg:     return 0b000010
            case .fsqrt:    return 0b000011
            case .frintn:   return 0b001000
            case .frintp:   return 0b001001
            case .frintm:   return 0b001010
            case .frintz:   return 0b001011
            case .frinta:   return 0b001100
            case .frintx:   return 0b001110
            case .frinti:   return 0b001111
            case .frint32z: return 0b010000
            case .frint32x: return 0b010001
            case .frint64z: return 0b010010
            case .frint64x: return 0b010011
            }
        }

        /// `frint32*` / `frint64*` exist only for single and double precision.
        var allowsHalf: Bool {
            switch self {
            case .frint32z, .frint32x, .frint64z, .frint64x: return false
            default: return true
            }
        }

        /// The round-to-integral forms (everything except fmov/fabs/fneg/fsqrt);
        /// the parser uses this to route bare scalar operands here.
        var isRoundToIntegral: Bool {
            switch self {
            case .fmov, .fabs, .fneg, .fsqrt: return false
            default: return true
            }
        }
    }

    enum FPDataProcessing3Kind: String, Equatable {
        case fmadd, fmsub, fnmadd, fnmsub
    }

    enum FPCompareKind: String, Equatable {
        case fcmp, fcmpe
    }

    /// Scalar floating-point conditional compare (`fccmp`/`fccmpe`). The `op`
    /// bit at [4] selects the signalling (`fccmpe`) variant.
    enum FPConditionalCompareKind: String, Equatable {
        case fccmp, fccmpe

        var op: UInt32 { self == .fccmpe ? 1 : 0 }
    }

    enum FPConvertToIntKind: String, Equatable {
        case fcvtzs, fcvtzu
    }

    enum FPConvertFromIntKind: String, Equatable {
        case scvtf, ucvtf
    }

    enum FPCompareOperand: Equatable {
        case register(FPRegister)
        case zero
    }

    enum AcrossLanesIntegerKind: String, Equatable {
        case saddlv, uaddlv, smaxv, umaxv, sminv, uminv, addv
    }

    /// Advanced SIMD table lookup (`TBL` / `TBX`).
    enum VectorTableLookupKind: String, Equatable {
        case tbl, tbx

        /// The `op` bit at [12] (0 for TBL, 1 for TBX).
        var op: UInt32 { self == .tbx ? 1 : 0 }
    }

    enum AcrossLanesFPKind: String, Equatable {
        case fmaxv, fminv, fmaxnmv, fminnmv
    }

    /// Advanced SIMD two-register-misc compare against zero (`Vd.T, Vn.T, #0` or `#0.0`).
    enum VectorCompareZeroKind: String, Equatable, CaseIterable {
        case cmgt, cmeq, cmlt, cmge, cmle
        case fcmgt, fcmeq, fcmlt, fcmge, fcmle

        /// `true` for the floating-point forms (which compare against `#0.0`).
        var isFloat: Bool { rawValue.hasPrefix("f") }

        /// The `U` bit at [29] and the 5-bit `opcode` at [16:12].
        var spec: (u: UInt32, opcode: UInt32) {
            switch self {
            case .cmgt: return (0, 0b01000)
            case .cmeq: return (0, 0b01001)
            case .cmlt: return (0, 0b01010)
            case .cmge: return (1, 0b01000)
            case .cmle: return (1, 0b01001)
            case .fcmgt: return (0, 0b01100)
            case .fcmeq: return (0, 0b01101)
            case .fcmlt: return (0, 0b01110)
            case .fcmge: return (1, 0b01100)
            case .fcmle: return (1, 0b01101)
            }
        }

        static func decode(u: UInt32, opcode: UInt32, isFloat: Bool) -> VectorCompareZeroKind? {
            allCases.first { $0.isFloat == isFloat && $0.spec == (u, opcode) }
        }
    }

    /// Advanced SIMD two-register-misc floating-point ↔ integer convert
    /// (`Vd.T, Vn.T` with single/double-precision arrangements `2s`/`4s`/`2d`).
    enum VectorConvertKind: String, Equatable, CaseIterable {
        case fcvtns, fcvtnu, fcvtps, fcvtpu, fcvtms, fcvtmu
        case fcvtzs, fcvtzu, fcvtas, fcvtau, scvtf, ucvtf

        /// The `U` bit at [29], the 5-bit `opcode` at [16:12], and the high `size`
        /// bit at [23] (`sz` at [22] still carries the single/double selector).
        var spec: (u: UInt32, opcode: UInt32, sizeHi: UInt32) {
            switch self {
            case .fcvtns: return (0, 0b11010, 0)
            case .fcvtnu: return (1, 0b11010, 0)
            case .fcvtps: return (0, 0b11010, 1)
            case .fcvtpu: return (1, 0b11010, 1)
            case .fcvtms: return (0, 0b11011, 0)
            case .fcvtmu: return (1, 0b11011, 0)
            case .fcvtzs: return (0, 0b11011, 1)
            case .fcvtzu: return (1, 0b11011, 1)
            case .fcvtas: return (0, 0b11100, 0)
            case .fcvtau: return (1, 0b11100, 0)
            case .scvtf: return (0, 0b11101, 0)
            case .ucvtf: return (1, 0b11101, 0)
            }
        }

        static func decode(u: UInt32, opcode: UInt32, sizeHi: UInt32) -> VectorConvertKind? {
            allCases.first { $0.spec == (u, opcode, sizeHi) }
        }
    }

    /// Advanced SIMD two-register-misc floating-point rounding (`FRINTN`…`FRINTI`)
    /// and reciprocal estimates (`FRECPE`/`FRSQRTE`/`URECPE`/`URSQRTE`).
    /// Shares the convert opcode space; the high `size` bit at [23] disambiguates.
    enum VectorRoundReciprocalKind: String, Equatable, CaseIterable {
        case frintn, frintm, frintp, frintz, frinta, frintx, frinti
        case frecpe, frsqrte, urecpe, ursqrte

        /// The `U` bit at [29], the 5-bit `opcode` at [16:12], and the high `size`
        /// bit at [23] (`sz` at [22] still selects single vs. double precision).
        var spec: (u: UInt32, opcode: UInt32, sizeHi: UInt32) {
            switch self {
            case .frintn:  return (0, 0b11000, 0)
            case .frintm:  return (0, 0b11001, 0)
            case .frintp:  return (0, 0b11000, 1)
            case .frintz:  return (0, 0b11001, 1)
            case .frinta:  return (1, 0b11000, 0)
            case .frintx:  return (1, 0b11001, 0)
            case .frinti:  return (1, 0b11001, 1)
            case .frecpe:  return (0, 0b11101, 1)
            case .frsqrte: return (1, 0b11101, 1)
            case .urecpe:  return (0, 0b11100, 1)
            case .ursqrte: return (1, 0b11100, 1)
            }
        }

        /// `URECPE`/`URSQRTE` are integer estimates restricted to `2s`/`4s`;
        /// the rest accept the `2d` double-precision arrangement too.
        var allowsDouble: Bool {
            switch self {
            case .urecpe, .ursqrte: return false
            default: return true
            }
        }

        /// `URECPE`/`URSQRTE` are integer estimates with no half-precision form;
        /// the FRINT* roundings and FRECPE/FRSQRTE accept `.4h`/`.8h`.
        var allowsFP16: Bool {
            switch self {
            case .urecpe, .ursqrte: return false
            default: return true
            }
        }

        static func decode(u: UInt32, opcode: UInt32, sizeHi: UInt32) -> VectorRoundReciprocalKind? {
            allCases.first { $0.spec == (u, opcode, sizeHi) }
        }
    }

    /// Advanced SIMD two-register-misc floating-point precision converts
    /// (`FCVTN`/`FCVTL`/`FCVTXN`). The `2` upper-half variants set `Q=1`, and the
    /// `sz` bit at [22] selects the half↔single (`sz=0`) vs. single↔double (`sz=1`) pair.
    enum VectorFPConvertPrecisionKind: String, Equatable, CaseIterable {
        case fcvtn, fcvtl, fcvtxn

        /// The `U` bit at [29] and the 5-bit `opcode` at [16:12].
        var spec: (u: UInt32, opcode: UInt32) {
            switch self {
            case .fcvtn:  return (0, 0b10110)
            case .fcvtl:  return (0, 0b10111)
            case .fcvtxn: return (1, 0b10110)
            }
        }

        static func decode(u: UInt32, opcode: UInt32) -> VectorFPConvertPrecisionKind? {
            allCases.first { $0.spec == (u, opcode) }
        }
    }

    /// Advanced SIMD two-register-misc extract-narrow (`XTN`/`SQXTN`/`UQXTN`/`SQXTUN`).
    /// The `2` upper-half variants are distinguished by a 128-bit (`Q=1`) destination.
    enum VectorExtractNarrowKind: String, Equatable, CaseIterable {
        case xtn, sqxtn, uqxtn, sqxtun

        /// The `U` bit at [29] and the 5-bit `opcode` at [16:12].
        var spec: (u: UInt32, opcode: UInt32) {
            switch self {
            case .xtn: return (0, 0b10010)
            case .sqxtun: return (1, 0b10010)
            case .sqxtn: return (0, 0b10100)
            case .uqxtn: return (1, 0b10100)
            }
        }

        static func decode(u: UInt32, opcode: UInt32) -> VectorExtractNarrowKind? {
            allCases.first { $0.spec == (u, opcode) }
        }
    }

    /// Advanced SIMD two-register-misc pairwise long add (`SADDLP`/`UADDLP`)
    /// and accumulate (`SADALP`/`UADALP`). Each adjacent pair of source elements
    /// is summed into a destination element of twice the width.
    enum VectorPairwiseLongAddKind: String, Equatable, CaseIterable {
        case saddlp, uaddlp, sadalp, uadalp

        /// The `U` bit at [29] and the 5-bit `opcode` at [16:12].
        var spec: (u: UInt32, opcode: UInt32) {
            switch self {
            case .saddlp: return (0, 0b00010)
            case .uaddlp: return (1, 0b00010)
            case .sadalp: return (0, 0b00110)
            case .uadalp: return (1, 0b00110)
            }
        }

        static func decode(u: UInt32, opcode: UInt32) -> VectorPairwiseLongAddKind? {
            allCases.first { $0.spec == (u, opcode) }
        }
    }

    /// Cryptographic AES single-round instructions (`Vd.16b, Vn.16b`).
    enum CryptoAESKind: String, Equatable, CaseIterable {
        case aese, aesd, aesmc, aesimc

        /// The 5-bit `opcode` at [16:12].
        var opcode: UInt32 {
            switch self {
            case .aese:   return 0b00100
            case .aesd:   return 0b00101
            case .aesmc:  return 0b00110
            case .aesimc: return 0b00111
            }
        }

        static func decode(opcode: UInt32) -> CryptoAESKind? {
            allCases.first { $0.opcode == opcode }
        }
    }

    /// The register shape of a single cryptographic SHA operand.
    enum CryptoSHAOperand: Equatable {
        case scalarS   // 32-bit `Sn`
        case scalarQ   // 128-bit `Qn`
        case vector4s  // `Vn.4s`
        case vector2d  // `Vn.2d`
        case vector16b // `Vn.16b`
    }

    /// Cryptographic three-register SHA1/SHA256 instructions. Operand register
    /// shapes are fixed by the mnemonic, so only register numbers are stored.
    enum CryptoSHA3Kind: String, Equatable, CaseIterable {
        case sha1c, sha1p, sha1m, sha1su0, sha256h, sha256h2, sha256su1

        /// The 3-bit `opcode` at [14:12].
        var opcode: UInt32 {
            switch self {
            case .sha1c:     return 0b000
            case .sha1p:     return 0b001
            case .sha1m:     return 0b010
            case .sha1su0:   return 0b011
            case .sha256h:   return 0b100
            case .sha256h2:  return 0b101
            case .sha256su1: return 0b110
            }
        }

        /// Register shapes for the destination, first, and second source operands.
        var shape: (d: CryptoSHAOperand, n: CryptoSHAOperand, m: CryptoSHAOperand) {
            switch self {
            case .sha1c, .sha1p, .sha1m:  return (.scalarQ, .scalarS, .vector4s)
            case .sha256h, .sha256h2:     return (.scalarQ, .scalarQ, .vector4s)
            case .sha1su0, .sha256su1:    return (.vector4s, .vector4s, .vector4s)
            }
        }

        static func decode(opcode: UInt32) -> CryptoSHA3Kind? {
            allCases.first { $0.opcode == opcode }
        }
    }

    /// Cryptographic two-register SHA1/SHA256 instructions.
    enum CryptoSHA2Kind: String, Equatable, CaseIterable {
        case sha1h, sha1su1, sha256su0

        /// The 5-bit `opcode` at [16:12].
        var opcode: UInt32 {
            switch self {
            case .sha1h:     return 0b00000
            case .sha1su1:   return 0b00001
            case .sha256su0: return 0b00010
            }
        }

        /// Register shapes for the destination and source operands.
        var shape: (d: CryptoSHAOperand, n: CryptoSHAOperand) {
            switch self {
            case .sha1h:                return (.scalarS, .scalarS)
            case .sha1su1, .sha256su0:  return (.vector4s, .vector4s)
            }
        }

        static func decode(opcode: UInt32) -> CryptoSHA2Kind? {
            allCases.first { $0.opcode == opcode }
        }
    }

    /// Cryptographic three-register SHA512 instructions (FEAT_SHA512).
    enum CryptoSHA512Kind: String, Equatable, CaseIterable {
        case sha512h, sha512h2, sha512su1

        /// The 2-bit `opcode` at [11:10] (the `O` bit at [14] is always 0).
        var opcode: UInt32 {
            switch self {
            case .sha512h:   return 0b00
            case .sha512h2:  return 0b01
            case .sha512su1: return 0b10
            }
        }

        /// Register shapes for the destination and two source operands.
        var shape: (d: CryptoSHAOperand, n: CryptoSHAOperand, m: CryptoSHAOperand) {
            switch self {
            case .sha512h, .sha512h2: return (.scalarQ, .scalarQ, .vector2d)
            case .sha512su1:          return (.vector2d, .vector2d, .vector2d)
            }
        }

        static func decode(opcode: UInt32) -> CryptoSHA512Kind? {
            allCases.first { $0.opcode == opcode }
        }
    }

    /// Cryptographic two-register SHA512 / SM4 instructions (FEAT_SHA512 / FEAT_SM4).
    enum CryptoTwoRegKind: String, Equatable, CaseIterable {
        case sha512su0, sm4e

        /// The 2-bit `opcode` at [11:10].
        var opcode: UInt32 {
            switch self {
            case .sha512su0: return 0b00
            case .sm4e:      return 0b01
            }
        }

        /// Register shapes for the destination and source operands.
        var shape: (d: CryptoSHAOperand, n: CryptoSHAOperand) {
            switch self {
            case .sha512su0: return (.vector2d, .vector2d)
            case .sm4e:      return (.vector4s, .vector4s)
            }
        }

        static func decode(opcode: UInt32) -> CryptoTwoRegKind? {
            allCases.first { $0.opcode == opcode }
        }
    }

    /// Cryptographic three-register SM3 / SM4 instructions (`Vd.4s, Vn.4s, Vm.4s`).
    enum CryptoSM3Kind: String, Equatable, CaseIterable {
        case sm3partw1, sm3partw2, sm4ekey

        /// The 2-bit `opcode` at [11:10].
        var opcode: UInt32 {
            switch self {
            case .sm3partw1: return 0b00
            case .sm3partw2: return 0b01
            case .sm4ekey:   return 0b10
            }
        }

        static func decode(opcode: UInt32) -> CryptoSM3Kind? {
            allCases.first { $0.opcode == opcode }
        }
    }

    /// Cryptographic three-register SM3 "imm2" indexed instructions
    /// (`Vd.4s, Vn.4s, Vm.s[index]`).
    enum CryptoSM3IndexedKind: String, Equatable, CaseIterable {
        case sm3tt1a, sm3tt1b, sm3tt2a, sm3tt2b

        /// The 2-bit `opcode` at [11:10].
        var opcode: UInt32 {
            switch self {
            case .sm3tt1a: return 0b00
            case .sm3tt1b: return 0b01
            case .sm3tt2a: return 0b10
            case .sm3tt2b: return 0b11
            }
        }

        static func decode(opcode: UInt32) -> CryptoSM3IndexedKind? {
            allCases.first { $0.opcode == opcode }
        }
    }

    /// Cryptographic four-register SHA3 instructions (`Vd.16b, Vn.16b, Vm.16b,
    /// Va.16b`) — FEAT_SHA3.
    enum CryptoSHA3FourKind: String, Equatable, CaseIterable {
        case eor3, bcax

        /// The 2-bit `Op0` field at [23:21] (only [22:21] vary).
        var op0: UInt32 {
            switch self {
            case .eor3: return 0b00
            case .bcax: return 0b01
            }
        }

        static func decode(op0: UInt32) -> CryptoSHA3FourKind? {
            allCases.first { $0.op0 == op0 }
        }
    }

    /// Advanced SIMD dot-product instructions (`Vd.2s/4s, Vn.8b/16b, Vm...`),
    /// in both the vector and indexed-element forms.
    enum VectorDotProductKind: String, Equatable, CaseIterable {
        case sdot, udot

        /// The `U` bit at [29].
        var u: UInt32 {
            switch self {
            case .sdot: return 0
            case .udot: return 1
            }
        }

        static func decode(u: UInt32) -> VectorDotProductKind? {
            allCases.first { $0.u == u }
        }
    }

    /// Advanced SIMD mixed-sign dot product (FEAT_I8MM): `usdot` (vector and
    /// by-element forms) and `sudot` (by-element form only).
    enum VectorMixedDotProductKind: String, Equatable, CaseIterable {
        case usdot, sudot
    }

    /// Advanced SIMD Int8 matrix multiply-accumulate (FEAT_I8MM): `smmla`,
    /// `ummla`, `usmmla`. Destination is always `.4s`, sources `.16b`.
    enum VectorMatrixMultiplyKind: String, Equatable, CaseIterable {
        case smmla, ummla, usmmla

        /// The `U` bit at [29].
        var u: UInt32 { self == .ummla ? 1 : 0 }
        /// The `B` bit at [11] (distinguishes usmmla from smmla).
        var b: UInt32 { self == .usmmla ? 1 : 0 }
    }

    /// Advanced SIMD three-same-extra saturating rounding multiply-accumulate
    /// instructions (ARMv8.1): the non-indexed `Vd, Vn, Vm` forms. The indexed
    /// forms reuse `VectorIndexedKind`.
    enum VectorThreeSameExtraKind: String, Equatable, CaseIterable {
        case sqrdmlah, sqrdmlsh

        /// The 4-bit `opcode` at [14:11] (`U` is always 1, bits 15 and 10 are 1).
        var opcode: UInt32 {
            switch self {
            case .sqrdmlah: return 0b0000
            case .sqrdmlsh: return 0b0001
            }
        }

        static func decode(opcode: UInt32) -> VectorThreeSameExtraKind? {
            allCases.first { $0.opcode == opcode }
        }
    }

    /// Advanced SIMD FP16→FP32 widening multiply-accumulate (FEAT_FHM):
    /// `fmlal`/`fmlal2`/`fmlsl`/`fmlsl2`, in both the vector and
    /// indexed-element forms. The destination is `.2s`/`.4s`, the sources
    /// `.2h`/`.4h` (vector) or `Vm.h[index]` (indexed).
    enum VectorFPMultiplyLongKind: String, Equatable, CaseIterable {
        case fmlal, fmlal2, fmlsl, fmlsl2

        /// Selects the upper half of the FP16 source elements; also the `U`
        /// bit at [29] (the "2" suffix forms).
        var upper: UInt32 {
            switch self {
            case .fmlal2, .fmlsl2: return 1
            case .fmlal, .fmlsl: return 0
            }
        }

        /// Subtract (multiply-subtract) rather than add.
        var sub: UInt32 {
            switch self {
            case .fmlsl, .fmlsl2: return 1
            case .fmlal, .fmlal2: return 0
            }
        }

        static func decode(upper: UInt32, sub: UInt32) -> VectorFPMultiplyLongKind {
            switch (upper, sub) {
            case (0, 0): return .fmlal
            case (0, _): return .fmlsl
            case (_, 0): return .fmlal2
            default: return .fmlsl2
            }
        }
    }

    enum VectorTwoRegisterMiscKind: String, Equatable {
        case rev64, rev32, rev16
        case abs, neg, mvn, rbit, cnt, cls, clz
        case sqabs, sqneg
        case suqadd, usqadd
        case fabs, fneg, fsqrt
        case frint32z, frint32x, frint64z, frint64x
    }

    /// Advanced SIMD "three same" instructions (`Vd.T, Vn.T, Vm.T`).
    ///
    /// Covers the integer opcode-table group, the size-selected logical group
    /// (`and`/`bic`/`orr`/`orn`/`eor`/`bsl`/`bit`/`bif`), and the
    /// single/double-precision floating-point group.
    enum VectorThreeSameKind: String, Equatable, CaseIterable {
        // Integer opcode-table group.
        case shadd, uhadd, sqadd, uqadd, srhadd, urhadd
        case shsub, uhsub, sqsub, uqsub
        case cmgt, cmhi, cmge, cmhs
        case sshl, ushl, sqshl, uqshl, srshl, urshl, sqrshl, uqrshl
        case smax, umax, smin, umin
        case sabd, uabd, saba, uaba
        case add, sub, cmtst, cmeq
        case mla, mls, mul, pmul
        case smaxp, umaxp, sminp, uminp
        case sqdmulh, sqrdmulh, addp
        // Size-selected logical group (`.8b`/`.16b` only).
        case and, bic, orr, orn, eor, bsl, bit, bif
        // Floating-point group (`.2s`/`.4s`/`.2d`).
        case fmaxnm, fmla, fadd, fmulx, fcmeq, fmax, frecps
        case fminnm, fmls, fsub, fmin, frsqrts
        case fmaxnmp, faddp, fmul, fcmge, facge, fmaxp, fdiv
        case fminnmp, fabd, fcmgt, facgt, fminp

        enum Family: Equatable { case integer, logical, floatingPoint }

        /// Encoding metadata: which sub-encoding, the `U` bit, the 5-bit
        /// `opcode`, and a `variant` (FP `a` bit at [23], or the logical group's
        /// `size` selector at [23:22]; unused for the integer group).
        var spec: (family: Family, u: UInt32, opcode: UInt32, variant: UInt32) {
            switch self {
            case .shadd: return (.integer, 0, 0b00000, 0)
            case .uhadd: return (.integer, 1, 0b00000, 0)
            case .sqadd: return (.integer, 0, 0b00001, 0)
            case .uqadd: return (.integer, 1, 0b00001, 0)
            case .srhadd: return (.integer, 0, 0b00010, 0)
            case .urhadd: return (.integer, 1, 0b00010, 0)
            case .shsub: return (.integer, 0, 0b00100, 0)
            case .uhsub: return (.integer, 1, 0b00100, 0)
            case .sqsub: return (.integer, 0, 0b00101, 0)
            case .uqsub: return (.integer, 1, 0b00101, 0)
            case .cmgt: return (.integer, 0, 0b00110, 0)
            case .cmhi: return (.integer, 1, 0b00110, 0)
            case .cmge: return (.integer, 0, 0b00111, 0)
            case .cmhs: return (.integer, 1, 0b00111, 0)
            case .sshl: return (.integer, 0, 0b01000, 0)
            case .ushl: return (.integer, 1, 0b01000, 0)
            case .sqshl: return (.integer, 0, 0b01001, 0)
            case .uqshl: return (.integer, 1, 0b01001, 0)
            case .srshl: return (.integer, 0, 0b01010, 0)
            case .urshl: return (.integer, 1, 0b01010, 0)
            case .sqrshl: return (.integer, 0, 0b01011, 0)
            case .uqrshl: return (.integer, 1, 0b01011, 0)
            case .smax: return (.integer, 0, 0b01100, 0)
            case .umax: return (.integer, 1, 0b01100, 0)
            case .smin: return (.integer, 0, 0b01101, 0)
            case .umin: return (.integer, 1, 0b01101, 0)
            case .sabd: return (.integer, 0, 0b01110, 0)
            case .uabd: return (.integer, 1, 0b01110, 0)
            case .saba: return (.integer, 0, 0b01111, 0)
            case .uaba: return (.integer, 1, 0b01111, 0)
            case .add: return (.integer, 0, 0b10000, 0)
            case .sub: return (.integer, 1, 0b10000, 0)
            case .cmtst: return (.integer, 0, 0b10001, 0)
            case .cmeq: return (.integer, 1, 0b10001, 0)
            case .mla: return (.integer, 0, 0b10010, 0)
            case .mls: return (.integer, 1, 0b10010, 0)
            case .mul: return (.integer, 0, 0b10011, 0)
            case .pmul: return (.integer, 1, 0b10011, 0)
            case .smaxp: return (.integer, 0, 0b10100, 0)
            case .umaxp: return (.integer, 1, 0b10100, 0)
            case .sminp: return (.integer, 0, 0b10101, 0)
            case .uminp: return (.integer, 1, 0b10101, 0)
            case .sqdmulh: return (.integer, 0, 0b10110, 0)
            case .sqrdmulh: return (.integer, 1, 0b10110, 0)
            case .addp: return (.integer, 0, 0b10111, 0)
            case .and: return (.logical, 0, 0b00011, 0b00)
            case .bic: return (.logical, 0, 0b00011, 0b01)
            case .orr: return (.logical, 0, 0b00011, 0b10)
            case .orn: return (.logical, 0, 0b00011, 0b11)
            case .eor: return (.logical, 1, 0b00011, 0b00)
            case .bsl: return (.logical, 1, 0b00011, 0b01)
            case .bit: return (.logical, 1, 0b00011, 0b10)
            case .bif: return (.logical, 1, 0b00011, 0b11)
            case .fmaxnm: return (.floatingPoint, 0, 0b11000, 0)
            case .fmla: return (.floatingPoint, 0, 0b11001, 0)
            case .fadd: return (.floatingPoint, 0, 0b11010, 0)
            case .fmulx: return (.floatingPoint, 0, 0b11011, 0)
            case .fcmeq: return (.floatingPoint, 0, 0b11100, 0)
            case .fmax: return (.floatingPoint, 0, 0b11110, 0)
            case .frecps: return (.floatingPoint, 0, 0b11111, 0)
            case .fminnm: return (.floatingPoint, 0, 0b11000, 1)
            case .fmls: return (.floatingPoint, 0, 0b11001, 1)
            case .fsub: return (.floatingPoint, 0, 0b11010, 1)
            case .fmin: return (.floatingPoint, 0, 0b11110, 1)
            case .frsqrts: return (.floatingPoint, 0, 0b11111, 1)
            case .fmaxnmp: return (.floatingPoint, 1, 0b11000, 0)
            case .faddp: return (.floatingPoint, 1, 0b11010, 0)
            case .fmul: return (.floatingPoint, 1, 0b11011, 0)
            case .fcmge: return (.floatingPoint, 1, 0b11100, 0)
            case .facge: return (.floatingPoint, 1, 0b11101, 0)
            case .fmaxp: return (.floatingPoint, 1, 0b11110, 0)
            case .fdiv: return (.floatingPoint, 1, 0b11111, 0)
            case .fminnmp: return (.floatingPoint, 1, 0b11000, 1)
            case .fabd: return (.floatingPoint, 1, 0b11010, 1)
            case .fcmgt: return (.floatingPoint, 1, 0b11100, 1)
            case .facgt: return (.floatingPoint, 1, 0b11101, 1)
            case .fminp: return (.floatingPoint, 1, 0b11110, 1)
            }
        }

        /// The arrangements accepted by this instruction (empirically matched to clang).
        var allowedArrangements: Set<VectorArrangement> {
            switch self {
            case .and, .bic, .orr, .orn, .eor, .bsl, .bit, .bif, .pmul:
                return [.b8, .b16]
            case .sqdmulh, .sqrdmulh:
                return [.h4, .h8, .s2, .s4]
            case .shadd, .uhadd, .srhadd, .urhadd, .shsub, .uhsub,
                 .smax, .umax, .smin, .umin, .sabd, .uabd, .saba, .uaba,
                 .mla, .mls, .mul, .smaxp, .umaxp, .sminp, .uminp:
                return [.b8, .b16, .h4, .h8, .s2, .s4]
            case .sqadd, .uqadd, .sqsub, .uqsub, .cmgt, .cmhi, .cmge, .cmhs,
                 .sshl, .ushl, .sqshl, .uqshl, .srshl, .urshl, .sqrshl, .uqrshl,
                 .add, .sub, .cmtst, .cmeq, .addp:
                return [.b8, .b16, .h4, .h8, .s2, .s4, .d2]
            case .fmaxnm, .fmla, .fadd, .fmulx, .fcmeq, .fmax, .frecps,
                 .fminnm, .fmls, .fsub, .fmin, .frsqrts,
                 .fmaxnmp, .faddp, .fmul, .fcmge, .facge, .fmaxp, .fdiv,
                 .fminnmp, .fabd, .fcmgt, .facgt, .fminp:
                // `.4h`/`.8h` use the separate three-same (FP16) encoding.
                return [.h4, .h8, .s2, .s4, .d2]
            }
        }
    }

    /// Advanced SIMD "shift by immediate" instructions.
    ///
    /// Covers same-arrangement shifts, narrowing shifts (`Vd.Tb, Vn.Ta`),
    /// widening shifts (`Vd.Ta, Vn.Tb`), and vector fixed-point conversions.
    enum VectorShiftImmediateKind: String, Equatable, CaseIterable {
        // Same-arrangement right shifts.
        case sshr, ushr, ssra, usra, srshr, urshr, srsra, ursra, sri
        // Same-arrangement left shifts.
        case shl, sli, sqshlu, sqshl, uqshl
        // Narrowing right shifts (`Vd.Tb, Vn.Ta`, Ta = 2× element of Tb).
        case shrn, rshrn, sqshrn, sqrshrn, sqshrun, sqrshrun, uqshrn, uqrshrn
        // Widening left shifts (`Vd.Ta, Vn.Tb`).
        case sshll, ushll
        // Vector fixed-point conversions.
        case scvtf, ucvtf, fcvtzs, fcvtzu

        enum Category: Equatable {
            /// `immhimmb = 2*esize - shift` on a single arrangement.
            case sameRight
            /// `immhimmb = esize + shift` on a single arrangement.
            case sameLeft
            /// Narrowing: destination element is half the source element.
            case narrow
            /// Widening: destination element is twice the source element.
            case widen
            /// Fixed-point convert: `immhimmb = 2*esize - fbits`.
            case convert
        }

        var spec: (category: Category, u: UInt32, opcode: UInt32) {
            switch self {
            case .sshr: return (.sameRight, 0, 0b00000)
            case .ushr: return (.sameRight, 1, 0b00000)
            case .ssra: return (.sameRight, 0, 0b00010)
            case .usra: return (.sameRight, 1, 0b00010)
            case .srshr: return (.sameRight, 0, 0b00100)
            case .urshr: return (.sameRight, 1, 0b00100)
            case .srsra: return (.sameRight, 0, 0b00110)
            case .ursra: return (.sameRight, 1, 0b00110)
            case .sri: return (.sameRight, 1, 0b01000)
            case .shl: return (.sameLeft, 0, 0b01010)
            case .sli: return (.sameLeft, 1, 0b01010)
            case .sqshlu: return (.sameLeft, 1, 0b01100)
            case .sqshl: return (.sameLeft, 0, 0b01110)
            case .uqshl: return (.sameLeft, 1, 0b01110)
            case .shrn: return (.narrow, 0, 0b10000)
            case .sqshrun: return (.narrow, 1, 0b10000)
            case .rshrn: return (.narrow, 0, 0b10001)
            case .sqrshrun: return (.narrow, 1, 0b10001)
            case .sqshrn: return (.narrow, 0, 0b10010)
            case .uqshrn: return (.narrow, 1, 0b10010)
            case .sqrshrn: return (.narrow, 0, 0b10011)
            case .uqrshrn: return (.narrow, 1, 0b10011)
            case .sshll: return (.widen, 0, 0b10100)
            case .ushll: return (.widen, 1, 0b10100)
            case .scvtf: return (.convert, 0, 0b11100)
            case .ucvtf: return (.convert, 1, 0b11100)
            case .fcvtzs: return (.convert, 0, 0b11111)
            case .fcvtzu: return (.convert, 1, 0b11111)
            }
        }
    }

    enum VectorModifiedImmediateKind: String, Equatable {
        case movi, mvni, orr, bic, fmov
    }

    /// A single addressed lane of a vector register, e.g. `v1.s[2]`.
    struct VectorElement: Equatable {
        var number: UInt32
        var width: VectorElementWidth
        var index: Int

        var encodedNumber: UInt32 { number & 0x1f }
    }

    enum VectorElementWidth: String, Equatable {
        case b, h, s, d

        /// `log2` of the element size in bytes (B=0, H=1, S=2, D=3).
        var sizeShift: UInt32 {
            switch self {
            case .b: return 0
            case .h: return 1
            case .s: return 2
            case .d: return 3
            }
        }

        var bitWidth: Int { 8 << sizeShift }

        /// The largest valid lane index for a 128-bit register.
        var maxIndex: Int { (128 / bitWidth) - 1 }

        /// The `imm5` selector field for `index` (low set bit marks the size).
        func imm5(index: Int) -> UInt32 {
            (UInt32(index) << (sizeShift + 1)) | (1 << sizeShift)
        }
    }

    /// Advanced SIMD "permute" instructions (`Vd.T, Vn.T, Vm.T`).
    enum VectorPermuteKind: String, Equatable, CaseIterable {
        case uzp1, trn1, zip1, uzp2, trn2, zip2

        /// The `opcode` field at bits[14:12].
        var opcode: UInt32 {
            switch self {
            case .uzp1: return 0b001
            case .trn1: return 0b010
            case .zip1: return 0b011
            case .uzp2: return 0b101
            case .trn2: return 0b110
            case .zip2: return 0b111
            }
        }
    }

    /// Advanced SIMD "three different" instructions.
    ///
    /// `long` forms widen both sources (`Vd.Ta, Vn.Tb, Vm.Tb`); `wide` forms
    /// widen only the second source (`Vd.Ta, Vn.Ta, Vm.Tb`); `narrow` forms
    /// produce a half-width result (`Vd.Tb, Vn.Ta, Vm.Ta`). In every form the
    /// `size`/`Q` fields come from the narrow operand.
    enum VectorThreeDifferentKind: String, Equatable, CaseIterable {
        case saddl, saddw, ssubl, ssubw, addhn, sabal, subhn, sabdl,
             smlal, sqdmlal, smlsl, sqdmlsl, smull, sqdmull, pmull,
             uaddl, uaddw, usubl, usubw, raddhn, uabal, rsubhn, uabdl,
             umlal, umlsl, umull

        enum Form { case long, wide, narrow }

        var spec: (form: Form, u: UInt32, opcode: UInt32) {
            switch self {
            case .saddl: return (.long, 0, 0b0000)
            case .saddw: return (.wide, 0, 0b0001)
            case .ssubl: return (.long, 0, 0b0010)
            case .ssubw: return (.wide, 0, 0b0011)
            case .addhn: return (.narrow, 0, 0b0100)
            case .sabal: return (.long, 0, 0b0101)
            case .subhn: return (.narrow, 0, 0b0110)
            case .sabdl: return (.long, 0, 0b0111)
            case .smlal: return (.long, 0, 0b1000)
            case .sqdmlal: return (.long, 0, 0b1001)
            case .smlsl: return (.long, 0, 0b1010)
            case .sqdmlsl: return (.long, 0, 0b1011)
            case .smull: return (.long, 0, 0b1100)
            case .sqdmull: return (.long, 0, 0b1101)
            case .pmull: return (.long, 0, 0b1110)
            case .uaddl: return (.long, 1, 0b0000)
            case .uaddw: return (.wide, 1, 0b0001)
            case .usubl: return (.long, 1, 0b0010)
            case .usubw: return (.wide, 1, 0b0011)
            case .raddhn: return (.narrow, 1, 0b0100)
            case .uabal: return (.long, 1, 0b0101)
            case .rsubhn: return (.narrow, 1, 0b0110)
            case .uabdl: return (.long, 1, 0b0111)
            case .umlal: return (.long, 1, 0b1000)
            case .umlsl: return (.long, 1, 0b1010)
            case .umull: return (.long, 1, 0b1100)
            }
        }
    }

    /// Advanced SIMD "vector x indexed element" instructions.
    ///
    /// `same` forms keep the element size (`Vd.T, Vn.T, Vm.Ts[i]`); `fp`
    /// forms are the floating-point equivalents; `long` forms widen the
    /// result (`Vd.Ta, Vn.Tb, Vm.Ts[i]`, with a `2` upper-half variant).
    enum VectorIndexedKind: String, Equatable, CaseIterable {
        case mul, mla, mls, sqdmulh, sqrdmulh, sqrdmlah, sqrdmlsh
        case fmul, fmla, fmls, fmulx
        case smull, umull, smlal, umlal, smlsl, umlsl, sqdmull, sqdmlal, sqdmlsl

        enum Form { case same, fp, long }

        var spec: (form: Form, u: UInt32, opcode: UInt32) {
            switch self {
            case .mla: return (.same, 1, 0b0000)
            case .mls: return (.same, 1, 0b0100)
            case .mul: return (.same, 0, 0b1000)
            case .sqdmulh: return (.same, 0, 0b1100)
            case .sqrdmulh: return (.same, 0, 0b1101)
            case .sqrdmlah: return (.same, 1, 0b1101)
            case .sqrdmlsh: return (.same, 1, 0b1111)
            case .fmla: return (.fp, 0, 0b0001)
            case .fmls: return (.fp, 0, 0b0101)
            case .fmul: return (.fp, 0, 0b1001)
            case .fmulx: return (.fp, 1, 0b1001)
            case .smlal: return (.long, 0, 0b0010)
            case .umlal: return (.long, 1, 0b0010)
            case .smlsl: return (.long, 0, 0b0110)
            case .umlsl: return (.long, 1, 0b0110)
            case .smull: return (.long, 0, 0b1010)
            case .umull: return (.long, 1, 0b1010)
            case .sqdmlal: return (.long, 0, 0b0011)
            case .sqdmlsl: return (.long, 0, 0b0111)
            case .sqdmull: return (.long, 0, 0b1011)
            }
        }
    }

    /// Advanced SIMD scalar three-same instructions (`Vd, Vn, Vm` on scalar FP registers).
    enum ScalarThreeSameKind: String, Equatable, CaseIterable {
        case add, sub, cmeq, cmge, cmgt, cmhi, cmhs, cmtst
        case sqadd, uqadd, sqsub, uqsub
        case sshl, ushl, srshl, urshl, sqshl, uqshl, sqrshl, uqrshl
        case sqdmulh, sqrdmulh

        /// Which scalar element widths an instruction permits.
        enum SizeClass { case doubleOnly, anySize, halfSingle }

        var spec: (u: UInt32, opcode: UInt32, size: SizeClass) {
            switch self {
            case .add:      return (0, 0b10000, .doubleOnly)
            case .sub:      return (1, 0b10000, .doubleOnly)
            case .cmeq:     return (1, 0b10001, .doubleOnly)
            case .cmtst:    return (0, 0b10001, .doubleOnly)
            case .cmge:     return (0, 0b00111, .doubleOnly)
            case .cmhs:     return (1, 0b00111, .doubleOnly)
            case .cmgt:     return (0, 0b00110, .doubleOnly)
            case .cmhi:     return (1, 0b00110, .doubleOnly)
            case .sshl:     return (0, 0b01000, .doubleOnly)
            case .ushl:     return (1, 0b01000, .doubleOnly)
            case .srshl:    return (0, 0b01010, .doubleOnly)
            case .urshl:    return (1, 0b01010, .doubleOnly)
            case .sqadd:    return (0, 0b00001, .anySize)
            case .uqadd:    return (1, 0b00001, .anySize)
            case .sqsub:    return (0, 0b00101, .anySize)
            case .uqsub:    return (1, 0b00101, .anySize)
            case .sqshl:    return (0, 0b01001, .anySize)
            case .uqshl:    return (1, 0b01001, .anySize)
            case .sqrshl:   return (0, 0b01011, .anySize)
            case .uqrshl:   return (1, 0b01011, .anySize)
            case .sqdmulh:  return (0, 0b10110, .halfSingle)
            case .sqrdmulh: return (1, 0b10110, .halfSingle)
            }
        }
    }

    /// Advanced SIMD scalar shift by immediate (`Vd, Vn, #shift`, double-width forms).
    enum ScalarShiftImmediateKind: String, Equatable, CaseIterable {
        case sshr, ushr, ssra, usra, srshr, urshr, srsra, ursra, sri   // right shifts
        case shl, sli, sqshl, uqshl, sqshlu                            // left shifts

        var spec: (u: UInt32, opcode: UInt32, isLeft: Bool) {
            switch self {
            case .sshr:   return (0, 0b00000, false)
            case .ushr:   return (1, 0b00000, false)
            case .ssra:   return (0, 0b00010, false)
            case .usra:   return (1, 0b00010, false)
            case .srshr:  return (0, 0b00100, false)
            case .urshr:  return (1, 0b00100, false)
            case .srsra:  return (0, 0b00110, false)
            case .ursra:  return (1, 0b00110, false)
            case .sri:    return (1, 0b01000, false)
            case .shl:    return (0, 0b01010, true)
            case .sli:    return (1, 0b01010, true)
            case .sqshl:  return (0, 0b01110, true)
            case .uqshl:  return (1, 0b01110, true)
            case .sqshlu: return (1, 0b01100, true)
            }
        }
    }

    /// Advanced SIMD scalar shift by immediate, narrowing (`Vd, Vn, #shift` — the
    /// destination is one element size narrower than the source).
    enum ScalarShiftNarrowKind: String, Equatable, CaseIterable {
        case sqshrun, sqrshrun, sqshrn, sqrshrn, uqshrn, uqrshrn

        var spec: (u: UInt32, opcode: UInt32) {
            switch self {
            case .sqshrun:  return (1, 0b10000)
            case .sqrshrun: return (1, 0b10001)
            case .sqshrn:   return (0, 0b10010)
            case .sqrshrn:  return (0, 0b10011)
            case .uqshrn:   return (1, 0b10010)
            case .uqrshrn:  return (1, 0b10011)
            }
        }
    }

    /// Advanced SIMD scalar shift by immediate, fixed-point convert
    /// (`Vd, Vn, #fbits` — convert between floating-point and fixed-point, scalar form).
    enum ScalarShiftFixedPointKind: String, Equatable, CaseIterable {
        case scvtf, ucvtf, fcvtzs, fcvtzu

        var spec: (u: UInt32, opcode: UInt32) {
            switch self {
            case .scvtf:  return (0, 0b11100)
            case .ucvtf:  return (1, 0b11100)
            case .fcvtzs: return (0, 0b11111)
            case .fcvtzu: return (1, 0b11111)
            }
        }
    }

    /// Advanced SIMD scalar three different (`Vd, Vn, Vm` — long, saturating doubling).
    enum ScalarThreeDifferentKind: String, Equatable, CaseIterable {
        case sqdmlal, sqdmlsl, sqdmull

        var opcode: UInt32 {
            switch self {
            case .sqdmlal: return 0b1001
            case .sqdmlsl: return 0b1011
            case .sqdmull: return 0b1101
            }
        }
    }

    /// Advanced SIMD scalar two-register misc, narrowing (`Vd, Vn` — the destination is
    /// one element size narrower than the source: saturating extract-narrow).
    enum ScalarTwoRegisterMiscNarrowKind: String, Equatable, CaseIterable {
        case sqxtun, sqxtn, uqxtn

        var spec: (u: UInt32, opcode: UInt32) {
            switch self {
            case .sqxtun: return (1, 0b10010)
            case .sqxtn:  return (0, 0b10100)
            case .uqxtn:  return (1, 0b10100)
            }
        }
    }

    /// Advanced SIMD scalar floating-point three-same (`Vd, Vn, Vm` on scalar FP registers).
    enum ScalarThreeSameFPKind: String, Equatable, CaseIterable {
        case fmulx, fcmeq, fcmge, fcmgt, facge, facgt, frecps, frsqrts, fabd

        var spec: (u: UInt32, hi: UInt32, opcode: UInt32) {
            switch self {
            case .fmulx:   return (0, 0, 0b11011)
            case .fcmeq:   return (0, 0, 0b11100)
            case .fcmge:   return (1, 0, 0b11100)
            case .fcmgt:   return (1, 1, 0b11100)
            case .facge:   return (1, 0, 0b11101)
            case .facgt:   return (1, 1, 0b11101)
            case .frecps:  return (0, 0, 0b11111)
            case .frsqrts: return (0, 1, 0b11111)
            case .fabd:    return (1, 1, 0b11010)
            }
        }
    }

    /// Advanced SIMD scalar floating-point two-register misc (FP converts, reciprocal
    /// estimates, the `fcvtxn` narrow, and the compare-against-`#0.0` forms).
    enum ScalarFPTwoRegisterMiscKind: String, Equatable, CaseIterable {
        case fcvtns, fcvtnu, fcvtms, fcvtmu, fcvtas, fcvtau, scvtf, ucvtf
        case fcvtps, fcvtpu, fcvtzs, fcvtzu, frecpe, frsqrte, frecpx
        case fcvtxn
        case fcmgt, fcmge, fcmeq, fcmle, fcmlt   // compared against #0.0

        enum Category { case convert, narrow, compareZero }

        var spec: (u: UInt32, hi: UInt32, opcode: UInt32, category: Category) {
            switch self {
            case .fcvtns:  return (0, 0, 0b11010, .convert)
            case .fcvtnu:  return (1, 0, 0b11010, .convert)
            case .fcvtms:  return (0, 0, 0b11011, .convert)
            case .fcvtmu:  return (1, 0, 0b11011, .convert)
            case .fcvtas:  return (0, 0, 0b11100, .convert)
            case .fcvtau:  return (1, 0, 0b11100, .convert)
            case .scvtf:   return (0, 0, 0b11101, .convert)
            case .ucvtf:   return (1, 0, 0b11101, .convert)
            case .fcvtps:  return (0, 1, 0b11010, .convert)
            case .fcvtpu:  return (1, 1, 0b11010, .convert)
            case .fcvtzs:  return (0, 1, 0b11011, .convert)
            case .fcvtzu:  return (1, 1, 0b11011, .convert)
            case .frecpe:  return (0, 1, 0b11101, .convert)
            case .frsqrte: return (1, 1, 0b11101, .convert)
            case .frecpx:  return (0, 1, 0b11111, .convert)
            case .fcvtxn:  return (1, 0, 0b10110, .narrow)
            case .fcmgt:   return (0, 1, 0b01100, .compareZero)
            case .fcmge:   return (1, 1, 0b01100, .compareZero)
            case .fcmeq:   return (0, 1, 0b01101, .compareZero)
            case .fcmle:   return (1, 1, 0b01101, .compareZero)
            case .fcmlt:   return (0, 1, 0b01110, .compareZero)
            }
        }
    }

    /// Advanced SIMD scalar two-register misc (`Vd, Vn`, plus the compare-against-`#0` forms).
    enum ScalarTwoRegisterMiscKind: String, Equatable, CaseIterable {
        case abs, neg, sqabs, sqneg, suqadd, usqadd
        case cmgt, cmge, cmeq, cmle, cmlt   // compared against #0

        enum SizeClass { case doubleOnly, anySize }

        var spec: (u: UInt32, opcode: UInt32, size: SizeClass, comparesZero: Bool) {
            switch self {
            case .abs:    return (0, 0b01011, .doubleOnly, false)
            case .neg:    return (1, 0b01011, .doubleOnly, false)
            case .sqabs:  return (0, 0b00111, .anySize, false)
            case .sqneg:  return (1, 0b00111, .anySize, false)
            case .suqadd: return (0, 0b00011, .anySize, false)
            case .usqadd: return (1, 0b00011, .anySize, false)
            case .cmgt:   return (0, 0b01000, .doubleOnly, true)
            case .cmge:   return (1, 0b01000, .doubleOnly, true)
            case .cmeq:   return (0, 0b01001, .doubleOnly, true)
            case .cmle:   return (1, 0b01001, .doubleOnly, true)
            case .cmlt:   return (0, 0b01010, .doubleOnly, true)
            }
        }
    }

    /// Advanced SIMD scalar pairwise reductions (`Vd, Vn.T`).
    enum ScalarPairwiseKind: String, Equatable, CaseIterable {
        case addp, faddp, fmaxp, fminp, fmaxnmp, fminnmp

        var spec: (u: UInt32, fp: Bool, o1: UInt32, opcode: UInt32) {
            switch self {
            case .addp:    return (0, false, 0, 0b11011)
            case .faddp:   return (1, true,  0, 0b01101)
            case .fmaxp:   return (1, true,  0, 0b01111)
            case .fminp:   return (1, true,  1, 0b01111)
            case .fmaxnmp: return (1, true,  0, 0b01100)
            case .fminnmp: return (1, true,  1, 0b01100)
            }
        }
    }

    /// The optional shift applied to a vector modified-immediate byte.
    enum VectorImmediateShift: Equatable {
        case none
        case lsl(Int)   // 0, 8, 16, or 24
        case msl(Int)   // 8 or 16 (shifting ones in)
    }

    enum MoveAliasSource: Equatable {
        case immediate(Int64)
        case register(Register)
    }

    enum AddSubOperand: Equatable {
        case immediate(Int64, shift: Int?)
        case shiftedRegister(Register, shift: Shift?)
        case extendedRegister(Register, extend: ExtendKind, amount: Int?)
    }

    enum LogicalOperand: Equatable {
        case immediate(Int64)
        case shiftedRegister(Register, shift: Shift?)
    }

    enum ExtractOperand: Equatable {
        case extract(Register, amount: Int64)
        case rotate(amount: Int64)
    }

    enum Instruction: Equatable {
        case nop
        case branchRegister(BranchRegisterKind, Register)
        case unconditionalBranch(link: Bool, offset: Int64)
        case conditionalBranch(Condition, offset: Int64)
        case compareAndBranch(nonzero: Bool, Register, offset: Int64)
        case testAndBranch(nonzero: Bool, Register, bit: Int64, offset: Int64)
        case address(page: Bool, Register, offset: Int64)
        case exception(ExceptionKind, immediate: Int64)
        case exceptionReturn
        case barrier(BarrierKind, option: UInt32)
        case hint(UInt32)
        case loadStoreExclusive(LoadStoreExclusiveKind, status: Register?, value: Register, value2: Register?, base: Register)
        case compareAndSwap(CompareAndSwapKind, compare: Register, value: Register, base: Register)
        case compareAndSwapPair(CompareAndSwapPairKind, compare: Register, value: Register, base: Register)
        case atomicMemory(AtomicMemoryKind, source: Register, value: Register?, base: Register)
        case loadAcquireRCpc(LoadAcquireRCpcKind, value: Register, base: Register)
        /// RCpc load/store with an unscaled immediate offset (`LDAPUR`/`STLUR`).
        case rcpcUnscaled(RCpcUnscaledKind, target: Register, base: Register, offset: Int64)
        case clearExclusive(UInt32)
        case prefetch(PrefetchKind, operation: UInt32, memory: MemoryOperand)
        /// Move to/from a system register (`MRS Xt, sysreg` / `MSR sysreg, Xt`).
        case systemRegisterMove(read: Bool, register: SystemRegister, value: Register)
        /// Write a PSTATE field with an immediate (`MSR <field>, #imm`).
        case pstate(PStateField, immediate: UInt32)
        /// A no-operand PSTATE flag manipulation instruction.
        case pstateFlag(PStateFlagKind)
        /// A system instruction (`SYS`/`SYSL` and the `DC`/`IC`/`AT`/`TLBI` aliases).
        case systemInstruction(read: Bool, op1: UInt32, crn: UInt32, crm: UInt32, op2: UInt32, register: Register?)
        case moveAlias(destination: Register, source: MoveAliasSource)
        case moveWide(MoveWideKind, destination: Register, immediate: Int64, shift: Int?)
        case addSub(AddSubKind, destination: Register, first: Register, operand: AddSubOperand)
        case compareAlias(CompareAliasKind, first: Register, operand: AddSubOperand)
        case logical(LogicalKind, destination: Register, first: Register, operand: LogicalOperand)
        case mvnAlias(destination: Register, source: Register, shift: Shift?)
        case shiftAlias(ShiftAliasKind, destination: Register, source: Register, amount: Int64)
        case extractOrRotateAlias(ExtractKind, destination: Register, first: Register, operand: ExtractOperand)
        case multiply(MultiplyKind, destination: Register, first: Register, second: Register, accumulator: Register?)
        case divide(DivideKind, destination: Register, first: Register, second: Register)
        case addSubCarry(AddSubCarryKind, destination: Register, first: Register, second: Register)
        case multiplyWide(MultiplyWideKind, destination: Register, first: Register, second: Register, accumulator: Register?)
        case bitfield(BitfieldKind, destination: Register, source: Register, immr: UInt32, imms: UInt32)
        case dataProcessingOneSource(DataProcessingOneSourceKind, destination: Register, source: Register)
        case crc32(CRC32Kind, destination: Register, first: Register, data: Register)
        case conditionalSelect(ConditionalSelectKind, destination: Register, first: Register, second: Register, condition: Condition)
        case conditionalCompare(ConditionalCompareKind, first: Register, second: ConditionalCompareOperand, nzcv: UInt32, condition: Condition)
        case conditionalSet(ConditionalSetKind, destination: Register, condition: Condition)
        case conditionalSelectAlias(ConditionalSelectAliasKind, destination: Register, source: Register, condition: Condition)
        case loadStoreSingle(LoadStoreSingleKind, target: Register, memory: MemoryOperand)
        case loadStorePair(LoadStorePairKind, first: Register, second: Register, memory: MemoryOperand)
        case loadStoreSingleFP(LoadStoreSingleKind, target: FPRegister, memory: MemoryOperand)
        case loadStorePairFP(LoadStorePairKind, first: FPRegister, second: FPRegister, memory: MemoryOperand)
        case loadStoreMultiple(LoadStoreMultipleKind, registers: VectorRegisterList, address: VectorMemoryOperand)
        case loadStoreSingleLane(LoadStoreMultipleKind, registers: VectorLaneList, address: VectorMemoryOperand)
        case loadStoreReplicate(LoadStoreReplicateKind, registers: VectorRegisterList, address: VectorMemoryOperand)
        case pointerAuthentication(PointerAuthenticationKind, register: Register?, architecture: ARM64Assembler.Architecture)
        case fpDataProcessing2(FPDataProcessing2Kind, destination: FPRegister, first: FPRegister, second: FPRegister)
        case fpDataProcessing1(FPDataProcessing1Kind, destination: FPRegister, source: FPRegister)
        case fpDataProcessing3(FPDataProcessing3Kind, destination: FPRegister, first: FPRegister, second: FPRegister, third: FPRegister)
        case fpCompare(FPCompareKind, first: FPRegister, second: FPCompareOperand)
        case fpConvertPrecision(destination: FPRegister, source: FPRegister)
        case fpMoveImmediate(destination: FPRegister, value: Double)
        case fpMoveToGeneral(destination: Register, source: FPRegister)
        case fpMoveFromGeneral(destination: FPRegister, source: Register)
        /// `fmov x<d>, v<n>.d[1]` — move the high 64 bits of a vector register into a general register.
        case fpMoveVectorHighToGeneral(destination: Register, source: VectorElement)
        /// `fmov v<d>.d[1], x<n>` — move a general register into the high 64 bits of a vector register.
        case fpMoveGeneralToVectorHigh(destination: VectorElement, source: Register)
        case fpConvertToInt(FPConvertToIntKind, destination: Register, source: FPRegister)
        case fpConvertFromInt(FPConvertFromIntKind, destination: FPRegister, source: Register)
        /// Scalar floating-point to fixed-point convert (`fcvtzs/fcvtzu <Wd|Xd>, <n>, #fbits`).
        case fpConvertToFixed(FPConvertToIntKind, destination: Register, source: FPRegister, fbits: UInt32)
        /// Scalar fixed-point to floating-point convert (`scvtf/ucvtf <d>, <Wn|Xn>, #fbits`).
        case fpConvertFromFixed(FPConvertFromIntKind, destination: FPRegister, source: Register, fbits: UInt32)
        /// Floating-point JavaScript Convert to Signed fixed-point (`fjcvtzs w<d>, d<n>`).
        case fjcvtzs(destination: Register, source: FPRegister)
        /// Scalar floating-point conditional select (`fcsel <d>, <n>, <m>, <cond>`).
        case fpConditionalSelect(destination: FPRegister, first: FPRegister, second: FPRegister, condition: Condition)
        /// Scalar floating-point conditional compare (`fccmp(e) <n>, <m>, #nzcv, <cond>`).
        case fpConditionalCompare(FPConditionalCompareKind, first: FPRegister, second: FPRegister, nzcv: UInt32, condition: Condition)
        case acrossLanesInteger(AcrossLanesIntegerKind, destination: FPRegister, source: VectorRegister)
        case acrossLanesFP(AcrossLanesFPKind, destination: FPRegister, source: VectorRegister)
        case vectorTwoRegisterMisc(VectorTwoRegisterMiscKind, destination: VectorRegister, source: VectorRegister)
        case vectorThreeSame(VectorThreeSameKind, destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorShiftImmediate(VectorShiftImmediateKind, destination: VectorRegister, source: VectorRegister, shift: Int)
        /// Shift-left-long by element size (`shll`/`shll2`): the shift always equals the source element width.
        case vectorShiftLeftLong(destination: VectorRegister, source: VectorRegister, shift: UInt32)
        case vectorModifiedImmediate(VectorModifiedImmediateKind, destination: VectorRegister, imm8: UInt8, shift: VectorImmediateShift)
        case vectorDuplicateElement(destination: VectorRegister, source: VectorElement)
        case vectorDuplicateGeneral(destination: VectorRegister, source: Register)
        case vectorMoveToGeneral(signed: Bool, destination: Register, source: VectorElement)
        case vectorInsertGeneral(destination: VectorElement, source: Register)
        case vectorInsertElement(destination: VectorElement, source: VectorElement)
        case vectorPermute(VectorPermuteKind, destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorExtract(destination: VectorRegister, first: VectorRegister, second: VectorRegister, index: Int)
        case vectorThreeDifferent(VectorThreeDifferentKind, destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorIndexed(VectorIndexedKind, destination: VectorRegister, first: VectorRegister, element: VectorElement)
        case vectorDotProduct(VectorDotProductKind, destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorDotProductByElement(VectorDotProductKind, destination: VectorRegister, first: VectorRegister, elementRegister: UInt32, index: UInt32)
        case vectorUSDotProduct(destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorMixedDotByElement(VectorMixedDotProductKind, destination: VectorRegister, first: VectorRegister, elementRegister: UInt32, index: UInt32)
        case vectorMatrixMultiply(VectorMatrixMultiplyKind, destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorThreeSameExtra(VectorThreeSameExtraKind, destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case scalarThreeSameExtra(VectorThreeSameExtraKind, destination: FPRegister, first: FPRegister, second: FPRegister)
        case vectorComplexAdd(destination: VectorRegister, first: VectorRegister, second: VectorRegister, rotation: Int)
        case vectorComplexMultiplyAdd(destination: VectorRegister, first: VectorRegister, second: VectorRegister, rotation: Int)
        case vectorComplexMultiplyAddByElement(destination: VectorRegister, first: VectorRegister, elementRegister: UInt32, index: UInt32, rotation: Int)
        case vectorFPMultiplyLong(VectorFPMultiplyLongKind, destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorFPMultiplyLongByElement(VectorFPMultiplyLongKind, destination: VectorRegister, first: VectorRegister, elementRegister: UInt32, index: UInt32)
        case vectorBFDot(destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorBFDotByElement(destination: VectorRegister, first: VectorRegister, elementRegister: UInt32, index: UInt32)
        case vectorBFMLAL(top: Bool, destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorBFMLALByElement(top: Bool, destination: VectorRegister, first: VectorRegister, elementRegister: UInt32, index: UInt32)
        case vectorBFMatrixMultiply(destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorBFConvertNarrow(top: Bool, destination: VectorRegister, source: VectorRegister)
        case scalarThreeSame(ScalarThreeSameKind, destination: FPRegister, first: FPRegister, second: FPRegister)
        case scalarPairwise(ScalarPairwiseKind, destination: FPRegister, source: VectorRegister)
        case scalarTwoRegisterMisc(ScalarTwoRegisterMiscKind, destination: FPRegister, source: FPRegister)
        case scalarShiftImmediate(ScalarShiftImmediateKind, destination: FPRegister, source: FPRegister, shift: Int)
        case scalarThreeDifferent(ScalarThreeDifferentKind, destination: FPRegister, first: FPRegister, second: FPRegister)
        case scalarIndexed(VectorIndexedKind, destination: FPRegister, first: FPRegister, element: VectorElement)
        case scalarCopyDuplicate(destination: FPRegister, element: VectorElement)
        case scalarFPTwoRegisterMisc(ScalarFPTwoRegisterMiscKind, destination: FPRegister, source: FPRegister)
        case scalarThreeSameFP(ScalarThreeSameFPKind, destination: FPRegister, first: FPRegister, second: FPRegister)
        case scalarShiftNarrow(ScalarShiftNarrowKind, destination: FPRegister, source: FPRegister, shift: Int)
        case scalarTwoRegisterMiscNarrow(ScalarTwoRegisterMiscNarrowKind, destination: FPRegister, source: FPRegister)
        case scalarShiftFixedPoint(ScalarShiftFixedPointKind, destination: FPRegister, source: FPRegister, fbits: Int)
        case vectorTableLookup(VectorTableLookupKind, destination: VectorRegister, table: VectorRegisterList, index: VectorRegister)
        case vectorCompareZero(VectorCompareZeroKind, destination: VectorRegister, source: VectorRegister)
        case vectorExtractNarrow(VectorExtractNarrowKind, destination: VectorRegister, source: VectorRegister)
        case vectorConvert(VectorConvertKind, destination: VectorRegister, source: VectorRegister)
        case vectorPairwiseLongAdd(VectorPairwiseLongAddKind, destination: VectorRegister, source: VectorRegister)
        case vectorRoundReciprocal(VectorRoundReciprocalKind, destination: VectorRegister, source: VectorRegister)
        case vectorFPConvertPrecision(VectorFPConvertPrecisionKind, upper: Bool, destination: VectorRegister, source: VectorRegister)
        case cryptoAES(CryptoAESKind, destination: VectorRegister, source: VectorRegister)
        case cryptoSHA3(CryptoSHA3Kind, d: UInt32, n: UInt32, m: UInt32)
        case cryptoSHA2(CryptoSHA2Kind, d: UInt32, n: UInt32)
        case cryptoSHA512(CryptoSHA512Kind, d: UInt32, n: UInt32, m: UInt32)
        case cryptoTwoReg(CryptoTwoRegKind, d: UInt32, n: UInt32)
        case cryptoSM3(CryptoSM3Kind, d: UInt32, n: UInt32, m: UInt32)
        case cryptoSM3Indexed(CryptoSM3IndexedKind, d: UInt32, n: UInt32, m: UInt32, index: UInt32)
        case cryptoSM3SS1(d: UInt32, n: UInt32, m: UInt32, a: UInt32)
        case cryptoSHA3Four(CryptoSHA3FourKind, d: UInt32, n: UInt32, m: UInt32, a: UInt32)
        case cryptoRAX1(d: UInt32, n: UInt32, m: UInt32)
        case cryptoXAR(d: UInt32, n: UInt32, m: UInt32, imm6: UInt32)
    }
}

internal typealias IntegerRegisterKind = A64.RegisterKind
internal typealias IntegerRegister = A64.Register
internal typealias FloatRegister = A64.FPRegister
internal typealias VectorRegister = A64.VectorRegister
internal typealias VectorRegisterList = A64.VectorRegisterList
internal typealias VectorMemoryOperand = A64.VectorMemoryOperand
internal typealias LoadStoreMultipleKind = A64.LoadStoreMultipleKind
internal typealias VectorLaneList = A64.VectorLaneList
internal typealias LoadStoreReplicateKind = A64.LoadStoreReplicateKind
internal typealias Condition = A64.Condition
internal typealias ShiftKind = A64.ShiftKind
internal typealias ExtendKind = A64.ExtendKind
internal typealias MemoryOperand = A64.MemoryOperand
internal typealias Instruction = A64.Instruction
internal typealias ParsedShift = A64.Shift
internal typealias VectorShiftImmediateKind = A64.VectorShiftImmediateKind
internal typealias VectorModifiedImmediateKind = A64.VectorModifiedImmediateKind
internal typealias VectorImmediateShift = A64.VectorImmediateShift
internal typealias VectorElement = A64.VectorElement
internal typealias VectorElementWidth = A64.VectorElementWidth
internal typealias VectorPermuteKind = A64.VectorPermuteKind
internal typealias VectorThreeDifferentKind = A64.VectorThreeDifferentKind
internal typealias VectorIndexedKind = A64.VectorIndexedKind
internal typealias VectorDotProductKind = A64.VectorDotProductKind
internal typealias VectorMixedDotProductKind = A64.VectorMixedDotProductKind
internal typealias VectorMatrixMultiplyKind = A64.VectorMatrixMultiplyKind
internal typealias ConditionalSelectKind = A64.ConditionalSelectKind
internal typealias ConditionalCompareKind = A64.ConditionalCompareKind
internal typealias ConditionalCompareOperand = A64.ConditionalCompareOperand
internal typealias DataProcessingOneSourceKind = A64.DataProcessingOneSourceKind
internal typealias MultiplyWideKind = A64.MultiplyWideKind
internal typealias BitfieldKind = A64.BitfieldKind
internal typealias AddSubCarryKind = A64.AddSubCarryKind
internal typealias HintKind = A64.HintKind
internal typealias LoadStoreExclusiveKind = A64.LoadStoreExclusiveKind
internal typealias CompareAndSwapKind = A64.CompareAndSwapKind
internal typealias CompareAndSwapPairKind = A64.CompareAndSwapPairKind
internal typealias AtomicMemoryKind = A64.AtomicMemoryKind
internal typealias LoadAcquireRCpcKind = A64.LoadAcquireRCpcKind
internal typealias PrefetchKind = A64.PrefetchKind
internal typealias SystemRegister = A64.SystemRegister
internal typealias PStateField = A64.PStateField
internal typealias PStateFlagKind = A64.PStateFlagKind
internal typealias SystemInstructionAlias = A64.SystemInstructionAlias
internal typealias RCpcUnscaledKind = A64.RCpcUnscaledKind
internal typealias CRC32Kind = A64.CRC32Kind
internal typealias ConditionalSetKind = A64.ConditionalSetKind
internal typealias ConditionalSelectAliasKind = A64.ConditionalSelectAliasKind
internal typealias VectorFPMultiplyLongKind = A64.VectorFPMultiplyLongKind
internal typealias VectorThreeSameExtraKind = A64.VectorThreeSameExtraKind
internal typealias ScalarThreeSameKind = A64.ScalarThreeSameKind
internal typealias ScalarPairwiseKind = A64.ScalarPairwiseKind
internal typealias ScalarTwoRegisterMiscKind = A64.ScalarTwoRegisterMiscKind
internal typealias ScalarShiftImmediateKind = A64.ScalarShiftImmediateKind
internal typealias ScalarThreeDifferentKind = A64.ScalarThreeDifferentKind
internal typealias ScalarFPTwoRegisterMiscKind = A64.ScalarFPTwoRegisterMiscKind
internal typealias ScalarThreeSameFPKind = A64.ScalarThreeSameFPKind
internal typealias ScalarShiftNarrowKind = A64.ScalarShiftNarrowKind
internal typealias ScalarTwoRegisterMiscNarrowKind = A64.ScalarTwoRegisterMiscNarrowKind
internal typealias ScalarShiftFixedPointKind = A64.ScalarShiftFixedPointKind
internal typealias VectorTableLookupKind = A64.VectorTableLookupKind
internal typealias VectorCompareZeroKind = A64.VectorCompareZeroKind
internal typealias VectorExtractNarrowKind = A64.VectorExtractNarrowKind
internal typealias VectorConvertKind = A64.VectorConvertKind
internal typealias VectorPairwiseLongAddKind = A64.VectorPairwiseLongAddKind
internal typealias VectorRoundReciprocalKind = A64.VectorRoundReciprocalKind
internal typealias VectorFPConvertPrecisionKind = A64.VectorFPConvertPrecisionKind
internal typealias CryptoAESKind = A64.CryptoAESKind
internal typealias CryptoSHA3Kind = A64.CryptoSHA3Kind
internal typealias CryptoSHA2Kind = A64.CryptoSHA2Kind
internal typealias CryptoSHA512Kind = A64.CryptoSHA512Kind
internal typealias CryptoTwoRegKind = A64.CryptoTwoRegKind
internal typealias CryptoSM3Kind = A64.CryptoSM3Kind
internal typealias CryptoSM3IndexedKind = A64.CryptoSM3IndexedKind
internal typealias CryptoSHA3FourKind = A64.CryptoSHA3FourKind
