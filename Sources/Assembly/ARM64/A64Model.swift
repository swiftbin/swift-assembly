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
    }
}

internal typealias IntegerRegisterKind = A64.RegisterKind
internal typealias IntegerRegister = A64.Register
internal typealias FloatRegister = A64.FPRegister
internal typealias Condition = A64.Condition
internal typealias ShiftKind = A64.ShiftKind
internal typealias ExtendKind = A64.ExtendKind
internal typealias MemoryOperand = A64.MemoryOperand
internal typealias Instruction = A64.Instruction
internal typealias ParsedShift = A64.Shift

