import Foundation

internal enum A64InstructionDecoder {
    static func decode(_ word: UInt32) throws -> Instruction {
        if word == A64.SpecialInstruction.nop { return .nop }
        if word == A64.SpecialInstruction.exceptionReturn { return .exceptionReturn }
        if let kind = PStateFlagKind.allCases.first(where: { $0.word == word }) {
            return .pstateFlag(kind)
        }

        if let instruction = decodePointerAuthentication(word) { return instruction }
        if let instruction = decodePointerAuthData(word) { return instruction }
        if let instruction = decodeBranchRegister(word) { return instruction }
        if let instruction = decodePointerAuthBranch(word) { return instruction }
        if let instruction = decodeUnconditionalBranch(word) { return instruction }
        if let instruction = decodeConditionalBranch(word) { return instruction }
        if let instruction = decodeCompareAndBranch(word) { return instruction }
        if let instruction = decodeTestAndBranch(word) { return instruction }
        if let instruction = decodeAddress(word) { return instruction }
        if let instruction = decodeUDF(word) { return instruction }
        if let instruction = decodeException(word) { return instruction }
        if let instruction = decodeBarrier(word) { return instruction }
        if let instruction = decodeClearExclusive(word) { return instruction }
        if let instruction = decodeWaitWithTimeout(word) { return instruction }
        if let instruction = decodeHint(word) { return instruction }
        if let instruction = decodeSystemRegisterMove(word) { return instruction }
        if let instruction = decodePStateImmediate(word) { return instruction }
        if let instruction = decodeSystemInstruction(word) { return instruction }
        if let instruction = decodeMoveWide(word) { return instruction }
        if let instruction = decodeMTEAddSubTag(word) { return instruction }
        if let instruction = decodeAddSubImmediate(word) { return instruction }
        if let instruction = decodeAddSubShiftedRegister(word) { return instruction }
        if let instruction = decodeAddSubExtendedRegister(word) { return instruction }
        if let instruction = decodeLogicalImmediate(word) { return instruction }
        if let instruction = decodeLogicalShiftedRegister(word) { return instruction }
        if let instruction = decodeBitfieldShiftAlias(word) { return instruction }
        if let instruction = decodeBitfield(word) { return instruction }
        if let instruction = decodeExtract(word) { return instruction }
        if let instruction = decodeMultiply(word) { return instruction }
        if let instruction = decodeMultiplyWide(word) { return instruction }
        if let instruction = decodeDivide(word) { return instruction }
        if let instruction = decodeVariableShift(word) { return instruction }
        if let instruction = decodeMinMaxRegister(word) { return instruction }
        if let instruction = decodeMinMaxImmediate(word) { return instruction }
        if let instruction = decodeAddSubCarry(word) { return instruction }
        if let instruction = decodeMTETag(word) { return instruction }
        if let instruction = decodeRMIF(word) { return instruction }
        if let instruction = decodeEvaluateIntoFlags(word) { return instruction }
        if let instruction = decodeCRC32(word) { return instruction }
        if let instruction = decodeDataProcessingOneSource(word) { return instruction }
        if let instruction = decodeConditionalSelect(word) { return instruction }
        if let instruction = decodeConditionalCompare(word) { return instruction }
        if let instruction = decodeLoadStoreExclusive(word) { return instruction }
        if let instruction = decodeCompareAndSwap(word) { return instruction }
        if let instruction = decodeAtomicMemory(word) { return instruction }
        if let instruction = decodeLoadAcquireRCpc(word) { return instruction }
        if let instruction = decodePrefetch(word) { return instruction }
        if let instruction = decodeRCpcUnscaled(word) { return instruction }
        if let instruction = decodePointerAuthLoad(word) { return instruction }
        if let instruction = decodeMTEMemoryTag(word) { return instruction }
        if let instruction = decodeMTEStoreTagPair(word) { return instruction }
        if let instruction = decodeLoadStoreUnprivileged(word) { return instruction }
        if let instruction = decodeLoadLiteral(word) { return instruction }
        if let instruction = decodeLoadStoreSingle(word) { return instruction }
        if let instruction = decodeLoadStorePair(word) { return instruction }
        if let instruction = decodeLoadStoreSingleFP(word) { return instruction }
        if let instruction = decodeLoadStorePairFP(word) { return instruction }
        if let instruction = decodeLoadStoreMultiple(word) { return instruction }
        if let instruction = decodeLoadStoreSingleStructure(word) { return instruction }
        if let instruction = decodeVectorTableLookup(word) { return instruction }
        if let instruction = decodeFPDataProcessing3(word) { return instruction }
        if let instruction = decodeFPDataProcessing2(word) { return instruction }
        if let instruction = decodeBFloat16Convert(word) { return instruction }
        if let instruction = decodeFPDataProcessing1(word) { return instruction }
        if let instruction = decodeFPCompare(word) { return instruction }
        if let instruction = decodeFPConditionalSelect(word) { return instruction }
        if let instruction = decodeFPConditionalCompare(word) { return instruction }
        if let instruction = decodeFPMoveImmediate(word) { return instruction }
        if let instruction = decodeFPMoveVectorHigh(word) { return instruction }
        if let instruction = decodeFPIntegerConversion(word) { return instruction }
        if let instruction = decodeFPFixedPointConvert(word) { return instruction }
        if let instruction = decodeAcrossLanes(word) { return instruction }
        if let instruction = decodeCryptoAES(word) { return instruction }
        if let instruction = decodeCryptoSHA3(word) { return instruction }
        if let instruction = decodeCryptoSHA2(word) { return instruction }
        if let instruction = decodeCryptoSHA512(word) { return instruction }
        if let instruction = decodeCryptoTwoReg(word) { return instruction }
        if let instruction = decodeCryptoSM3(word) { return instruction }
        if let instruction = decodeCryptoSM3Indexed(word) { return instruction }
        if let instruction = decodeCryptoSM3SS1(word) { return instruction }
        if let instruction = decodeCryptoSHA3Four(word) { return instruction }
        if let instruction = decodeCryptoRAX1(word) { return instruction }
        if let instruction = decodeCryptoXAR(word) { return instruction }
        if let instruction = decodeVectorTwoRegisterMiscFP16(word) { return instruction }
        if let instruction = decodeVectorFRINTToInteger(word) { return instruction }
        if let instruction = decodeVectorShiftLeftLong(word) { return instruction }
        if let instruction = decodeVectorTwoRegisterMisc(word) { return instruction }
        if let instruction = decodeVectorCompareZero(word) { return instruction }
        if let instruction = decodeVectorExtractNarrow(word) { return instruction }
        if let instruction = decodeVectorFPConvertPrecision(word) { return instruction }
        if let instruction = decodeVectorConvert(word) { return instruction }
        if let instruction = decodeVectorRoundReciprocal(word) { return instruction }
        if let instruction = decodeVectorPairwiseLongAdd(word) { return instruction }
        if let instruction = decodeVectorThreeSameExtra(word) { return instruction }
        if let instruction = decodeVectorComplex(word) { return instruction }
        if let instruction = decodeVectorBFloat16(word) { return instruction }
        if let instruction = decodeVectorFPMultiplyLong(word) { return instruction }
        if let instruction = decodeVectorThreeSameFP16(word) { return instruction }
        if let instruction = decodeVectorThreeSame(word) { return instruction }
        if let instruction = decodeVectorModifiedImmediate(word) { return instruction }
        if let instruction = decodeVectorShiftImmediate(word) { return instruction }
        if let instruction = decodeVectorCopy(word) { return instruction }
        if let instruction = decodeVectorPermute(word) { return instruction }
        if let instruction = decodeVectorExtract(word) { return instruction }
        if let instruction = decodeVectorThreeDifferent(word) { return instruction }
        if let instruction = decodeVectorDotProduct(word) { return instruction }
        if let instruction = decodeVectorMixedDotProduct(word) { return instruction }
        if let instruction = decodeVectorMatrixMultiply(word) { return instruction }
        if let instruction = decodeVectorComplexByElement(word) { return instruction }
        if let instruction = decodeVectorIndexed(word) { return instruction }
        if let instruction = decodeScalarThreeSameExtra(word) { return instruction }
        if let instruction = decodeScalarThreeSame(word) { return instruction }
        if let instruction = decodeScalarPairwiseFP16(word) { return instruction }
        if let instruction = decodeScalarPairwise(word) { return instruction }
        if let instruction = decodeScalarTwoRegisterMisc(word) { return instruction }
        if let instruction = decodeScalarShiftImmediate(word) { return instruction }
        if let instruction = decodeScalarThreeDifferent(word) { return instruction }
        if let instruction = decodeScalarIndexed(word) { return instruction }
        if let instruction = decodeScalarCopy(word) { return instruction }
        if let instruction = decodeScalarFPTwoRegisterMiscFP16(word) { return instruction }
        if let instruction = decodeScalarFPTwoRegisterMisc(word) { return instruction }
        if let instruction = decodeScalarThreeSameFP16(word) { return instruction }
        if let instruction = decodeScalarThreeSameFP(word) { return instruction }
        if let instruction = decodeScalarShiftNarrow(word) { return instruction }
        if let instruction = decodeScalarTwoRegisterMiscNarrow(word) { return instruction }
        if let instruction = decodeScalarShiftFixedPoint(word) { return instruction }

        throw AssemblerError.unknownEncoding(word)
    }

    private static func decodeBranchRegister(_ word: UInt32) -> Instruction? {
        guard let kind = A64.BranchRegisterKind.decode(masked: word & 0xffff_fc1f) else { return nil }
        return .branchRegister(kind, xRegister(number: (word >> 5) & 0x1f))
    }

    private static func decodePointerAuthBranch(_ word: UInt32) -> Instruction? {
        for kind in A64.PointerAuthBranchKind.allCases {
            switch kind.form {
            case .noOperand:
                if word == kind.baseWord {
                    return .pointerAuthBranch(kind, target: nil, modifier: nil)
                }
            case .oneRegister:
                // Rn is variable (bits [9:5]); the rest of the word is fixed.
                if word & ~UInt32(0x3e0) == kind.baseWord {
                    return .pointerAuthBranch(kind, target: xRegister(number: (word >> 5) & 0x1f), modifier: nil)
                }
            case .twoRegister:
                // Rn (bits [9:5]) and Rm (bits [4:0]) are variable.
                if word & ~UInt32(0x3ff) == kind.baseWord {
                    return .pointerAuthBranch(
                        kind,
                        target: xRegister(number: (word >> 5) & 0x1f),
                        modifier: xRegister(number: word & 0x1f)
                    )
                }
            }
        }
        return nil
    }

    private static func decodeUnconditionalBranch(_ word: UInt32) -> Instruction? {
        typealias F = A64.UnconditionalBranchImmediate
        guard word & F.classMask == F.baseWord else { return nil }
        let offset = signExtend(F.imm26.extract(word), bitCount: 26) * 4
        return .unconditionalBranch(link: F.op.extract(word) == 1, offset: offset)
    }

    private static func decodeConditionalBranch(_ word: UInt32) -> Instruction? {
        typealias F = A64.ConditionalBranchImmediate
        guard word & F.classMask == F.baseWord else { return nil }
        guard let condition = Condition(rawValue: F.cond.extract(word)) else { return nil }
        let offset = signExtend(F.imm19.extract(word), bitCount: 19) * 4
        return .conditionalBranch(condition, offset: offset)
    }

    private static func decodeCompareAndBranch(_ word: UInt32) -> Instruction? {
        typealias F = A64.CompareAndBranch
        guard word & F.classMask == F.baseWord else { return nil }
        let is64Bit = F.sf.extract(word) == 1
        let nonzero = F.op.extract(word) == 1
        let rt = integerRegister(number: F.rt.extract(word), width: is64Bit ? 64 : 32)
        let offset = signExtend(F.imm19.extract(word), bitCount: 19) * 4
        return .compareAndBranch(nonzero: nonzero, rt, offset: offset)
    }

    private static func decodeTestAndBranch(_ word: UInt32) -> Instruction? {
        typealias F = A64.TestAndBranch
        guard word & F.classMask == F.baseWord else { return nil }
        let bit = Int64(F.b5.extract(word) << 5) | Int64(F.b40.extract(word))
        let nonzero = F.op.extract(word) == 1
        let rt = integerRegister(number: F.rt.extract(word), width: bit >= 32 ? 64 : 32)
        let offset = signExtend(F.imm14.extract(word), bitCount: 14) * 4
        return .testAndBranch(nonzero: nonzero, rt, bit: bit, offset: offset)
    }

    private static func decodeAddress(_ word: UInt32) -> Instruction? {
        typealias F = A64.PCRelativeAddressing
        guard word & F.classMask == F.baseWord else { return nil }
        let page = F.op.extract(word) == 1
        let immlo = F.immlo.extract(word)
        let immhi = F.immhi.extract(word)
        let immediate = signExtend((immhi << 2) | immlo, bitCount: 21)
        return .address(page: page, xRegister(number: F.rd.extract(word)), offset: page ? immediate * 4096 : immediate)
    }

    private static func decodeUDF(_ word: UInt32) -> Instruction? {
        typealias F = A64.PermanentlyUndefined
        guard word & F.classMask == F.baseWord else { return nil }
        return .permanentlyUndefined(F.imm16.extract(word))
    }

    private static func decodeException(_ word: UInt32) -> Instruction? {
        guard let kind = A64.ExceptionKind.decode(masked: word & 0xffe0_001f) else { return nil }
        return .exception(kind, immediate: Int64((word >> 5) & 0xffff))
    }

    private static func decodeBarrier(_ word: UInt32) -> Instruction? {
        guard let kind = A64.BarrierKind.decode(masked: word & 0xffff_f0ff) else { return nil }
        // SB (speculation barrier) has a fixed CRm of 0; the others carry the option.
        let option = kind == .speculation ? 0 : (word >> 8) & 0xf
        return .barrier(kind, option: option)
    }

    private static func decodeClearExclusive(_ word: UInt32) -> Instruction? {
        typealias F = A64.ClearExclusive
        guard word & F.classMask == F.baseWord else { return nil }
        return .clearExclusive(F.crm.extract(word))
    }

    private static func decodeWaitWithTimeout(_ word: UInt32) -> Instruction? {
        typealias F = A64.WaitWithTimeout
        guard word & F.classMask == F.baseWord else { return nil }
        let isEvent = F.op2.extract(word) == 0
        return .waitWithTimeout(isEvent: isEvent, register: xRegister(number: F.rt.extract(word)))
    }

    private static func decodeHint(_ word: UInt32) -> Instruction? {
        // nop (#0) and the paciasp-family hints are claimed earlier in the chain.
        typealias F = A64.Hint
        guard word & F.classMask == F.baseWord else { return nil }
        return .hint(F.imm.extract(word))
    }

    private static func decodeSystemRegisterMove(_ word: UInt32) -> Instruction? {
        typealias F = A64.SystemRegisterMove
        guard word & F.classMask == F.baseWord else { return nil }
        let register = SystemRegister(
            op0: F.o0.extract(word) + 2,
            op1: F.op1.extract(word),
            crn: F.crn.extract(word),
            crm: F.crm.extract(word),
            op2: F.op2.extract(word)
        )
        let value = integerRegister(number: F.rt.extract(word), width: 64)
        return .systemRegisterMove(read: F.l.extract(word) == 1, register: register, value: value)
    }

    private static func decodePStateImmediate(_ word: UInt32) -> Instruction? {
        typealias F = A64.PStateImmediate
        guard word & F.classMask == F.baseWord else { return nil }
        guard let field = PStateField.decode(op1: F.op1.extract(word), op2: F.op2.extract(word)) else { return nil }
        return .pstate(field, immediate: F.crm.extract(word))
    }

    private static func decodeSystemInstruction(_ word: UInt32) -> Instruction? {
        typealias F = A64.SystemInstruction
        guard word & F.classMask == F.baseWord else { return nil }
        let rt = F.rt.extract(word)
        let register: IntegerRegister? = rt == 31 ? nil : integerRegister(number: rt, width: 64)
        return .systemInstruction(
            read: F.l.extract(word) == 1,
            op1: F.op1.extract(word),
            crn: F.crn.extract(word),
            crm: F.crm.extract(word),
            op2: F.op2.extract(word),
            register: register
        )
    }

    private static func decodePointerAuthentication(_ word: UInt32) -> Instruction? {
        switch word {
        case 0xd503233f: return .pointerAuthentication(.paciasp, register: nil, architecture: .arm64e)
        case 0xd50323bf: return .pointerAuthentication(.autiasp, register: nil, architecture: .arm64e)
        case 0xd503237f: return .pointerAuthentication(.pacibsp, register: nil, architecture: .arm64e)
        case 0xd50323ff: return .pointerAuthentication(.autibsp, register: nil, architecture: .arm64e)
        case 0xd503211f: return .pointerAuthentication(.pacia1716, register: nil, architecture: .arm64e)
        case 0xd503215f: return .pointerAuthentication(.pacib1716, register: nil, architecture: .arm64e)
        case 0xd503219f: return .pointerAuthentication(.autia1716, register: nil, architecture: .arm64e)
        case 0xd50321df: return .pointerAuthentication(.autib1716, register: nil, architecture: .arm64e)
        case 0xd50320ff: return .pointerAuthentication(.xpaclri, register: nil, architecture: .arm64e)
        default: break
        }
        if word & 0xffff_ffe0 == 0xdac1_43e0 {
            return .pointerAuthentication(.xpaci, register: integerRegister(number: word & 0x1f, width: 64), architecture: .arm64e)
        }
        if word & 0xffff_ffe0 == 0xdac1_47e0 {
            return .pointerAuthentication(.xpacd, register: integerRegister(number: word & 0x1f, width: 64), architecture: .arm64e)
        }
        return nil
    }

    private static func decodePointerAuthData(_ word: UInt32) -> Instruction? {
        // PACGA: data-processing (2 source), opcode[15:10]=001100.
        if word & 0xffe0_fc00 == A64.PointerAuthData.pacga {
            let rd = integerRegister(number: word & 0x1f, width: 64)
            let rn = integerRegister(number: (word >> 5) & 0x1f, width: 64)
            let rm = integerRegister(number: (word >> 16) & 0x1f, width: 64)
            return .pointerAuthData(.pacga, destination: rd, source: rn, modifier: rm)
        }
        // Data-processing (1 source): bit31=1, op[30:21]=1011000001, opcode[15:10]=0000xx..0011xx.
        guard word & 0xffff_0000 == A64.PointerAuthData.dataBase else { return nil }
        let opcode = (word >> 10) & 0x3f
        guard let kind = A64.PointerAuthDataKind.decodeOneSource(opcode: opcode) else { return nil }
        let rd = integerRegister(number: word & 0x1f, width: 64)
        if kind.isImplicitModifier {
            return .pointerAuthData(kind, destination: rd, source: nil, modifier: nil)
        }
        let rn = integerRegister(number: (word >> 5) & 0x1f, width: 64)
        return .pointerAuthData(kind, destination: rd, source: rn, modifier: nil)
    }

    private static func decodeMoveWide(_ word: UInt32) -> Instruction? {
        typealias F = A64.MoveWide
        guard word & F.classMask == F.baseWord else { return nil }
        let sf = F.sf.extract(word)
        guard let kind = A64.MoveWideKind.decode(opc: F.opc.extract(word)) else { return nil }
        let hw = F.hw.extract(word)
        if sf == 0 && hw > 1 { return nil }
        let imm = Int64(F.imm16.extract(word))
        let rd = integerRegister(number: F.rd.extract(word), width: sf == 1 ? 64 : 32)
        let shift = hw == 0 ? nil : Int(hw) * 16
        return .moveWide(kind, destination: rd, immediate: imm, shift: shift)
    }

