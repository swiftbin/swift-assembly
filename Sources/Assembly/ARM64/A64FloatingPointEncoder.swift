import Foundation

/// Encodes/decodes the 8-bit modified floating-point immediate used by `FMOV (scalar, immediate)`.
///
/// The representable set is `±(16 + n)/16 × 2^e` for `n` in `0...15` and `e` in `-3...4`,
/// matching the Arm `VFPExpandImm` pseudocode.
internal enum A64FloatImmediate {
    static func encode(_ value: Double) -> UInt32? {
        guard value.isFinite else { return nil }
        let sign: UInt32 = value.sign == .minus ? 1 : 0
        let magnitude = abs(value)
        guard magnitude != 0 else { return nil }

        for exponent in -3...4 {
            let scaled = magnitude / pow(2.0, Double(exponent))
            guard scaled >= 1.0, scaled < 2.0 else { continue }
            let fractionValue = (scaled - 1.0) * 16.0
            let fraction = fractionValue.rounded()
            guard fraction == fractionValue, (0...15).contains(fraction) else { continue }

            let frac = UInt32(fraction)
            let exp = UInt32(exponent + 127)             // biased, lies in 124...131
            let b: UInt32 = ((exp >> 7) & 1) == 0 ? 1 : 0
            let c = (exp >> 1) & 1
            let d = exp & 1
            return (sign << 7) | (b << 6) | (c << 5) | (d << 4) | frac
        }
        return nil
    }

    static func decode(_ imm8: UInt32) -> Double {
        let sign = (imm8 >> 7) & 1
        let b = (imm8 >> 6) & 1
        let cd = (imm8 >> 4) & 0b11
        let frac = imm8 & 0xf

        let exp: Int
        if b == 0 {
            exp = Int(0b1000_0000 | cd) - 127
        } else {
            exp = Int(0b0111_1100 | cd) - 127
        }
        let mantissa = 1.0 + Double(frac) / 16.0
        let magnitude = mantissa * pow(2.0, Double(exp))
        return sign == 1 ? -magnitude : magnitude
    }
}

internal enum A64FloatEncoder {
    private static func ptype(_ register: FloatRegister, instruction: String) throws -> UInt32 {
        guard let value = register.ptype else { throw AssemblerError.invalidRegister(instruction) }
        return value
    }

    private static func requireSameType(_ registers: FloatRegister..., instruction: String) throws {
        guard let first = registers.first else { return }
        for register in registers where register.width != first.width {
            throw AssemblerError.invalidRegister(instruction)
        }
    }

