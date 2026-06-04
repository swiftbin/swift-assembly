import Foundation

internal enum A64InstructionDecoder {
    static func decode(_ word: UInt32) throws -> Instruction {
        if word == 0xd503201f { return .nop }
        if word == 0xd69f03e0 { return .exceptionReturn }

        if let instruction = decodePointerAuthentication(word) { return instruction }
        if let instruction = decodeBranchRegister(word) { return instruction }
        if let instruction = decodeUnconditionalBranch(word) { return instruction }
        if let instruction = decodeConditionalBranch(word) { return instruction }
        if let instruction = decodeCompareAndBranch(word) { return instruction }
        if let instruction = decodeTestAndBranch(word) { return instruction }
        if let instruction = decodeAddress(word) { return instruction }
        if let instruction = decodeException(word) { return instruction }
        if let instruction = decodeBarrier(word) { return instruction }
        if let instruction = decodeMoveWide(word) { return instruction }
        if let instruction = decodeAddSubImmediate(word) { return instruction }
        if let instruction = decodeAddSubShiftedRegister(word) { return instruction }
        if let instruction = decodeLogicalImmediate(word) { return instruction }
        if let instruction = decodeLogicalShiftedRegister(word) { return instruction }
        if let instruction = decodeBitfieldShiftAlias(word) { return instruction }
        if let instruction = decodeExtract(word) { return instruction }
        if let instruction = decodeMultiply(word) { return instruction }
        if let instruction = decodeDivide(word) { return instruction }
        if let instruction = decodeLoadStoreSingle(word) { return instruction }
        if let instruction = decodeLoadStorePair(word) { return instruction }
        if let instruction = decodeLoadStoreSingleFP(word) { return instruction }
        if let instruction = decodeLoadStorePairFP(word) { return instruction }
        if let instruction = decodeLoadStoreMultiple(word) { return instruction }
        if let instruction = decodeLoadStoreSingleStructure(word) { return instruction }
        if let instruction = decodeVectorTableLookup(word) { return instruction }
        if let instruction = decodeFPDataProcessing3(word) { return instruction }
        if let instruction = decodeFPDataProcessing2(word) { return instruction }
        if let instruction = decodeFPDataProcessing1(word) { return instruction }
        if let instruction = decodeFPCompare(word) { return instruction }
        if let instruction = decodeFPMoveImmediate(word) { return instruction }
        if let instruction = decodeFPIntegerConversion(word) { return instruction }
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
        if let instruction = decodeVectorComplexByElement(word) { return instruction }
        if let instruction = decodeVectorIndexed(word) { return instruction }
        if let instruction = decodeScalarThreeSameExtra(word) { return instruction }
        if let instruction = decodeScalarThreeSame(word) { return instruction }
        if let instruction = decodeScalarPairwise(word) { return instruction }
        if let instruction = decodeScalarTwoRegisterMisc(word) { return instruction }
        if let instruction = decodeScalarShiftImmediate(word) { return instruction }
        if let instruction = decodeScalarThreeDifferent(word) { return instruction }
        if let instruction = decodeScalarIndexed(word) { return instruction }
        if let instruction = decodeScalarCopy(word) { return instruction }
        if let instruction = decodeScalarFPTwoRegisterMisc(word) { return instruction }
        if let instruction = decodeScalarThreeSameFP(word) { return instruction }
        if let instruction = decodeScalarShiftNarrow(word) { return instruction }
        if let instruction = decodeScalarTwoRegisterMiscNarrow(word) { return instruction }
        if let instruction = decodeScalarShiftFixedPoint(word) { return instruction }

        throw AssemblerError.unknownEncoding(word)
    }

    private static func decodeBranchRegister(_ word: UInt32) -> Instruction? {
        let mask: UInt32 = 0xffff_fc1f
        let rn = xRegister(number: (word >> 5) & 0x1f)
        switch word & mask {
        case 0xd65f0000:
            return .branchRegister(.ret, rn)
        case 0xd61f0000:
            return .branchRegister(.br, rn)
        case 0xd63f0000:
            return .branchRegister(.blr, rn)
        default:
            return nil
        }
    }

    private static func decodeUnconditionalBranch(_ word: UInt32) -> Instruction? {
        switch word & 0xfc00_0000 {
        case 0x14000000:
            return .unconditionalBranch(link: false, offset: signExtend(word & 0x03ff_ffff, bitCount: 26) * 4)
        case 0x94000000:
            return .unconditionalBranch(link: true, offset: signExtend(word & 0x03ff_ffff, bitCount: 26) * 4)
        default:
            return nil
        }
    }

    private static func decodeConditionalBranch(_ word: UInt32) -> Instruction? {
        guard word & 0xff00_0010 == 0x5400_0000 else { return nil }
        guard let condition = Condition(rawValue: word & 0xf) else { return nil }
        let offset = signExtend((word >> 5) & 0x7ffff, bitCount: 19) * 4
        return .conditionalBranch(condition, offset: offset)
    }