    private static func decodeMTEAddSubTag(_ word: UInt32) -> Instruction? {
        // ADDG/SUBG (add/subtract immediate, with tags).
        typealias F = A64.AddSubTag
        guard word & F.classMask == F.baseWord else { return nil }
        let subtract = F.op.extract(word) == 1
        let uimm6 = F.uimm6.extract(word)
        let tag = F.uimm4.extract(word)
        let rn = xRegister(number: F.rn.extract(word))
        let rd = xRegister(number: F.rd.extract(word))
        return .mteAddSubTag(subtract: subtract, destination: rd, source: rn, offset: uimm6 * 16, tag: tag)
    }

    private static func decodeMTETag(_ word: UInt32) -> Instruction? {
        // Data-processing (2 source), 64-bit: sf=1, bit30=0, bits[28:21]=11010110.
        guard ((word >> 31) & 1) == 1, ((word >> 30) & 1) == 0, ((word >> 21) & 0xff) == 0xd6 else { return nil }
        let setsFlags = ((word >> 29) & 1) == 1
        let opcode = (word >> 10) & 0x3f
        guard let kind = A64.MTETagKind.decode(setsFlags: setsFlags, opcode: opcode) else { return nil }
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        switch kind {
        case .irg:
            let mask = integerRegister(number: rmNum, width: 64)
            return .mteTag(kind, destination: xRegister(number: rdNum), first: xRegister(number: rnNum), second: mask)
        case .gmi:
            return .mteTag(kind, destination: integerRegister(number: rdNum, width: 64), first: xRegister(number: rnNum), second: integerRegister(number: rmNum, width: 64))
        case .subp, .subps:
            return .mteTag(kind, destination: integerRegister(number: rdNum, width: 64), first: xRegister(number: rnNum), second: xRegister(number: rmNum))
        }
    }

    private static func decodeRMIF(_ word: UInt32) -> Instruction? {
        typealias F = A64.RMIF
        guard word & F.classMask == F.baseWord else { return nil }
        let rotate = F.rotate.extract(word)
        let mask = F.mask.extract(word)
        let source = xRegister(number: F.rn.extract(word))
        return .rmif(source: source, rotate: rotate, mask: mask)
    }

    private static func decodeEvaluateIntoFlags(_ word: UInt32) -> Instruction? {
        typealias F = A64.EvaluateIntoFlags
        guard word & F.classMask == F.baseWord else { return nil }
        let kind: A64.EvaluateFlagsKind = F.sz.extract(word) == 1 ? .setf16 : .setf8
        let source = integerRegister(number: F.rn.extract(word), width: 32)
        return .evaluateIntoFlags(kind, source: source)
    }

    private static func decodeAddSubImmediate(_ word: UInt32) -> Instruction? {
        // bit23=0 excludes the FEAT_CSSC min/max immediate space.
        typealias F = A64.AddSubImmediate
        guard word & F.classMask == F.baseWord else { return nil }
        let sf = F.sf.extract(word)
        let op = F.op.extract(word)
        let s = F.s.extract(word)
        let sh = F.sh.extract(word)
        let imm12 = F.imm12.extract(word)
        let width = sf == 1 ? 64 : 32
        let rnNum = F.rn.extract(word)
        let operand = A64.AddSubOperand.immediate(Int64(imm12), shift: sh == 1 ? 12 : nil)
        if s == 1 && F.rd.extract(word) == 31 {
            return .compareAlias(op == 1 ? .cmp : .cmn, first: baseRegister(number: rnNum, width: width), operand: operand)
        }
        let rn = baseRegister(number: rnNum, width: width)
        let rd: IntegerRegister = s == 0 ? baseRegister(number: F.rd.extract(word), width: width) : integerRegister(number: F.rd.extract(word), width: width)
        let kind: A64.AddSubKind = op == 0 ? (s == 0 ? .add : .adds) : (s == 0 ? .sub : .subs)
        return .addSub(kind, destination: rd, first: rn, operand: operand)
    }

    private static func decodeAddSubShiftedRegister(_ word: UInt32) -> Instruction? {
        typealias F = A64.AddSubShiftedRegister
        guard word & F.classMask == F.baseWord else { return nil }
        let sf = F.sf.extract(word)
        let op = F.op.extract(word)
        let s = F.s.extract(word)
        guard let shiftKind = ShiftKind(rawValue: F.shift.extract(word)), shiftKind != .ror else { return nil }
        let amount = F.imm6.extract(word)
        let width = sf == 1 ? 64 : 32
        if sf == 0 && amount > 31 { return nil }
        let rm = integerRegister(number: F.rm.extract(word), width: width)
        let rnNum = F.rn.extract(word)
        let shift: ParsedShift? = (amount == 0 && shiftKind == .lsl) ? nil : ParsedShift(kind: shiftKind, amount: Int(amount))
        let operand = A64.AddSubOperand.shiftedRegister(rm, shift: shift)
        if s == 1 && F.rd.extract(word) == 31 {
            return .compareAlias(op == 1 ? .cmp : .cmn, first: integerRegister(number: rnNum, width: width), operand: operand)
        }
        let kind: A64.AddSubKind = op == 0 ? (s == 0 ? .add : .adds) : (s == 0 ? .sub : .subs)
        return .addSub(kind, destination: integerRegister(number: F.rd.extract(word), width: width), first: integerRegister(number: rnNum, width: width), operand: operand)
    }

    private static func decodeLogicalImmediate(_ word: UInt32) -> Instruction? {
        typealias F = A64.LogicalImmediate
        guard word & F.classMask == F.baseWord else { return nil }
        let sf = F.sf.extract(word)
        let n = F.n.extract(word)
        if sf == 0 && n != 0 { return nil }
        let width = sf == 1 ? 64 : 32
        let immr = F.immr.extract(word)
        let imms = F.imms.extract(word)
        guard let value = A64BitmaskImmediate.decode(n: n, immr: immr, imms: imms, width: width) else { return nil }
        let kind: A64.LogicalKind
        switch F.opc.extract(word) {
        case 0: kind = .and
        case 1: kind = .orr
        case 2: kind = .eor
        case 3: kind = .ands
        default: return nil
        }
        let rd = integerRegister(number: F.rd.extract(word), width: width)
        let rn = integerRegister(number: F.rn.extract(word), width: width)
        return .logical(kind, destination: rd, first: rn, operand: .immediate(Int64(bitPattern: value)))
    }

    private static func decodeLogicalShiftedRegister(_ word: UInt32) -> Instruction? {
        typealias F = A64.LogicalShiftedRegister
        guard word & F.classMask == F.baseWord else { return nil }
        let sf = F.sf.extract(word)
        let n = F.n.extract(word)
        guard let shiftKind = ShiftKind(rawValue: F.shift.extract(word)) else { return nil }
        let amount = F.imm6.extract(word)
        let width = sf == 1 ? 64 : 32
        if sf == 0 && amount > 31 { return nil }
        let kind: A64.LogicalKind
        switch (F.opc.extract(word), n) {
        case (0, 0): kind = .and
        case (0, 1): kind = .bic
        case (1, 0): kind = .orr
        case (1, 1): kind = .orn
        case (2, 0): kind = .eor
        case (2, 1): kind = .eon
        case (3, 0): kind = .ands
        case (3, 1): kind = .bics
        default: return nil
        }
        let rm = integerRegister(number: F.rm.extract(word), width: width)
        let rnNum = F.rn.extract(word)
        let rd = integerRegister(number: F.rd.extract(word), width: width)
        let shift: ParsedShift? = (amount == 0 && shiftKind == .lsl) ? nil : ParsedShift(kind: shiftKind, amount: Int(amount))
        if kind == .orn && rnNum == 31 {
            return .mvnAlias(destination: rd, source: rm, shift: shift)
        }
        if kind == .orr && rnNum == 31 && shift == nil {
            return .moveAlias(destination: rd, source: .register(rm))
        }
        return .logical(kind, destination: rd, first: integerRegister(number: rnNum, width: width), operand: .shiftedRegister(rm, shift: shift))
    }

    private static func decodeBitfieldShiftAlias(_ word: UInt32) -> Instruction? {
        guard word & 0x1f80_0000 == 0x1300_0000 else { return nil }
        let sf = (word >> 31) & 1
        let n = (word >> 22) & 1
        guard n == sf else { return nil }
        let width = sf == 1 ? 64 : 32
        let maxShift = UInt32(width - 1)
        let immr = (word >> 16) & 0x3f
        let imms = (word >> 10) & 0x3f
        let rd = integerRegister(number: word & 0x1f, width: width)
        let rn = integerRegister(number: (word >> 5) & 0x1f, width: width)
        switch (word >> 29) & 3 {
        case 2:
            if imms == maxShift {
                return .shiftAlias(.lsr, destination: rd, source: rn, amount: Int64(immr))
            }
            if immr == imms + 1 {
                return .shiftAlias(.lsl, destination: rd, source: rn, amount: Int64(maxShift - imms))
            }
            return nil
        case 0:
            if imms == maxShift {
                return .shiftAlias(.asr, destination: rd, source: rn, amount: Int64(immr))
            }
            return nil
        default:
            return nil
        }
    }

    private static func decodeBitfield(_ word: UInt32) -> Instruction? {
        // Bitfield group fixed field [28:23]=100110. The shift-alias decoder
        // runs first and claims the asr/lsl/lsr patterns; everything else
        // (all bfm, plus the remaining sbfm/ubfm forms) lands here.
        typealias F = A64.Bitfield
        guard word & F.classMask == F.baseWord else { return nil }
        let sf = F.sf.extract(word)
        guard F.n.extract(word) == sf else { return nil }
        guard let kind = A64.BitfieldKind.decode(opc: F.opc.extract(word)) else { return nil }
        let width = sf == 1 ? 64 : 32
        let immr = F.immr.extract(word)
        let imms = F.imms.extract(word)
        let rd = integerRegister(number: F.rd.extract(word), width: width)
        let rn = integerRegister(number: F.rn.extract(word), width: width)
        return .bitfield(kind, destination: rd, source: rn, immr: immr, imms: imms)
    }

    private static func decodeExtract(_ word: UInt32) -> Instruction? {
        typealias F = A64.Extract
        guard word & F.classMask == F.baseWord else { return nil }
        let sf = F.sf.extract(word)
        guard F.n.extract(word) == sf else { return nil }
        let width = sf == 1 ? 64 : 32
        let imms = F.imms.extract(word)
        if sf == 0 && imms > 31 { return nil }
        let rmNum = F.rm.extract(word)
        let rnNum = F.rn.extract(word)
        let rd = integerRegister(number: F.rd.extract(word), width: width)
        let rn = integerRegister(number: rnNum, width: width)
        if rmNum == rnNum {
            return .extractOrRotateAlias(.ror, destination: rd, first: rn, operand: .rotate(amount: Int64(imms)))
        }
        return .extractOrRotateAlias(.extr, destination: rd, first: rn, operand: .extract(integerRegister(number: rmNum, width: width), amount: Int64(imms)))
    }

    private static func decodeMultiplyWide(_ word: UInt32) -> Instruction? {
        // Data-processing 3-source group; the wide forms are always 64-bit (sf=1).
        typealias F = A64.DataProcessing3Source
        guard word & F.classMask == F.baseWord, F.sf.extract(word) == 1 else { return nil }
        let op31 = F.op31.extract(word)
        let o0 = F.o0.extract(word)
        let ra = F.ra.extract(word)
        // High-half multiplies ignore Ra (always XZR); the long forms treat an
        // XZR accumulator as the no-accumulator (`mull`/`negl`) mnemonic.
        let isHighOpcode = op31 == 0b010 || op31 == 0b110
        let hasAccumulator = !isHighOpcode && ra != 31
        guard let kind = A64.MultiplyWideKind.decode(op31: op31, o0: o0, hasAccumulator: hasAccumulator) else { return nil }
        let sourceWidth = kind.isHigh ? 64 : 32
        let rd = integerRegister(number: F.rd.extract(word), width: 64)
        let rn = integerRegister(number: F.rn.extract(word), width: sourceWidth)
        let rm = integerRegister(number: F.rm.extract(word), width: sourceWidth)
        let accumulator = hasAccumulator ? integerRegister(number: ra, width: 64) : nil
        return .multiplyWide(kind, destination: rd, first: rn, second: rm, accumulator: accumulator)
    }

    private static func decodeMultiply(_ word: UInt32) -> Instruction? {
        // Data-processing 3-source with op31=000 (the MADD/MSUB/MUL/MNEG forms).
        typealias F = A64.DataProcessing3Source
        guard word & F.classMask == F.baseWord, F.op31.extract(word) == 0 else { return nil }
        let width = F.sf.extract(word) == 1 ? 64 : 32
        let o0 = F.o0.extract(word)
        let rm = integerRegister(number: F.rm.extract(word), width: width)
        let ra = F.ra.extract(word)
        let rn = integerRegister(number: F.rn.extract(word), width: width)
        let rd = integerRegister(number: F.rd.extract(word), width: width)
        if ra == 31 {
            return .multiply(o0 == 1 ? .mneg : .mul, destination: rd, first: rn, second: rm, accumulator: nil)
        }
        return .multiply(o0 == 1 ? .msub : .madd, destination: rd, first: rn, second: rm, accumulator: integerRegister(number: ra, width: width))
    }

    private static func decodeDivide(_ word: UInt32) -> Instruction? {
        typealias F = A64.DataProcessing2Source
        guard word & F.classMask == F.baseWord else { return nil }
        guard let kind = A64.DivideKind.decode(opcode: F.opcode.extract(word)) else { return nil }
        let width = F.sf.extract(word) == 1 ? 64 : 32
        return .divide(
            kind,
            destination: integerRegister(number: F.rd.extract(word), width: width),
            first: integerRegister(number: F.rn.extract(word), width: width),
            second: integerRegister(number: F.rm.extract(word), width: width)
        )
    }

    private static func decodeVariableShift(_ word: UInt32) -> Instruction? {
        // Data-processing-2-source class; the LSLV/LSRV/ASRV/RORV variants are
        // selected by decoding the `opcode` field (other opcodes fall through).
        typealias F = A64.DataProcessing2Source
        guard word & F.classMask == F.baseWord else { return nil }
        guard let kind = A64.VariableShiftKind.decode(opcode: F.opcode.extract(word)) else { return nil }
        let width = F.sf.extract(word) == 1 ? 64 : 32
        return .variableShift(
            kind,
            destination: integerRegister(number: F.rd.extract(word), width: width),
            first: integerRegister(number: F.rn.extract(word), width: width),
            second: integerRegister(number: F.rm.extract(word), width: width)
        )
    }

    private static func decodeMinMaxRegister(_ word: UInt32) -> Instruction? {
        // FEAT_CSSC min/max (register): data-processing-2-source class.
        typealias F = A64.DataProcessing2Source
        guard word & F.classMask == F.baseWord else { return nil }
        guard let kind = A64.MinMaxKind.decodeRegister(opcode: F.opcode.extract(word)) else { return nil }
        let width = F.sf.extract(word) == 1 ? 64 : 32
        return .minMaxRegister(
            kind,
            destination: integerRegister(number: F.rd.extract(word), width: width),
            first: integerRegister(number: F.rn.extract(word), width: width),
            second: integerRegister(number: F.rm.extract(word), width: width)
        )
    }

    private static func decodeMinMaxImmediate(_ word: UInt32) -> Instruction? {
        // FEAT_CSSC min/max (immediate).
        typealias F = A64.MinMaxImmediate
        guard word & F.classMask == F.baseWord else { return nil }
        guard let kind = A64.MinMaxKind.decodeImmediate(opc: F.opc.extract(word)) else { return nil }
        let width = F.sf.extract(word) == 1 ? 64 : 32
        let imm8 = F.imm8.extract(word)
        let immediate: Int64 = kind.isSigned ? Int64(signExtend(imm8, bitCount: 8)) : Int64(imm8)
        return .minMaxImmediate(
            kind,
            destination: integerRegister(number: F.rd.extract(word), width: width),
            source: integerRegister(number: F.rn.extract(word), width: width),
            immediate: immediate
        )
    }

    private static func decodeAddSubExtendedRegister(_ word: UInt32) -> Instruction? {
        // bit21=1 distinguishes this from the shifted-register form (bit21=0).
        typealias F = A64.AddSubExtendedRegister
        guard word & F.classMask == F.baseWord else { return nil }
        let sf = F.sf.extract(word)
        let op = F.op.extract(word)
        let s = F.s.extract(word)
        guard let extend = ExtendKind(rawValue: F.option.extract(word)) else { return nil }
        let imm3 = F.imm3.extract(word)
        guard imm3 <= 4 else { return nil }
        let width = sf == 1 ? 64 : 32
        let rmWidth = (extend == .uxtx || extend == .sxtx) ? 64 : 32
        let rm = integerRegister(number: F.rm.extract(word), width: rmWidth)
        let rnNum = F.rn.extract(word)
        let amount = imm3 == 0 ? nil : Int(imm3)
        let operand = A64.AddSubOperand.extendedRegister(rm, extend: extend, amount: amount)
        if s == 1 && F.rd.extract(word) == 31 {
            return .compareAlias(op == 1 ? .cmp : .cmn, first: baseRegister(number: rnNum, width: width), operand: operand)
        }
        let kind: A64.AddSubKind = op == 0 ? (s == 0 ? .add : .adds) : (s == 0 ? .sub : .subs)
        let rd: IntegerRegister = s == 0 ? baseRegister(number: F.rd.extract(word), width: width) : integerRegister(number: F.rd.extract(word), width: width)
        return .addSub(kind, destination: rd, first: baseRegister(number: rnNum, width: width), operand: operand)
    }

    private static func decodeAddSubCarry(_ word: UInt32) -> Instruction? {
        typealias F = A64.AddSubWithCarry
        guard word & F.classMask == F.baseWord else { return nil }
        let kind = A64.AddSubCarryKind.decode(op: F.op.extract(word), setsFlags: F.s.extract(word))
        let width = F.sf.extract(word) == 1 ? 64 : 32
        let rm = integerRegister(number: F.rm.extract(word), width: width)
        let rn = integerRegister(number: F.rn.extract(word), width: width)
        let rd = integerRegister(number: F.rd.extract(word), width: width)
        return .addSubCarry(kind, destination: rd, first: rn, second: rm)
    }

    private static func decodeCRC32(_ word: UInt32) -> Instruction? {
        // Data-processing 2-source class.
        typealias F = A64.DataProcessing2Source
        guard word & F.classMask == F.baseWord else { return nil }
        guard let kind = A64.CRC32Kind.decode(opcode: F.opcode.extract(word)) else { return nil }
        // Rd and Rn are 32-bit; Rm is 64-bit only for the `x` variants.
        let rd = integerRegister(number: F.rd.extract(word), width: 32)
        let rn = integerRegister(number: F.rn.extract(word), width: 32)
        let rm = integerRegister(number: F.rm.extract(word), width: kind.usesDoubleWordSource ? 64 : 32)
        return .crc32(kind, destination: rd, first: rn, data: rm)
    }

