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
        if let instruction = decodeFPDataProcessing3(word) { return instruction }
        if let instruction = decodeFPDataProcessing2(word) { return instruction }
        if let instruction = decodeFPDataProcessing1(word) { return instruction }
        if let instruction = decodeFPCompare(word) { return instruction }
        if let instruction = decodeFPMoveImmediate(word) { return instruction }
        if let instruction = decodeFPIntegerConversion(word) { return instruction }
        if let instruction = decodeAcrossLanes(word) { return instruction }
        if let instruction = decodeVectorTwoRegisterMisc(word) { return instruction }

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
        case .abs, .neg, .sqabs, .sqneg:
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
