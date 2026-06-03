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
        case h4 = "4h"
        case h8 = "8h"
        case s2 = "2s"
        case s4 = "4s"
        case d1 = "1d"
        case d2 = "2d"

        /// The `size` field (element size code: B=0, H=1, S=2, D=3).
        var elementSize: UInt32 {
            switch self {
            case .b8, .b16: return 0b00
            case .h4, .h8: return 0b01
            case .s2, .s4: return 0b10
            case .d1, .d2: return 0b11
            }
        }

        /// The element width in bits.
        var elementWidth: Int {
            switch self {
            case .b8, .b16: return 8
            case .h4, .h8: return 16
            case .s2, .s4: return 32
            case .d1, .d2: return 64
            }
        }

        /// The `Q` bit (1 for 128-bit / fully populated arrangements).
        var q: UInt32 {
            switch self {
            case .b16, .h8, .s4, .d2: return 1
            case .b8, .h4, .s2, .d1: return 0
            }
        }
    }

    struct VectorRegister: Equatable {
        var number: UInt32
        var arrangement: VectorArrangement

        var encodedNumber: UInt32 { number & 0x1f }
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

    enum LoadStoreSingleKind: String, Equatable {
        case ldr, ldrb, ldrh, ldrsb, ldrsh, ldrsw
        case str, strb, strh
        case ldur, ldurb, ldurh, ldursb, ldursh, ldursw
        case stur, sturb, sturh
    }

    enum LoadStorePairKind: String, Equatable {
        case ldp, stp
    }

    enum PointerAuthenticationKind: String, Equatable {
        case paciasp, autiasp, pacibsp, autibsp, xpaci, xpacd
    }

    enum FPDataProcessing2Kind: String, Equatable {
        case fmul, fdiv, fadd, fsub, fmax, fmin, fmaxnm, fminnm, fnmul
    }

    enum FPDataProcessing1Kind: String, Equatable {
        case fmov, fabs, fneg, fsqrt
    }

    enum FPDataProcessing3Kind: String, Equatable {
        case fmadd, fmsub, fnmadd, fnmsub
    }

    enum FPCompareKind: String, Equatable {
        case fcmp, fcmpe
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

    enum AcrossLanesFPKind: String, Equatable {
        case fmaxv, fminv, fmaxnmv, fminnmv
    }

    enum VectorTwoRegisterMiscKind: String, Equatable {
        case rev64, rev32, rev16
        case abs, neg, mvn, rbit, cnt, cls, clz
        case sqabs, sqneg
        case fabs, fneg, fsqrt
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
                return [.s2, .s4, .d2]
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
        case mul, mla, mls, sqdmulh, sqrdmulh
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
        case loadStoreSingle(LoadStoreSingleKind, target: Register, memory: MemoryOperand)
        case loadStorePair(LoadStorePairKind, first: Register, second: Register, memory: MemoryOperand)
        case pointerAuthentication(PointerAuthenticationKind, register: Register?, architecture: ARM64Assembler.Architecture)
        case fpDataProcessing2(FPDataProcessing2Kind, destination: FPRegister, first: FPRegister, second: FPRegister)
        case fpDataProcessing1(FPDataProcessing1Kind, destination: FPRegister, source: FPRegister)
        case fpDataProcessing3(FPDataProcessing3Kind, destination: FPRegister, first: FPRegister, second: FPRegister, third: FPRegister)
        case fpCompare(FPCompareKind, first: FPRegister, second: FPCompareOperand)
        case fpConvertPrecision(destination: FPRegister, source: FPRegister)
        case fpMoveImmediate(destination: FPRegister, value: Double)
        case fpMoveToGeneral(destination: Register, source: FPRegister)
        case fpMoveFromGeneral(destination: FPRegister, source: Register)
        case fpConvertToInt(FPConvertToIntKind, destination: Register, source: FPRegister)
        case fpConvertFromInt(FPConvertFromIntKind, destination: FPRegister, source: Register)
        case acrossLanesInteger(AcrossLanesIntegerKind, destination: FPRegister, source: VectorRegister)
        case acrossLanesFP(AcrossLanesFPKind, destination: FPRegister, source: VectorRegister)
        case vectorTwoRegisterMisc(VectorTwoRegisterMiscKind, destination: VectorRegister, source: VectorRegister)
        case vectorThreeSame(VectorThreeSameKind, destination: VectorRegister, first: VectorRegister, second: VectorRegister)
        case vectorShiftImmediate(VectorShiftImmediateKind, destination: VectorRegister, source: VectorRegister, shift: Int)
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
    }
}

internal typealias IntegerRegisterKind = A64.RegisterKind
internal typealias IntegerRegister = A64.Register
internal typealias FloatRegister = A64.FPRegister
internal typealias VectorRegister = A64.VectorRegister
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
internal typealias ScalarThreeSameKind = A64.ScalarThreeSameKind
internal typealias ScalarPairwiseKind = A64.ScalarPairwiseKind
internal typealias ScalarTwoRegisterMiscKind = A64.ScalarTwoRegisterMiscKind
internal typealias ScalarShiftImmediateKind = A64.ScalarShiftImmediateKind
internal typealias ScalarThreeDifferentKind = A64.ScalarThreeDifferentKind
internal typealias ScalarFPTwoRegisterMiscKind = A64.ScalarFPTwoRegisterMiscKind
internal typealias ScalarThreeSameFPKind = A64.ScalarThreeSameFPKind
internal typealias ScalarShiftNarrowKind = A64.ScalarShiftNarrowKind
internal typealias ScalarTwoRegisterMiscNarrowKind = A64.ScalarTwoRegisterMiscNarrowKind
