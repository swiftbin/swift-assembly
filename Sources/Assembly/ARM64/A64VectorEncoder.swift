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
}