    private static func decodeDataProcessingOneSource(_ word: UInt32) -> Instruction? {
        typealias F = A64.DataProcessing1Source
        guard word & F.classMask == F.baseWord else { return nil }
        let is64Bit = F.sf.extract(word) == 1
        guard let kind = A64.DataProcessingOneSourceKind.decode(opcode: F.opcode.extract(word), is64Bit: is64Bit) else { return nil }
        let width = is64Bit ? 64 : 32
        let rn = integerRegister(number: F.rn.extract(word), width: width)
        let rd = integerRegister(number: F.rd.extract(word), width: width)
        return .dataProcessingOneSource(kind, destination: rd, source: rn)
    }

    private static func decodeConditionalSelect(_ word: UInt32) -> Instruction? {
        typealias F = A64.ConditionalSelect
        guard word & F.classMask == F.baseWord else { return nil }
        let op = F.op.extract(word)
        let o2 = F.o2.extract(word)
        guard let kind = A64.ConditionalSelectKind.decode(op: op, o2: o2),
              let condition = Condition(rawValue: F.cond.extract(word)) else { return nil }
        let width = F.sf.extract(word) == 1 ? 64 : 32
        let rmNum = F.rm.extract(word)
        let rnNum = F.rn.extract(word)
        let rawCond = F.cond.extract(word)
        let rd = integerRegister(number: F.rd.extract(word), width: width)

        // Prefer the conditional-set / conditional-select aliases when the
        // register pattern and condition (not AL/NV) match. The displayed
        // condition is the inverse of the encoded one.
        if rmNum == rnNum, rawCond < 0b1110, let inverted = Condition(rawValue: rawCond ^ 1) {
            switch kind {
            case .csinc, .csinv:
                let setKind: A64.ConditionalSetKind = kind == .csinc ? .cset : .csetm
                let aliasKind: A64.ConditionalSelectAliasKind = kind == .csinc ? .cinc : .cinv
                if rnNum == 31 {
                    return .conditionalSet(setKind, destination: rd, condition: inverted)
                }
                return .conditionalSelectAlias(aliasKind, destination: rd, source: integerRegister(number: rnNum, width: width), condition: inverted)
            case .csneg:
                return .conditionalSelectAlias(.cneg, destination: rd, source: integerRegister(number: rnNum, width: width), condition: inverted)
            case .csel:
                break
            }
        }

        let rm = integerRegister(number: rmNum, width: width)
        let rn = integerRegister(number: rnNum, width: width)
        return .conditionalSelect(kind, destination: rd, first: rn, second: rm, condition: condition)
    }

    private static func decodeConditionalCompare(_ word: UInt32) -> Instruction? {
        typealias F = A64.ConditionalCompare
        guard word & F.classMask == F.baseWord else { return nil }
        let kind: A64.ConditionalCompareKind = F.op.extract(word) == 1 ? .ccmp : .ccmn
        guard let condition = Condition(rawValue: F.cond.extract(word)) else { return nil }
        let width = F.sf.extract(word) == 1 ? 64 : 32
        let nzcv = F.nzcv.extract(word)
        let second: A64.ConditionalCompareOperand
        if F.immFlag.extract(word) == 1 {
            second = .immediate(F.imm5OrRm.extract(word))
        } else {
            second = .register(integerRegister(number: F.imm5OrRm.extract(word), width: width))
        }
        let rn = integerRegister(number: F.rn.extract(word), width: width)
        return .conditionalCompare(kind, first: rn, second: second, nzcv: nzcv, condition: condition)
    }

    private static func decodeLoadStoreExclusive(_ word: UInt32) -> Instruction? {
        typealias F = A64.LoadStoreExclusive
        guard word & F.classMask == F.baseWord else { return nil }
        let size = F.size.extract(word)
        let o2 = F.o2.extract(word)
        let l = F.l.extract(word)
        let o1 = F.o1.extract(word)
        let o0 = F.o0.extract(word)

        let fixedSize: UInt32?
        if o1 == 1 {
            guard size == 2 || size == 3 else { return nil }
            fixedSize = nil
        } else {
            switch size {
            case 0: fixedSize = 0
            case 1: fixedSize = 1
            case 2, 3: fixedSize = nil
            default: return nil
            }
        }

        guard let kind = A64.LoadStoreExclusiveKind.decode(o2: o2, l: l, o1: o1, o0: o0, fixedSize: fixedSize) else {
            return nil
        }

        let valueWidth = fixedSize == nil ? (size == 3 ? 64 : 32) : 32
        let status: IntegerRegister? = kind.hasStatusRegister
            ? integerRegister(number: F.rs.extract(word), width: 32) : nil
        let value = integerRegister(number: F.rt.extract(word), width: valueWidth)
        let value2: IntegerRegister? = kind.isPair
            ? integerRegister(number: F.rt2.extract(word), width: valueWidth) : nil
        let base = xRegister(number: F.rn.extract(word))
        return .loadStoreExclusive(kind, status: status, value: value, value2: value2, base: base)
    }

    private static func decodeCompareAndSwap(_ word: UInt32) -> Instruction? {
        typealias F = A64.LoadStoreExclusive
        guard word & F.classMask == F.baseWord else { return nil }
        let o2 = F.o2.extract(word)
        let o1 = F.o1.extract(word)
        guard o1 == 1 else { return nil }
        let size = F.size.extract(word)
        let acquire = F.l.extract(word)
        let release = F.o0.extract(word)
        let rsNum = F.rs.extract(word)
        let rnNum = F.rn.extract(word)
        let rtNum = F.rt.extract(word)

        if o2 == 1 {
            // Compare and swap (single register).
            let fixedSize: UInt32?
            let width: Int
            switch size {
            case 0: fixedSize = 0; width = 32
            case 1: fixedSize = 1; width = 32
            case 2: fixedSize = nil; width = 32
            case 3: fixedSize = nil; width = 64
            default: return nil
            }
            guard let kind = A64.CompareAndSwapKind.decode(acquire: acquire, release: release, fixedSize: fixedSize) else {
                return nil
            }
            return .compareAndSwap(
                kind,
                compare: integerRegister(number: rsNum, width: width),
                value: integerRegister(number: rtNum, width: width),
                base: xRegister(number: rnNum)
            )
        }

        // Compare and swap pair: size 00 (32-bit) or 01 (64-bit) only.
        let width: Int
        switch size {
        case 0: width = 32
        case 1: width = 64
        default: return nil
        }
        guard let kind = A64.CompareAndSwapPairKind.decode(acquire: acquire, release: release) else {
            return nil
        }
        return .compareAndSwapPair(
            kind,
            compare: integerRegister(number: rsNum, width: width),
            value: integerRegister(number: rtNum, width: width),
            base: xRegister(number: rnNum)
        )
    }

    private static func decodeAtomicMemory(_ word: UInt32) -> Instruction? {
        typealias F = A64.AtomicMemory
        guard word & F.classMask == F.baseWord else { return nil }
        let o3 = F.o3.extract(word)
        let opc = F.opc.extract(word)
        let operation: A64.AtomicMemoryOperation
        if o3 == 1 {
            guard opc == 0 else { return nil }
            operation = .swp
        } else {
            guard let op = A64.AtomicMemoryOperation.allCases.first(where: { $0 != .swp && $0.opc == opc }) else {
                return nil
            }
            operation = op
        }

        let size = F.size.extract(word)
        let acquire = F.a.extract(word) == 1
        let release = F.r.extract(word) == 1
        let fixedSize: UInt32?
        let width: Int
        switch size {
        case 0: fixedSize = 0; width = 32
        case 1: fixedSize = 1; width = 32
        case 2: fixedSize = nil; width = 32
        case 3: fixedSize = nil; width = 64
        default: return nil
        }

        let rsNum = F.rs.extract(word)
        let rtNum = F.rt.extract(word)
        let base = xRegister(number: F.rn.extract(word))
        let source = integerRegister(number: rsNum, width: width)

        // Prefer the ST<op> alias when the result register is discarded and the
        // form does not acquire (no `swp` store alias exists).
        if operation.hasStoreAlias && !acquire && rtNum == 0b11111 {
            let kind = A64.AtomicMemoryKind(
                operation: operation, acquire: false, release: release, fixedSize: fixedSize, isStore: true
            )
            return .atomicMemory(kind, source: source, value: nil, base: base)
        }

        let kind = A64.AtomicMemoryKind(
            operation: operation, acquire: acquire, release: release, fixedSize: fixedSize, isStore: false
        )
        return .atomicMemory(kind, source: source, value: integerRegister(number: rtNum, width: width), base: base)
    }

    private static func decodeLoadAcquireRCpc(_ word: UInt32) -> Instruction? {
        typealias F = A64.LoadAcquireRCpc
        guard word & F.classMask == F.baseWord else { return nil }
        let kind: A64.LoadAcquireRCpcKind
        let width: Int
        switch F.size.extract(word) {
        case 0: kind = .ldaprb; width = 32
        case 1: kind = .ldaprh; width = 32
        case 2: kind = .ldapr; width = 32
        case 3: kind = .ldapr; width = 64
        default: return nil
        }
        return .loadAcquireRCpc(
            kind,
            value: integerRegister(number: F.rt.extract(word), width: width),
            base: xRegister(number: F.rn.extract(word))
        )
    }

    private static func decodePrefetch(_ word: UInt32) -> Instruction? {
        // PRFM/PRFUM are load/store single forms with size=11, opc=10, V=0.
        typealias F = A64.LoadStoreSingle
        let sizeOpc = F.size.insert(0b11) | F.opc.insert(0b10)
        let operation = F.rt.extract(word)
        let base = xRegister(number: F.rn.extract(word))

        // PRFM (immediate, unsigned offset), scaled by 8.
        if word & 0xffc0_0000 == F.unsignedBase | sizeOpc {
            let offset = Int64(F.imm12.extract(word)) * 8
            return .prefetch(.prfm, operation: operation, memory: .unsignedOffset(base: base, offset: offset))
        }
        // PRFM (register offset): bit21=1, bits[11:10]=10.
        if word & 0xffe0_0c00 == F.registerOffsetBase | sizeOpc {
            let option = F.option.extract(word)
            let s = F.s.extract(word)
            let shift = s == 1 ? 3 : 0
            let rmWidth = (option == 2 || option == 6) ? 32 : 64
            let rm = integerRegister(number: F.rm.extract(word), width: rmWidth)
            let extend: ExtendKind? = option == 3 ? nil : ExtendKind(rawValue: option)
            return .prefetch(.prfm, operation: operation, memory: .registerOffset(base: base, offset: rm, extend: extend, shift: shift))
        }
        // PRFUM (unscaled immediate): bit21=0, bits[11:10]=00.
        if word & 0xffe0_0c00 == F.unscaledBase | sizeOpc {
            let imm9 = signExtend(F.imm9.extract(word), bitCount: 9)
            let mem: MemoryOperand = imm9 >= 0 ? .unsignedOffset(base: base, offset: imm9) : .signedUnscaled(base: base, offset: imm9)
            return .prefetch(.prfum, operation: operation, memory: mem)
        }
        return nil
    }

    private static func decodeRCpcUnscaled(_ word: UInt32) -> Instruction? {
        typealias F = A64.RCpcUnscaledImmediate
        guard word & F.classMask == F.baseWord else { return nil }
        guard let info = RCpcUnscaledKind.decode(size: F.size.extract(word), opc: F.opc.extract(word)) else { return nil }
        let base = xRegister(number: F.rn.extract(word))
        let target = integerRegister(number: F.rt.extract(word), width: info.width)
        let offset = signExtend(F.imm9.extract(word), bitCount: 9)
        return .rcpcUnscaled(info.kind, target: target, base: base, offset: offset)
    }

    private static func decodeMTEMemoryTag(_ word: UInt32) -> Instruction? {
        // Load/store memory tags (single).
        typealias F = A64.MTEMemoryTag
        guard word & F.classMask == F.baseWord else { return nil }
        let opc = F.opc.extract(word)
        let op2 = F.op2.extract(word)
        let imm9 = signExtend(F.imm9.extract(word), bitCount: 9) * 16
        let base = xRegister(number: F.rn.extract(word))
        let rt = integerRegister(number: F.rt.extract(word), width: 64)

        if op2 != 0 {
            // STG/STZG/ST2G/STZ2G with an addressing mode.
            let kind: A64.MTEStoreTagKind
            switch opc {
            case 0: kind = .stg
            case 1: kind = .stzg
            case 2: kind = .st2g
            case 3: kind = .stz2g
            default: return nil
            }
            let memory: MemoryOperand
            switch op2 {
            case 0b10: memory = imm9 >= 0 ? .unsignedOffset(base: base, offset: imm9) : .signedUnscaled(base: base, offset: imm9)
            case 0b01: memory = .postIndexed(base: base, offset: imm9)
            case 0b11: memory = .preIndexed(base: base, offset: imm9)
            default: return nil
            }
            return .mteStoreTag(kind, source: rt, memory: memory)
        }

        // op2 == 00.
        if opc == 1 {
            // LDG: signed-offset only.
            let memory: MemoryOperand = imm9 >= 0 ? .unsignedOffset(base: base, offset: imm9) : .signedUnscaled(base: base, offset: imm9)
            return .mteLoadTag(target: rt, memory: memory)
        }
        guard let kind = A64.MTETagMultipleKind.decode(opc: opc) else { return nil }
        return .mteTagMultiple(kind, target: rt, base: base)
    }

    private static func decodeMTEStoreTagPair(_ word: UInt32) -> Instruction? {
        // STGP.
        typealias F = A64.MTEStoreTagPair
        guard word & F.classMask == F.baseWord else { return nil }
        let offset = signExtend(F.imm7.extract(word), bitCount: 7) * 16
        let rt2 = integerRegister(number: F.rt2.extract(word), width: 64)
        let base = xRegister(number: F.rn.extract(word))
        let rt = integerRegister(number: F.rt.extract(word), width: 64)
        let memory: MemoryOperand
        switch F.mode.extract(word) {
        case 1: memory = .postIndexed(base: base, offset: offset)
        case 2: memory = offset >= 0 ? .unsignedOffset(base: base, offset: offset) : .signedUnscaled(base: base, offset: offset)
        case 3: memory = .preIndexed(base: base, offset: offset)
        default: return nil
        }
        return .mteStoreTagPair(first: rt, second: rt2, memory: memory)
    }

    private static func decodePointerAuthLoad(_ word: UInt32) -> Instruction? {
        // LDRAA/LDRAB.
        typealias F = A64.PointerAuthLoad
        guard word & F.classMask == F.baseWord else { return nil }
        let kind: A64.PointerAuthLoadKind = F.m.extract(word) == 1 ? .ldrab : .ldraa
        let s = F.s.extract(word)
        let imm9 = F.imm9.extract(word)
        let writeback = F.w.extract(word) == 1
        let offset = signExtend((s << 9) | imm9, bitCount: 10) * 8
        let base = xRegister(number: F.rn.extract(word))
        let target = integerRegister(number: F.rt.extract(word), width: 64)
        let memory: MemoryOperand = writeback
            ? .preIndexed(base: base, offset: offset)
            : .unsignedOffset(base: base, offset: offset)
        return .pointerAuthLoad(kind, target: target, memory: memory)
    }

    private static func decodeLoadLiteral(_ word: UInt32) -> Instruction? {
        typealias F = A64.LoadLiteral
        guard word & F.classMask == F.baseWord else { return nil }
        let opc = F.opc.extract(word)
        let v = F.v.extract(word)
        let offset = signExtend(F.imm19.extract(word), bitCount: 19) * F.scale
        let rt = F.rt.extract(word)
        if v == 1 {
            let width: Int
            switch opc {
            case 0: width = 32
            case 1: width = 64
            case 2: width = 128
            default: return nil
            }
            return .loadLiteralFP(target: floatRegister(number: rt, width: width), offset: offset)
        }
        switch opc {
        case 0: return .loadLiteral(.ldr, target: integerRegister(number: rt, width: 32), offset: offset)
        case 1: return .loadLiteral(.ldr, target: integerRegister(number: rt, width: 64), offset: offset)
        case 2: return .loadLiteral(.ldrsw, target: integerRegister(number: rt, width: 64), offset: offset)
        default: return .prefetchLiteral(operation: rt, offset: offset)   // opc=11: PRFM (literal)
        }
    }

    private static func decodeLoadStoreUnprivileged(_ word: UInt32) -> Instruction? {
        typealias F = A64.LoadStoreUnprivileged
        guard word & F.classMask == F.baseWord else { return nil }
        guard let info = A64.LoadStoreUnprivilegedKind.decode(size: F.size.extract(word), opc: F.opc.extract(word)) else { return nil }
        let base = xRegister(number: F.rn.extract(word))
        let rt = integerRegister(number: F.rt.extract(word), width: info.width)
        let imm9 = signExtend(F.imm9.extract(word), bitCount: 9)
        let mem: MemoryOperand = imm9 >= 0 ? .unsignedOffset(base: base, offset: imm9) : .signedUnscaled(base: base, offset: imm9)
        return .loadStoreUnprivileged(info.kind, target: rt, memory: mem)
    }

    private static func decodeLoadStoreSingle(_ word: UInt32) -> Instruction? {
        typealias F = A64.LoadStoreSingle
        let op = word & 0x3f00_0000
        guard op == 0x3800_0000 || op == 0x3900_0000 else { return nil }
        let size = F.size.extract(word)
        let opc = F.opc.extract(word)
        guard let info = loadStoreSingleKind(size: size, opc: opc) else { return nil }
        let scaledKind = info.scaled
        let unscaledKind = info.unscaled
        let base = xRegister(number: F.rn.extract(word))
        let rt = integerRegister(number: F.rt.extract(word), width: info.rtWidth)

        if op == 0x3900_0000 {
            let offset = Int64(F.imm12.extract(word)) * info.byteSize
            return .loadStoreSingle(scaledKind, target: rt, memory: .unsignedOffset(base: base, offset: offset))
        }

        if (word >> 21) & 1 == 1 {
            guard F.mode.extract(word) == 2 else { return nil }
            let optionRaw = F.option.extract(word)
            let s = F.s.extract(word)
            let rmWidth = (optionRaw == 2 || optionRaw == 6) ? 32 : 64
            let rm = integerRegister(number: F.rm.extract(word), width: rmWidth)
            let shift = s == 1 ? Int(size) : 0
            let extend: ExtendKind? = optionRaw == 3 ? nil : ExtendKind(rawValue: optionRaw)
            return .loadStoreSingle(scaledKind, target: rt, memory: .registerOffset(base: base, offset: rm, extend: extend, shift: shift))
        }

        let imm9 = signExtend(F.imm9.extract(word), bitCount: 9)
        switch F.mode.extract(word) {
        case 0:
            let mem: MemoryOperand = imm9 >= 0 ? .unsignedOffset(base: base, offset: imm9) : .signedUnscaled(base: base, offset: imm9)
            return .loadStoreSingle(unscaledKind, target: rt, memory: mem)
        case 1:
            return .loadStoreSingle(scaledKind, target: rt, memory: .postIndexed(base: base, offset: imm9))
        case 3:
            return .loadStoreSingle(scaledKind, target: rt, memory: .preIndexed(base: base, offset: imm9))
        default:
            return nil
        }
    }

