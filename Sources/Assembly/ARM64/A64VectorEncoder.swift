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
}