    private static func decodeCompareAndBranch(_ word: UInt32) -> Instruction? {
        guard word & 0x7e00_0000 == 0x3400_0000 else { return nil }
        let is64Bit = (word >> 31) & 1 == 1
        let nonzero = (word >> 24) & 1 == 1
        let rt = integerRegister(number: word & 0x1f, width: is64Bit ? 64 : 32)
        let offset = signExtend((word >> 5) & 0x7ffff, bitCount: 19) * 4
        return .compareAndBranch(nonzero: nonzero, rt, offset: offset)
    }

    private static func decodeTestAndBranch(_ word: UInt32) -> Instruction? {
        guard word & 0x7e00_0000 == 0x3600_0000 else { return nil }
        let bit = Int64(((word >> 31) & 1) << 5) | Int64((word >> 19) & 0x1f)
        let nonzero = (word >> 24) & 1 == 1
        let rt = integerRegister(number: word & 0x1f, width: bit >= 32 ? 64 : 32)
        let offset = signExtend((word >> 5) & 0x3fff, bitCount: 14) * 4
        return .testAndBranch(nonzero: nonzero, rt, bit: bit, offset: offset)
    }

    private static func decodeAddress(_ word: UInt32) -> Instruction? {
        let page: Bool
        switch word & 0x9f00_0000 {
        case 0x1000_0000:
            page = false
        case 0x9000_0000:
            page = true
        default:
            return nil
        }
        let immlo = (word >> 29) & 0x3
        let immhi = (word >> 5) & 0x7ffff
        let immediate = signExtend((immhi << 2) | immlo, bitCount: 21)
        return .address(page: page, xRegister(number: word & 0x1f), offset: page ? immediate * 4096 : immediate)
    }

    private static func decodeException(_ word: UInt32) -> Instruction? {
        let mask: UInt32 = 0xffe0_001f
        let immediate = Int64((word >> 5) & 0xffff)
        switch word & mask {
        case 0xd4000001:
            return .exception(.supervisorCall, immediate: immediate)
        case 0xd4200000:
            return .exception(.breakpoint, immediate: immediate)
        case 0xd4400000:
            return .exception(.halt, immediate: immediate)
        default:
            return nil
        }
    }

    private static func decodeBarrier(_ word: UInt32) -> Instruction? {
        let mask: UInt32 = 0xffff_f0ff
        let option = (word >> 8) & 0xf
        switch word & mask {
        case 0xd50330df:
            return .barrier(.instructionSynchronization, option: option)
        case 0xd503309f:
            return .barrier(.dataSynchronization, option: option)
        case 0xd50330bf:
            return .barrier(.dataMemory, option: option)
        default:
            return nil
        }
    }