    private static func decodeLoadStorePair(_ word: UInt32) -> Instruction? {
        typealias F = A64.LoadStorePair
        guard word & F.classMask == F.baseWord else { return nil }
        let opc2 = F.opc.extract(word)
        let l = F.l.extract(word)
        // opc=01 is LDPSW (load-only, signed word into 64-bit registers).
        if opc2 == 1 {
            guard l == 1 else { return nil }
            let scale: Int64 = 4
            let offset = signExtend(F.imm7.extract(word), bitCount: 7) * scale
            let rt2 = integerRegister(number: F.rt2.extract(word), width: 64)
            let base = xRegister(number: F.rn.extract(word))
            let rt = integerRegister(number: F.rt.extract(word), width: 64)
            let memory: MemoryOperand
            switch F.mode.extract(word) {
            case 1: memory = .postIndexed(base: base, offset: offset)
            case 2: memory = .unsignedOffset(base: base, offset: offset)
            case 3: memory = .preIndexed(base: base, offset: offset)
            default: return nil
            }
            return .loadStorePair(.ldpsw, first: rt, second: rt2, memory: memory)
        }
        guard opc2 == 0 || opc2 == 2 else { return nil }
        let is64 = opc2 == 2
        let width = is64 ? 64 : 32
        let scale: Int64 = is64 ? 8 : 4
        let offset = signExtend(F.imm7.extract(word), bitCount: 7) * scale
        let rt2 = integerRegister(number: F.rt2.extract(word), width: width)
        let base = xRegister(number: F.rn.extract(word))
        let rt = integerRegister(number: F.rt.extract(word), width: width)
        let memory: MemoryOperand
        let kind: A64.LoadStorePairKind
        switch F.mode.extract(word) {
        case 0:
            kind = l == 1 ? .ldnp : .stnp
            memory = .unsignedOffset(base: base, offset: offset)
        case 1:
            kind = l == 1 ? .ldp : .stp
            memory = .postIndexed(base: base, offset: offset)
        case 2:
            kind = l == 1 ? .ldp : .stp
            memory = .unsignedOffset(base: base, offset: offset)
        case 3:
            kind = l == 1 ? .ldp : .stp
            memory = .preIndexed(base: base, offset: offset)
        default: return nil
        }
        return .loadStorePair(kind, first: rt, second: rt2, memory: memory)
    }

    private static func decodeLoadStoreSingleFP(_ word: UInt32) -> Instruction? {
        // SIMD&FP load/store register: the integer forms with the V (bit 26) set.
        typealias F = A64.LoadStoreSingle
        let op = word & 0x3f00_0000
        guard op == 0x3c00_0000 || op == 0x3d00_0000 else { return nil }
        let size = F.size.extract(word)
        let opc = F.opc.extract(word)
        // opc bit 1 selects the 128-bit (Q) form; opc bit 0 selects load.
        let isLoad = (opc & 1) == 1
        let isQuad = (opc & 2) == 2
        let width: Int
        let byteSize: Int64
        if isQuad {
            guard size == 0 else { return nil }
            width = 128; byteSize = 16
        } else {
            switch size {
            case 0: width = 8;  byteSize = 1
            case 1: width = 16; byteSize = 2
            case 2: width = 32; byteSize = 4
            case 3: width = 64; byteSize = 8
            default: return nil
            }
        }
        let scaledKind: A64.LoadStoreSingleKind = isLoad ? .ldr : .str
        let unscaledKind: A64.LoadStoreSingleKind = isLoad ? .ldur : .stur
        let base = xRegister(number: F.rn.extract(word))
        let rt = floatRegister(number: F.rt.extract(word), width: width)

        if op == 0x3d00_0000 {
            let offset = Int64(F.imm12.extract(word)) * byteSize
            return .loadStoreSingleFP(scaledKind, target: rt, memory: .unsignedOffset(base: base, offset: offset))
        }

        if (word >> 21) & 1 == 1 {
            guard F.mode.extract(word) == 2 else { return nil }
            let optionRaw = F.option.extract(word)
            let s = F.s.extract(word)
            let rmWidth = (optionRaw == 2 || optionRaw == 6) ? 32 : 64
            let rm = integerRegister(number: F.rm.extract(word), width: rmWidth)
            let shift = s == 1 ? Int(log2(Double(byteSize))) : 0
            let extend: ExtendKind? = optionRaw == 3 ? nil : ExtendKind(rawValue: optionRaw)
            return .loadStoreSingleFP(scaledKind, target: rt, memory: .registerOffset(base: base, offset: rm, extend: extend, shift: shift))
        }

        let imm9 = signExtend(F.imm9.extract(word), bitCount: 9)
        switch F.mode.extract(word) {
        case 0:
            let mem: MemoryOperand = imm9 >= 0 ? .unsignedOffset(base: base, offset: imm9) : .signedUnscaled(base: base, offset: imm9)
            return .loadStoreSingleFP(unscaledKind, target: rt, memory: mem)
        case 1:
            return .loadStoreSingleFP(scaledKind, target: rt, memory: .postIndexed(base: base, offset: imm9))
        case 3:
            return .loadStoreSingleFP(scaledKind, target: rt, memory: .preIndexed(base: base, offset: imm9))
        default:
            return nil
        }
    }

    private static func decodeLoadStorePairFP(_ word: UInt32) -> Instruction? {
        // SIMD&FP load/store pair: the integer pair forms with the V (bit 26) set.
        typealias F = A64.LoadStorePair
        guard word & 0x3e00_0000 == 0x2c00_0000 else { return nil }
        let opc2 = F.opc.extract(word)
        let width: Int
        let scale: Int64
        switch opc2 {
        case 0: width = 32;  scale = 4
        case 1: width = 64;  scale = 8
        case 2: width = 128; scale = 16
        default: return nil
        }
        let l = F.l.extract(word)
        let offset = signExtend(F.imm7.extract(word), bitCount: 7) * scale
        let rt2 = floatRegister(number: F.rt2.extract(word), width: width)
        let base = xRegister(number: F.rn.extract(word))
        let rt = floatRegister(number: F.rt.extract(word), width: width)
        let memory: MemoryOperand
        let kind: A64.LoadStorePairKind
        switch F.mode.extract(word) {
        case 0:
            kind = l == 1 ? .ldnp : .stnp
            memory = .unsignedOffset(base: base, offset: offset)
        case 1:
            kind = l == 1 ? .ldp : .stp
            memory = .postIndexed(base: base, offset: offset)
        case 2:
            kind = l == 1 ? .ldp : .stp
            memory = .unsignedOffset(base: base, offset: offset)
        case 3:
            kind = l == 1 ? .ldp : .stp
            memory = .preIndexed(base: base, offset: offset)
        default: return nil
        }
        return .loadStorePairFP(kind, first: rt, second: rt2, memory: memory)
    }

    private static func decodeLoadStoreMultiple(_ word: UInt32) -> Instruction? {
        // Advanced SIMD load/store multiple structures.
        typealias F = A64.LoadStoreMultiple
        guard word & F.classMask == F.baseWord else { return nil }
        let post = F.post.extract(word)
        if post == 0 {
            // The non-post form requires bits[21:16] == 0.
            guard (word >> 16) & 0x3f == 0 else { return nil }
        }
        let q = F.q.extract(word)
        let l = F.l.extract(word)
        let opcode = F.opcode.extract(word)
        let size = F.size.extract(word)
        let rn = F.rn.extract(word)
        let rt = F.rt.extract(word)

        guard let (structure, count) = A64.LoadStoreMultipleKind.decode(opcode: opcode),
              let kind = A64.LoadStoreMultipleKind.forStructure(structure, isLoad: l == 1),
              let arrangement = fullVectorArrangement(size: size, q: q) else { return nil }

        let list = A64.VectorRegisterList(firstNumber: rt, count: count, arrangement: arrangement)
        let base = xRegister(number: rn)
        let address: A64.VectorMemoryOperand
        if post == 0 {
            address = .base(base)
        } else {
            let rm = F.rm.extract(word)
            address = rm == 0x1f ? .postImmediate(base) : .postRegister(base, offset: xRegister(number: rm))
        }
        return .loadStoreMultiple(kind, registers: list, address: address)
    }

    private static func decodeLoadStoreSingleStructure(_ word: UInt32) -> Instruction? {
        // Advanced SIMD load/store single structure & replicate.
        typealias F = A64.LoadStoreSingleStructure
        guard word & F.classMask == F.baseWord else { return nil }
        let post = F.post.extract(word)
        if post == 0 {
            // Non-post form: the Rm field (bits[20:16]) must be 0.
            guard (word >> 16) & 0x1f == 0 else { return nil }
        }
        let q = F.q.extract(word)
        let l = F.l.extract(word)
        let r = F.r.extract(word)
        let opcode = F.opcode.extract(word)
        let s = F.s.extract(word)
        let size = F.size.extract(word)
        let rn = F.rn.extract(word)
        let rt = F.rt.extract(word)
        let sizeClass = opcode >> 1
        let opcode0 = opcode & 1
        let selem = Int((opcode0 << 1) | r) + 1

        let base = xRegister(number: rn)
        func address() -> A64.VectorMemoryOperand {
            if post == 0 { return .base(base) }
            let rm = F.rm.extract(word)
            return rm == 0x1f ? .postImmediate(base) : .postRegister(base, offset: xRegister(number: rm))
        }

        if sizeClass == 0b11 {
            // Replicate form (LD1R–LD4R): load-only with S == 0.
            guard l == 1, s == 0 else { return nil }
            guard let arrangement = fullVectorArrangement(size: size, q: q),
                  let kind = A64.LoadStoreReplicateKind.forStructure(selem) else { return nil }
            let list = A64.VectorRegisterList(firstNumber: rt, count: selem, arrangement: arrangement)
            return .loadStoreReplicate(kind, registers: list, address: address())
        }

        // Single-lane form: recover the element width and lane index from Q/S/size.
        let width: A64.VectorElementWidth
        let index: Int
        switch sizeClass {
        case 0b00:
            width = .b
            index = Int((q << 3) | (s << 2) | size)
        case 0b01:
            guard size & 1 == 0 else { return nil }
            width = .h
            index = Int((q << 2) | (s << 1) | (size >> 1))
        case 0b10:
            if size == 0b00 {
                width = .s
                index = Int((q << 1) | s)
            } else if size == 0b01 {
                guard s == 0 else { return nil }
                width = .d
                index = Int(q)
            } else {
                return nil
            }
        default:
            return nil
        }
        guard let kind = A64.LoadStoreMultipleKind.forStructure(selem, isLoad: l == 1) else { return nil }
        let list = A64.VectorLaneList(firstNumber: rt, count: selem, width: width, index: index)
        return .loadStoreSingleLane(kind, registers: list, address: address())
    }

    private static func decodeVectorTableLookup(_ word: UInt32) -> Instruction? {
        // Advanced SIMD table lookup.
        typealias F = A64.VectorTableLookup
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let rm = F.rm.extract(word)
        let len = F.len.extract(word)
        let op = F.op.extract(word)
        let rn = F.rn.extract(word)
        let rd = F.rd.extract(word)
        let arrangement: A64.VectorArrangement = q == 1 ? .b16 : .b8
        let kind: A64.VectorTableLookupKind = op == 1 ? .tbx : .tbl
        let table = A64.VectorRegisterList(firstNumber: rn, count: Int(len) + 1, arrangement: .b16)
        return .vectorTableLookup(
            kind,
            destination: A64.VectorRegister(number: rd, arrangement: arrangement),
            table: table,
            index: A64.VectorRegister(number: rm, arrangement: arrangement)
        )
    }

    private static func fullVectorArrangement(size: UInt32, q: UInt32) -> A64.VectorArrangement? {
        switch (size, q) {
        case (0b00, 0): return .b8
        case (0b00, 1): return .b16
        case (0b01, 0): return .h4
        case (0b01, 1): return .h8
        case (0b10, 0): return .s2
        case (0b10, 1): return .s4
        case (0b11, 0): return .d1
        case (0b11, 1): return .d2
        default: return nil
        }
    }

    private static func loadStoreSingleKind(size: UInt32, opc: UInt32) -> (scaled: A64.LoadStoreSingleKind, unscaled: A64.LoadStoreSingleKind, rtWidth: Int, byteSize: Int64)? {
        switch (size, opc) {
        case (0, 0): return (.strb, .sturb, 32, 1)
        case (0, 1): return (.ldrb, .ldurb, 32, 1)
        case (0, 2): return (.ldrsb, .ldursb, 64, 1)
        case (0, 3): return (.ldrsb, .ldursb, 32, 1)
        case (1, 0): return (.strh, .sturh, 32, 2)
        case (1, 1): return (.ldrh, .ldurh, 32, 2)
        case (1, 2): return (.ldrsh, .ldursh, 64, 2)
        case (1, 3): return (.ldrsh, .ldursh, 32, 2)
        case (2, 0): return (.str, .stur, 32, 4)
        case (2, 1): return (.ldr, .ldur, 32, 4)
        case (2, 2): return (.ldrsw, .ldursw, 64, 4)
        case (3, 0): return (.str, .stur, 64, 8)
        case (3, 1): return (.ldr, .ldur, 64, 8)
        default: return nil
        }
    }

    private static func decodeFPDataProcessing2(_ word: UInt32) -> Instruction? {
        typealias F = A64.FPDataProcessing2
        guard word & F.classMask == F.baseWord else { return nil }
        guard let width = floatWidth(forPtype: F.type.extract(word)) else { return nil }
        let kind: A64.FPDataProcessing2Kind
        switch F.opcode.extract(word) {
        case 0b0000: kind = .fmul
        case 0b0001: kind = .fdiv
        case 0b0010: kind = .fadd
        case 0b0011: kind = .fsub
        case 0b0100: kind = .fmax
        case 0b0101: kind = .fmin
        case 0b0110: kind = .fmaxnm
        case 0b0111: kind = .fminnm
        case 0b1000: kind = .fnmul
        default: return nil
        }
        return .fpDataProcessing2(
            kind,
            destination: floatRegister(number: F.rd.extract(word), width: width),
            first: floatRegister(number: F.rn.extract(word), width: width),
            second: floatRegister(number: F.rm.extract(word), width: width)
        )
    }

    private static func decodeBFloat16Convert(_ word: UInt32) -> Instruction? {
        // BFCVT Hd, Sn: fixed encoding (ptype=01, opcode=000110); only Rn/Rd vary.
        guard word & 0xffff_fc00 == A64.FPMisc.bfcvt else { return nil }
        return .bfloat16Convert(
            destination: floatRegister(number: word & 0x1f, width: 16),
            source: floatRegister(number: (word >> 5) & 0x1f, width: 32)
        )
    }

    private static func decodeFPDataProcessing1(_ word: UInt32) -> Instruction? {
        typealias F = A64.FPDataProcessing1
        guard word & F.classMask == F.baseWord else { return nil }
        guard let width = floatWidth(forPtype: F.type.extract(word)) else { return nil }
        let opcode = F.opcode.extract(word)
        let rn = floatRegister(number: F.rn.extract(word), width: width)
        let kind: A64.FPDataProcessing1Kind
        switch opcode {
        case 0b000000: kind = .fmov
        case 0b000001: kind = .fabs
        case 0b000010: kind = .fneg
        case 0b000011: kind = .fsqrt
        case 0b001000: kind = .frintn
        case 0b001001: kind = .frintp
        case 0b001010: kind = .frintm
        case 0b001011: kind = .frintz
        case 0b001100: kind = .frinta
        case 0b001110: kind = .frintx
        case 0b001111: kind = .frinti
        case 0b010000: kind = .frint32z
        case 0b010001: kind = .frint32x
        case 0b010010: kind = .frint64z
        case 0b010011: kind = .frint64x
        case 0b000100, 0b000101, 0b000111:
            guard let target = floatWidth(forPtype: opcode & 3), target != width else { return nil }
            return .fpConvertPrecision(
                destination: floatRegister(number: F.rd.extract(word), width: target),
                source: rn
            )
        default:
            return nil
        }
        // frint32*/frint64* have no half-precision form.
        if !kind.allowsHalf, width == 16 { return nil }
        return .fpDataProcessing1(kind, destination: floatRegister(number: F.rd.extract(word), width: width), source: rn)
    }

    private static func decodeFPDataProcessing3(_ word: UInt32) -> Instruction? {
        typealias F = A64.FPDataProcessing3
        guard word & F.classMask == F.baseWord else { return nil }
        guard let width = floatWidth(forPtype: F.type.extract(word)) else { return nil }
        let o1 = F.o1.extract(word)
        let o0 = F.o0.extract(word)
        let kind: A64.FPDataProcessing3Kind
        switch (o1, o0) {
        case (0, 0): kind = .fmadd
        case (0, 1): kind = .fmsub
        case (1, 0): kind = .fnmadd
        case (1, 1): kind = .fnmsub
        default: return nil
        }
        return .fpDataProcessing3(
            kind,
            destination: floatRegister(number: F.rd.extract(word), width: width),
            first: floatRegister(number: F.rn.extract(word), width: width),
            second: floatRegister(number: F.rm.extract(word), width: width),
            third: floatRegister(number: F.ra.extract(word), width: width)
        )
    }

    private static func decodeFPCompare(_ word: UInt32) -> Instruction? {
        typealias F = A64.FPCompare
        guard word & F.classMask == F.baseWord else { return nil }
        guard let width = floatWidth(forPtype: F.type.extract(word)) else { return nil }
        let opcode2 = F.opcode2.extract(word)
        let kind: A64.FPCompareKind = (opcode2 >> 4) & 1 == 1 ? .fcmpe : .fcmp
        let rn = floatRegister(number: F.rn.extract(word), width: width)
        let second: A64.FPCompareOperand
        if (opcode2 >> 3) & 1 == 1 {
            guard F.rm.extract(word) == 0 else { return nil }
            second = .zero
        } else {
            second = .register(floatRegister(number: F.rm.extract(word), width: width))
        }
        return .fpCompare(kind, first: rn, second: second)
    }

    private static func decodeFPMoveVectorHigh(_ word: UInt32) -> Instruction? {
        // `fmov x<d>, v<n>.d[1]` (opcode 110) / `fmov v<d>.d[1], x<n>` (opcode 111).
        guard word & 0xfffe_fc00 == A64.FPMisc.fmovVectorHighToGeneral else { return nil }
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        if (word >> 16) & 1 == 0 {
            return .fpMoveVectorHighToGeneral(
                destination: integerRegister(number: rdNum, width: 64),
                source: A64.VectorElement(number: rnNum, width: .d, index: 1)
            )
        }
        return .fpMoveGeneralToVectorHigh(
            destination: A64.VectorElement(number: rdNum, width: .d, index: 1),
            source: integerRegister(number: rnNum, width: 64)
        )
    }

