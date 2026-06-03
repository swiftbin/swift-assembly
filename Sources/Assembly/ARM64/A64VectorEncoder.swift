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

        let head: UInt32 = (rn.arrangement.q << 30) | (u << 29) | 0x0e30_0800 | (rn.arrangement.elementSize << 22)
        return head | (opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func acrossLanesFP(_ kind: A64.AcrossLanesFPKind, destination rd: FloatRegister, source rn: VectorRegister) throws -> UInt32 {
        // Only the single-precision `.4s` form (sz=0) is supported; `.8h` (FP16) is out of scope.
        guard rn.arrangement == .s4, rd.width == 32 else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }

        let o1: UInt32
        let opcode: UInt32
        switch kind {
        case .fmaxv: o1 = 0; opcode = 0b01111
        case .fminv: o1 = 1; opcode = 0b01111
        case .fmaxnmv: o1 = 0; opcode = 0b01100
        case .fminnmv: o1 = 1; opcode = 0b01100
        }

        let head: UInt32 = 0x6e30_0800 | (o1 << 23)
        return head | (opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
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
        case .abs: u = 0; opcode = 0b01011
        case .neg: u = 1; opcode = 0b01011
        case .fabs: u = 0; opcode = 0b01111
        case .fneg: u = 1; opcode = 0b01111
        case .fsqrt: u = 1; opcode = 0b11111
        }

        let size = kind == .rbit ? UInt32(0b01) : rn.arrangement.elementSize
        let head = (rn.arrangement.q << 30) | (u << 29) | 0x0e20_0800 | (size << 22)
        return head | (opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
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
        // Base: bits[28:24]=01110, bit21=1, bit10=1.
        let base: UInt32 = 0x0e20_0400
        let registers = (rm.encodedNumber << 16) | (rn.encodedNumber << 5) | rd.encodedNumber

        switch spec.family {
        case .integer:
            let head = (arrangement.q << 30) | (spec.u << 29) | base | (arrangement.elementSize << 22)
            return head | (spec.opcode << 11) | registers
        case .logical:
            // The element-`size` field carries the operation selector.
            let head = (arrangement.q << 30) | (spec.u << 29) | base | (spec.variant << 22)
            return head | (spec.opcode << 11) | registers
        case .floatingPoint:
            // `a` selects the operation sub-group at bit23; `sz` (bit22) is 0 for
            // single precision (`.2s`/`.4s`) and 1 for double precision (`.2d`).
            let sz: UInt32 = arrangement.elementWidth == 64 ? 1 : 0
            let head = (arrangement.q << 30) | (spec.u << 29) | base | (spec.variant << 23) | (sz << 22)
            return head | (spec.opcode << 11) | registers
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
        case .d1, .d2: return nil
        }
    }

    static func shiftImmediate(_ kind: A64.VectorShiftImmediateKind, destination rd: VectorRegister, source rn: VectorRegister, shift: Int) throws -> UInt32 {
        let spec = kind.spec
        let base: UInt32 = 0x0f00_0400

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

        let immh = immhimmb >> 3
        let immb = immhimmb & 0b111
        let head = (q << 30) | (spec.u << 29) | base | (immh << 19) | (immb << 16)
        return head | (spec.opcode << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
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
        // Base: bits[29:24]=001110, bits[11:10]=10.
        let base: UInt32 = 0x0e00_0800
        let head = (arrangement.q << 30) | base | (arrangement.elementSize << 22)
        return head | (rm.encodedNumber << 16) | (kind.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
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
        // Base: bits[29:24]=101110.
        let base: UInt32 = 0x2e00_0000
        let head = (arrangement.q << 30) | base
        return head | (rm.encodedNumber << 16) | (UInt32(index) << 11) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    // MARK: - Three different (long / wide / narrow)

    static func threeDifferent(_ kind: A64.VectorThreeDifferentKind, destination rd: VectorRegister, first rn: VectorRegister, second rm: VectorRegister) throws -> UInt32 {
        let spec = kind.spec
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }

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

        let base: UInt32 = 0x0e20_0000
        let head = (narrow.q << 30) | (spec.u << 29) | base | (size << 22)
        return head | (rm.encodedNumber << 16) | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
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
                  [.s2, .s4, .d2].contains(rn.arrangement),
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

        let base: UInt32 = 0x0f00_0000
        let head = (q << 30) | (spec.u << 29) | base | (size << 22)
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
            // fmul / fmla / fmls / fmulx: S or D, all widths equal.
            guard elementBits == 32 || elementBits == 64,
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

        // Base: bit30=1, bits[28:24]=11111.
        let base: UInt32 = 0x5f00_0000
        let head = (spec.u << 29) | base | (size << 22)
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
        case .abs, .neg, .sqabs, .sqneg:
            return [.b8, .b16, .h4, .h8, .s2, .s4, .d2].contains(arrangement)
        case .fabs, .fneg, .fsqrt:
            return [.s2, .s4, .d2].contains(arrangement)
        }
    }

    /// Arrangements permitted by the integer compare-against-zero forms.
    private static let allowedCompareZeroInteger: Set<A64.VectorArrangement> = [.b8, .b16, .h4, .h8, .s2, .s4, .d2]
    /// Arrangements permitted by the floating-point compare-against-zero forms.
    private static let allowedCompareZeroFloat: Set<A64.VectorArrangement> = [.s2, .s4, .d2]

    static func compareZero(_ kind: A64.VectorCompareZeroKind, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        guard rd.arrangement == rn.arrangement else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let allowed = kind.isFloat ? allowedCompareZeroFloat : allowedCompareZeroInteger
        guard allowed.contains(rd.arrangement) else { throw AssemblerError.invalidRegister(kind.rawValue) }

        let spec = kind.spec
        let size = rd.arrangement.elementSize
        let head = (rd.arrangement.q << 30) | (spec.u << 29) | 0x0e20_0800 | (size << 22)
        return head | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func convert(_ kind: A64.VectorConvertKind, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        guard rd.arrangement == rn.arrangement else { throw AssemblerError.invalidRegister(kind.rawValue) }
        guard [A64.VectorArrangement.s2, .s4, .d2].contains(rd.arrangement) else { throw AssemblerError.invalidRegister(kind.rawValue) }

        let spec = kind.spec
        let sz: UInt32 = rd.arrangement.elementWidth == 64 ? 1 : 0
        let size = (spec.sizeHi << 1) | sz
        let head = (rd.arrangement.q << 30) | (spec.u << 29) | 0x0e20_0800 | (size << 22)
        return head | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func extractNarrow(_ kind: A64.VectorExtractNarrowKind, destination rd: VectorRegister, source rn: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        // Destination is the narrow arrangement (`8b`/`16b`/`4h`/`8h`/`2s`/`4s`); the
        // source is the fully populated arrangement one element-size up.
        guard [A64.VectorArrangement.b8, .b16, .h4, .h8, .s2, .s4].contains(rd.arrangement) else { throw fail() }
        guard let expectedSource = doubledArrangement(rd.arrangement), rn.arrangement == expectedSource else { throw fail() }

        let spec = kind.spec
        let size = rd.arrangement.elementSize
        let head = (rd.arrangement.q << 30) | (spec.u << 29) | 0x0e20_0800 | (size << 22)
        return head | (spec.opcode << 12) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func tableLookup(_ kind: A64.VectorTableLookupKind, destination rd: VectorRegister, table: A64.VectorRegisterList, index rm: VectorRegister) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        // The destination and index share an 8b/16b arrangement; the table registers must be 16b.
        guard [A64.VectorArrangement.b8, .b16].contains(rd.arrangement), rd.arrangement == rm.arrangement else { throw fail() }
        guard table.arrangement == .b16, (1...4).contains(table.count) else { throw fail() }
        let q = rd.arrangement.q
        let len = UInt32(table.count - 1)
        return 0x0e00_0000 | (q << 30) | (rm.encodedNumber << 16) | (len << 13) | (kind.op << 12) | (table.encodedNumber << 5) | rd.encodedNumber
    }
}