    private static func decodePointerAuthentication(_ word: UInt32) -> Instruction? {
        switch word {
        case 0xd503233f: return .pointerAuthentication(.paciasp, register: nil, architecture: .arm64e)
        case 0xd50323bf: return .pointerAuthentication(.autiasp, register: nil, architecture: .arm64e)
        case 0xd503237f: return .pointerAuthentication(.pacibsp, register: nil, architecture: .arm64e)
        case 0xd50323ff: return .pointerAuthentication(.autibsp, register: nil, architecture: .arm64e)
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

    private static func decodeMoveWide(_ word: UInt32) -> Instruction? {
        guard word & 0x1f80_0000 == 0x1280_0000 else { return nil }
        let sf = (word >> 31) & 1
        let kind: A64.MoveWideKind
        switch (word >> 29) & 3 {
        case 0: kind = .movn
        case 2: kind = .movz
        case 3: kind = .movk
        default: return nil
        }
        let hw = (word >> 21) & 3
        if sf == 0 && hw > 1 { return nil }
        let imm = Int64((word >> 5) & 0xffff)
        let rd = integerRegister(number: word & 0x1f, width: sf == 1 ? 64 : 32)
        let shift = hw == 0 ? nil : Int(hw) * 16
        return .moveWide(kind, destination: rd, immediate: imm, shift: shift)
    }

    private static func decodeAddSubImmediate(_ word: UInt32) -> Instruction? {
        guard word & 0x1f00_0000 == 0x1100_0000 else { return nil }
        let sf = (word >> 31) & 1
        let op = (word >> 30) & 1
        let s = (word >> 29) & 1
        let sh = (word >> 22) & 1
        let imm12 = (word >> 10) & 0xfff
        let width = sf == 1 ? 64 : 32
        let rnNum = (word >> 5) & 0x1f
        let operand = A64.AddSubOperand.immediate(Int64(imm12), shift: sh == 1 ? 12 : nil)
        if s == 1 && word & 0x1f == 31 {
            return .compareAlias(op == 1 ? .cmp : .cmn, first: baseRegister(number: rnNum, width: width), operand: operand)
        }
        let rn = baseRegister(number: rnNum, width: width)
        let rd: IntegerRegister = s == 0 ? baseRegister(number: word & 0x1f, width: width) : integerRegister(number: word & 0x1f, width: width)
        let kind: A64.AddSubKind = op == 0 ? (s == 0 ? .add : .adds) : (s == 0 ? .sub : .subs)
        return .addSub(kind, destination: rd, first: rn, operand: operand)
    }

    private static func decodeAddSubShiftedRegister(_ word: UInt32) -> Instruction? {
        guard word & 0x1f20_0000 == 0x0b00_0000 else { return nil }
        let sf = (word >> 31) & 1
        let op = (word >> 30) & 1
        let s = (word >> 29) & 1
        let shiftField = (word >> 22) & 3
        guard let shiftKind = ShiftKind(rawValue: shiftField), shiftKind != .ror else { return nil }
        let amount = (word >> 10) & 0x3f
        let width = sf == 1 ? 64 : 32
        if sf == 0 && amount > 31 { return nil }
        let rm = integerRegister(number: (word >> 16) & 0x1f, width: width)
        let rnNum = (word >> 5) & 0x1f
        let shift: ParsedShift? = (amount == 0 && shiftKind == .lsl) ? nil : ParsedShift(kind: shiftKind, amount: Int(amount))
        let operand = A64.AddSubOperand.shiftedRegister(rm, shift: shift)
        if s == 1 && word & 0x1f == 31 {
            return .compareAlias(op == 1 ? .cmp : .cmn, first: integerRegister(number: rnNum, width: width), operand: operand)
        }
        let kind: A64.AddSubKind = op == 0 ? (s == 0 ? .add : .adds) : (s == 0 ? .sub : .subs)
        return .addSub(kind, destination: integerRegister(number: word & 0x1f, width: width), first: integerRegister(number: rnNum, width: width), operand: operand)
    }

    private static func decodeLogicalImmediate(_ word: UInt32) -> Instruction? {
        guard word & 0x1f80_0000 == 0x1200_0000 else { return nil }
        let sf = (word >> 31) & 1
        let n = (word >> 22) & 1
        if sf == 0 && n != 0 { return nil }
        let width = sf == 1 ? 64 : 32
        let immr = (word >> 16) & 0x3f
        let imms = (word >> 10) & 0x3f
        guard let value = A64BitmaskImmediate.decode(n: n, immr: immr, imms: imms, width: width) else { return nil }
        let kind: A64.LogicalKind
        switch (word >> 29) & 3 {
        case 0: kind = .and
        case 1: kind = .orr
        case 2: kind = .eor
        case 3: kind = .ands
        default: return nil
        }
        let rd = integerRegister(number: word & 0x1f, width: width)
        let rn = integerRegister(number: (word >> 5) & 0x1f, width: width)
        return .logical(kind, destination: rd, first: rn, operand: .immediate(Int64(bitPattern: value)))
    }

    private static func decodeLogicalShiftedRegister(_ word: UInt32) -> Instruction? {
        guard word & 0x1f00_0000 == 0x0a00_0000 else { return nil }
        let sf = (word >> 31) & 1
        let shiftField = (word >> 22) & 3
        let n = (word >> 21) & 1
        guard let shiftKind = ShiftKind(rawValue: shiftField) else { return nil }
        let amount = (word >> 10) & 0x3f
        let width = sf == 1 ? 64 : 32
        if sf == 0 && amount > 31 { return nil }
        let kind: A64.LogicalKind
        switch ((word >> 29) & 3, n) {
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
        let rm = integerRegister(number: (word >> 16) & 0x1f, width: width)
        let rnNum = (word >> 5) & 0x1f
        let rd = integerRegister(number: word & 0x1f, width: width)
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

    private static func decodeExtract(_ word: UInt32) -> Instruction? {
        guard word & 0x7fa0_0000 == 0x1380_0000 else { return nil }
        let sf = (word >> 31) & 1
        let n = (word >> 22) & 1
        guard n == sf else { return nil }
        let width = sf == 1 ? 64 : 32
        let imms = (word >> 10) & 0x3f
        if sf == 0 && imms > 31 { return nil }
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rd = integerRegister(number: word & 0x1f, width: width)
        let rn = integerRegister(number: rnNum, width: width)
        if rmNum == rnNum {
            return .extractOrRotateAlias(.ror, destination: rd, first: rn, operand: .rotate(amount: Int64(imms)))
        }
        return .extractOrRotateAlias(.extr, destination: rd, first: rn, operand: .extract(integerRegister(number: rmNum, width: width), amount: Int64(imms)))
    }

    private static func decodeMultiply(_ word: UInt32) -> Instruction? {
        guard word & 0x7fe0_0000 == 0x1b00_0000 else { return nil }
        let sf = (word >> 31) & 1
        let o0 = (word >> 15) & 1
        let width = sf == 1 ? 64 : 32
        let rm = integerRegister(number: (word >> 16) & 0x1f, width: width)
        let ra = (word >> 10) & 0x1f
        let rn = integerRegister(number: (word >> 5) & 0x1f, width: width)
        let rd = integerRegister(number: word & 0x1f, width: width)
        if ra == 31 {
            return .multiply(o0 == 1 ? .mneg : .mul, destination: rd, first: rn, second: rm, accumulator: nil)
        }
        return .multiply(o0 == 1 ? .msub : .madd, destination: rd, first: rn, second: rm, accumulator: integerRegister(number: ra, width: width))
    }

    private static func decodeDivide(_ word: UInt32) -> Instruction? {
        guard word & 0x7fe0_f800 == 0x1ac0_0800 else { return nil }
        let sf = (word >> 31) & 1
        let o1 = (word >> 10) & 1
        let width = sf == 1 ? 64 : 32
        let rm = integerRegister(number: (word >> 16) & 0x1f, width: width)
        let rn = integerRegister(number: (word >> 5) & 0x1f, width: width)
        let rd = integerRegister(number: word & 0x1f, width: width)
        return .divide(o1 == 1 ? .sdiv : .udiv, destination: rd, first: rn, second: rm)
    }

    private static func decodeLoadStoreSingle(_ word: UInt32) -> Instruction? {
        let op = word & 0x3f00_0000
        guard op == 0x3800_0000 || op == 0x3900_0000 else { return nil }
        let size = (word >> 30) & 3
        let opc = (word >> 22) & 3
        guard let info = loadStoreSingleKind(size: size, opc: opc) else { return nil }
        let scaledKind = info.scaled
        let unscaledKind = info.unscaled
        let base = xRegister(number: (word >> 5) & 0x1f)
        let rt = integerRegister(number: word & 0x1f, width: info.rtWidth)

        if op == 0x3900_0000 {
            let offset = Int64((word >> 10) & 0xfff) * info.byteSize
            return .loadStoreSingle(scaledKind, target: rt, memory: .unsignedOffset(base: base, offset: offset))
        }

        if (word >> 21) & 1 == 1 {
            guard (word >> 10) & 3 == 2 else { return nil }
            let optionRaw = (word >> 13) & 7
            let s = (word >> 12) & 1
            let rmWidth = (optionRaw == 2 || optionRaw == 6) ? 32 : 64
            let rm = integerRegister(number: (word >> 16) & 0x1f, width: rmWidth)
            let shift = s == 1 ? Int(size) : 0
            let extend: ExtendKind? = optionRaw == 3 ? nil : ExtendKind(rawValue: optionRaw)
            return .loadStoreSingle(scaledKind, target: rt, memory: .registerOffset(base: base, offset: rm, extend: extend, shift: shift))
        }

        let imm9 = signExtend((word >> 12) & 0x1ff, bitCount: 9)
        switch (word >> 10) & 3 {
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
        guard word & 0x3e00_0000 == 0x2800_0000 else { return nil }
        let opc2 = (word >> 30) & 3
        guard opc2 == 0 || opc2 == 2 else { return nil }
        let is64 = opc2 == 2
        let width = is64 ? 64 : 32
        let l = (word >> 22) & 1
        let scale: Int64 = is64 ? 8 : 4
        let offset = signExtend((word >> 15) & 0x7f, bitCount: 7) * scale
        let rt2 = integerRegister(number: (word >> 10) & 0x1f, width: width)
        let base = xRegister(number: (word >> 5) & 0x1f)
        let rt = integerRegister(number: word & 0x1f, width: width)
        let kind: A64.LoadStorePairKind = l == 1 ? .ldp : .stp
        let memory: MemoryOperand
        switch (word >> 23) & 3 {
        case 1: memory = .postIndexed(base: base, offset: offset)
        case 2: memory = .unsignedOffset(base: base, offset: offset)
        case 3: memory = .preIndexed(base: base, offset: offset)
        default: return nil
        }
        return .loadStorePair(kind, first: rt, second: rt2, memory: memory)
    }

    private static func decodeLoadStoreSingleFP(_ word: UInt32) -> Instruction? {
        // SIMD&FP load/store register: the integer forms with the V (bit 26) set.
        let op = word & 0x3f00_0000
        guard op == 0x3c00_0000 || op == 0x3d00_0000 else { return nil }
        let size = (word >> 30) & 3
        let opc = (word >> 22) & 3
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
        let base = xRegister(number: (word >> 5) & 0x1f)
        let rt = floatRegister(number: word & 0x1f, width: width)

        if op == 0x3d00_0000 {
            let offset = Int64((word >> 10) & 0xfff) * byteSize
            return .loadStoreSingleFP(scaledKind, target: rt, memory: .unsignedOffset(base: base, offset: offset))
        }

        if (word >> 21) & 1 == 1 {
            guard (word >> 10) & 3 == 2 else { return nil }
            let optionRaw = (word >> 13) & 7
            let s = (word >> 12) & 1
            let rmWidth = (optionRaw == 2 || optionRaw == 6) ? 32 : 64
            let rm = integerRegister(number: (word >> 16) & 0x1f, width: rmWidth)
            let shift = s == 1 ? Int(log2(Double(byteSize))) : 0
            let extend: ExtendKind? = optionRaw == 3 ? nil : ExtendKind(rawValue: optionRaw)
            return .loadStoreSingleFP(scaledKind, target: rt, memory: .registerOffset(base: base, offset: rm, extend: extend, shift: shift))
        }

        let imm9 = signExtend((word >> 12) & 0x1ff, bitCount: 9)
        switch (word >> 10) & 3 {
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
        guard word & 0x3e00_0000 == 0x2c00_0000 else { return nil }
        let opc2 = (word >> 30) & 3
        let width: Int
        let scale: Int64
        switch opc2 {
        case 0: width = 32;  scale = 4
        case 1: width = 64;  scale = 8
        case 2: width = 128; scale = 16
        default: return nil
        }
        let l = (word >> 22) & 1
        let offset = signExtend((word >> 15) & 0x7f, bitCount: 7) * scale
        let rt2 = floatRegister(number: (word >> 10) & 0x1f, width: width)
        let base = xRegister(number: (word >> 5) & 0x1f)
        let rt = floatRegister(number: word & 0x1f, width: width)
        let kind: A64.LoadStorePairKind = l == 1 ? .ldp : .stp
        let memory: MemoryOperand
        switch (word >> 23) & 3 {
        case 1: memory = .postIndexed(base: base, offset: offset)
        case 2: memory = .unsignedOffset(base: base, offset: offset)
        case 3: memory = .preIndexed(base: base, offset: offset)
        default: return nil
        }
        return .loadStorePairFP(kind, first: rt, second: rt2, memory: memory)
    }

    private static func decodeLoadStoreMultiple(_ word: UInt32) -> Instruction? {
        // Advanced SIMD load/store multiple structures: bit31=0, bits[29:24]=001100, bit24=0.
        guard word & 0xbf00_0000 == 0x0c00_0000 else { return nil }
        let post = (word >> 23) & 1
        if post == 0 {
            // The non-post form requires bits[21:16] == 0.
            guard (word >> 16) & 0x3f == 0 else { return nil }
        }
        let q = (word >> 30) & 1
        let l = (word >> 22) & 1
        let opcode = (word >> 12) & 0xf
        let size = (word >> 10) & 3
        let rn = (word >> 5) & 0x1f
        let rt = word & 0x1f

        guard let (structure, count) = A64.LoadStoreMultipleKind.decode(opcode: opcode),
              let kind = A64.LoadStoreMultipleKind.forStructure(structure, isLoad: l == 1),
              let arrangement = fullVectorArrangement(size: size, q: q) else { return nil }

        let list = A64.VectorRegisterList(firstNumber: rt, count: count, arrangement: arrangement)
        let base = xRegister(number: rn)
        let address: A64.VectorMemoryOperand
        if post == 0 {
            address = .base(base)
        } else {
            let rm = (word >> 16) & 0x1f
            address = rm == 0x1f ? .postImmediate(base) : .postRegister(base, offset: xRegister(number: rm))
        }
        return .loadStoreMultiple(kind, registers: list, address: address)
    }

    private static func decodeLoadStoreSingleStructure(_ word: UInt32) -> Instruction? {
        // Advanced SIMD load/store single structure & replicate: bit31=0, bits[29:23]=0011010, bit24=1.
        guard word & 0xbf00_0000 == 0x0d00_0000 else { return nil }
        let post = (word >> 23) & 1
        if post == 0 {
            // Non-post form: the Rm field (bits[20:16]) must be 0.
            guard (word >> 16) & 0x1f == 0 else { return nil }
        }
        let q = (word >> 30) & 1
        let l = (word >> 22) & 1
        let r = (word >> 21) & 1
        let opcode = (word >> 13) & 0b111
        let s = (word >> 12) & 1
        let size = (word >> 10) & 3
        let rn = (word >> 5) & 0x1f
        let rt = word & 0x1f
        let sizeClass = opcode >> 1
        let opcode0 = opcode & 1
        let selem = Int((opcode0 << 1) | r) + 1

        let base = xRegister(number: rn)
        func address() -> A64.VectorMemoryOperand {
            if post == 0 { return .base(base) }
            let rm = (word >> 16) & 0x1f
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
        // Advanced SIMD table lookup: bit31=0, bits[29:24]=001110, bits[23:21]=000,
        // bit15=0, bits[11:10]=00.
        guard word & 0xbfe0_8c00 == 0x0e00_0000 else { return nil }
        let q = (word >> 30) & 1
        let rm = (word >> 16) & 0x1f
        let len = (word >> 13) & 3
        let op = (word >> 12) & 1
        let rn = (word >> 5) & 0x1f
        let rd = word & 0x1f
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
        guard word & 0xff20_0c00 == 0x1e20_0800 else { return nil }
        guard let width = floatWidth(forPtype: (word >> 22) & 3) else { return nil }
        let kind: A64.FPDataProcessing2Kind
        switch (word >> 12) & 0xf {
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
            destination: floatRegister(number: word & 0x1f, width: width),
            first: floatRegister(number: (word >> 5) & 0x1f, width: width),
            second: floatRegister(number: (word >> 16) & 0x1f, width: width)
        )
    }

    private static func decodeFPDataProcessing1(_ word: UInt32) -> Instruction? {
        guard word & 0xff20_7c00 == 0x1e20_4000 else { return nil }
        guard let width = floatWidth(forPtype: (word >> 22) & 3) else { return nil }
        let opcode = (word >> 15) & 0x3f
        let rn = floatRegister(number: (word >> 5) & 0x1f, width: width)
        let kind: A64.FPDataProcessing1Kind
        switch opcode {
        case 0b000000: kind = .fmov
        case 0b000001: kind = .fabs
        case 0b000010: kind = .fneg
        case 0b000011: kind = .fsqrt
        case 0b000100, 0b000101, 0b000111:
            guard let target = floatWidth(forPtype: opcode & 3), target != width else { return nil }
            return .fpConvertPrecision(
                destination: floatRegister(number: word & 0x1f, width: target),
                source: rn
            )
        default:
            return nil
        }
        return .fpDataProcessing1(kind, destination: floatRegister(number: word & 0x1f, width: width), source: rn)
    }

    private static func decodeFPDataProcessing3(_ word: UInt32) -> Instruction? {
        guard word & 0xff00_0000 == 0x1f00_0000 else { return nil }
        guard let width = floatWidth(forPtype: (word >> 22) & 3) else { return nil }
        let o1 = (word >> 21) & 1
        let o0 = (word >> 15) & 1
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
            destination: floatRegister(number: word & 0x1f, width: width),
            first: floatRegister(number: (word >> 5) & 0x1f, width: width),
            second: floatRegister(number: (word >> 16) & 0x1f, width: width),
            third: floatRegister(number: (word >> 10) & 0x1f, width: width)
        )
    }

    private static func decodeFPCompare(_ word: UInt32) -> Instruction? {
        guard word & 0xff20_fc07 == 0x1e20_2000 else { return nil }
        guard let width = floatWidth(forPtype: (word >> 22) & 3) else { return nil }
        let opcode2 = word & 0x1f
        let kind: A64.FPCompareKind = (opcode2 >> 4) & 1 == 1 ? .fcmpe : .fcmp
        let rn = floatRegister(number: (word >> 5) & 0x1f, width: width)
        let second: A64.FPCompareOperand
        if (opcode2 >> 3) & 1 == 1 {
            guard (word >> 16) & 0x1f == 0 else { return nil }
            second = .zero
        } else {
            second = .register(floatRegister(number: (word >> 16) & 0x1f, width: width))
        }
        return .fpCompare(kind, first: rn, second: second)
    }

    private static func decodeFPMoveImmediate(_ word: UInt32) -> Instruction? {
        guard word & 0xff20_1fe0 == 0x1e20_1000 else { return nil }
        guard let width = floatWidth(forPtype: (word >> 22) & 3) else { return nil }
        let value = A64FloatImmediate.decode((word >> 13) & 0xff)
        return .fpMoveImmediate(destination: floatRegister(number: word & 0x1f, width: width), value: value)
    }

    private static func decodeFPIntegerConversion(_ word: UInt32) -> Instruction? {
        guard word & 0x7f20_fc00 == 0x1e20_0000 else { return nil }
        guard let width = floatWidth(forPtype: (word >> 22) & 3) else { return nil }
        let sf = (word >> 31) & 1
        let generalWidth = sf == 1 ? 64 : 32
        let rmode = (word >> 19) & 3
        let opcode = (word >> 16) & 7
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        switch (rmode, opcode) {
        case (0b11, 0b000), (0b11, 0b001):
            let kind: A64.FPConvertToIntKind = opcode == 0b000 ? .fcvtzs : .fcvtzu
            return .fpConvertToInt(kind, destination: integerRegister(number: rdNum, width: generalWidth), source: floatRegister(number: rnNum, width: width))
        case (0b00, 0b010), (0b00, 0b011):
            let kind: A64.FPConvertFromIntKind = opcode == 0b010 ? .scvtf : .ucvtf
            return .fpConvertFromInt(kind, destination: floatRegister(number: rdNum, width: width), source: integerRegister(number: rnNum, width: generalWidth))
        case (0b00, 0b110):
            guard width == 32 || width == 64 else { return nil }
            return .fpMoveToGeneral(destination: integerRegister(number: rdNum, width: generalWidth), source: floatRegister(number: rnNum, width: width))
        case (0b00, 0b111):
            guard width == 32 || width == 64 else { return nil }
            return .fpMoveFromGeneral(destination: floatRegister(number: rdNum, width: width), source: integerRegister(number: rnNum, width: generalWidth))
        default:
            return nil
        }
    }

    private static func decodeAcrossLanes(_ word: UInt32) -> Instruction? {
        guard word & 0x9f3e_0c00 == 0x0e30_0800 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let size = (word >> 22) & 3
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

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
        guard word & 0xffff_cc00 == 0x4e28_4800 else { return nil }
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
        guard word & 0xffe0_8c00 == 0x5e00_0000 else { return nil }
        let mNum = (word >> 16) & 0x1f
        let opcode = (word >> 12) & 0x7
        let nNum = (word >> 5) & 0x1f
        let dNum = word & 0x1f
        guard let kind = A64.CryptoSHA3Kind.decode(opcode: opcode) else { return nil }
        return .cryptoSHA3(kind, d: dNum, n: nNum, m: mNum)
    }

    private static func decodeCryptoSHA2(_ word: UInt32) -> Instruction? {
        // Crypto two-register SHA: 01011110 00 10100 0 000xx 10 Rn Rd.
        guard word & 0xffff_cc00 == 0x5e28_0800 else { return nil }
        let opcode = (word >> 12) & 0x1f
        let nNum = (word >> 5) & 0x1f
        let dNum = word & 0x1f
        guard let kind = A64.CryptoSHA2Kind.decode(opcode: opcode) else { return nil }
        return .cryptoSHA2(kind, d: dNum, n: nNum)
    }

    private static func decodeCryptoSHA512(_ word: UInt32) -> Instruction? {
        // Three-register SHA512: 11001110 011 Rm 1 0 00 opcode Rn Rd.
        guard word & 0xffe0_f000 == 0xce60_8000 else { return nil }
        let opcode = (word >> 10) & 0x3
        guard let kind = A64.CryptoSHA512Kind.decode(opcode: opcode) else { return nil }
        return .cryptoSHA512(kind, d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f)
    }

    private static func decodeCryptoTwoReg(_ word: UInt32) -> Instruction? {
        // Two-register SHA512/SM4: 11001110 110 00000 10 00 opcode Rn Rd.
        guard word & 0xffff_f000 == 0xcec0_8000 else { return nil }
        let opcode = (word >> 10) & 0x3
        guard let kind = A64.CryptoTwoRegKind.decode(opcode: opcode) else { return nil }
        return .cryptoTwoReg(kind, d: word & 0x1f, n: (word >> 5) & 0x1f)
    }

    private static func decodeCryptoSM3(_ word: UInt32) -> Instruction? {
        // Three-register SM3/SM4: 11001110 011 Rm 1 1 00 opcode Rn Rd.
        guard word & 0xffe0_f000 == 0xce60_c000 else { return nil }
        let opcode = (word >> 10) & 0x3
        guard let kind = A64.CryptoSM3Kind.decode(opcode: opcode) else { return nil }
        return .cryptoSM3(kind, d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f)
    }

    private static func decodeCryptoSM3Indexed(_ word: UInt32) -> Instruction? {
        // Three-register SM3 "imm2": 11001110 010 Rm 1 0 imm2 opcode Rn Rd.
        guard word & 0xffe0_c000 == 0xce40_8000 else { return nil }
        let opcode = (word >> 10) & 0x3
        guard let kind = A64.CryptoSM3IndexedKind.decode(opcode: opcode) else { return nil }
        let index = (word >> 12) & 0x3
        return .cryptoSM3Indexed(kind, d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f, index: index)
    }

    private static func decodeCryptoSM3SS1(_ word: UInt32) -> Instruction? {
        // Four-register SM3: 11001110 010 Rm 0 Ra Rn Rd.
        guard word & 0xffe0_8000 == 0xce40_0000 else { return nil }
        return .cryptoSM3SS1(d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f, a: (word >> 10) & 0x1f)
    }

    private static func decodeCryptoSHA3Four(_ word: UInt32) -> Instruction? {
        // Four-register SHA3: 11001110 0 Op0 Rm 0 Ra Rn Rd.
        guard word & 0xff80_8000 == 0xce00_0000 else { return nil }
        let op0 = (word >> 21) & 0x3
        guard let kind = A64.CryptoSHA3FourKind.decode(op0: op0) else { return nil }
        return .cryptoSHA3Four(kind, d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f, a: (word >> 10) & 0x1f)
    }

    private static func decodeCryptoRAX1(_ word: UInt32) -> Instruction? {
        // Three-register SHA3 RAX1: 11001110 011 Rm 1 0 0011 Rn Rd.
        guard word & 0xffe0_fc00 == 0xce60_8c00 else { return nil }
        return .cryptoRAX1(d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f)
    }

    private static func decodeCryptoXAR(_ word: UInt32) -> Instruction? {
        // XAR: 11001110 100 Rm imm6 Rn Rd.
        guard word & 0xffe0_0000 == 0xce80_0000 else { return nil }
        let imm6 = (word >> 10) & 0x3f
        return .cryptoXAR(d: word & 0x1f, n: (word >> 5) & 0x1f, m: (word >> 16) & 0x1f, imm6: imm6)
    }

    private static func decodeVectorTwoRegisterMiscFP16(_ word: UInt32) -> Instruction? {
        // Advanced SIMD two-register miscellaneous (FP16): bits[28:24]=01110,
        // [22]=1, [21:17]=11100, [11:10]=10. `a`=bit23 carries the regular form's
        // high `size` bit and selects the operation sub-page.
        guard word & 0x9f7e_0c00 == 0x0e78_0800 else { return nil }
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

    private static func decodeVectorTwoRegisterMisc(_ word: UInt32) -> Instruction? {
        guard word & 0x9f20_0c00 == 0x0e20_0800 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let size = (word >> 22) & 3
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

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
        // Shares the two-register-misc encoding (mask 0x9f200c00 == 0x0e200800);
        // selected by the compare-against-zero opcodes.
        guard word & 0x9f20_0c00 == 0x0e20_0800 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let size = (word >> 22) & 3
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

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
        guard word & 0x9f20_0c00 == 0x0e20_0800 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let sizeHi = (word >> 23) & 1
        let sz = (word >> 22) & 1
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

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
        guard word & 0x9f20_0c00 == 0x0e20_0800 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let size = (word >> 22) & 3
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

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
        guard word & 0x9f20_0c00 == 0x0e20_0800 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let size = (word >> 22) & 3
        let opcode = (word >> 12) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

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
        guard word & 0xbf20_c400 == 0x2e00_c400 else { return nil }
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
        guard word & 0xbf00_9400 == 0x2f00_1000 else { return nil }
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
        // bits[28:24]=01110, bit21=1, bit10=1 — unique to the three-same group.
        guard word & 0x9f20_0400 == 0x0e20_0400 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let size = (word >> 22) & 3
        let opcode = (word >> 11) & 0x1f
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

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
        guard word & 0x9f60_c400 == 0x0e40_0400 else { return nil }
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

    private static func decodeVectorShiftImmediate(_ word: UInt32) -> Instruction? {
        // bits[28:23]=011110, bit10=1; `immh` (22:19) must be non-zero (immh=0
        // is the modified-immediate group).
        guard word & 0x9f80_0400 == 0x0f00_0400 else { return nil }
        let immh = (word >> 19) & 0xf
        guard immh != 0 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let immb = (word >> 16) & 0x7
        let opcode = (word >> 11) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
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
        // bit31=0, bits[28:21]=01110000, bit15=0, bit10=1.
        guard word & 0x9fe0_8400 == 0x0e00_0400 else { return nil }
        let q = (word >> 30) & 1
        let op = (word >> 29) & 1
        let imm5 = (word >> 16) & 0x1f
        let imm4 = (word >> 11) & 0xf
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

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
        // bit31=0, bits[29:24]=001110, bit21=0, bit15=0, bits[11:10]=10.
        guard word & 0xbf20_8c00 == 0x0e00_0800 else { return nil }
        let q = (word >> 30) & 1
        let size = (word >> 22) & 0x3
        let opcode = (word >> 12) & 0x7
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
        guard let kind = A64.VectorPermuteKind.allCases.first(where: { $0.opcode == opcode }),
              let arrangement = threeSameIntegerArrangement(size: size, q: q) else { return nil }
        return .vectorPermute(kind,
            destination: VectorRegister(number: rdNum, arrangement: arrangement),
            first: VectorRegister(number: rnNum, arrangement: arrangement),
            second: VectorRegister(number: rmNum, arrangement: arrangement))
    }

    private static func decodeVectorExtract(_ word: UInt32) -> Instruction? {
        // bit31=0, bits[29:24]=101110, bits[23:22]=00, bit21=0, bit15=0, bit10=0.
        guard word & 0xbfe0_8400 == 0x2e00_0000 else { return nil }
        let q = (word >> 30) & 1
        let imm4 = (word >> 11) & 0xf
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f
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
        // bit31=0, bits[28:24]=01110, bit21=1, bits[11:10]=00.
        guard word & 0x9f20_0c00 == 0x0e20_0000 else { return nil }
        let q = (word >> 30) & 1
        let u = (word >> 29) & 1
        let size = (word >> 22) & 0x3
        let opcode = (word >> 12) & 0xf
        let rmNum = (word >> 16) & 0x1f
        let rnNum = (word >> 5) & 0x1f
        let rdNum = word & 0x1f

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
        guard word & 0x9f00_0400 == 0x0f00_0000 else { return nil }
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
        guard word & 0xdf20_0400 == 0x5e20_0400 else { return nil }
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
        guard word & 0xdf3e_0c00 == 0x5e20_0800 else { return nil }
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
        guard word & 0xdf80_0400 == 0x5f00_0400 else { return nil }
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
        guard word & 0xdf80_0400 == 0x5f00_0400 else { return nil }
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
        guard word & 0xdf80_0400 == 0x5f00_0400 else { return nil }
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

    private static func decodeScalarThreeSameFP(_ word: UInt32) -> Instruction? {
        // Shares the scalar three-same base (bit21=1, bit10=1), distinguished by
        // (U, bit23, opcode[15:11]); bit22 is the `sz` (single/double) bit.
        guard word & 0xdf20_0400 == 0x5e20_0400 else { return nil }
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

    private static func decodeScalarFPTwoRegisterMisc(_ word: UInt32) -> Instruction? {
        // Shares the scalar two-register misc base (bits[21:17]=10000, bits[11:10]=10),
        // distinguished by (U, bit23, opcode). bit22 is the `sz` (single/double) bit.
        guard word & 0xdf3e_0c00 == 0x5e20_0800 else { return nil }
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
        guard word & 0xffe0_fc00 == 0x5e00_0400 else { return nil }
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
        guard word & 0xdf00_0400 == 0x5f00_0000 else { return nil }
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
        guard word & 0xdf20_0c00 == 0x5e20_0000 else { return nil }
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
        guard word & 0xdf3e_0c00 == 0x5e20_0800 else { return nil }
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

    private static func decodeScalarPairwise(_ word: UInt32) -> Instruction? {
        // bit31=0, bit30=1, bits[28:24]=11110, bits[21:17]=11000, bits[11:10]=10.
        guard word & 0xdf3e_0c00 == 0x5e30_0800 else { return nil }
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
        case .fabs, .fneg, .fsqrt:
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