    private static func decodeFPFixedPointConvert(_ word: UInt32) -> Instruction? {
        typealias F = A64.FPFixedConversion
        guard word & F.classMask == F.baseWord else { return nil }
        guard let width = floatWidth(forPtype: F.type.extract(word)) else { return nil }
        let sf = F.sf.extract(word)
        let generalWidth = sf == 1 ? 64 : 32
        let rmode = F.rmode.extract(word)
        let opcode = F.opcode.extract(word)
        let scale = F.scale.extract(word)
        // For 32-bit general registers `scale` must have its high bit set (fbits 1...32).
        if sf == 0 { guard scale >= 32 else { return nil } }
        let fbits = 64 - scale
        guard fbits >= 1 else { return nil }
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)
        switch (rmode, opcode) {
        case (0b11, 0b000), (0b11, 0b001):
            let kind: A64.FPConvertToIntKind = opcode == 0b000 ? .fcvtzs : .fcvtzu
            return .fpConvertToFixed(kind, destination: integerRegister(number: rdNum, width: generalWidth), source: floatRegister(number: rnNum, width: width), fbits: fbits)
        case (0b00, 0b010), (0b00, 0b011):
            let kind: A64.FPConvertFromIntKind = opcode == 0b010 ? .scvtf : .ucvtf
            return .fpConvertFromFixed(kind, destination: floatRegister(number: rdNum, width: width), source: integerRegister(number: rnNum, width: generalWidth), fbits: fbits)
        default:
            return nil
        }
    }

    private static func decodeFPConditionalSelect(_ word: UInt32) -> Instruction? {
        typealias F = A64.FPConditionalSelect
        guard word & F.classMask == F.baseWord else { return nil }
        guard let width = floatWidth(forPtype: F.type.extract(word)) else { return nil }
        guard let condition = Condition(rawValue: F.cond.extract(word)) else { return nil }
        return .fpConditionalSelect(
            destination: floatRegister(number: F.rd.extract(word), width: width),
            first: floatRegister(number: F.rn.extract(word), width: width),
            second: floatRegister(number: F.rm.extract(word), width: width),
            condition: condition
        )
    }

    private static func decodeFPConditionalCompare(_ word: UInt32) -> Instruction? {
        typealias F = A64.FPConditionalCompare
        guard word & F.classMask == F.baseWord else { return nil }
        guard let width = floatWidth(forPtype: F.type.extract(word)) else { return nil }
        guard let condition = Condition(rawValue: F.cond.extract(word)) else { return nil }
        let kind: A64.FPConditionalCompareKind = F.op.extract(word) == 1 ? .fccmpe : .fccmp
        return .fpConditionalCompare(
            kind,
            first: floatRegister(number: F.rn.extract(word), width: width),
            second: floatRegister(number: F.rm.extract(word), width: width),
            nzcv: F.nzcv.extract(word),
            condition: condition
        )
    }

    private static func decodeFPMoveImmediate(_ word: UInt32) -> Instruction? {
        typealias F = A64.FPMoveImmediate
        guard word & F.classMask == F.baseWord else { return nil }
        guard let width = floatWidth(forPtype: F.type.extract(word)) else { return nil }
        let value = A64FloatImmediate.decode(F.imm8.extract(word))
        return .fpMoveImmediate(destination: floatRegister(number: F.rd.extract(word), width: width), value: value)
    }

    private static func decodeFPIntegerConversion(_ word: UInt32) -> Instruction? {
        typealias F = A64.FPIntegerConversion
        guard word & F.classMask == F.baseWord else { return nil }
        guard let width = floatWidth(forPtype: F.type.extract(word)) else { return nil }
        let sf = F.sf.extract(word)
        let generalWidth = sf == 1 ? 64 : 32
        let rmode = F.rmode.extract(word)
        let opcode = F.opcode.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)
        if let kind = A64.FPConvertToIntKind.decode(rmode: rmode, opcode: opcode) {
            return .fpConvertToInt(kind, destination: integerRegister(number: rdNum, width: generalWidth), source: floatRegister(number: rnNum, width: width))
        }
        switch (rmode, opcode) {
        case (0b00, 0b010), (0b00, 0b011):
            let kind: A64.FPConvertFromIntKind = opcode == 0b010 ? .scvtf : .ucvtf
            return .fpConvertFromInt(kind, destination: floatRegister(number: rdNum, width: width), source: integerRegister(number: rnNum, width: generalWidth))
        case (0b00, 0b110):
            // Half-precision (type=11) pairs with either a 32- or 64-bit register;
            // single (type=00) pairs with W, double (type=01) with X.
            guard width == 16 || width == 32 || width == 64 else { return nil }
            return .fpMoveToGeneral(destination: integerRegister(number: rdNum, width: generalWidth), source: floatRegister(number: rnNum, width: width))
        case (0b00, 0b111):
            guard width == 16 || width == 32 || width == 64 else { return nil }
            return .fpMoveFromGeneral(destination: floatRegister(number: rdNum, width: width), source: integerRegister(number: rnNum, width: generalWidth))
        case (0b11, 0b110):
            // FJCVTZS: fixed 32-bit general destination, double-precision source.
            guard sf == 0, width == 64 else { return nil }
            return .fjcvtzs(destination: integerRegister(number: rdNum, width: 32), source: floatRegister(number: rnNum, width: 64))
        default:
            return nil
        }
    }

    private static func decodeAcrossLanes(_ word: UInt32) -> Instruction? {
        typealias F = A64.VectorAcrossLanes
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let u = F.u.extract(word)
        let size = F.size.extract(word)
        let opcode = F.opcode.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)

        // Floating-point across lanes (U=1, opcode 01100 / 01111).
        if u == 1 && (opcode == 0b01100 || opcode == 0b01111) {
            let sz = (word >> 22) & 1
            let o1 = (word >> 23) & 1
            guard sz == 0, q == 1 else { return nil }   // only `.4s` supported
            let kind: A64.AcrossLanesFPKind
            switch (opcode, o1) {
            case (0b01111, 0): kind = .fmaxv
            case (0b01111, 1): kind = .fminv
            case (0b01100, 0): kind = .fmaxnmv
            case (0b01100, 1): kind = .fminnmv
            default: return nil
            }
            return .acrossLanesFP(kind, destination: floatRegister(number: rdNum, width: 32), source: VectorRegister(number: rnNum, arrangement: .s4))
        }

        // Half-precision (FP16) floating-point across lanes (U=0, opcode 01100 / 01111).
        if u == 0 && (opcode == 0b01100 || opcode == 0b01111) {
            let sz = (word >> 22) & 1
            let o1 = (word >> 23) & 1
            guard sz == 0 else { return nil }
            let kind: A64.AcrossLanesFPKind
            switch (opcode, o1) {
            case (0b01111, 0): kind = .fmaxv
            case (0b01111, 1): kind = .fminv
            case (0b01100, 0): kind = .fmaxnmv
            case (0b01100, 1): kind = .fminnmv
            default: return nil
            }
            let arrangement: A64.VectorArrangement = q == 1 ? .h8 : .h4
            return .acrossLanesFP(kind, destination: floatRegister(number: rdNum, width: 16), source: VectorRegister(number: rnNum, arrangement: arrangement))
        }

        let kind: A64.AcrossLanesIntegerKind
        switch (u, opcode) {
        case (0, 0b00011): kind = .saddlv
        case (1, 0b00011): kind = .uaddlv
        case (0, 0b01010): kind = .smaxv
        case (1, 0b01010): kind = .umaxv
        case (0, 0b11010): kind = .sminv
        case (1, 0b11010): kind = .uminv
        case (0, 0b11011): kind = .addv
        default: return nil
        }
        guard let arrangement = vectorArrangement(size: size, q: q) else { return nil }
        let isLong = kind == .saddlv || kind == .uaddlv
        let destinationWidth = isLong ? arrangement.elementWidth * 2 : arrangement.elementWidth
        return .acrossLanesInteger(kind, destination: floatRegister(number: rdNum, width: destinationWidth), source: VectorRegister(number: rnNum, arrangement: arrangement))
    }

    private static func decodeCryptoAES(_ word: UInt32) -> Instruction? {
        // Crypto AES (`Vd.16b, Vn.16b`): fixed bits 01001110 00 10100 0 001xx 10.
        // Decoded ahead of the two-register-misc group, whose mask does not check
        // bit[19] and would otherwise mis-decode these as `cls`/`clz` forms.
        typealias F = A64.Crypto
        guard word & 0xffff_cc00 == (F.aesBase | (0b00100 << 12)) else { return nil }
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        guard let kind = A64.CryptoAESKind.decode(opcode: opcode) else { return nil }
        return .cryptoAES(
            kind,
            destination: VectorRegister(number: rdNum, arrangement: .b16),
            source: VectorRegister(number: rnNum, arrangement: .b16)
        )
    }

    private static func decodeCryptoSHA3(_ word: UInt32) -> Instruction? {
        // Crypto three-register SHA: 01011110 000 Rm 0 opcode 00 Rn Rd.
        typealias F = A64.Crypto
        guard word & 0xffe0_8c00 == F.sha3Base else { return nil }
        let mNum = F.rm.extract(word)
        let opcode = (word >> 12) & 0x7
        let nNum = F.rn.extract(word)
        let dNum = F.rd.extract(word)
        guard let kind = A64.CryptoSHA3Kind.decode(opcode: opcode) else { return nil }
        return .cryptoSHA3(kind, d: dNum, n: nNum, m: mNum)
    }

    private static func decodeCryptoSHA2(_ word: UInt32) -> Instruction? {
        // Crypto two-register SHA: 01011110 00 10100 0 000xx 10 Rn Rd.
        typealias F = A64.Crypto
        guard word & 0xffff_cc00 == F.sha2Base else { return nil }
        let opcode = (word >> 12) & 0x1f
        let nNum = (word >> 5) & 0x1f
        let dNum = word & 0x1f
        guard let kind = A64.CryptoSHA2Kind.decode(opcode: opcode) else { return nil }
        return .cryptoSHA2(kind, d: dNum, n: nNum)
    }

    private static func decodeCryptoSHA512(_ word: UInt32) -> Instruction? {
        // Three-register SHA512: 11001110 011 Rm 1 0 00 opcode Rn Rd.
        typealias F = A64.Crypto
        guard word & 0xffe0_f000 == F.sha512Base else { return nil }
        let opcode = (word >> 10) & 0x3
        guard let kind = A64.CryptoSHA512Kind.decode(opcode: opcode) else { return nil }
        return .cryptoSHA512(kind, d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f)
    }

    private static func decodeCryptoTwoReg(_ word: UInt32) -> Instruction? {
        // Two-register SHA512/SM4: 11001110 110 00000 10 00 opcode Rn Rd.
        typealias F = A64.Crypto
        guard word & 0xffff_f000 == F.twoRegBase else { return nil }
        let opcode = (word >> 10) & 0x3
        guard let kind = A64.CryptoTwoRegKind.decode(opcode: opcode) else { return nil }
        return .cryptoTwoReg(kind, d: word & 0x1f, n: (word >> 5) & 0x1f)
    }

    private static func decodeCryptoSM3(_ word: UInt32) -> Instruction? {
        // Three-register SM3/SM4: 11001110 011 Rm 1 1 00 opcode Rn Rd.
        typealias F = A64.Crypto
        guard word & 0xffe0_f000 == F.sm3Base else { return nil }
        let opcode = (word >> 10) & 0x3
        guard let kind = A64.CryptoSM3Kind.decode(opcode: opcode) else { return nil }
        return .cryptoSM3(kind, d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f)
    }

    private static func decodeCryptoSM3Indexed(_ word: UInt32) -> Instruction? {
        // Three-register SM3 "imm2": 11001110 010 Rm 1 0 imm2 opcode Rn Rd.
        typealias F = A64.Crypto
        guard word & 0xffe0_c000 == F.sm3IndexedBase else { return nil }
        let opcode = (word >> 10) & 0x3
        guard let kind = A64.CryptoSM3IndexedKind.decode(opcode: opcode) else { return nil }
        let index = (word >> 12) & 0x3
        return .cryptoSM3Indexed(kind, d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f, index: index)
    }

    private static func decodeCryptoSM3SS1(_ word: UInt32) -> Instruction? {
        // Four-register SM3: 11001110 010 Rm 0 Ra Rn Rd.
        typealias F = A64.Crypto
        guard word & 0xffe0_8000 == F.sm3ss1Base else { return nil }
        return .cryptoSM3SS1(d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f, a: (word >> 10) & 0x1f)
    }

    private static func decodeCryptoSHA3Four(_ word: UInt32) -> Instruction? {
        // Four-register SHA3: 11001110 0 Op0 Rm 0 Ra Rn Rd.
        typealias F = A64.Crypto
        guard word & 0xff80_8000 == F.sha3FourBase else { return nil }
        let op0 = (word >> 21) & 0x3
        guard let kind = A64.CryptoSHA3FourKind.decode(op0: op0) else { return nil }
        return .cryptoSHA3Four(kind, d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f, a: (word >> 10) & 0x1f)
    }

    private static func decodeCryptoRAX1(_ word: UInt32) -> Instruction? {
        // Three-register SHA3 RAX1: 11001110 011 Rm 1 0 0011 Rn Rd.
        typealias F = A64.Crypto
        guard word & 0xffe0_fc00 == F.rax1Base else { return nil }
        return .cryptoRAX1(d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f)
    }

    private static func decodeCryptoXAR(_ word: UInt32) -> Instruction? {
        // XAR: 11001110 100 Rm imm6 Rn Rd.
        typealias F = A64.Crypto
        guard word & 0xffe0_0000 == F.xarBase else { return nil }
        let imm6 = (word >> 10) & 0x3f
        return .cryptoXAR(d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f, imm6: imm6)
    }

    private static func decodeVectorTwoRegisterMiscFP16(_ word: UInt32) -> Instruction? {
        // Advanced SIMD two-register miscellaneous (FP16): bits[28:24]=01110,
        // [22]=1, [21:17]=11100, [11:10]=10. `a`=bit23 carries the regular form's
        // high `size` bit and selects the operation sub-page.
        guard word & 0x9f7e_0c00 == A64.AdvSIMD.twoRegisterMiscFP16 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let a = (word >> 23) & 1
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        let arrangement: A64.VectorArrangement = q == 1 ? .h8 : .h4
        func reg(_ n: UInt32) -> VectorRegister { VectorRegister(number: n, arrangement: arrangement) }

        // fabs / fneg / fsqrt (`a`=1).
        if a == 1 {
            let miscKind: A64.VectorTwoRegisterMiscKind?
            switch (u, opcode) {
            case (0, 0b01111): miscKind = .fabs
            case (1, 0b01111): miscKind = .fneg
            case (1, 0b11111): miscKind = .fsqrt
            default: miscKind = nil
            }
            if let kind = miscKind {
                return .vectorTwoRegisterMisc(kind, destination: reg(rdNum), source: reg(rnNum))
            }
        }

        // Compare against #0.0 (`a`=1): opcodes 01100/01101/01110.
        if a == 1, [0b01100, 0b01101, 0b01110].contains(opcode),
           let kind = A64.VectorCompareZeroKind.decode(u: u, opcode: opcode, isFloat: true) {
            return .vectorCompareZero(kind, destination: reg(rdNum), source: reg(rnNum))
        }

        // FP↔int convert: opcodes 11010/11011/11100/11101 (high size bit = `a`).
        if [0b11010, 0b11011, 0b11100, 0b11101].contains(opcode),
           let kind = A64.VectorConvertKind.decode(u: u, opcode: opcode, sizeHi: a) {
            return .vectorConvert(kind, destination: reg(rdNum), source: reg(rnNum))
        }

        // FRINT* and FRECPE/FRSQRTE: opcodes 11000/11001/11100/11101.
        if [0b11000, 0b11001, 0b11100, 0b11101].contains(opcode),
           let kind = A64.VectorRoundReciprocalKind.decode(u: u, opcode: opcode, sizeHi: a), kind.allowsFP16 {
            return .vectorRoundReciprocal(kind, destination: reg(rdNum), source: reg(rnNum))
        }

        return nil
    }

    private static func decodeVectorFRINTToInteger(_ word: UInt32) -> Instruction? {
        // Vector frint32/frint64 share the two-register-misc base but encode the
        // FP `sz` at bit22 with size-hi (bit23) = 0 — which is what distinguishes
        // frint64x from fsqrt (opcode 11111, but fsqrt has bit23=1). Opcodes
        // 11110/11111 select frint32/frint64; U selects the z/x rounding mode.
        guard word & 0x9fa0_0c00 == 0x0e20_0800 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let sz = (word >> 22) & 1
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        let kind: A64.VectorTwoRegisterMiscKind
        switch (u, opcode) {
        case (0, 0b11110): kind = .frint32z
        case (1, 0b11110): kind = .frint32x
        case (0, 0b11111): kind = .frint64z
        case (1, 0b11111): kind = .frint64x
        default: return nil
        }

        let arrangement: A64.VectorArrangement
        switch (sz, q) {
        case (0, 0): arrangement = .s2
        case (0, 1): arrangement = .s4
        case (1, 1): arrangement = .d2
        default: return nil   // sz=1,q=0 would be the reserved scalar `1d`.
        }
        return .vectorTwoRegisterMisc(
            kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            source: VectorRegister(number: rnNum, arrangement: arrangement)
        )
    }

    private static func decodeVectorTwoRegisterMisc(_ word: UInt32) -> Instruction? {
        typealias F = A64.VectorTwoRegisterMisc
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let u = F.u.extract(word)
        let size = F.size.extract(word)
        let opcode = F.opcode.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)

        let kind: A64.VectorTwoRegisterMiscKind
        switch (u, opcode) {
        case (0, 0b00000): kind = .rev64
        case (1, 0b00000): kind = .rev32
        case (0, 0b00001): kind = .rev16
        case (0, 0b00101): kind = .cnt
        case (1, 0b00101): kind = size == 0b01 ? .rbit : .mvn
        case (0, 0b00100): kind = .cls
        case (1, 0b00100): kind = .clz
        case (0, 0b00111): kind = .sqabs
        case (1, 0b00111): kind = .sqneg
        case (0, 0b00011): kind = .suqadd
        case (1, 0b00011): kind = .usqadd
        case (0, 0b01011): kind = .abs
        case (1, 0b01011): kind = .neg
        case (0, 0b01111): kind = .fabs
        case (1, 0b01111): kind = .fneg
        case (1, 0b11111): kind = .fsqrt
        default: return nil
        }

        guard let arrangement = vectorTwoRegisterMiscArrangement(kind, size: size, q: q) else { return nil }
        return .vectorTwoRegisterMisc(
            kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            source: VectorRegister(number: rnNum, arrangement: arrangement)
        )
    }

    private static func decodeVectorCompareZero(_ word: UInt32) -> Instruction? {
        // Shares the two-register-misc encoding; selected by the compare-against-zero opcodes.
        typealias F = A64.VectorTwoRegisterMisc
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let u = F.u.extract(word)
        let size = F.size.extract(word)
        let opcode = F.opcode.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)

        // Integer opcodes 01000/01001/01010; floating-point 01100/01101/01110.
        let isFloat: Bool
        switch opcode {
        case 0b01000, 0b01001, 0b01010: isFloat = false
        case 0b01100, 0b01101, 0b01110: isFloat = true
        default: return nil
        }
        guard let kind = A64.VectorCompareZeroKind.decode(u: u, opcode: opcode, isFloat: isFloat),
              let arrangement = fullVectorArrangement(size: size, q: q) else { return nil }
        if isFloat {
            guard [A64.VectorArrangement.s2, .s4, .d2].contains(arrangement) else { return nil }
        } else {
            guard arrangement != .d1 else { return nil }  // 1d is the scalar form.
        }
        return .vectorCompareZero(
            kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            source: VectorRegister(number: rnNum, arrangement: arrangement)
        )
    }

    private static func decodeVectorConvert(_ word: UInt32) -> Instruction? {
        // Shares the two-register-misc encoding; selected by opcodes 11010/11011/11100/11101.
        typealias F = A64.VectorTwoRegisterMisc
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let u = F.u.extract(word)
        let sizeHi = (word >> 23) & 1
        let sz = (word >> 22) & 1
        let opcode = F.opcode.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)

        switch opcode {
        case 0b11010, 0b11011, 0b11100, 0b11101: break
        default: return nil
        }
        guard let kind = A64.VectorConvertKind.decode(u: u, opcode: opcode, sizeHi: sizeHi) else { return nil }
        // `sz` selects single (2s/4s) vs. double (2d) precision.
        let arrangement: A64.VectorArrangement
        switch (sz, q) {
        case (0, 0): arrangement = .s2
        case (0, 1): arrangement = .s4
        case (1, 1): arrangement = .d2
        default: return nil
        }
        return .vectorConvert(
            kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            source: VectorRegister(number: rnNum, arrangement: arrangement)
        )
    }

    private static func decodeVectorExtractNarrow(_ word: UInt32) -> Instruction? {
        // Shares the two-register-misc encoding; selected by opcodes 10010/10100.
        typealias F = A64.VectorTwoRegisterMisc
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let u = F.u.extract(word)
        let size = F.size.extract(word)
        let opcode = F.opcode.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)

        guard opcode == 0b10010 || opcode == 0b10100 else { return nil }
        guard let kind = A64.VectorExtractNarrowKind.decode(u: u, opcode: opcode),
              let destination = fullVectorArrangement(size: size, q: q),
              [A64.VectorArrangement.b8, .b16, .h4, .h8, .s2, .s4].contains(destination) else { return nil }
        // The source is the fully populated arrangement one element-size up.
        let source: A64.VectorArrangement
        switch destination {
        case .b8, .b16: source = .h8
        case .h4, .h8: source = .s4
        case .s2, .s4: source = .d2
        default: return nil
        }
        return .vectorExtractNarrow(
            kind,
            destination: VectorRegister(number: rdNum, arrangement: destination),
            source: VectorRegister(number: rnNum, arrangement: source)
        )
    }

    private static func decodeVectorFPConvertPrecision(_ word: UInt32) -> Instruction? {
        // Shares the two-register-misc encoding; selected by opcodes 10110 (fcvtn/fcvtxn) / 10111 (fcvtl).
        guard word & 0x9f20_0c00 == 0x0e20_0800 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let sz = (word >> 22) & 1
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        // BFCVTN/BFCVTN2 (FP32→BF16) reuse opcode 10110 but with the high size
        // bit set (size=10); the Q bit selects the bottom/top half.
        if (word >> 23) & 1 == 1 {
            guard u == 0, sz == 0, opcode == 0b10110 else { return nil }
            let top = q == 1
            return .vectorBFConvertNarrow(top: top,
                destination: VectorRegister(number: rdNum, arrangement: top ? .h8 : .h4),
                source: VectorRegister(number: rnNum, arrangement: .s4))
        }

        guard opcode == 0b10110 || opcode == 0b10111 else { return nil }
        guard let kind = A64.VectorFPConvertPrecisionKind.decode(u: u, opcode: opcode) else { return nil }
        let upper = q == 1

        let source: A64.VectorArrangement
        let destination: A64.VectorArrangement
        switch kind {
        case .fcvtn:
            switch sz {
            case 0: source = .s4; destination = upper ? .h8 : .h4
            default: source = .d2; destination = upper ? .s4 : .s2
            }
        case .fcvtl:
            switch sz {
            case 0: source = upper ? .h8 : .h4; destination = .s4
            default: source = upper ? .s4 : .s2; destination = .d2
            }
        case .fcvtxn:
            guard sz == 1 else { return nil }
            source = .d2; destination = upper ? .s4 : .s2
        }
        return .vectorFPConvertPrecision(
            kind,
            upper: upper,
            destination: VectorRegister(number: rdNum, arrangement: destination),
            source: VectorRegister(number: rnNum, arrangement: source)
        )
    }

    private static func decodeVectorRoundReciprocal(_ word: UInt32) -> Instruction? {
        // Shares the two-register-misc encoding; opcodes 11000/11001 (frint),
        // 11100/11101 (estimates). The high `size` bit at [23] separates these
        // from the convert group that reuses the same opcodes.
        guard word & 0x9f20_0c00 == 0x0e20_0800 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let sizeHi = (word >> 23) & 1
        let sz = (word >> 22) & 1
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        switch opcode {
        case 0b11000, 0b11001, 0b11100, 0b11101: break
        default: return nil
        }
        guard let kind = A64.VectorRoundReciprocalKind.decode(u: u, opcode: opcode, sizeHi: sizeHi) else { return nil }
        let arrangement: A64.VectorArrangement
        switch (sz, q) {
        case (0, 0): arrangement = .s2
        case (0, 1): arrangement = .s4
        case (1, 1) where kind.allowsDouble: arrangement = .d2
        default: return nil
        }
        return .vectorRoundReciprocal(
            kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            source: VectorRegister(number: rnNum, arrangement: arrangement)
        )
    }

    private static func decodeVectorPairwiseLongAdd(_ word: UInt32) -> Instruction? {
        // Shares the two-register-misc encoding; selected by opcodes 00010 (add) / 00110 (accumulate).
        typealias F = A64.VectorTwoRegisterMisc
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let u = F.u.extract(word)
        let size = F.size.extract(word)
        let opcode = F.opcode.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)

        guard opcode == 0b00010 || opcode == 0b00110 else { return nil }
        guard let kind = A64.VectorPairwiseLongAddKind.decode(u: u, opcode: opcode),
              let source = fullVectorArrangement(size: size, q: q) else { return nil }
        // The destination has the element width doubled (same `Q`); source must be b/h/s.
        let destination: A64.VectorArrangement
        switch source {
        case .b8: destination = .h4
        case .b16: destination = .h8
        case .h4: destination = .s2
        case .h8: destination = .s4
        case .s2: destination = .d1
        case .s4: destination = .d2
        default: return nil
        }
        return .vectorPairwiseLongAdd(
            kind,
            destination: VectorRegister(number: rdNum, arrangement: destination),
            source: VectorRegister(number: rnNum, arrangement: source)
        )
    }

    /// Maps a complex-arithmetic `size`/`Q` to its arrangement (`4h`/`8h`/`2s`/`4s`/`2d`).
    private static func complexArrangement(size: UInt32, q: UInt32) -> A64.VectorArrangement? {
        switch (size, q) {
        case (0b01, 0): return .h4
        case (0b01, 1): return .h8
        case (0b10, 0): return .s2
        case (0b10, 1): return .s4
        case (0b11, 1): return .d2
        default:        return nil
        }
    }

    private static func decodeVectorComplex(_ word: UInt32) -> Instruction? {
        // bits[28:24]=01110, U=1, bit21=0, bits[15:14]=11, bit10=1.
        guard word & 0xbf20_c400 == A64.AdvSIMD.complexMultiplyAdd else { return nil }
        let q = (word >> 30) & 1
        let size = (word >> 22) & 3
        guard let arrangement = complexArrangement(size: size, q: q) else { return nil }
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        let rd = VectorRegister(number: rdNum, arrangement: arrangement)
        let rn = VectorRegister(number: rnNum, arrangement: arrangement)
        let rm = VectorRegister(number: rmNum, arrangement: arrangement)

        if (word >> 13) & 1 == 1 {
            // FCADD: bit13=1, rotation in bit12 (0→#90, 1→#270), bit11=0.
            guard (word >> 11) & 1 == 0 else { return nil }
            let rotation = ((word >> 12) & 1) == 0 ? 90 : 270
            return .vectorComplexAdd(destination: rd, first: rn, second: rm, rotation: rotation)
        }
        // FCMLA: bit13=0, rotation in bits[12:11].
        let rotation = Int((word >> 11) & 3) * 90
        return .vectorComplexMultiplyAdd(destination: rd, first: rn, second: rm, rotation: rotation)
    }

    private static func decodeVectorComplexByElement(_ word: UInt32) -> Instruction? {
        // bits[28:24]=01111, U=1, bit12=1, bit10=0, bit15=0.
        guard word & 0xbf00_9400 == A64.AdvSIMD.complexMultiplyAddByElement else { return nil }
        let q = (word >> 30) & 1
        let size = (word >> 22) & 3
        let l = (word >> 21) & 1
        let m = (word >> 20) & 1
        let rmField = (word >> 16) & 0xf
        let rotation = Int((word >> 13) & 3) * 90
        let h = (word >> 11) & 1
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        let arrangement: A64.VectorArrangement
        let index: UInt32
        let elementRegister: UInt32
        switch (size, q) {
        case (0b01, 0), (0b01, 1):
            arrangement = q == 0 ? .h4 : .h8
            index = (h << 1) | l
            elementRegister = rmField
        case (0b10, 0), (0b10, 1):
            arrangement = q == 0 ? .s2 : .s4
            guard l == 0 else { return nil }
            index = h
            elementRegister = (m << 4) | rmField
        default:
            return nil
        }
        return .vectorComplexMultiplyAddByElement(
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            first: VectorRegister(number: rnNum, arrangement: arrangement),
            elementRegister: elementRegister, index: index, rotation: rotation)
    }

    private static func decodeVectorThreeSameExtra(_ word: UInt32) -> Instruction? {
        // bits[28:24]=01110, U=1, bit21=0, bit15=1, bit10=1.
        guard word & 0xbf20_8400 == 0x2e00_8400 else { return nil }
        let q = (word >> 30) & 1
        let size = (word >> 22) & 3
        let opcode = (word >> 11) & 0xf
        guard let kind = A64.VectorThreeSameExtraKind.decode(opcode: opcode) else { return nil }
        let arrangement: A64.VectorArrangement
        switch (size, q) {
        case (0b01, 0): arrangement = .h4
        case (0b01, 1): arrangement = .h8
        case (0b10, 0): arrangement = .s2
        case (0b10, 1): arrangement = .s4
        default: return nil
        }
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        return .vectorThreeSameExtra(kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            first: VectorRegister(number: rnNum, arrangement: arrangement),
            second: VectorRegister(number: rmNum, arrangement: arrangement))
    }

    private static func decodeScalarThreeSameExtra(_ word: UInt32) -> Instruction? {
        // bit30=1, bits[28:24]=11110, U=1, bit21=0, bit15=1, bit10=1.
        guard word & 0xff20_8400 == 0x7e00_8400 else { return nil }
        let size = (word >> 22) & 3
        let opcode = (word >> 11) & 0xf
        guard let kind = A64.VectorThreeSameExtraKind.decode(opcode: opcode) else { return nil }
        let width: Int
        switch size {
        case 0b01: width = 16
        case 0b10: width = 32
        default: return nil
        }
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        return .scalarThreeSameExtra(kind,
            destination: floatRegister(number: rdNum, width: width),
            first: floatRegister(number: rnNum, width: width),
            second: floatRegister(number: rmNum, width: width))
    }

    private static func decodeVectorThreeSame(_ word: UInt32) -> Instruction? {
        // Three-same group.
        typealias F = A64.VectorThreeSame
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let u = F.u.extract(word)
        let size = F.size.extract(word)
        let opcode = F.opcode.extract(word)
        let rmNum = F.rm.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)

        let family: A64.VectorThreeSameKind.Family
        let variant: UInt32
        let arrangement: A64.VectorArrangement
        if opcode >= 0b11000 {
            // Floating-point group: `a` at bit23, `sz` at bit22.
            family = .floatingPoint
            variant = (word >> 23) & 1
            let sz = (word >> 22) & 1
            switch (sz, q) {
            case (0, 0): arrangement = .s2
            case (0, 1): arrangement = .s4
            case (1, 1): arrangement = .d2
            default: return nil
            }
        } else if opcode == 0b00011 {
            // Size-selected logical group.
            family = .logical
            variant = size
            switch q {
            case 0: arrangement = .b8
            default: arrangement = .b16
            }
        } else {
            family = .integer
            variant = 0
            guard let arr = threeSameIntegerArrangement(size: size, q: q) else { return nil }
            arrangement = arr
        }

        guard let kind = A64.VectorThreeSameKind.allCases.first(where: {
            let spec = $0.spec
            return spec.family == family && spec.u == u && spec.opcode == opcode && spec.variant == variant
        }) else { return nil }
        guard kind.allowedArrangements.contains(arrangement) else { return nil }

        return .vectorThreeSame(
            kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            first: VectorRegister(number: rnNum, arrangement: arrangement),
            second: VectorRegister(number: rmNum, arrangement: arrangement)
        )
    }

    private static func decodeVectorThreeSameFP16(_ word: UInt32) -> Instruction? {
        // Three-same (FP16): bits[28:24]=01110, [22:21]=10, [15:14]=00, bit10=1.
        guard word & 0x9f60_c400 == A64.AdvSIMD.threeSameFP16 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let a = (word >> 23) & 1
        // Reconstruct the regular 5-bit FP opcode (always 11xxx).
        let opcode = 0b11000 | ((word >> 11) & 0b111)
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.VectorThreeSameKind.allCases.first(where: {
            let spec = $0.spec
            return spec.family == .floatingPoint && spec.u == u && spec.opcode == opcode && spec.variant == a
        }) else { return nil }

        let arrangement: A64.VectorArrangement = q == 0 ? .h4 : .h8
        return .vectorThreeSame(
            kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            first: VectorRegister(number: rnNum, arrangement: arrangement),
            second: VectorRegister(number: rmNum, arrangement: arrangement)
        )
    }

    private static func decodeVectorModifiedImmediate(_ word: UInt32) -> Instruction? {
        // bits[28:24]=01111, bits[23:19]=00000, bit10=1.
        guard word & 0x9ff8_0400 == 0x0f00_0400 else { return nil }
        let q = (word >> 30) & 1
        let op = (word >> 29) & 1
        let cmode = (word >> 12) & 0xf
        let abc = (word >> 16) & 0x7
        let defgh = (word >> 5) & 0x1f
        let imm8 = UInt8((abc << 5) | defgh)
        let rdNum = word & 0x1f

        let kind: A64.VectorModifiedImmediateKind
        let arrangement: A64.VectorArrangement
        var shift: A64.VectorImmediateShift = .none

        func makeShift(lsl amount: UInt32) -> A64.VectorImmediateShift {
            amount == 0 ? .none : .lsl(Int(amount))
        }

        if cmode == 0b1111 {
            kind = .fmov
            arrangement = op == 1 ? .d2 : (q == 1 ? .s4 : .s2)
        } else if cmode == 0b1110 {
            kind = .movi
            if op == 0 {
                arrangement = q == 1 ? .b16 : .b8
            } else {
                arrangement = q == 1 ? .d2 : .d1
            }
        } else if cmode == 0b1100 || cmode == 0b1101 {
            // 32-bit MSL form (movi / mvni).
            kind = op == 0 ? .movi : .mvni
            arrangement = q == 1 ? .s4 : .s2
            shift = .msl((cmode & 1) == 1 ? 16 : 8)
        } else if (cmode & 0b1000) != 0 {
            // 16-bit LSL form (cmode 1000..1011).
            let logical = (cmode & 1) == 1
            kind = logical ? (op == 0 ? .orr : .bic) : (op == 0 ? .movi : .mvni)
            arrangement = q == 1 ? .h8 : .h4
            shift = makeShift(lsl: ((cmode >> 1) & 1) * 8)
        } else {
            // 32-bit LSL form (cmode 0000..0111).
            let logical = (cmode & 1) == 1
            kind = logical ? (op == 0 ? .orr : .bic) : (op == 0 ? .movi : .mvni)
            arrangement = q == 1 ? .s4 : .s2
            shift = makeShift(lsl: ((cmode >> 1) & 0x3) * 8)
        }

        return .vectorModifiedImmediate(kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            imm8: imm8,
            shift: shift)
    }

    private static func decodeVectorShiftLeftLong(_ word: UInt32) -> Instruction? {
        // Advanced SIMD two-register-misc, U=1, opcode=0b10011 (SHLL/SHLL2).
        typealias F = A64.VectorTwoRegisterMisc
        guard word & 0xbf3f_fc00 == 0x2e21_3800 else { return nil }
        let q = F.q.extract(word)
        let size = F.size.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)
        let dst: A64.VectorArrangement
        let src: A64.VectorArrangement
        switch size {
        case 0b00: dst = .h8; src = q == 1 ? .b16 : .b8
        case 0b01: dst = .s4; src = q == 1 ? .h8 : .h4
        case 0b10: dst = .d2; src = q == 1 ? .s4 : .s2
        default: return nil
        }
        let shift = UInt32(8 << size)
        return .vectorShiftLeftLong(
            destination: VectorRegister(number: rdNum, arrangement: dst),
            source: VectorRegister(number: rnNum, arrangement: src),
            shift: shift
        )
    }

    private static func decodeVectorShiftImmediate(_ word: UInt32) -> Instruction? {
        // `immh` (22:19) must be non-zero (immh=0 is the modified-immediate group).
        typealias F = A64.VectorShiftImmediate
        guard word & F.classMask == F.baseWord else { return nil }
        let immh = F.immh.extract(word)
        guard immh != 0 else { return nil }
        let q = F.q.extract(word)
        let u = F.u.extract(word)
        let immb = F.immb.extract(word)
        let opcode = F.opcode.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)
        let immhimmb = Int((immh << 3) | immb)

        guard let kind = A64.VectorShiftImmediateKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.opcode == opcode
        }) else { return nil }

        // The most-significant set bit of `immh` selects the element size.
        let esize: Int
        if immh & 0b1000 != 0 { esize = 64 }
        else if immh & 0b0100 != 0 { esize = 32 }
        else if immh & 0b0010 != 0 { esize = 16 }
        else { esize = 8 }

        switch kind.spec.category {
        case .sameRight:
            guard let arrangement = shiftSameArrangement(esize: esize, q: q) else { return nil }
            let shift = 2 * esize - immhimmb
            return .vectorShiftImmediate(kind,
                destination: VectorRegister(number: rdNum, arrangement: arrangement),
                source: VectorRegister(number: rnNum, arrangement: arrangement),
                shift: shift)
        case .sameLeft:
            guard let arrangement = shiftSameArrangement(esize: esize, q: q) else { return nil }
            let shift = immhimmb - esize
            return .vectorShiftImmediate(kind,
                destination: VectorRegister(number: rdNum, arrangement: arrangement),
                source: VectorRegister(number: rnNum, arrangement: arrangement),
                shift: shift)
        case .narrow:
            // `esize` is the destination (narrow) element size.
            guard let destination = shiftSameArrangement(esize: esize, q: q),
                  let source = doubledArrangement(destination) else { return nil }
            let shift = 2 * esize - immhimmb
            return .vectorShiftImmediate(kind,
                destination: VectorRegister(number: rdNum, arrangement: destination),
                source: VectorRegister(number: rnNum, arrangement: source),
                shift: shift)
        case .widen:
            // `esize` is the source (narrow) element size.
            guard let source = shiftSameArrangement(esize: esize, q: q),
                  let destination = doubledArrangement(source) else { return nil }
            let shift = immhimmb - esize
            return .vectorShiftImmediate(kind,
                destination: VectorRegister(number: rdNum, arrangement: destination),
                source: VectorRegister(number: rnNum, arrangement: source),
                shift: shift)
        case .convert:
            guard esize == 32 || esize == 64,
                  let arrangement = shiftSameArrangement(esize: esize, q: q) else { return nil }
            let shift = 2 * esize - immhimmb
            return .vectorShiftImmediate(kind,
                destination: VectorRegister(number: rdNum, arrangement: arrangement),
                source: VectorRegister(number: rnNum, arrangement: arrangement),
                shift: shift)
        }
    }

    private static func decodeVectorCopy(_ word: UInt32) -> Instruction? {
        typealias F = A64.VectorCopy
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let op = F.op.extract(word)
        let imm5 = F.imm5.extract(word)
        let imm4 = F.imm4.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)

        // The lowest set bit of `imm5` selects the element size.
        let width: A64.VectorElementWidth
        let sizeShift: UInt32
        if imm5 & 0b00001 != 0 { width = .b; sizeShift = 0 }
        else if imm5 & 0b00010 != 0 { width = .h; sizeShift = 1 }
        else if imm5 & 0b00100 != 0 { width = .s; sizeShift = 2 }
        else if imm5 & 0b01000 != 0 { width = .d; sizeShift = 3 }
        else { return nil }
        let index = Int(imm5 >> (sizeShift + 1))

        if op == 1 {
            // INS (element): both lanes share the element width; `imm4` holds the source index.
            guard q == 1 else { return nil }
            let sourceIndex = Int(imm4 >> sizeShift)
            return .vectorInsertElement(
                destination: A64.VectorElement(number: rdNum, width: width, index: index),
                source: A64.VectorElement(number: rnNum, width: width, index: sourceIndex)
            )
        }

        switch imm4 {
        case 0b0000:
            guard let arrangement = copyArrangement(width: width, q: q) else { return nil }
            return .vectorDuplicateElement(
                destination: VectorRegister(number: rdNum, arrangement: arrangement),
                source: A64.VectorElement(number: rnNum, width: width, index: index)
            )
        case 0b0001:
            guard let arrangement = copyArrangement(width: width, q: q) else { return nil }
            return .vectorDuplicateGeneral(
                destination: VectorRegister(number: rdNum, arrangement: arrangement),
                source: integerRegister(number: rnNum, width: width == .d ? 64 : 32)
            )
        case 0b0011:
            guard q == 1 else { return nil }
            return .vectorInsertGeneral(
                destination: A64.VectorElement(number: rdNum, width: width, index: index),
                source: integerRegister(number: rnNum, width: width == .d ? 64 : 32)
            )
        case 0b0101, 0b0111:
            return .vectorMoveToGeneral(
                signed: imm4 == 0b0101,
                destination: integerRegister(number: rdNum, width: q == 1 ? 64 : 32),
                source: A64.VectorElement(number: rnNum, width: width, index: index)
            )
        default:
            return nil
        }
    }

    private static func decodeVectorPermute(_ word: UInt32) -> Instruction? {
        typealias F = A64.VectorPermute
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let size = F.size.extract(word)
        let opcode = F.opcode.extract(word)
        let rmNum = F.rm.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)
        guard let kind = A64.VectorPermuteKind.allCases.first(where: { $0.opcode == opcode }),
              let arrangement = threeSameIntegerArrangement(size: size, q: q) else { return nil }
        return .vectorPermute(kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            first: VectorRegister(number: rnNum, arrangement: arrangement),
            second: VectorRegister(number: rmNum, arrangement: arrangement))
    }

    private static func decodeVectorExtract(_ word: UInt32) -> Instruction? {
        typealias F = A64.VectorExtract
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let imm4 = F.index.extract(word)
        let rmNum = F.rm.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)
        // The 8-byte form only addresses lanes 0..7.
        guard q == 1 || imm4 <= 7 else { return nil }
        let arrangement: A64.VectorArrangement = q == 1 ? .b16 : .b8
        return .vectorExtract(
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            first: VectorRegister(number: rnNum, arrangement: arrangement),
            second: VectorRegister(number: rmNum, arrangement: arrangement),
            index: Int(imm4))
    }

    private static func decodeVectorThreeDifferent(_ word: UInt32) -> Instruction? {
        // Three-different group.
        typealias F = A64.VectorThreeDifferent
        guard word & F.classMask == F.baseWord else { return nil }
        let q = F.q.extract(word)
        let u = F.u.extract(word)
        let size = F.size.extract(word)
        let opcode = F.opcode.extract(word)
        let rmNum = F.rm.extract(word)
        let rnNum = F.rn.extract(word)
        let rdNum = F.rd.extract(word)

        guard let kind = A64.VectorThreeDifferentKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.opcode == opcode
        }) else { return nil }

        // PMULL/PMULL2 64→128 polynomial form: source `1d`/`2d`, destination `1q`.
        if kind == .pmull, size == 0b11 {
            let source: A64.VectorArrangement = q == 0 ? .d1 : .d2
            return .vectorThreeDifferent(kind,
                destination: VectorRegister(number: rdNum, arrangement: .q1),
                first: VectorRegister(number: rnNum, arrangement: source),
                second: VectorRegister(number: rmNum, arrangement: source))
        }

        // Per-instruction size restrictions mirror the encoder.
        switch kind {
        case .pmull: guard size == 0b00 else { return nil }
        case .sqdmull, .sqdmlal, .sqdmlsl: guard size == 0b01 || size == 0b10 else { return nil }
        default: break
        }

        guard let narrow = differentNarrowArrangement(size: size, q: q),
              let wide = doubledArrangement(narrow) else { return nil }

        let destination: A64.VectorArrangement
        let first: A64.VectorArrangement
        let second: A64.VectorArrangement
        switch kind.spec.form {
        case .long:   destination = wide; first = narrow; second = narrow
        case .wide:   destination = wide; first = wide;   second = narrow
        case .narrow: destination = narrow; first = wide; second = wide
        }

        return .vectorThreeDifferent(kind,
            destination: VectorRegister(number: rdNum, arrangement: destination),
            first: VectorRegister(number: rnNum, arrangement: first),
            second: VectorRegister(number: rmNum, arrangement: second))
    }

    private static func decodeVectorDotProduct(_ word: UInt32) -> Instruction? {
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        guard let kind = A64.VectorDotProductKind.decode(u: u) else { return nil }
        let destination: A64.VectorArrangement = q == 0 ? .s2 : .s4
        let source: A64.VectorArrangement = q == 0 ? .b8 : .b16
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        // Vector form: bits[28:24]=01110, size=10, bit21=0, bits[15:10]=100101.
        if word & 0x9fe0_fc00 == 0x0e80_9400 {
            let rmNum = (word >> 16) & 0x1f
            return .vectorDotProduct(kind,
                destination: VectorRegister(number: rdNum, arrangement: destination),
                first: VectorRegister(number: rnNum, arrangement: source),
                second: VectorRegister(number: rmNum, arrangement: source))
        }

        // By-element form: bits[28:24]=01111, size=10, bits[15:12]=1110, bit10=0.
        if word & 0x9fc0_f400 == 0x0f80_e000 {
            let l = (word >> 21) & 1
            let m = (word >> 20) & 1
            let rmLow = (word >> 16) & 0xf
            let h = (word >> 11) & 1
            let index = (h << 1) | l
            let elementRegister = (m << 4) | rmLow
            return .vectorDotProductByElement(kind,
                destination: VectorRegister(number: rdNum, arrangement: destination),
                first: VectorRegister(number: rnNum, arrangement: source),
                elementRegister: elementRegister, index: index)
        }

        return nil
    }

    private static func decodeVectorMixedDotProduct(_ word: UInt32) -> Instruction? {
        let q = (word >> 30) & 1
        let destination: A64.VectorArrangement = q == 0 ? .s2 : .s4
        let source: A64.VectorArrangement = q == 0 ? .b8 : .b16
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        // USDOT (vector): U=0, size=10, bit21=0, bits[15:10]=100111.
        if word & 0xbfe0_fc00 == A64.AdvSIMD.usDotProduct {
            let rmNum = (word >> 16) & 0x1f
            return .vectorUSDotProduct(
                destination: VectorRegister(number: rdNum, arrangement: destination),
                first: VectorRegister(number: rnNum, arrangement: source),
                second: VectorRegister(number: rmNum, arrangement: source))
        }

        // USDOT/SUDOT (by element): U=0, bits[28:24]=01111, bit22=0,
        // bits[15:12]=1111, bit10=0; bit23 selects usdot(1)/sudot(0).
        if word & 0xbf40_f400 == A64.AdvSIMD.mixedDotByElement {
            let kind: A64.VectorMixedDotProductKind = ((word >> 23) & 1) == 1 ? .usdot : .sudot
            let l = (word >> 21) & 1
            let m = (word >> 20) & 1
            let rmLow = (word >> 16) & 0xf
            let h = (word >> 11) & 1
            let index = (h << 1) | l
            let elementRegister = (m << 4) | rmLow
            return .vectorMixedDotByElement(kind,
                destination: VectorRegister(number: rdNum, arrangement: destination),
                first: VectorRegister(number: rnNum, arrangement: source),
                elementRegister: elementRegister, index: index)
        }

        return nil
    }

    private static func decodeVectorMatrixMultiply(_ word: UInt32) -> Instruction? {
        // FEAT_I8MM: Q=1, size=10, bit21=0, bits[15:12]=1010, bit10=0;
        // U(bit29) and B(bit11) select smmla/ummla/usmmla.
        guard word & 0xcee0_f400 == A64.AdvSIMD.matrixMultiply else { return nil }
        let u = (word >> 29) & 1
        let b = (word >> 11) & 1
        let kind: A64.VectorMatrixMultiplyKind
        switch (u, b) {
        case (1, 0): kind = .ummla
        case (0, 1): kind = .usmmla
        case (0, 0): kind = .smmla
        default: return nil
        }
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        return .vectorMatrixMultiply(kind,
            destination: VectorRegister(number: rdNum, arrangement: .s4),
            first: VectorRegister(number: rnNum, arrangement: .b16),
            second: VectorRegister(number: rmNum, arrangement: .b16))
    }

    private static func decodeVectorBFloat16(_ word: UInt32) -> Instruction? {
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        // BFDOT (vector): U=1, size=01, opcode[15:11]=11111, bit10=1.
        if word & 0xbfe0_fc00 == 0x2e40_fc00 {
            let q = (word >> 30) & 1
            let dest: A64.VectorArrangement = q == 0 ? .s2 : .s4
            let src: A64.VectorArrangement = q == 0 ? .h4 : .h8
            let rmNum = (word >> 16) & 0x1f
            return .vectorBFDot(
                destination: VectorRegister(number: rdNum, arrangement: dest),
                first: VectorRegister(number: rnNum, arrangement: src),
                second: VectorRegister(number: rmNum, arrangement: src))
        }

        // BFMMLA: Q=1, U=1, size=01, opcode[15:11]=11101, bit10=1.
        if word & 0xffe0_fc00 == 0x6e40_ec00 {
            let rmNum = (word >> 16) & 0x1f
            return .vectorBFMatrixMultiply(
                destination: VectorRegister(number: rdNum, arrangement: .s4),
                first: VectorRegister(number: rnNum, arrangement: .h8),
                second: VectorRegister(number: rmNum, arrangement: .h8))
        }

        // BFMLALB/BFMLALT (vector): U=1, size=11, opcode[15:11]=11111, bit10=1;
        // the Q bit selects bottom (0) / top (1).
        if word & 0xbfe0_fc00 == 0x2ec0_fc00 {
            let top = ((word >> 30) & 1) == 1
            let rmNum = (word >> 16) & 0x1f
            return .vectorBFMLAL(top: top,
                destination: VectorRegister(number: rdNum, arrangement: .s4),
                first: VectorRegister(number: rnNum, arrangement: .h8),
                second: VectorRegister(number: rmNum, arrangement: .h8))
        }

        // BFDOT (by element): U=0, size=01, opcode[15:12]=1111, bit10=0.
        if word & 0xbfc0_f400 == 0x0f40_f000 {
            let q = (word >> 30) & 1
            let dest: A64.VectorArrangement = q == 0 ? .s2 : .s4
            let src: A64.VectorArrangement = q == 0 ? .h4 : .h8
            let l = (word >> 21) & 1
            let m = (word >> 20) & 1
            let rmLow = (word >> 16) & 0xf
            let h = (word >> 11) & 1
            let index = (h << 1) | l
            return .vectorBFDotByElement(
                destination: VectorRegister(number: rdNum, arrangement: dest),
                first: VectorRegister(number: rnNum, arrangement: src),
                elementRegister: (m << 4) | rmLow, index: index)
        }

        // BFMLALB/BFMLALT (by element): U=0, size=11, opcode[15:12]=1111,
        // bit10=0; Q selects bottom/top, Vm is V0–V15, index = H:L:M.
        if word & 0xbfc0_f400 == 0x0fc0_f000 {
            let top = ((word >> 30) & 1) == 1
            let l = (word >> 21) & 1
            let m = (word >> 20) & 1
            let rmLow = (word >> 16) & 0xf
            let h = (word >> 11) & 1
            let index = (h << 2) | (l << 1) | m
            return .vectorBFMLALByElement(top: top,
                destination: VectorRegister(number: rdNum, arrangement: .s4),
                first: VectorRegister(number: rnNum, arrangement: .h8),
                elementRegister: rmLow, index: index)
        }

        return nil
    }

    private static func decodeVectorFPMultiplyLong(_ word: UInt32) -> Instruction? {
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        let destination: A64.VectorArrangement = q == 0 ? .s2 : .s4
        let source: A64.VectorArrangement = q == 0 ? .h2 : .h4

        // Vector form: bits[28:24]=01110, bit22=0, bit21=1, bits[15:14]=11,
        // bit12=0, bit11=1, bit10=1. The (U, opcode) pair selects the form:
        // U=0 ⇒ opcode 11101, U=1 ⇒ opcode 11001; bit23 is the subtract bit.
        if word & 0x9f60_dc00 == 0x0e20_cc00 {
            let opcode = (word >> 11) & 0b11111
            let upper: UInt32
            switch (u, opcode) {
            case (0, 0b11101): upper = 0
            case (1, 0b11001): upper = 1
            default: return nil
            }
            let sub = (word >> 23) & 1
            let kind = A64.VectorFPMultiplyLongKind.decode(upper: upper, sub: sub)
            let rmNum = (word >> 16) & 0x1f
            return .vectorFPMultiplyLong(kind,
                destination: VectorRegister(number: rdNum, arrangement: destination),
                first: VectorRegister(number: rnNum, arrangement: source),
                second: VectorRegister(number: rmNum, arrangement: source))
        }

        // By-element form: bits[28:24]=01111, size[23:22]=10, bit10=0. The
        // opcode[15:12] = (upper<<3)|(sub<<2) with bits[13:12]=00; index = H:L:M.
        if word & 0x9fc0_0400 == 0x0f80_0000 {
            let opcode = (word >> 12) & 0b1111
            guard opcode & 0b0011 == 0 else { return nil }
            let upper = (opcode >> 3) & 1
            let sub = (opcode >> 2) & 1
            guard upper == u else { return nil }
            let kind = A64.VectorFPMultiplyLongKind.decode(upper: upper, sub: sub)
            let l = (word >> 21) & 1
            let m = (word >> 20) & 1
            let rmLow = (word >> 16) & 0xf
            let h = (word >> 11) & 1
            let index = (h << 2) | (l << 1) | m
            return .vectorFPMultiplyLongByElement(kind,
                destination: VectorRegister(number: rdNum, arrangement: destination),
                first: VectorRegister(number: rnNum, arrangement: source),
                elementRegister: rmLow, index: index)
        }

        return nil
    }

    private static func decodeVectorIndexed(_ word: UInt32) -> Instruction? {
        // bit31=0, bits[28:24]=01111, bit10=0.
        guard word & 0x9f00_0400 == A64.AdvSIMD.vectorImmediate else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let size = (word >> 22) & 0x3
        let l = (word >> 21) & 1
        let m = (word >> 20) & 1
        let rmField = (word >> 16) & 0xf
        let opcode = (word >> 12) & 0xf
        let h = (word >> 11) & 1
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.VectorIndexedKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.opcode == opcode
        }) else { return nil }

        // Element width, index, and `Vm` reconstruction depend on `size`.
        let width: A64.VectorElementWidth
        let index: Int
        let vm: UInt32
        switch size {
        case 0b00, 0b01:
            // `size=00` is the FP16 by-element form; `size=01` is the integer
            // `.h` element. Both pack the index as H:L:M and Vm in four bits.
            width = .h
            index = Int((h << 2) | (l << 1) | m)
            vm = rmField
        case 0b10:
            width = .s
            index = Int((h << 1) | l)
            vm = (m << 4) | rmField
        case 0b11:
            width = .d
            index = Int(h)
            vm = (m << 4) | rmField
        default:
            return nil
        }

        let destination: A64.VectorArrangement
        let first: A64.VectorArrangement
        switch kind.spec.form {
        case .same:
            guard size != 0b00, width != .d,
                  let arrangement = differentNarrowArrangement(size: size, q: q) else { return nil }
            destination = arrangement
            first = arrangement
        case .fp:
            switch size {
            case 0b00: destination = q == 1 ? .h8 : .h4
            case 0b10: destination = q == 1 ? .s4 : .s2
            case 0b11: guard q == 1 else { return nil }; destination = .d2
            default: return nil
            }
            first = destination
        case .long:
            guard size != 0b00, width != .d,
                  let narrow = differentNarrowArrangement(size: size, q: q),
                  let wide = doubledArrangement(narrow) else { return nil }
            destination = wide
            first = narrow
        }

        return .vectorIndexed(kind,
            destination: VectorRegister(number: rdNum, arrangement: destination),
            first: VectorRegister(number: rnNum, arrangement: first),
            element: VectorElement(number: vm, width: width, index: index))
    }

    private static func decodeScalarThreeSame(_ word: UInt32) -> Instruction? {
        // bit31=0, bit30=1, bits[28:24]=11110, bit21=1, bit10=1.
        guard word & 0xdf20_0400 == A64.ScalarAdvSIMD.threeSameBase else { return nil }
        let u = (word >> 29) & 1
        let size = (word >> 22) & 0x3
        let opcode = (word >> 11) & 0x1f
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarThreeSameKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.opcode == opcode
        }) else { return nil }

        let width: Int
        switch kind.spec.size {
        case .doubleOnly:
            guard size == 0b11 else { return nil }
            width = 64
        case .halfSingle:
            switch size {
            case 0b01: width = 16
            case 0b10: width = 32
            default: return nil
            }
        case .anySize:
            width = 8 << size
        }

        return .scalarThreeSame(kind,
            destination: floatRegister(number: rdNum, width: width),
            first: floatRegister(number: rnNum, width: width),
            second: floatRegister(number: rmNum, width: width))
    }

    private static func decodeScalarTwoRegisterMiscNarrow(_ word: UInt32) -> Instruction? {
        // Shares the scalar two-register misc base; distinguished by the narrowing
        // opcodes (0x12 / 0x14). The destination element size comes from `size`.
        guard word & 0xdf3e_0c00 == A64.ScalarAdvSIMD.twoRegisterMiscBase else { return nil }
        let u = (word >> 29) & 1
        let size = (word >> 22) & 0x3
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarTwoRegisterMiscNarrowKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.opcode == opcode
        }) else { return nil }

        let destWidth: Int
        switch size {
        case 0b00: destWidth = 8    // h -> b
        case 0b01: destWidth = 16   // s -> h
        case 0b10: destWidth = 32   // d -> s
        default: return nil
        }

        return .scalarTwoRegisterMiscNarrow(kind,
            destination: floatRegister(number: rdNum, width: destWidth),
            source: floatRegister(number: rnNum, width: destWidth * 2))
    }

    private static func decodeScalarShiftNarrow(_ word: UInt32) -> Instruction? {
        // Shares the scalar shift-by-immediate base; narrowing forms have immh = 0xxx
        // (the highest set bit selects the destination element size).
        guard word & 0xdf80_0400 == A64.AdvSIMD.scalarShift else { return nil }
        let u = (word >> 29) & 1
        let immh = (word >> 19) & 0xf
        let immb = (word >> 16) & 0x7
        guard immh != 0, immh & 0b1000 == 0 else { return nil }
        let opcode = (word >> 11) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarShiftNarrowKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.opcode == opcode
        }) else { return nil }

        // Highest set bit of immh selects the destination element size.
        let destEsize: Int
        if immh & 0b0100 != 0 { destEsize = 32 }
        else if immh & 0b0010 != 0 { destEsize = 16 }
        else { destEsize = 8 }   // immh == 0b0001

        let immhb = Int((immh << 3) | immb)
        let shift = 2 * destEsize - immhb
        guard shift >= 1, shift <= destEsize else { return nil }

        return .scalarShiftNarrow(kind,
            destination: floatRegister(number: rdNum, width: destEsize),
            source: floatRegister(number: rnNum, width: destEsize * 2),
            shift: shift)
    }

    private static func decodeScalarShiftImmediate(_ word: UInt32) -> Instruction? {
        // bit31=0, bit30=1, bits[28:23]=111110, bit10=1.
        guard word & 0xdf80_0400 == A64.AdvSIMD.scalarShift else { return nil }
        let u = (word >> 29) & 1
        let immh = (word >> 19) & 0xf
        let immb = (word >> 16) & 0x7
        // Only the double-width form (immh = 1xxx) is supported.
        guard immh & 0b1000 != 0 else { return nil }
        let opcode = (word >> 11) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarShiftImmediateKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.opcode == opcode
        }) else { return nil }

        let immhb = Int((immh << 3) | immb)
        let shift = kind.spec.isLeft ? (immhb - 64) : (128 - immhb)

        return .scalarShiftImmediate(kind,
            destination: floatRegister(number: rdNum, width: 64),
            source: floatRegister(number: rnNum, width: 64),
            shift: shift)
    }

    private static func decodeScalarShiftFixedPoint(_ word: UInt32) -> Instruction? {
        // Shares the scalar shift-by-immediate base (bit30=1, bits[28:23]=111110, bit10=1),
        // distinguished by opcode (scvtf/ucvtf = 0b11100, fcvtzs/fcvtzu = 0b11111).
        guard word & 0xdf80_0400 == A64.AdvSIMD.scalarShift else { return nil }
        let u = (word >> 29) & 1
        let immh = (word >> 19) & 0xf
        let immb = (word >> 16) & 0x7
        let opcode = (word >> 11) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarShiftFixedPointKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.opcode == opcode
        }) else { return nil }

        let immhb = (immh << 3) | immb
        let width: Int
        let fbits: Int
        if immh & 0b1000 != 0 {            // 1xxx -> D (64-bit), fbits = 128 - immhb
            width = 64
            fbits = Int(128 - immhb)
        } else if immh & 0b0100 != 0 {     // 01xx -> S (32-bit), fbits = 64 - immhb
            width = 32
            fbits = Int(64 - immhb)
        } else {                           // 001x / 0001 are FP16/reserved here
            return nil
        }

        return .scalarShiftFixedPoint(kind,
            destination: floatRegister(number: rdNum, width: width),
            source: floatRegister(number: rnNum, width: width),
            fbits: fbits)
    }

    private static func decodeScalarThreeSameFP16(_ word: UInt32) -> Instruction? {
        // Half-precision scalar three-same: bits[31:30]=01, bits[28:24]=11110,
        // bit22=1, bit21=0, bits[15:14]=00, bit10=1. Distinguished by (U, bit23,
        // opcode) where the encoded opcode field is only 3 bits ([13:11]) and the
        // full opcode is 0b11_000 | field.
        guard word & 0xdf60_c400 == A64.AdvSIMD.scalarThreeSameFP16 else { return nil }
        let u = (word >> 29) & 1
        let hi = (word >> 23) & 1
        let opcode = 0b11000 | ((word >> 11) & 0b111)
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarThreeSameFPKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.hi == hi && spec.opcode == opcode
        }) else { return nil }

        return .scalarThreeSameFP(kind,
            destination: floatRegister(number: rdNum, width: 16),
            first: floatRegister(number: rnNum, width: 16),
            second: floatRegister(number: rmNum, width: 16))
    }

    private static func decodeScalarThreeSameFP(_ word: UInt32) -> Instruction? {
        // Shares the scalar three-same base (bit21=1, bit10=1), distinguished by
        // (U, bit23, opcode[15:11]); bit22 is the `sz` (single/double) bit.
        guard word & 0xdf20_0400 == A64.ScalarAdvSIMD.threeSameBase else { return nil }
        let u = (word >> 29) & 1
        let hi = (word >> 23) & 1
        let sz = (word >> 22) & 1
        let opcode = (word >> 11) & 0x1f
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarThreeSameFPKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.hi == hi && spec.opcode == opcode
        }) else { return nil }

        let width = sz == 0 ? 32 : 64
        return .scalarThreeSameFP(kind,
            destination: floatRegister(number: rdNum, width: width),
            first: floatRegister(number: rnNum, width: width),
            second: floatRegister(number: rmNum, width: width))
    }

    private static func decodeScalarFPTwoRegisterMiscFP16(_ word: UInt32) -> Instruction? {
        // Half-precision scalar two-register misc: bit30=1, bits[28:24]=11110,
        // bit22=1, bits[21:17]=11100, bits[11:10]=10. Distinguished by
        // (U, bit23, opcode[16:12]); the narrow `fcvtxn` has no FP16 form.
        guard word & 0xdf7e_0c00 == A64.AdvSIMD.scalarFPTwoRegisterMiscFP16 else { return nil }
        let u = (word >> 29) & 1
        let hi = (word >> 23) & 1
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarFPTwoRegisterMiscKind.allCases.first(where: {
            let spec = $0.spec
            return spec.category != .narrow && spec.u == u && spec.hi == hi && spec.opcode == opcode
        }) else { return nil }

        return .scalarFPTwoRegisterMisc(kind,
            destination: floatRegister(number: rdNum, width: 16),
            source: floatRegister(number: rnNum, width: 16))
    }

    private static func decodeScalarFPTwoRegisterMisc(_ word: UInt32) -> Instruction? {
        // Shares the scalar two-register misc base (bits[21:17]=10000, bits[11:10]=10),
        // distinguished by (U, bit23, opcode). bit22 is the `sz` (single/double) bit.
        guard word & 0xdf3e_0c00 == A64.ScalarAdvSIMD.twoRegisterMiscBase else { return nil }
        let u = (word >> 29) & 1
        let hi = (word >> 23) & 1
        let sz = (word >> 22) & 1
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarFPTwoRegisterMiscKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.hi == hi && spec.opcode == opcode
        }) else { return nil }

        let destWidth: Int
        let sourceWidth: Int
        switch kind.spec.category {
        case .convert, .compareZero:
            let width = sz == 0 ? 32 : 64
            destWidth = width; sourceWidth = width
        case .narrow:
            destWidth = 32; sourceWidth = 64
        }

        return .scalarFPTwoRegisterMisc(kind,
            destination: floatRegister(number: rdNum, width: destWidth),
            source: floatRegister(number: rnNum, width: sourceWidth))
    }

    private static func decodeScalarCopy(_ word: UInt32) -> Instruction? {
        // bit30=1, bits[28:21]=11110000, bit15=0, imm4[14:11]=0000, bit10=1 (DUP element scalar).
        guard word & 0xffe0_fc00 == A64.AdvSIMD.scalarCopy else { return nil }
        let imm5 = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        // The lowest set bit of imm5 selects the element size.
        let width: A64.VectorElementWidth
        let size: UInt32
        if imm5 & 0b1 != 0 { width = .b; size = 0 }
        else if imm5 & 0b10 != 0 { width = .h; size = 1 }
        else if imm5 & 0b100 != 0 { width = .s; size = 2 }
        else if imm5 & 0b1000 != 0 { width = .d; size = 3 }
        else { return nil }

        let index = Int(imm5 >> (size + 1))
        let destWidth = 8 << Int(size)

        return .scalarCopyDuplicate(
            destination: floatRegister(number: rdNum, width: destWidth),
            element: VectorElement(number: rnNum, width: width, index: index))
    }

    private static func decodeScalarIndexed(_ word: UInt32) -> Instruction? {
        // bit31=0, bit30=1, bits[28:24]=11111, bit10=0.
        guard word & 0xdf00_0400 == A64.AdvSIMD.scalarIndexed else { return nil }
        let u = (word >> 29) & 1
        let size = (word >> 22) & 0x3
        let l = (word >> 21) & 1
        let m = (word >> 20) & 1
        let rmField = (word >> 16) & 0xf
        let opcode = (word >> 12) & 0xf
        let h = (word >> 11) & 1
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.VectorIndexedKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.opcode == opcode
        }) else { return nil }

        let width: A64.VectorElementWidth
        let index: Int
        let vm: UInt32
        switch size {
        case 0b00, 0b01:
            // `size=00` is the FP16 by-element form; `size=01` is the integer
            // `.h` element. Both pack the index as H:L:M and Vm in four bits.
            width = .h
            index = Int((h << 2) | (l << 1) | m)
            vm = rmField
        case 0b10:
            width = .s
            index = Int((h << 1) | l)
            vm = (m << 4) | rmField
        case 0b11:
            width = .d
            index = Int(h)
            vm = (m << 4) | rmField
        default:
            return nil
        }

        let elementBits: Int
        switch width {
        case .h: elementBits = 16
        case .s: elementBits = 32
        case .d: elementBits = 64
        case .b: return nil
        }

        let destWidth: Int
        let firstWidth: Int
        switch kind.spec.form {
        case .same:
            guard size != 0b00, elementBits == 16 || elementBits == 32 else { return nil }
            destWidth = elementBits; firstWidth = elementBits
        case .fp:
            // FP16 uses size=00; FP32/64 use size=10/11; size=01 is invalid.
            guard size != 0b01 else { return nil }
            destWidth = elementBits; firstWidth = elementBits
        case .long:
            guard size != 0b00, elementBits == 16 || elementBits == 32 else { return nil }
            firstWidth = elementBits; destWidth = elementBits * 2
        }

        return .scalarIndexed(kind,
            destination: floatRegister(number: rdNum, width: destWidth),
            first: floatRegister(number: rnNum, width: firstWidth),
            element: VectorElement(number: vm, width: width, index: index))
    }

    private static func decodeScalarThreeDifferent(_ word: UInt32) -> Instruction? {
        // bit31=0, bit30=1, bits[28:24]=11110, bit21=1, bits[11:10]=00.
        guard word & 0xdf20_0c00 == A64.ScalarAdvSIMD.threeDifferentBase else { return nil }
        let size = (word >> 22) & 0x3
        let opcode = (word >> 12) & 0xf
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarThreeDifferentKind.allCases.first(where: { $0.opcode == opcode }) else { return nil }

        let sourceWidth: Int
        let destWidth: Int
        switch size {
        case 0b01: sourceWidth = 16; destWidth = 32   // h -> s
        case 0b10: sourceWidth = 32; destWidth = 64   // s -> d
        default: return nil
        }

        return .scalarThreeDifferent(kind,
            destination: floatRegister(number: rdNum, width: destWidth),
            first: floatRegister(number: rnNum, width: sourceWidth),
            second: floatRegister(number: rmNum, width: sourceWidth))
    }

    private static func decodeScalarTwoRegisterMisc(_ word: UInt32) -> Instruction? {
        // bit31=0, bit30=1, bits[28:24]=11110, bits[21:17]=10000, bits[11:10]=10.
        guard word & 0xdf3e_0c00 == A64.ScalarAdvSIMD.twoRegisterMiscBase else { return nil }
        let u = (word >> 29) & 1
        let size = (word >> 22) & 0x3
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarTwoRegisterMiscKind.allCases.first(where: {
            let spec = $0.spec
            return spec.u == u && spec.opcode == opcode
        }) else { return nil }

        let width: Int
        switch kind.spec.size {
        case .doubleOnly:
            guard size == 0b11 else { return nil }
            width = 64
        case .anySize:
            width = 8 << size
        }

        return .scalarTwoRegisterMisc(kind,
            destination: floatRegister(number: rdNum, width: width),
            source: floatRegister(number: rnNum, width: width))
    }

    private static func decodeScalarPairwiseFP16(_ word: UInt32) -> Instruction? {
        // Half-precision scalar pairwise: like the FP32/64 form but with U=0 and
        // sz=0, reducing a `.2h` source into a scalar `h`. Distinguished by
        // (o1=bit23, opcode[16:12]).
        guard word & 0xff7e_0c00 == A64.ScalarAdvSIMD.pairwiseBase else { return nil }
        let o1 = (word >> 23) & 1
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarPairwiseKind.allCases.first(where: {
            let spec = $0.spec
            return spec.fp && spec.o1 == o1 && spec.opcode == opcode
        }) else { return nil }

        return .scalarPairwise(kind,
            destination: floatRegister(number: rdNum, width: 16),
            source: VectorRegister(number: rnNum, arrangement: .h2))
    }

    private static func decodeScalarPairwise(_ word: UInt32) -> Instruction? {
        // bit31=0, bit30=1, bits[28:24]=11110, bits[21:17]=11000, bits[11:10]=10.
        guard word & 0xdf3e_0c00 == A64.ScalarAdvSIMD.pairwiseBase else { return nil }
        let u = (word >> 29) & 1
        let o1 = (word >> 23) & 1
        let sz = (word >> 22) & 1
        let size = (word >> 22) & 0x3
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

        guard let kind = A64.ScalarPairwiseKind.allCases.first(where: {
            let spec = $0.spec
            guard spec.u == u else { return false }
            return spec.fp ? (spec.opcode == opcode && spec.o1 == o1) : (spec.opcode == opcode)
        }) else { return nil }

        let arrangement: A64.VectorArrangement
        let width: Int
        if kind.spec.fp {
            if sz == 0 { arrangement = .s2; width = 32 } else { arrangement = .d2; width = 64 }
        } else {
            guard size == 0b11 else { return nil }
            arrangement = .d2
            width = 64
        }

        return .scalarPairwise(kind,
            destination: floatRegister(number: rdNum, width: width),
            source: VectorRegister(number: rnNum, arrangement: arrangement))
    }

    /// Maps the narrow operand's `size`/`Q` to an arrangement; `size=11` is reserved.
    private static func differentNarrowArrangement(size: UInt32, q: UInt32) -> A64.VectorArrangement? {
        switch (size, q) {
        case (0b00, 0): return .b8
        case (0b00, 1): return .b16
        case (0b01, 0): return .h4
        case (0b01, 1): return .h8
        case (0b10, 0): return .s2
        case (0b10, 1): return .s4
        default: return nil
        }
    }

    /// Maps an element width and `Q` to a vector arrangement; `(D, Q=0)` is the
    /// scalar `1d` form and is rejected for the copy group.
    private static func copyArrangement(width: A64.VectorElementWidth, q: UInt32) -> A64.VectorArrangement? {
        switch (width, q) {
        case (.b, 0): return .b8
        case (.b, 1): return .b16
        case (.h, 0): return .h4
        case (.h, 1): return .h8
        case (.s, 0): return .s2
        case (.s, 1): return .s4
        case (.d, 1): return .d2
        default: return nil
        }
    }

    /// Maps an element size and `Q` to a same-element vector arrangement.
    /// `64`-bit with `Q=0` is the scalar `1d` form and is rejected.
    private static func shiftSameArrangement(esize: Int, q: UInt32) -> A64.VectorArrangement? {
        switch (esize, q) {
        case (8, 0): return .b8
        case (8, 1): return .b16
        case (16, 0): return .h4
        case (16, 1): return .h8
        case (32, 0): return .s2
        case (32, 1): return .s4
        case (64, 1): return .d2
        default: return nil
        }
    }

    /// Maps a "low" arrangement to the fully populated arrangement one element
    /// size up (`8b`/`16b` → `8h`, `4h`/`8h` → `4s`, `2s`/`4s` → `2d`).
    private static func doubledArrangement(_ arrangement: A64.VectorArrangement) -> A64.VectorArrangement? {
        switch arrangement {
        case .b8, .b16: return .h8
        case .h4, .h8: return .s4
        case .s2, .s4: return .d2
        case .h2, .d1, .d2, .q1: return nil
        }
    }

    /// Maps `size`/`Q` to an integer three-same arrangement; `1d` (size=11,Q=0) is reserved.
    private static func threeSameIntegerArrangement(size: UInt32, q: UInt32) -> A64.VectorArrangement? {
        switch (size, q) {
        case (0b00, 0): return .b8
        case (0b00, 1): return .b16
        case (0b01, 0): return .h4
        case (0b01, 1): return .h8
        case (0b10, 0): return .s2
        case (0b10, 1): return .s4
        case (0b11, 1): return .d2
        default: return nil
        }
    }

    /// Reconstructs an integer across-lanes source arrangement; `2s`/`1d`/`2d` are reserved.
    private static func vectorArrangement(size: UInt32, q: UInt32) -> A64.VectorArrangement? {
        switch (size, q) {
        case (0b00, 0): return .b8
        case (0b00, 1): return .b16
        case (0b01, 0): return .h4
        case (0b01, 1): return .h8
        case (0b10, 1): return .s4
        default: return nil
        }
    }

    private static func vectorTwoRegisterMiscArrangement(_ kind: A64.VectorTwoRegisterMiscKind, size: UInt32, q: UInt32) -> A64.VectorArrangement? {
        switch kind {
        case .rev64, .cls, .clz:
            switch (size, q) {
            case (0b00, 0): return .b8
            case (0b00, 1): return .b16
            case (0b01, 0): return .h4
            case (0b01, 1): return .h8
            case (0b10, 0): return .s2
            case (0b10, 1): return .s4
            default: return nil
            }
        case .rev32:
            switch (size, q) {
            case (0b00, 0): return .b8
            case (0b00, 1): return .b16
            case (0b01, 0): return .h4
            case (0b01, 1): return .h8
            default: return nil
            }
        case .rev16, .cnt, .mvn:
            switch (size, q) {
            case (0b00, 0): return .b8
            case (0b00, 1): return .b16
            default: return nil
            }
        case .rbit:
            switch (size, q) {
            case (0b01, 0): return .b8
            case (0b01, 1): return .b16
            default: return nil
            }
        case .abs, .neg, .sqabs, .sqneg, .suqadd, .usqadd:
            switch (size, q) {
            case (0b00, 0): return .b8
            case (0b00, 1): return .b16
            case (0b01, 0): return .h4
            case (0b01, 1): return .h8
            case (0b10, 0): return .s2
            case (0b10, 1): return .s4
            case (0b11, 1): return .d2
            default: return nil
            }
        case .fabs, .fneg, .fsqrt,
             .frint32z, .frint32x, .frint64z, .frint64x:
            switch (size, q) {
            case (0b10, 0): return .s2
            case (0b10, 1): return .s4
            case (0b11, 1): return .d2
            default: return nil
            }
        }
    }

    private static func floatRegister(number: UInt32, width: Int) -> FloatRegister {
        FloatRegister(number: number, width: width)
    }

    private static func floatWidth(forPtype ptype: UInt32) -> Int? {
        switch ptype {
        case 0b00: return 32
        case 0b01: return 64
        case 0b11: return 16
        default: return nil
        }
    }

    private static func baseRegister(number: UInt32, width: Int) -> IntegerRegister {
        IntegerRegister(number: number, width: width, kind: number == 31 ? .stackPointer : .general)
    }

    private static func xRegister(number: UInt32) -> IntegerRegister {
        IntegerRegister(number: number, width: 64, kind: number == 31 ? .stackPointer : .general)
    }

    private static func integerRegister(number: UInt32, width: Int) -> IntegerRegister {
        IntegerRegister(number: number, width: width, kind: number == 31 ? .zero : .general)
    }

    private static func signExtend(_ value: UInt32, bitCount: Int) -> Int64 {
        let signBit = UInt32(1) << UInt32(bitCount - 1)
        let mask = (UInt32(1) << UInt32(bitCount)) - 1
        let value = value & mask
        if value & signBit == 0 { return Int64(value) }
        return Int64(Int32(bitPattern: value | ~mask))
    }
}
