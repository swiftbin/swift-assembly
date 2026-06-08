import Foundation

internal enum A64VectorEncoder {
    /// The arrangements permitted by the integer "across lanes" group.
    /// `2s`, `1d` and `2d` are reserved (`size=10` requires `Q=1`, i.e. `4s`).
    private static let allowedIntegerArrangements: Set<A64.VectorArrangement> = [.b8, .b16, .h4, .h8, .s4]

    static func acrossLanesInteger(_ kind: A64.AcrossLanesIntegerKind, destination rd: FloatRegister, source rn: VectorRegister) throws -> UInt32 {
        guard allowedIntegerArrangements.contains(rn.arrangement) else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }

        let isLong = kind == .saddlv || kind == .uaddlv
        let expectedDestinationWidth = isLong ? rn.arrangement.elementWidth * 2 : rn.arrangement.elementWidth
        guard rd.width == expectedDestinationWidth else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }

        let u: UInt32
        let opcode: UInt32
        switch kind {
        case .saddlv: u = 0; opcode = 0b00011
        case .uaddlv: u = 1; opcode = 0b00011
        case .smaxv: u = 0; opcode = 0b01010
        case .umaxv: u = 1; opcode = 0b01010
        case .sminv: u = 0; opcode = 0b11010
        case .uminv: u = 1; opcode = 0b11010
        case .addv: u = 0; opcode = 0b11011
        }

        typealias F = A64.VectorAcrossLanes
        return F.baseWord | F.q.insert(rn.arrangement.q) | F.u.insert(u) | F.size.insert(rn.arrangement.elementSize)
            | F.opcode.insert(opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func acrossLanesFP(_ kind: A64.AcrossLanesFPKind, destination rd: FloatRegister, source rn: VectorRegister) throws -> UInt32 {
        let o1: UInt32
        let opcode: UInt32
        switch kind {
        case .fmaxv: o1 = 0; opcode = 0b01111
        case .fminv: o1 = 1; opcode = 0b01111
        case .fmaxnmv: o1 = 0; opcode = 0b01100
        case .fminnmv: o1 = 1; opcode = 0b01100
        }

        typealias F = A64.VectorAcrossLanes
        let common = F.baseWord | F.size.insert(o1 << 1) | F.opcode.insert(opcode)
            | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)

        // Half-precision (FP16) form: source `.4h`/`.8h`, destination `h` (U=0).
        if rn.arrangement == .h4 || rn.arrangement == .h8 {
            guard rd.width == 16 else { throw AssemblerError.invalidRegister(kind.rawValue) }
            return common | F.q.insert(rn.arrangement.q)
        }

        // Single-precision `.4s` form (sz=0): Q=1, U=1.
        guard rn.arrangement == .s4, rd.width == 32 else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }
        return common | F.q.insert(1) | F.u.insert(1)
    }

    static func twoRegisterMisc(_ kind: A64.VectorTwoRegisterMiscKind, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        guard rd.arrangement == rn.arrangement else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }
        guard isValidTwoRegisterMiscArrangement(kind, rn.arrangement) else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }

        let u: UInt32
        let opcode: UInt32
        switch kind {
        case .rev64: u = 0; opcode = 0b00000
        case .rev32: u = 1; opcode = 0b00000
        case .rev16: u = 0; opcode = 0b00001
        case .cnt: u = 0; opcode = 0b00101
        case .mvn: u = 1; opcode = 0b00101
        case .rbit: u = 1; opcode = 0b00101
        case .cls: u = 0; opcode = 0b00100
        case .clz: u = 1; opcode = 0b00100
        case .sqabs: u = 0; opcode = 0b00111
        case .sqneg: u = 1; opcode = 0b00111
        case .suqadd: u = 0; opcode = 0b00011
        case .usqadd: u = 1; opcode = 0b00011
        case .abs: u = 0; opcode = 0b01011
        case .neg: u = 1; opcode = 0b01011
        case .fabs: u = 0; opcode = 0b01111
        case .fneg: u = 1; opcode = 0b01111
        case .fsqrt: u = 1; opcode = 0b11111
        case .frint32z: u = 0; opcode = 0b11110
        case .frint32x: u = 1; opcode = 0b11110
        case .frint64z: u = 0; opcode = 0b11111
        case .frint64x: u = 1; opcode = 0b11111
        }

        typealias F = A64.VectorTwoRegisterMisc
        let regs = F.q.insert(rn.arrangement.q) | F.u.insert(u)
            | F.opcode.insert(opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)

        let isFloat = kind == .fabs || kind == .fneg || kind == .fsqrt
        if isFloat, rn.arrangement.elementWidth == 16 {
            // FP16 form (`.4h`/`.8h`): the FP16 misc page fixes `a` (bit23) = 1.
            return fp16TwoRegisterMiscBase | regs | (1 << 23)
        }

        // frint32/frint64 carry the FP `sz` at bit22 with size-hi (bit23) = 0,
        // unlike the rest of the group which encodes the element `size` at [23:22].
        switch kind {
        case .frint32z, .frint32x, .frint64z, .frint64x:
            let sz: UInt32 = rn.arrangement.elementWidth == 64 ? 1 : 0
            return F.baseWord | regs | F.size.insert(sz)
        default:
            break
        }

        let size = kind == .rbit ? UInt32(0b01) : rn.arrangement.elementSize
        return F.baseWord | regs | F.size.insert(size)
    }

    static func threeSame(_ kind: A64.VectorThreeSameKind, destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        let arrangement = rd.arrangement
        guard rn.arrangement == arrangement, rm.arrangement == arrangement else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }
        guard kind.allowedArrangements.contains(arrangement) else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }

        let spec = kind.spec
        typealias F = A64.VectorThreeSame
        let regs = F.q.insert(arrangement.q) | F.u.insert(spec.u)
            | F.rm.insert(rm.encodedNumber) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)

        switch spec.family {
        case .integer:
            return F.baseWord | regs | F.size.insert(arrangement.elementSize) | F.opcode.insert(spec.opcode)
        case .logical:
            // The element-`size` field carries the operation selector.
            return F.baseWord | regs | F.size.insert(spec.variant) | F.opcode.insert(spec.opcode)
        case .floatingPoint:
            if arrangement.elementWidth == 16 {
                // Three-same (FP16): `.4h`/`.8h`. Distinct base ([22:21]=10);
                // opcode is the low 3 bits and `a` selects the sub-group at bit23.
                let fp16Base: UInt32 = 0x0e40_0400
                return fp16Base | regs | F.size.insert(spec.variant << 1) | F.opcode.insert(spec.opcode & 0b111)
            }
            // `a` selects the operation sub-group at bit23; `sz` (bit22) is 0 for
            // single precision (`.2s`/`.4s`) and 1 for double precision (`.2d`).
            let sz: UInt32 = arrangement.elementWidth == 64 ? 1 : 0
            return F.baseWord | regs | F.size.insert((spec.variant << 1) | sz) | F.opcode.insert(spec.opcode)
        }
    }

    /// The arrangements permitted by the same-arrangement shift forms.
    /// `1d` is the scalar form and is not a vector arrangement here.
    private static let allowedSameArrangements: Set<A64.VectorArrangement> = [.b8, .b16, .h4, .h8, .s2, .s4, .d2]

    /// Maps a "low" arrangement (`8b`, `4h`, `2s`, ...) to the fully populated
    /// arrangement one element-size up (`8h`, `4s`, `2d`), used by the
    /// narrowing and widening shift forms.
    private static func doubledArrangement(_ arrangement: A64.VectorArrangement) -> A64.VectorArrangement? {
        switch arrangement {
        case .b8, .b16: return .h8
        case .h4, .h8: return .s4
        case .s2, .s4: return .d2
        case .h2, .d1, .d2, .q1: return nil
        }
    }

    static func shiftLeftLong(destination rd: VectorRegister, source rn: VectorRegister, shift: UInt32) throws -> UInt32 {
        // `shll`/`shll2`: source is 8b/16b, 4h/8h, 2s/4s; destination is the long
        // form 8h/4s/2d; the shift always equals the source element width.
        switch (rn.arrangement, rd.arrangement) {
        case (.b8, .h8), (.b16, .h8), (.h4, .s4), (.h8, .s4), (.s2, .d2), (.s4, .d2):
            break
        default:
            throw AssemblerError.invalidRegister("shll")
        }
        guard shift == UInt32(rn.arrangement.elementWidth) else {
            throw AssemblerError.invalidImmediate("#\(shift)")
        }
        typealias F = A64.VectorTwoRegisterMisc
        return F.baseWord | F.q.insert(rn.arrangement.q) | F.u.insert(1) | F.size.insert(rn.arrangement.elementSize)
            | F.opcode.insert(0b10011) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func shiftImmediate(_ kind: A64.VectorShiftImmediateKind, destination rd: VectorRegister, source rn: VectorRegister, shift: Int) throws -> UInt32 {
        let spec = kind.spec

        let q: UInt32
        let esize: Int
        let immhimmb: UInt32

        switch spec.category {
        case .sameRight:
            guard rd.arrangement == rn.arrangement, allowedSameArrangements.contains(rd.arrangement) else {
                throw AssemblerError.invalidRegister(kind.rawValue)
            }
            esize = rd.arrangement.elementWidth
            try checkRange(Int64(shift), 1...Int64(esize), instruction: kind.rawValue)
            q = rd.arrangement.q
            immhimmb = UInt32(2 * esize - shift)

        case .sameLeft:
            guard rd.arrangement == rn.arrangement, allowedSameArrangements.contains(rd.arrangement) else {
                throw AssemblerError.invalidRegister(kind.rawValue)
            }
            esize = rd.arrangement.elementWidth
            try checkRange(Int64(shift), 0...Int64(esize - 1), instruction: kind.rawValue)
            q = rd.arrangement.q
            immhimmb = UInt32(esize + shift)

        case .narrow:
            // Destination is the narrow arrangement; the source is the fully
            // populated arrangement one element-size up.
            guard let expectedSource = doubledArrangement(rd.arrangement), rn.arrangement == expectedSource else {
                throw AssemblerError.invalidRegister(kind.rawValue)
            }
            esize = rd.arrangement.elementWidth
            try checkRange(Int64(shift), 1...Int64(esize), instruction: kind.rawValue)
            q = rd.arrangement.q
            immhimmb = UInt32(2 * esize - shift)

        case .widen:
            // Source is the narrow arrangement; the destination is the fully
            // populated arrangement one element-size up.
            guard let expectedDestination = doubledArrangement(rn.arrangement), rd.arrangement == expectedDestination else {
                throw AssemblerError.invalidRegister(kind.rawValue)
            }
            esize = rn.arrangement.elementWidth
            try checkRange(Int64(shift), 0...Int64(esize - 1), instruction: kind.rawValue)
            q = rn.arrangement.q
            immhimmb = UInt32(esize + shift)

        case .convert:
            guard rd.arrangement == rn.arrangement, [.s2, .s4, .d2].contains(rd.arrangement) else {
                throw AssemblerError.invalidRegister(kind.rawValue)
            }
            esize = rd.arrangement.elementWidth
            try checkRange(Int64(shift), 1...Int64(esize), instruction: kind.rawValue)
            q = rd.arrangement.q
            immhimmb = UInt32(2 * esize - shift)
        }

        typealias F = A64.VectorShiftImmediate
        return F.baseWord | F.q.insert(q) | F.u.insert(spec.u) | F.immh.insert(immhimmb >> 3) | F.immb.insert(immhimmb & 0b111)
            | F.opcode.insert(spec.opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func modifiedImmediate(_ kind: A64.VectorModifiedImmediateKind, destination rd: VectorRegister, imm8: UInt8, shift: A64.VectorImmediateShift) throws -> UInt32 {
        let arrangement = rd.arrangement
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // op[29] distinguishes the "negated" variants; cmode[15:12] selects the form.
        let op: UInt32
        let cmode: UInt32

        switch kind {
        case .fmov:
            guard case .none = shift else { throw fail() }
            switch arrangement {
            case .s2, .s4: op = 0; cmode = 0b1111
            case .d2: op = 1; cmode = 0b1111
            default: throw fail()
            }
        case .movi, .mvni, .orr, .bic:
            let isNegated = kind == .mvni || kind == .bic       // op = 1
            let isLogical = kind == .orr || kind == .bic        // cmode bit0 = 1
            switch arrangement {
            case .b8, .b16:
                guard kind == .movi, case .none = shift else { throw fail() }
                op = 0; cmode = 0b1110
            case .h4, .h8:
                let amount = try lslAmount(shift, allowed: [0, 8], kind: kind)
                op = isNegated ? 1 : 0
                cmode = 0b1000 | (UInt32(amount / 8) << 1) | (isLogical ? 1 : 0)
            case .s2, .s4:
                if case .msl(let amount) = shift {
                    guard !isLogical, amount == 8 || amount == 16 else { throw fail() }
                    op = isNegated ? 1 : 0
                    cmode = 0b1100 | (amount == 16 ? 1 : 0)
                } else {
                    let amount = try lslAmount(shift, allowed: [0, 8, 16, 24], kind: kind)
                    op = isNegated ? 1 : 0
                    cmode = 0b0000 | (UInt32(amount / 8) << 1) | (isLogical ? 1 : 0)
                }
            case .d1, .d2:
                // 64-bit `movi` (vector `.2d` or the scalar `d` form).
                guard kind == .movi, case .none = shift else { throw fail() }
                op = 1; cmode = 0b1110
            case .h2, .q1:
                throw fail()
            }
        }

        let q: UInt32 = arrangement == .d1 ? 0 : arrangement.q
        let abc = (UInt32(imm8) >> 5) & 0x7
        let defgh = UInt32(imm8) & 0x1f
        let base: UInt32 = 0x0f00_0000 | (1 << 10)
        return (q << 30) | (op << 29) | base | (abc << 16) | (cmode << 12) | (defgh << 5) | rd.encodedNumber
    }

    // MARK: - Copy (DUP / SMOV / UMOV / INS)

    /// The element width implied by a vector arrangement.
    private static func elementWidth(of arrangement: A64.VectorArrangement) -> A64.VectorElementWidth {
        switch arrangement.elementWidth {
        case 8: return .b
        case 16: return .h
        case 32: return .s
        default: return .d
        }
    }

    private static func encodeCopy(q: UInt32, op: UInt32, imm5: UInt32, imm4: UInt32, rn: UInt32, rd: UInt32) -> UInt32 {
        // Base: bits[28:24]=01110, bit10=1.
        let base: UInt32 = 0x0e00_0400
        return (q << 30) | (op << 29) | base | (imm5 << 16) | (imm4 << 11) | (rn << 5) | rd
    }

    private static func validateLane(_ element: A64.VectorElement) throws {
        guard element.index >= 0, element.index <= element.width.maxIndex else {
            throw AssemblerError.invalidRegister("v\(element.number).\(element.width.rawValue)[\(element.index)]")
        }
    }

    static func duplicateElement(destination rd: VectorRegister, source element: A64.VectorElement) throws -> UInt32 {
        guard rd.arrangement != .d1 else { throw AssemblerError.invalidRegister("dup") }
        guard elementWidth(of: rd.arrangement) == element.width else { throw AssemblerError.invalidRegister("dup") }
        try validateLane(element)
        let imm5 = element.width.imm5(index: element.index)
        return encodeCopy(q: rd.arrangement.q, op: 0, imm5: imm5, imm4: 0b0000, rn: element.encodedNumber, rd: rd.encodedNumber)
    }

    static func duplicateGeneral(destination rd: VectorRegister, source rn: IntegerRegister) throws -> UInt32 {
        guard rd.arrangement != .d1 else { throw AssemblerError.invalidRegister("dup") }
        let width = elementWidth(of: rd.arrangement)
        // A 64-bit element requires an X register; narrower elements require W.
        guard rn.is64Bit == (width == .d) else { throw AssemblerError.invalidRegister("dup") }
        let imm5 = width.imm5(index: 0)
        return encodeCopy(q: rd.arrangement.q, op: 0, imm5: imm5, imm4: 0b0001, rn: rn.encodedNumber, rd: rd.encodedNumber)
    }

    static func moveToGeneral(signed: Bool, destination rd: IntegerRegister, source element: A64.VectorElement) throws -> UInt32 {
        try validateLane(element)
        // SMOV: Wd <- B/H, Xd <- B/H/S.   UMOV: Wd <- B/H/S, Xd <- D.
        let valid: Bool
        if signed {
            valid = rd.is64Bit ? [.b, .h, .s].contains(element.width) : [.b, .h].contains(element.width)
        } else {
            valid = rd.is64Bit ? element.width == .d : [.b, .h, .s].contains(element.width)
        }
        guard valid else { throw AssemblerError.invalidRegister(signed ? "smov" : "umov") }
        let imm4: UInt32 = signed ? 0b0101 : 0b0111
        let q: UInt32 = rd.is64Bit ? 1 : 0
        let imm5 = element.width.imm5(index: element.index)
        return encodeCopy(q: q, op: 0, imm5: imm5, imm4: imm4, rn: element.encodedNumber, rd: rd.encodedNumber)
    }

    static func insertGeneral(destination element: A64.VectorElement, source rn: IntegerRegister) throws -> UInt32 {
        try validateLane(element)
        guard rn.is64Bit == (element.width == .d) else { throw AssemblerError.invalidRegister("ins") }
        let imm5 = element.width.imm5(index: element.index)
        return encodeCopy(q: 1, op: 0, imm5: imm5, imm4: 0b0011, rn: rn.encodedNumber, rd: element.encodedNumber)
    }

    static func insertElement(destination dst: A64.VectorElement, source src: A64.VectorElement) throws -> UInt32 {
        guard dst.width == src.width else { throw AssemblerError.invalidRegister("ins") }
        try validateLane(dst)
        try validateLane(src)
        let imm5 = dst.width.imm5(index: dst.index)
        let imm4 = UInt32(src.index) << dst.width.sizeShift
        return encodeCopy(q: 1, op: 1, imm5: imm5, imm4: imm4, rn: src.encodedNumber, rd: dst.encodedNumber)
    }

    // MARK: - Permute (ZIP / UZP / TRN) and Extract (EXT)

    /// Arrangements permitted by the permute group (`1d` is reserved).
    private static let allowedPermuteArrangements: Set<A64.VectorArrangement> = [.b8, .b16, .h4, .h8, .s2, .s4, .d2]

    static func permute(_ kind: A64.VectorPermuteKind, destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        let arrangement = rd.arrangement
        guard rn.arrangement == arrangement, rm.arrangement == arrangement,
              allowedPermuteArrangements.contains(arrangement) else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }
        typealias F = A64.VectorPermute
        return F.baseWord | F.q.insert(arrangement.q) | F.size.insert(arrangement.elementSize)
            | F.rm.insert(rm.encodedNumber) | F.opcode.insert(kind.opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func extract(destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister, index: Int) throws -> UInt32 {
        let arrangement = rd.arrangement
        guard rn.arrangement == arrangement, rm.arrangement == arrangement,
              arrangement == .b8 || arrangement == .b16 else {
            throw AssemblerError.invalidRegister("ext")
        }
        // 8-byte form indexes 0..7; 16-byte form indexes 0..15.
        let maxIndex = arrangement == .b16 ? 15 : 7
        try checkRange(Int64(index), 0...Int64(maxIndex), instruction: "ext")
        typealias F = A64.VectorExtract
        return F.baseWord | F.q.insert(arrangement.q) | F.rm.insert(rm.encodedNumber)
            | F.index.insert(UInt32(index)) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    // MARK: - Three different (long / wide / narrow)

    static func threeDifferent(_ kind: A64.VectorThreeDifferentKind, destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // PMULL/PMULL2 also have a 64→128 polynomial form whose source is the
        // doubleword arrangement (`1d`/`2d`) and whose destination is `1q`. This
        // does not fit the regular "doubled element" long form, so handle it here.
        typealias F = A64.VectorThreeDifferent
        func encode(q: UInt32, size: UInt32) -> UInt32 {
            F.baseWord | F.q.insert(q) | F.u.insert(spec.u) | F.size.insert(size)
                | F.rm.insert(rm.encodedNumber) | F.opcode.insert(spec.opcode)
                | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
        }

        if kind == .pmull, rd.arrangement == .q1 {
            guard rn.arrangement == rm.arrangement,
                  rn.arrangement == .d1 || rn.arrangement == .d2 else { throw fail() }
            return encode(q: rn.arrangement.q, size: 0b11)
        }

        // The narrow operand fixes both `size` and `Q`.
        let narrow: A64.VectorArrangement
        switch spec.form {
        case .long:
            guard rn.arrangement == rm.arrangement,
                  doubledArrangement(rn.arrangement) == rd.arrangement else { throw fail() }
            narrow = rn.arrangement
        case .wide:
            guard rd.arrangement == rn.arrangement,
                  doubledArrangement(rm.arrangement) == rd.arrangement else { throw fail() }
            narrow = rm.arrangement
        case .narrow:
            guard rn.arrangement == rm.arrangement,
                  doubledArrangement(rd.arrangement) == rn.arrangement else { throw fail() }
            narrow = rd.arrangement
        }

        let size = narrow.elementSize
        switch kind {
        case .pmull:
            // Only the byte form (`Vd.8H, Vn.8B`) is supported; the 64→128 (`1q`) form is out of scope.
            guard size == 0b00 else { throw fail() }
        case .sqdmull, .sqdmlal, .sqdmlsl:
            guard size == 0b01 || size == 0b10 else { throw fail() }
        default:
            break
        }

        return encode(q: narrow.q, size: size)
    }

    // MARK: - Dot product

    /// Validates that a dot-product destination (`2s`/`4s`) is paired with the
    /// matching source byte arrangement (`8b`/`16b`) and returns the `Q` bit.
    private static func dotProductQ(destination rd: VectorRegister, first rn: VectorRegister) -> UInt32? {
        switch (rd.arrangement, rn.arrangement) {
        case (.s2, .b8):  return 0
        case (.s4, .b16): return 1
        default:          return nil
        }
    }

    static func dotProduct(_ kind: A64.VectorDotProductKind, destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        guard let q = dotProductQ(destination: rd, first: rn), rn.arrangement == rm.arrangement else { throw fail() }
        let base: UInt32 = 0x0e80_9400
        let head = (q << 30) | (kind.u << 29) | base
        return head | (rm.encodedNumber << 16) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func dotProductByElement(_ kind: A64.VectorDotProductKind, destination rd: VectorRegister, first rn: VectorRegister, elementRegister: UInt32, index: UInt32) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        guard let q = dotProductQ(destination: rd, first: rn) else { throw fail() }
        guard elementRegister <= 31, index <= 3 else { throw fail() }
        let l = index & 1
        let h = (index >> 1) & 1
        let m = (elementRegister >> 4) & 1
        let rmLow = elementRegister & 0xf
        let base: UInt32 = 0x0f80_e000
        let head = (q << 30) | (kind.u << 29) | base
        return head | (l << 21) | (m << 20) | (rmLow << 16) | (h << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    // MARK: - Mixed-sign dot product (FEAT_I8MM)

    static func usDotProduct(destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister("usdot") }
        guard let q = dotProductQ(destination: rd, first: rn), rn.arrangement == rm.arrangement else { throw fail() }
        let head = (q << 30) | 0x0e80_9c00
        return head | (rm.encodedNumber << 16) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func mixedDotByElement(_ kind: A64.VectorMixedDotProductKind, destination rd: VectorRegister, first rn: VectorRegister, elementRegister: UInt32, index: UInt32) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        guard let q = dotProductQ(destination: rd, first: rn) else { throw fail() }
        guard elementRegister <= 31, index <= 3 else { throw fail() }
        let l = index & 1
        let h = (index >> 1) & 1
        let m = (elementRegister >> 4) & 1
        let rmLow = elementRegister & 0xf
        let us: UInt32 = kind == .usdot ? 1 : 0
        let head = (q << 30) | 0x0f00_f000 | (us << 23)
        return head | (l << 21) | (m << 20) | (rmLow << 16) | (h << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    // MARK: - Int8 matrix multiply-accumulate (FEAT_I8MM)

    static func matrixMultiply(_ kind: A64.VectorMatrixMultiplyKind, destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        guard rd.arrangement == .s4, rn.arrangement == .b16, rm.arrangement == .b16 else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }
        let base: UInt32 = 0x4e80_a400
        return base | (kind.u << 29) | (rm.encodedNumber << 16) | (kind.b << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    // MARK: - Three-same extra (saturating rounding multiply-accumulate)

    static func threeSameExtra(_ kind: A64.VectorThreeSameExtraKind, destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        guard rd.arrangement == rn.arrangement, rn.arrangement == rm.arrangement else { throw fail() }
        let size: UInt32
        switch rd.arrangement {
        case .h4, .h8: size = 0b01
        case .s2, .s4: size = 0b10
        default: throw fail()
        }
        let base: UInt32 = 0x0e00_8400   // bits[28:24]=01110, bit15=1, bit10=1.
        let head = (rd.arrangement.q << 30) | (1 << 29) | base | (size << 22)
        return head | (rm.encodedNumber << 16) | (kind.opcode << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarThreeSameExtra(_ kind: A64.VectorThreeSameExtraKind, destination rd: FloatRegister, first rn: FloatRegister, second rm: FloatRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        guard rd.width == rn.width, rn.width == rm.width else { throw fail() }
        let size: UInt32
        switch rd.width {
        case 16: size = 0b01
        case 32: size = 0b10
        default: throw fail()
        }
        let base: UInt32 = 0x5e00_8400   // bit30=1, bits[28:24]=11110, bit15=1, bit10=1.
        let head = (1 << 29) | base | (size << 22)
        return head | (rm.encodedNumber << 16) | (kind.opcode << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    // MARK: - Complex number (FCADD / FCMLA)

    /// Maps a complex-arithmetic arrangement (`4h`/`8h`/`2s`/`4s`/`2d`) to its
    /// `size` field; `1d` and the byte forms are invalid.
    private static func complexSize(_ arrangement: A64.VectorArrangement) -> UInt32? {
        switch arrangement {
        case .h4, .h8: return 0b01
        case .s2, .s4: return 0b10
        case .d2:      return 0b11
        default:       return nil
        }
    }

    static func complexAdd(destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister, rotation: Int) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister("fcadd") }
        guard rd.arrangement == rn.arrangement, rn.arrangement == rm.arrangement,
              let size = complexSize(rd.arrangement) else { throw fail() }
        let rot: UInt32
        switch rotation {
        case 90:  rot = 0
        case 270: rot = 1
        default:  throw fail()
        }
        let base: UInt32 = 0x2e00_e400   // U=1, bits[28:24]=01110, bits[15:13]=111, bit10=1.
        let head = (rd.arrangement.q << 30) | base | (size << 22)
        return head | (rm.encodedNumber << 16) | (rot << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func complexMultiplyAdd(destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister, rotation: Int) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister("fcmla") }
        guard rd.arrangement == rn.arrangement, rn.arrangement == rm.arrangement,
              let size = complexSize(rd.arrangement) else { throw fail() }
        guard rotation % 90 == 0, (0...270).contains(rotation) else { throw fail() }
        let rot = UInt32(rotation / 90)
        let base: UInt32 = 0x2e00_c400   // U=1, bits[28:24]=01110, bits[15:13]=110, bit10=1.
        let head = (rd.arrangement.q << 30) | base | (size << 22)
        return head | (rm.encodedNumber << 16) | (rot << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func complexMultiplyAddByElement(destination rd: VectorRegister, first rn: VectorRegister, elementRegister: UInt32, index: UInt32, rotation: Int) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister("fcmla") }
        guard rd.arrangement == rn.arrangement else { throw fail() }
        guard rotation % 90 == 0, (0...270).contains(rotation) else { throw fail() }
        let rot = UInt32(rotation / 90)

        let size: UInt32
        let l: UInt32, m: UInt32, h: UInt32, rm: UInt32
        switch rd.arrangement {
        case .h4, .h8:
            // Half precision: index 0–3 as H:L, Vm restricted to V0–V15.
            guard elementRegister <= 15, index <= 3 else { throw fail() }
            size = 0b01
            l = index & 1
            h = (index >> 1) & 1
            m = 0
            rm = elementRegister & 0xf
        case .s2, .s4:
            // Single precision: index 0–1 as H, Vm is the full M:Rm register.
            guard elementRegister <= 31, index <= 1 else { throw fail() }
            size = 0b10
            l = 0
            h = index & 1
            m = (elementRegister >> 4) & 1
            rm = elementRegister & 0xf
        default:
            throw fail()
        }

        let base: UInt32 = 0x2f00_1000   // U=1, bits[28:24]=01111, bit12=1, bit10=0.
        let head = (rd.arrangement.q << 30) | base | (size << 22)
        return head | (l << 21) | (m << 20) | (rm << 16) | (rot << 13) | (h << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    // MARK: - FP16→FP32 widening multiply-accumulate (FMLAL / FMLSL)

    /// Maps the (dest, source) arrangement pair to the `Q` bit; the destination
    /// is `.2s`/`.4s` and the sources are the matching `.2h`/`.4h`.
    private static func fpMultiplyLongQ(destination rd: VectorRegister, first rn: VectorRegister) -> UInt32? {
        switch (rd.arrangement, rn.arrangement) {
        case (.s2, .h2): return 0
        case (.s4, .h4): return 1
        default:         return nil
        }
    }

    static func fpMultiplyLong(_ kind: A64.VectorFPMultiplyLongKind, destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        guard let q = fpMultiplyLongQ(destination: rd, first: rn), rn.arrangement == rm.arrangement else { throw fail() }
        // bits[28:24]=01110, bit21=1, bit10=1; opcode[15:11]=11101 (non-"2") or
        // 11001 ("2"); U=[29] and sz=[23] select the "2" and subtract forms.
        let opcode: UInt32 = kind.upper == 1 ? 0b11001 : 0b11101
        let base: UInt32 = 0x0e20_0400
        let head = (q << 30) | (kind.upper << 29) | base | (kind.sub << 23)
        return head | (rm.encodedNumber << 16) | (opcode << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func fpMultiplyLongByElement(_ kind: A64.VectorFPMultiplyLongKind, destination rd: VectorRegister, first rn: VectorRegister, elementRegister: UInt32, index: UInt32) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        guard let q = fpMultiplyLongQ(destination: rd, first: rn) else { throw fail() }
        // FP16 element: index 0–7 as H:L:M, Vm restricted to V0–V15.
        guard elementRegister <= 15, index <= 7 else { throw fail() }
        let m = index & 1
        let l = (index >> 1) & 1
        let h = (index >> 2) & 1
        let opcode: UInt32 = (kind.upper << 3) | (kind.sub << 2)
        let base: UInt32 = 0x0f80_0000   // bits[28:24]=01111, size[23:22]=10, bit10=0.
        let head = (q << 30) | (kind.upper << 29) | base
        return head | (l << 21) | (m << 20) | ((elementRegister & 0xf) << 16) | (opcode << 12) | (h << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    // MARK: - BFloat16 (FEAT_BF16)

    static func bfDot(destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister("bfdot") }
        // Vd.2s/4s, Vn/Vm.4h/8h.
        let q: UInt32
        switch (rd.arrangement, rn.arrangement) {
        case (.s2, .h4): q = 0
        case (.s4, .h8): q = 1
        default: throw fail()
        }
        guard rn.arrangement == rm.arrangement else { throw fail() }
        // U=1, bits[28:24]=01110, size=01, opcode[15:11]=11111, bit10=1.
        let base: UInt32 = 0x2e40_fc00
        return (q << 30) | base | (rm.encodedNumber << 16) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func bfDotByElement(destination rd: VectorRegister, first rn: VectorRegister, elementRegister: UInt32, index: UInt32) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister("bfdot") }
        let q: UInt32
        switch (rd.arrangement, rn.arrangement) {
        case (.s2, .h4): q = 0
        case (.s4, .h8): q = 1
        default: throw fail()
        }
        // Element is a BF16 pair `Vm.2h[index]`: index 0–3 as H:L, Vm = M:Rm (0–31).
        guard elementRegister <= 31, index <= 3 else { throw fail() }
        let l = index & 1
        let h = (index >> 1) & 1
        let m = (elementRegister >> 4) & 1
        let rmLow = elementRegister & 0xf
        // U=0, bits[28:24]=01111, size=01, opcode[15:12]=1111, bit10=0.
        let base: UInt32 = 0x0f40_f000
        return (q << 30) | base | (l << 21) | (m << 20) | (rmLow << 16) | (h << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func bfMultiplyLong(top: Bool, destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(top ? "bfmlalt" : "bfmlalb") }
        // Vd.4s, Vn/Vm.8h. The bottom/top selector occupies the Q bit.
        guard rd.arrangement == .s4, rn.arrangement == .h8, rm.arrangement == .h8 else { throw fail() }
        // U=1, bits[28:24]=01110, size=11, opcode[15:11]=11111, bit10=1.
        let base: UInt32 = 0x2ec0_fc00
        let qt: UInt32 = top ? 1 : 0
        return (qt << 30) | base | (rm.encodedNumber << 16) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func bfMultiplyLongByElement(top: Bool, destination rd: VectorRegister, first rn: VectorRegister, elementRegister: UInt32, index: UInt32) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(top ? "bfmlalt" : "bfmlalb") }
        guard rd.arrangement == .s4, rn.arrangement == .h8 else { throw fail() }
        // Element `Vm.h[index]`: index 0–7 as H:L:M, Vm restricted to V0–V15.
        guard elementRegister <= 15, index <= 7 else { throw fail() }
        let m = index & 1
        let l = (index >> 1) & 1
        let h = (index >> 2) & 1
        // U=0, bits[28:24]=01111, size=11, opcode[15:12]=1111, bit10=0.
        let base: UInt32 = 0x0fc0_f000
        let qt: UInt32 = top ? 1 : 0
        return (qt << 30) | base | (l << 21) | (m << 20) | ((elementRegister & 0xf) << 16) | (h << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func bfMatrixMultiply(destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister("bfmmla") }
        // Vd.4s, Vn/Vm.8h. Q, U, size are fixed.
        guard rd.arrangement == .s4, rn.arrangement == .h8, rm.arrangement == .h8 else { throw fail() }
        // Q=1, U=1, bits[28:24]=01110, size=01, opcode[15:11]=11101, bit10=1.
        let base: UInt32 = 0x6e40_ec00
        return base | (rm.encodedNumber << 16) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func bfConvertNarrow(top: Bool, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(top ? "bfcvtn2" : "bfcvtn") }
        // FP32→BF16 narrowing: Vn.4s → Vd.4h (bottom) / Vd.8h (top).
        guard rn.arrangement == .s4, rd.arrangement == (top ? .h8 : .h4) else { throw fail() }
        // Two-register-misc: bits[28:24]=01110, size=10 (bit23=1), bit21=1,
        // opcode[16:12]=10110, bits[11:10]=10; the Q bit selects bottom/top.
        let base: UInt32 = 0x0ea1_6800
        let q: UInt32 = top ? 1 : 0
        return (q << 30) | base | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func indexed(_ kind: A64.VectorIndexedKind, destination rd: VectorRegister, first rn: VectorRegister, element: A64.VectorElement) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // Validate the operand shapes per form, and fix the element width.
        switch spec.form {
        case .same:
            guard rd.arrangement == rn.arrangement,
                  [.h4, .h8, .s2, .s4].contains(rn.arrangement),
                  elementWidth(of: rn.arrangement) == element.width else { throw fail() }
        case .fp:
            guard rd.arrangement == rn.arrangement,
                  [.h4, .h8, .s2, .s4, .d2].contains(rn.arrangement),
                  elementWidth(of: rn.arrangement) == element.width else { throw fail() }
        case .long:
            guard [.h4, .h8, .s2, .s4].contains(rn.arrangement),
                  doubledArrangement(rn.arrangement) == rd.arrangement,
                  elementWidth(of: rn.arrangement) == element.width else { throw fail() }
        }

        let q = rn.arrangement.q

        // Element-width-specific encoding of `size`, the index bits, and `Vm`.
        let size: UInt32
        let l: UInt32, m: UInt32, h: UInt32, rm: UInt32
        switch element.width {
        case .h:
            guard element.number <= 15, element.index >= 0, element.index <= 7 else { throw fail() }
            size = 0b01
            let idx = UInt32(element.index)
            h = (idx >> 2) & 1
            l = (idx >> 1) & 1
            m = idx & 1
            rm = element.number & 0xf
        case .s:
            guard element.number <= 31, element.index >= 0, element.index <= 3 else { throw fail() }
            size = 0b10
            let idx = UInt32(element.index)
            h = (idx >> 1) & 1
            l = idx & 1
            m = (element.number >> 4) & 1
            rm = element.number & 0xf
        case .d:
            guard element.number <= 31, element.index >= 0, element.index <= 1 else { throw fail() }
            size = 0b11
            h = UInt32(element.index) & 1
            l = 0
            m = (element.number >> 4) & 1
            rm = element.number & 0xf
        case .b:
            throw fail()
        }

        // The FP16 by-element form (fmul/fmla/fmls/fmulx on `.4h`/`.8h`) uses
        // `size=00` (half precision), unlike the integer `.h` element which is
        // `size=01`. The index/Vm fields are identical to the `.h` case above.
        let encodedSize = (spec.form == .fp && element.width == .h) ? 0b00 : size

        let base: UInt32 = 0x0f00_0000
        let head = (q << 30) | (spec.u << 29) | base | (encodedSize << 22)
        return head | (l << 21) | (m << 20) | (rm << 16) | (spec.opcode << 12) | (h << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarThreeSame(_ kind: A64.ScalarThreeSameKind, destination rd: FloatRegister, first rn: FloatRegister, second rm: FloatRegister) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        guard rd.width == rn.width, rn.width == rm.width else { throw fail() }

        let size: UInt32
        switch spec.size {
        case .doubleOnly:
            guard rd.width == 64 else { throw fail() }
            size = 0b11
        case .halfSingle:
            switch rd.width {
            case 16: size = 0b01
            case 32: size = 0b10
            default: throw fail()
            }
        case .anySize:
            switch rd.width {
            case 8: size = 0b00
            case 16: size = 0b01
            case 32: size = 0b10
            case 64: size = 0b11
            default: throw fail()
            }
        }

        // Base: bit30=1, bits[28:24]=11110, bit21=1, bit10=1.
        let base: UInt32 = 0x5e20_0400
        return base | (spec.u << 29) | (size << 22) | (rm.encodedNumber << 16) | (spec.opcode << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarShiftImmediate(_ kind: A64.ScalarShiftImmediateKind, destination rd: FloatRegister, source rn: FloatRegister, shift: Int) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // Only the double-width (`d`) scalar forms are supported.
        guard rd.width == 64, rn.width == 64 else { throw fail() }

        let immhb: UInt32
        if spec.isLeft {
            guard shift >= 0, shift <= 63 else { throw fail() }
            immhb = UInt32(64 + shift)        // esize + shift
        } else {
            guard shift >= 1, shift <= 64 else { throw fail() }
            immhb = UInt32(128 - shift)       // 2*esize - shift
        }
        let immh = (immhb >> 3) & 0xf
        let immb = immhb & 0x7

        // Base: bit30=1, bits[28:23]=111110, bit10=1.
        let base: UInt32 = 0x5f00_0400
        return base | (spec.u << 29) | (immh << 19) | (immb << 16) | (spec.opcode << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarThreeSameFP(_ kind: A64.ScalarThreeSameFPKind, destination rd: FloatRegister, first rn: FloatRegister, second rm: FloatRegister) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        guard rd.width == rn.width, rn.width == rm.width else { throw fail() }

        // Half-precision (`h` registers) use a distinct encoding with a 3-bit
        // opcode field and bit23 carrying the `hi` selector.
        if rd.width == 16 {
            // Base: bits[31:30]=01, bits[28:24]=11110, bit22=1, bit21=0, bits[15:14]=00, bit10=1.
            let base: UInt32 = 0x5e40_0400
            return base | (spec.u << 29) | (spec.hi << 23) | (rm.encodedNumber << 16) | ((spec.opcode & 0b111) << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
        }

        let sz: UInt32
        switch rd.width {
        case 32: sz = 0
        case 64: sz = 1
        default: throw fail()
        }

        // Base: bit30=1, bits[28:24]=11110, bit21=1, bit10=1.
        let base: UInt32 = 0x5e20_0400
        return base | (spec.u << 29) | (spec.hi << 23) | (sz << 22) | (rm.encodedNumber << 16) | (spec.opcode << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarFPTwoRegisterMisc(_ kind: A64.ScalarFPTwoRegisterMiscKind, destination rd: FloatRegister, source rn: FloatRegister) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // Half-precision (`h` register) forms exist for the convert and
        // compare-against-#0.0 categories; `fcvtxn` (narrow) has no FP16 form.
        if rd.width == 16 {
            switch spec.category {
            case .convert, .compareZero:
                guard rn.width == 16 else { throw fail() }
                // Base: bit30=1, bits[28:24]=11110, bit22=1, bits[21:17]=11100, bits[11:10]=10.
                let base: UInt32 = 0x5e78_0800
                return base | (spec.u << 29) | (spec.hi << 23) | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
            case .narrow:
                throw fail()
            }
        }

        let sz: UInt32
        switch spec.category {
        case .convert, .compareZero:
            // Single (`s`, sz=0) or double (`d`, sz=1); both operands share the width.
            guard rd.width == rn.width else { throw fail() }
            switch rd.width {
            case 32: sz = 0
            case 64: sz = 1
            default: throw fail()
            }
        case .narrow:
            // fcvtxn: narrows a double source to a single destination.
            guard rd.width == 32, rn.width == 64 else { throw fail() }
            sz = 1
        }

        // Base: bit30=1, bits[28:24]=11110, bits[21:17]=10000, bits[11:10]=10.
        let base: UInt32 = 0x5e20_0800
        return base | (spec.u << 29) | (spec.hi << 23) | (sz << 22) | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarCopyDuplicate(destination rd: FloatRegister, element: A64.VectorElement) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister("dup") }

        // Scalar destination width must match the indexed element width.
        let size: UInt32
        let maxIndex: Int
        switch element.width {
        case .b: size = 0; maxIndex = 15; guard rd.width == 8  else { throw fail() }
        case .h: size = 1; maxIndex = 7;  guard rd.width == 16 else { throw fail() }
        case .s: size = 2; maxIndex = 3;  guard rd.width == 32 else { throw fail() }
        case .d: size = 3; maxIndex = 1;  guard rd.width == 64 else { throw fail() }
        }
        guard element.index >= 0, element.index <= maxIndex, element.number <= 31 else { throw fail() }

        // imm5 = index << (size + 1) | (1 << size).
        let imm5 = (UInt32(element.index) << (size + 1)) | (UInt32(1) << size)

        // Base: bit30=1, bits[28:21]=11110000, bit10=1 (DUP element: op=0, imm4=0000).
        let base: UInt32 = 0x5e00_0400
        return base | (imm5 << 16) | (element.number << 5) | rd.encodedNumber
    }

    static func scalarIndexed(_ kind: A64.VectorIndexedKind, destination rd: FloatRegister, first rn: FloatRegister, element: A64.VectorElement) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // Scalar element width (bits) implied by the indexed element.
        let elementBits: Int
        switch element.width {
        case .h: elementBits = 16
        case .s: elementBits = 32
        case .d: elementBits = 64
        case .b: throw fail()
        }

        // Validate scalar operand widths per form.
        switch spec.form {
        case .same:
            // sqdmulh / sqrdmulh: H or S only, all widths equal.
            guard elementBits == 16 || elementBits == 32,
                  rd.width == elementBits, rn.width == elementBits else { throw fail() }
        case .fp:
            // fmul / fmla / fmls / fmulx: H (FP16), S or D, all widths equal.
            guard elementBits == 16 || elementBits == 32 || elementBits == 64,
                  rd.width == elementBits, rn.width == elementBits else { throw fail() }
        case .long:
            // sqdmlal / sqdmlsl / sqdmull: H->S or S->D.
            guard elementBits == 16 || elementBits == 32,
                  rn.width == elementBits, rd.width == elementBits * 2 else { throw fail() }
        }

        // Element-width-specific encoding of `size`, the index bits, and `Vm`.
        let size: UInt32
        let l: UInt32, m: UInt32, h: UInt32, rm: UInt32
        switch element.width {
        case .h:
            guard element.number <= 15, element.index >= 0, element.index <= 7 else { throw fail() }
            size = 0b01
            let idx = UInt32(element.index)
            h = (idx >> 2) & 1
            l = (idx >> 1) & 1
            m = idx & 1
            rm = element.number & 0xf
        case .s:
            guard element.number <= 31, element.index >= 0, element.index <= 3 else { throw fail() }
            size = 0b10
            let idx = UInt32(element.index)
            h = (idx >> 1) & 1
            l = idx & 1
            m = (element.number >> 4) & 1
            rm = element.number & 0xf
        case .d:
            guard element.number <= 31, element.index >= 0, element.index <= 1 else { throw fail() }
            size = 0b11
            h = UInt32(element.index) & 1
            l = 0
            m = (element.number >> 4) & 1
            rm = element.number & 0xf
        case .b:
            throw fail()
        }

        // The FP16 scalar by-element form uses `size=00` (half precision),
        // unlike the integer `.h` element which is `size=01`.
        let encodedSize = (spec.form == .fp && element.width == .h) ? 0b00 : size

        // Base: bit30=1, bits[28:24]=11111.
        let base: UInt32 = 0x5f00_0000
        let head = (spec.u << 29) | base | (encodedSize << 22)
        return head | (l << 21) | (m << 20) | (rm << 16) | (spec.opcode << 12) | (h << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarTwoRegisterMiscNarrow(_ kind: A64.ScalarTwoRegisterMiscNarrowKind, destination rd: FloatRegister, source rn: FloatRegister) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // The destination is one element size narrower than the source.
        let size: UInt32
        switch (rd.width, rn.width) {
        case (8, 16):  size = 0b00   // h -> b
        case (16, 32): size = 0b01   // s -> h
        case (32, 64): size = 0b10   // d -> s
        default: throw fail()
        }

        // Base: bit30=1, bits[28:24]=11110, bits[21:17]=10000, bits[11:10]=10.
        let base: UInt32 = 0x5e20_0800
        return base | (spec.u << 29) | (size << 22) | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarShiftNarrow(_ kind: A64.ScalarShiftNarrowKind, destination rd: FloatRegister, source rn: FloatRegister, shift: Int) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // The destination is one element size narrower than the source.
        let destEsize: Int
        switch (rd.width, rn.width) {
        case (8, 16):  destEsize = 8
        case (16, 32): destEsize = 16
        case (32, 64): destEsize = 32
        default: throw fail()
        }
        guard shift >= 1, shift <= destEsize else { throw fail() }

        // immhb = 2*destEsize - shift; immh's highest set bit selects the size.
        let immhb = UInt32(2 * destEsize - shift)
        let immh = (immhb >> 3) & 0xf
        let immb = immhb & 0x7

        // Base: bit30=1, bits[28:23]=111110, bit10=1.
        let base: UInt32 = 0x5f00_0400
        return base | (spec.u << 29) | (immh << 19) | (immb << 16) | (spec.opcode << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarShiftFixedPoint(_ kind: A64.ScalarShiftFixedPointKind, destination rd: FloatRegister, source rn: FloatRegister, fbits: Int) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // Source and destination are the same scalar FP register width (S or D).
        guard rd.width == rn.width else { throw fail() }
        // immhb encodes the number of fractional bits; immh's highest set bit selects the size.
        // S (32-bit): immh = 01xx, immhb = 64 - fbits, fbits in 1...32.
        // D (64-bit): immh = 1xxx, immhb = 128 - fbits, fbits in 1...64.
        let immhb: UInt32
        switch rd.width {
        case 32:
            guard fbits >= 1, fbits <= 32 else { throw fail() }
            immhb = UInt32(64 - fbits)
        case 64:
            guard fbits >= 1, fbits <= 64 else { throw fail() }
            immhb = UInt32(128 - fbits)
        default:
            throw fail()
        }
        let immh = (immhb >> 3) & 0xf
        let immb = immhb & 0x7

        // Base: bit30=1, bits[28:23]=111110, bit10=1.
        let base: UInt32 = 0x5f00_0400
        return base | (spec.u << 29) | (immh << 19) | (immb << 16) | (spec.opcode << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarThreeDifferent(_ kind: A64.ScalarThreeDifferentKind, destination rd: FloatRegister, first rn: FloatRegister, second rm: FloatRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // Long, saturating-doubling: source elements are H or S, the result is one size up.
        let size: UInt32
        switch (rn.width, rm.width, rd.width) {
        case (16, 16, 32): size = 0b01    // h, h -> s
        case (32, 32, 64): size = 0b10    // s, s -> d
        default: throw fail()
        }

        // Base: bit30=1, bits[28:24]=11110, bit21=1, bits[11:10]=00.
        let base: UInt32 = 0x5e20_0000
        return base | (size << 22) | (rm.encodedNumber << 16) | (kind.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarTwoRegisterMisc(_ kind: A64.ScalarTwoRegisterMiscKind, destination rd: FloatRegister, source rn: FloatRegister) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        guard rd.width == rn.width else { throw fail() }

        let size: UInt32
        switch spec.size {
        case .doubleOnly:
            guard rd.width == 64 else { throw fail() }
            size = 0b11
        case .anySize:
            switch rd.width {
            case 8: size = 0b00
            case 16: size = 0b01
            case 32: size = 0b10
            case 64: size = 0b11
            default: throw fail()
            }
        }

        // Base: bit30=1, bits[28:24]=11110, bits[21:17]=10000, bits[11:10]=10.
        let base: UInt32 = 0x5e20_0800
        return base | (spec.u << 29) | (size << 22) | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func scalarPairwise(_ kind: A64.ScalarPairwiseKind, destination rd: FloatRegister, source rn: VectorRegister) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

        // Base: bit30=1, bits[28:24]=11110, bits[21:17]=11000, bits[11:10]=10.
        let base: UInt32 = 0x5e30_0800

        if spec.fp {
            // Half-precision form: `.2h` source reducing into a scalar `h`. This
            // variant clears U (the FP32/64 forms set it) and uses sz=0.
            if rn.arrangement == .h2 {
                guard rd.width == 16 else { throw fail() }
                return base | (spec.o1 << 23) | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
            }
            let sz: UInt32
            switch rn.arrangement {
            case .s2: guard rd.width == 32 else { throw fail() }; sz = 0
            case .d2: guard rd.width == 64 else { throw fail() }; sz = 1
            default: throw fail()
            }
            return base | (spec.u << 29) | (spec.o1 << 23) | (sz << 22) | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
        } else {
            // `addp` reduces a `2d` source into a scalar `d`.
            guard rn.arrangement == .d2, rd.width == 64 else { throw fail() }
            return base | (spec.u << 29) | (0b11 << 22) | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
        }
    }

    private static func lslAmount(_ shift: A64.VectorImmediateShift, allowed: [Int], kind: A64.VectorModifiedImmediateKind) throws -> Int {
        let amount: Int
        switch shift {
        case .none: amount = 0
        case .lsl(let value): amount = value
        case .msl: throw AssemblerError.invalidRegister(kind.rawValue)
        }
        guard allowed.contains(amount) else { throw AssemblerError.invalidRegister(kind.rawValue) }
        return amount
    }

    private static func isValidTwoRegisterMiscArrangement(_ kind: A64.VectorTwoRegisterMiscKind, _ arrangement: A64.VectorArrangement) -> Bool {
        switch kind {
        case .rev64, .cls, .clz:
            return [.b8, .b16, .h4, .h8, .s2, .s4].contains(arrangement)
        case .rev32:
            return [.b8, .b16, .h4, .h8].contains(arrangement)
        case .rev16, .cnt, .mvn, .rbit:
            return [.b8, .b16].contains(arrangement)
        case .abs, .neg, .sqabs, .sqneg, .suqadd, .usqadd:
            return [.b8, .b16, .h4, .h8, .s2, .s4, .d2].contains(arrangement)
        case .fabs, .fneg, .fsqrt:
            return [.h4, .h8, .s2, .s4, .d2].contains(arrangement)
        case .frint32z, .frint32x, .frint64z, .frint64x:
            return [.s2, .s4, .d2].contains(arrangement)
        }
    }

    /// Base for the "Advanced SIMD two-register miscellaneous (FP16)" encoding
    /// class: bits[28:24]=01110, [22]=1, [21:17]=11100, [11:10]=10. The `a` bit
    /// at [23] (which equals the regular form's high `size` bit) and the 5-bit
    /// `opcode` at [16:12] select the operation.
    static let fp16TwoRegisterMiscBase: UInt32 = 0x0e78_0800

    /// Arrangements permitted by the integer compare-against-zero forms.
    private static let allowedCompareZeroInteger: Set<A64.VectorArrangement> = [.b8, .b16, .h4, .h8, .s2, .s4, .d2]
    /// Arrangements permitted by the floating-point compare-against-zero forms.
    private static let allowedCompareZeroFloat: Set<A64.VectorArrangement> = [.h4, .h8, .s2, .s4, .d2]

    static func compareZero(_ kind: A64.VectorCompareZeroKind, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        guard rd.arrangement == rn.arrangement else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let allowed = kind.isFloat ? allowedCompareZeroFloat : allowedCompareZeroInteger
        guard allowed.contains(rd.arrangement) else { throw AssemblerError.invalidRegister(kind.rawValue) }

        let spec = kind.spec
        typealias F = A64.VectorTwoRegisterMisc
        let regs = F.q.insert(rd.arrangement.q) | F.u.insert(spec.u)
            | F.opcode.insert(spec.opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
        if kind.isFloat, rd.arrangement.elementWidth == 16 {
            // FP16 form: the compare-against-#0.0 opcodes live on the `a`=1 page.
            return fp16TwoRegisterMiscBase | regs | (1 << 23)
        }
        return F.baseWord | regs | F.size.insert(rd.arrangement.elementSize)
    }

    static func convert(_ kind: A64.VectorConvertKind, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        guard rd.arrangement == rn.arrangement else { throw AssemblerError.invalidRegister(kind.rawValue) }
        guard [A64.VectorArrangement.h4, .h8, .s2, .s4, .d2].contains(rd.arrangement) else { throw AssemblerError.invalidRegister(kind.rawValue) }

        let spec = kind.spec
        typealias F = A64.VectorTwoRegisterMisc
        let regs = F.q.insert(rd.arrangement.q) | F.u.insert(spec.u)
            | F.opcode.insert(spec.opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
        if rd.arrangement.elementWidth == 16 {
            // FP16 form: `a` (bit23) carries the high `size` bit selector.
            return fp16TwoRegisterMiscBase | regs | (spec.sizeHi << 23)
        }
        let sz: UInt32 = rd.arrangement.elementWidth == 64 ? 1 : 0
        return F.baseWord | regs | F.size.insert((spec.sizeHi << 1) | sz)
    }

    static func cryptoSHA3(_ kind: A64.CryptoSHA3Kind, d: UInt32, n: UInt32, m: UInt32) -> UInt32 {
        0x5e00_0000 | (m << 16) | (kind.opcode << 12) | (n << 5) | d
    }

    static func cryptoSHA2(_ kind: A64.CryptoSHA2Kind, d: UInt32, n: UInt32) -> UInt32 {
        0x5e28_0800 | (kind.opcode << 12) | (n << 5) | d
    }

    static func cryptoSHA512(_ kind: A64.CryptoSHA512Kind, d: UInt32, n: UInt32, m: UInt32) -> UInt32 {
        // Three-register SHA512: 11001110 011 Rm 1 0 00 opcode Rn Rd.
        0xce60_8000 | (m << 16) | (kind.opcode << 10) | (n << 5) | d
    }

    static func cryptoTwoReg(_ kind: A64.CryptoTwoRegKind, d: UInt32, n: UInt32) -> UInt32 {
        // Two-register SHA512/SM4: 11001110 110 00000 10 00 opcode Rn Rd.
        0xcec0_8000 | (kind.opcode << 10) | (n << 5) | d
    }

    static func cryptoSM3(_ kind: A64.CryptoSM3Kind, d: UInt32, n: UInt32, m: UInt32) -> UInt32 {
        // Three-register SM3/SM4: 11001110 011 Rm 1 1 00 opcode Rn Rd.
        0xce60_c000 | (m << 16) | (kind.opcode << 10) | (n << 5) | d
    }

    static func cryptoSM3Indexed(_ kind: A64.CryptoSM3IndexedKind, d: UInt32, n: UInt32, m: UInt32, index: UInt32) -> UInt32 {
        // Three-register SM3 "imm2": 11001110 010 Rm 1 0 imm2 opcode Rn Rd.
        0xce40_8000 | (m << 16) | (index << 12) | (kind.opcode << 10) | (n << 5) | d
    }

    static func cryptoSM3SS1(d: UInt32, n: UInt32, m: UInt32, a: UInt32) -> UInt32 {
        // Four-register SM3: 11001110 010 Rm 0 Ra Rn Rd.
        0xce40_0000 | (m << 16) | (a << 10) | (n << 5) | d
    }

    static func cryptoSHA3Four(_ kind: A64.CryptoSHA3FourKind, d: UInt32, n: UInt32, m: UInt32, a: UInt32) -> UInt32 {
        // Four-register SHA3: 11001110 0 Op0 Rm 0 Ra Rn Rd.
        0xce00_0000 | (kind.op0 << 21) | (m << 16) | (a << 10) | (n << 5) | d
    }

    static func cryptoRAX1(d: UInt32, n: UInt32, m: UInt32) -> UInt32 {
        // Three-register SHA3 RAX1: 11001110 011 Rm 1 0 0011 Rn Rd.
        0xce60_8c00 | (m << 16) | (n << 5) | d
    }

    static func cryptoXAR(d: UInt32, n: UInt32, m: UInt32, imm6: UInt32) throws -> UInt32 {
        // XAR: 11001110 100 Rm imm6 Rn Rd.
        guard imm6 <= 63 else { throw AssemblerError.invalidImmediate("xar") }
        return 0xce80_0000 | (m << 16) | (imm6 << 10) | (n << 5) | d
    }

    static func cryptoAES(_ kind: A64.CryptoAESKind, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        // Both operands are fixed `16b`.
        guard rd.arrangement == .b16, rn.arrangement == .b16 else { throw AssemblerError.invalidRegister(kind.rawValue) }
        return 0x4e28_0800 | (kind.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func fpConvertPrecision(_ kind: A64.VectorFPConvertPrecisionKind, upper: Bool, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        // Resolve `sz` (the [22] precision selector) from the destination/source
        // arrangement pair; reject any combination not defined for the mnemonic.
        let sz: UInt32
        switch kind {
        case .fcvtn:
            // f32→f16 (sz=0) or f64→f32 (sz=1); the `2` form keeps a 128-bit destination.
            switch (rn.arrangement, rd.arrangement) {
            case (.s4, .h4) where !upper: sz = 0
            case (.s4, .h8) where upper:  sz = 0
            case (.d2, .s2) where !upper: sz = 1
            case (.d2, .s4) where upper:  sz = 1
            default: throw fail()
            }
        case .fcvtl:
            // f16→f32 (sz=0) or f32→f64 (sz=1); the `2` form reads a 128-bit source.
            switch (rn.arrangement, rd.arrangement) {
            case (.h4, .s4) where !upper: sz = 0
            case (.h8, .s4) where upper:  sz = 0
            case (.s2, .d2) where !upper: sz = 1
            case (.s4, .d2) where upper:  sz = 1
            default: throw fail()
            }
        case .fcvtxn:
            // f64→f32 with round-to-odd; sz is always 1.
            switch (rn.arrangement, rd.arrangement) {
            case (.d2, .s2) where !upper: sz = 1
            case (.d2, .s4) where upper:  sz = 1
            default: throw fail()
            }
        }

        let spec = kind.spec
        let q: UInt32 = upper ? 1 : 0
        let head = (q << 30) | (spec.u << 29) | 0x0e20_0800 | (sz << 22)
        return head | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func roundReciprocal(_ kind: A64.VectorRoundReciprocalKind, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        guard rd.arrangement == rn.arrangement else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let allowed: [A64.VectorArrangement] = kind.allowsFP16
            ? (kind.allowsDouble ? [.h4, .h8, .s2, .s4, .d2] : [.h4, .h8, .s2, .s4])
            : (kind.allowsDouble ? [.s2, .s4, .d2] : [.s2, .s4])
        guard allowed.contains(rd.arrangement) else { throw AssemblerError.invalidRegister(kind.rawValue) }

        let spec = kind.spec
        typealias F = A64.VectorTwoRegisterMisc
        let regs = F.q.insert(rd.arrangement.q) | F.u.insert(spec.u)
            | F.opcode.insert(spec.opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
        if rd.arrangement.elementWidth == 16 {
            // FP16 form: `a` (bit23) carries the high `size` bit selector.
            return fp16TwoRegisterMiscBase | regs | (spec.sizeHi << 23)
        }
        let sz: UInt32 = rd.arrangement.elementWidth == 64 ? 1 : 0
        return F.baseWord | regs | F.size.insert((spec.sizeHi << 1) | sz)
    }

    static func extractNarrow(_ kind: A64.VectorExtractNarrowKind, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        // Destination is the narrow arrangement (`8b`/`16b`/`4h`/`8h`/`2s`/`4s`); the
        // source is the fully populated arrangement one element-size up.
        guard [A64.VectorArrangement.b8, .b16, .h4, .h8, .s2, .s4].contains(rd.arrangement) else { throw fail() }
        guard let expectedSource = doubledArrangement(rd.arrangement), rn.arrangement == expectedSource else { throw fail() }

        let spec = kind.spec
        typealias F = A64.VectorTwoRegisterMisc
        return F.baseWord | F.q.insert(rd.arrangement.q) | F.u.insert(spec.u) | F.size.insert(rd.arrangement.elementSize)
            | F.opcode.insert(spec.opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    /// Maps a source arrangement to the pairwise-long-add destination, which has
    /// the element width doubled but the same total width (`Q` preserved):
    /// `8b→4h`, `16b→8h`, `4h→2s`, `8h→4s`, `2s→1d`, `4s→2d`.
    private static func widenedArrangement(_ arrangement: A64.VectorArrangement) -> A64.VectorArrangement? {
        switch arrangement {
        case .b8: return .h4
        case .b16: return .h8
        case .h4: return .s2
        case .h8: return .s4
        case .s2: return .d1
        case .s4: return .d2
        case .h2, .d1, .d2, .q1: return nil
        }
    }

    static func pairwiseLongAdd(_ kind: A64.VectorPairwiseLongAddKind, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        // The source is `8b/16b/4h/8h/2s/4s`; the destination has the element width
        // doubled (same lane count halved, `Q` preserved).
        guard let expectedDestination = widenedArrangement(rn.arrangement), rd.arrangement == expectedDestination else { throw fail() }

        let spec = kind.spec
        typealias F = A64.VectorTwoRegisterMisc
        return F.baseWord | F.q.insert(rn.arrangement.q) | F.u.insert(spec.u) | F.size.insert(rn.arrangement.elementSize)
            | F.opcode.insert(spec.opcode) | F.rn.insert(rn.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }

    static func tableLookup(_ kind: A64.VectorTableLookupKind, destination rd: VectorRegister, table: A64.VectorRegisterList, index rm: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        // The destination and index share an 8b/16b arrangement; the table registers must be 16b.
        guard [A64.VectorArrangement.b8, .b16].contains(rd.arrangement), rd.arrangement == rm.arrangement else { throw fail() }
        guard table.arrangement == .b16, (1...4).contains(table.count) else { throw fail() }
        typealias F = A64.VectorTableLookup
        return F.baseWord | F.q.insert(rd.arrangement.q) | F.rm.insert(rm.encodedNumber)
            | F.len.insert(UInt32(table.count - 1)) | F.op.insert(kind.op) | F.rn.insert(table.encodedNumber) | F.rd.insert(rd.encodedNumber)
    }
}