    static func dataProcessing2(_ kind: A64.FPDataProcessing2Kind, destination rd: FloatRegister, first rn: FloatRegister, second rm: FloatRegister) throws -> UInt32 {
        try requireSameType(rd, rn, rm, instruction: kind.rawValue)
        let type = try ptype(rd, instruction: kind.rawValue)
        let opcode: UInt32
        switch kind {
        case .fmul: opcode = 0b0000
        case .fdiv: opcode = 0b0001
        case .fadd: opcode = 0b0010
        case .fsub: opcode = 0b0011
        case .fmax: opcode = 0b0100
        case .fmin: opcode = 0b0101
        case .fmaxnm: opcode = 0b0110
        case .fminnm: opcode = 0b0111
        case .fnmul: opcode = 0b1000
        }
        typealias F = A64.FPDataProcessing2
        return F.baseWord | F.type.insert(type) | F.rm.insert(rm.encodedNumber) | F.opcode.insert(opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func dataProcessing1(_ kind: A64.FPDataProcessing1Kind, destination rd: FloatRegister, source rn: FloatRegister) throws -> UInt32 {
        try requireSameType(rd, rn, instruction: kind.rawValue)
        let type = try ptype(rd, instruction: kind.rawValue)
        // frint32*/frint64* have no half-precision form.
        if !kind.allowsHalf, rd.width == 16 { throw AssemblerError.invalidRegister(kind.rawValue) }
        typealias F = A64.FPDataProcessing1
        return F.baseWord | F.type.insert(type) | F.opcode.insert(kind.opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func dataProcessing3(_ kind: A64.FPDataProcessing3Kind, destination rd: FloatRegister, first rn: FloatRegister, second rm: FloatRegister, third ra: FloatRegister) throws -> UInt32 {
        try requireSameType(rd, rn, rm, ra, instruction: kind.rawValue)
        let type = try ptype(rd, instruction: kind.rawValue)
        let o1: UInt32 = (kind == .fnmadd || kind == .fnmsub) ? 1 : 0
        let o0: UInt32 = (kind == .fmsub || kind == .fnmsub) ? 1 : 0
        typealias F = A64.FPDataProcessing3
        return F.baseWord | F.type.insert(type) | F.o1.insert(o1) | F.rm.insert(rm.encodedNumber)
            | F.o0.insert(o0) | F.ra.insert(ra.encodedNumber) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func compare(_ kind: A64.FPCompareKind, first rn: FloatRegister, second: A64.FPCompareOperand) throws -> UInt32 {
        let type = try ptype(rn, instruction: kind.rawValue)
        var rm: UInt32 = 0
        var opcode2: UInt32 = kind == .fcmpe ? 0b10000 : 0b00000
        switch second {
        case .register(let register):
            try requireSameType(rn, register, instruction: kind.rawValue)
            rm = register.encodedNumber
        case .zero:
            opcode2 |= 0b01000
        }
        typealias F = A64.FPCompare
        return F.baseWord | F.type.insert(type) | F.rm.insert(rm) | F.rn.insert(rn.encodedNumber) | F.opcode2.insert(opcode2)
    }

    static func convertPrecision(destination rd: FloatRegister, source rn: FloatRegister) throws -> UInt32 {
        let sourceType = try ptype(rn, instruction: "fcvt")
        guard rd.width != rn.width else { throw AssemblerError.invalidRegister("fcvt") }
        let targetOpc: UInt32
        switch rd.width {
        case 32: targetOpc = 0b00
        case 64: targetOpc = 0b01
        case 16: targetOpc = 0b11
        default: throw AssemblerError.invalidRegister("fcvt")
        }
        let opcode: UInt32 = 0b0001_00 | targetOpc
        let head: UInt32 = 0x1e20_4000 | (sourceType << 22)
        return head | (opcode << 15) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func bfloat16Convert(destination rd: FloatRegister, source rn: FloatRegister) throws -> UInt32 {
        // BFCVT converts a single-precision source to a BFloat16 (half-width) result.
        guard rd.width == 16, rn.width == 32 else { throw AssemblerError.invalidRegister("bfcvt") }
        return 0x1e63_4000 | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func moveImmediate(destination rd: FloatRegister, value: Double) throws -> UInt32 {
        let type = try ptype(rd, instruction: "fmov")
        guard let imm8 = A64FloatImmediate.encode(value) else {
            throw AssemblerError.invalidImmediate("#\(value)")
        }
        typealias F = A64.FPMoveImmediate
        return F.baseWord | F.type.insert(type) | F.imm8.insert(imm8) | F.rd.insert(rd.encodedNumber)
    }

    static func moveToGeneral(destination rd: IntegerRegister, source rn: FloatRegister) throws -> UInt32 {
        let (sf, type) = try generalMoveFields(general: rd, float: rn, instruction: "fmov")
        typealias F = A64.FPIntegerConversion
        return F.baseWord | F.sf.insert(sf) | F.type.insert(type) | F.opcode.insert(0b110) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func moveFromGeneral(destination rd: FloatRegister, source rn: IntegerRegister) throws -> UInt32 {
        let (sf, type) = try generalMoveFields(general: rn, float: rd, instruction: "fmov")
        typealias F = A64.FPIntegerConversion
        return F.baseWord | F.sf.insert(sf) | F.type.insert(type) | F.opcode.insert(0b111) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func convertToInt(_ kind: A64.FPConvertToIntKind, destination rd: IntegerRegister, source rn: FloatRegister) throws -> UInt32 {
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let type = try ptype(rn, instruction: kind.rawValue)
        let (rmode, opcode) = kind.spec
        typealias F = A64.FPIntegerConversion
        return F.baseWord | F.sf.insert(sf) | F.type.insert(type) | F.rmode.insert(rmode) | F.opcode.insert(opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func convertFromInt(_ kind: A64.FPConvertFromIntKind, destination rd: FloatRegister, source rn: IntegerRegister) throws -> UInt32 {
        let sf: UInt32 = rn.is64Bit ? 1 : 0
        let type = try ptype(rd, instruction: kind.rawValue)
        let opcode: UInt32 = kind == .scvtf ? 0b010 : 0b011
        typealias F = A64.FPIntegerConversion
        return F.baseWord | F.sf.insert(sf) | F.type.insert(type) | F.opcode.insert(opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func moveVectorHighToGeneral(destination rd: IntegerRegister, source element: A64.VectorElement) throws -> UInt32 {
        // Only `fmov x<d>, v<n>.d[1]` is encodable (64-bit general, top half of a 128-bit register).
        guard rd.is64Bit, element.width == .d, element.index == 1 else {
            throw AssemblerError.invalidRegister("fmov")
        }
        return 0x9eae_0000 | (element.encodedNumber << 5) | rd.encodedNumber
    }

    static func moveGeneralToVectorHigh(destination element: A64.VectorElement, source rn: IntegerRegister) throws -> UInt32 {
        guard rn.is64Bit, element.width == .d, element.index == 1 else {
            throw AssemblerError.invalidRegister("fmov")
        }
        return 0x9eaf_0000 | (rn.encodedNumber << 5) | element.encodedNumber
    }

    static func convertToFixed(_ kind: A64.FPConvertToIntKind, destination rd: IntegerRegister, source rn: FloatRegister, fbits: UInt32) throws -> UInt32 {
        // Only the round-toward-zero forms (`fcvtzs`/`fcvtzu`) have a fixed-point shape.
        guard kind.hasFixedPointForm else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let type = try ptype(rn, instruction: kind.rawValue)
        let maxFbits: UInt32 = rd.is64Bit ? 64 : 32
        guard fbits >= 1, fbits <= maxFbits else { throw AssemblerError.invalidImmediate("#\(fbits)") }
        let scale = 64 - fbits
        let opcode: UInt32 = kind == .fcvtzs ? 0b000 : 0b001
        typealias F = A64.FPFixedConversion
        return F.baseWord | F.sf.insert(sf) | F.type.insert(type) | F.rmode.insert(0b11)
            | F.opcode.insert(opcode) | F.scale.insert(scale) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func convertFromFixed(_ kind: A64.FPConvertFromIntKind, destination rd: FloatRegister, source rn: IntegerRegister, fbits: UInt32) throws -> UInt32 {
        let sf: UInt32 = rn.is64Bit ? 1 : 0
        let type = try ptype(rd, instruction: kind.rawValue)
        let maxFbits: UInt32 = rn.is64Bit ? 64 : 32
        guard fbits >= 1, fbits <= maxFbits else { throw AssemblerError.invalidImmediate("#\(fbits)") }
        let scale = 64 - fbits
        let opcode: UInt32 = kind == .scvtf ? 0b010 : 0b011
        typealias F = A64.FPFixedConversion
        return F.baseWord | F.sf.insert(sf) | F.type.insert(type)
            | F.opcode.insert(opcode) | F.scale.insert(scale) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func conditionalSelect(destination rd: FloatRegister, first rn: FloatRegister, second rm: FloatRegister, condition: A64.Condition) throws -> UInt32 {
        try requireSameType(rd, rn, rm, instruction: "fcsel")
        let type = try ptype(rd, instruction: "fcsel")
        typealias F = A64.FPConditionalSelect
        return F.baseWord | F.type.insert(type) | F.rm.insert(rm.encodedNumber) | F.cond.insert(condition.rawValue) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func conditionalCompare(_ kind: A64.FPConditionalCompareKind, first rn: FloatRegister, second rm: FloatRegister, nzcv: UInt32, condition: A64.Condition) throws -> UInt32 {
        try requireSameType(rn, rm, instruction: kind.rawValue)
        let type = try ptype(rn, instruction: kind.rawValue)
        guard nzcv <= 0xf else { throw AssemblerError.invalidImmediate("#\(nzcv)") }
        typealias F = A64.FPConditionalCompare
        return F.baseWord | F.type.insert(type) | F.rm.insert(rm.encodedNumber) | F.cond.insert(condition.rawValue)
            | F.rn.insert(rn.encodedNumber) | F.op.insert(kind.op) | F.nzcv.insert(nzcv)
    }

    static func fjcvtzs(destination rd: IntegerRegister, source rn: FloatRegister) throws -> UInt32 {
        // Fixed form: 32-bit general destination, double-precision source.
        guard !rd.is64Bit, rn.width == 64 else {
            throw AssemblerError.invalidRegister("fjcvtzs")
        }
        return 0x1e7e_0000 | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    /// Resolves the `sf`/`type` fields for `FMOV` between a general register and a single/double FP register.
    private static func generalMoveFields(general: IntegerRegister, float: FloatRegister, instruction: String) throws -> (sf: UInt32, type: UInt32) {
        switch (general.is64Bit, float.width) {
        case (false, 32): return (0, 0b00)
        case (true, 64): return (1, 0b01)
        // Half-precision (FEAT_FP16) pairs with either a 32- or 64-bit register.
        case (false, 16): return (0, 0b11)
        case (true, 16): return (1, 0b11)
        default: throw AssemblerError.invalidRegister(instruction)
        }
    }
}
