import Foundation

internal enum X86InstructionDecoder {
    /// One decoded instruction plus the number of bytes it consumed.
    /// x86 instructions are variable-length (1–15 bytes), so the decoder
    /// must report its progress to the caller's cursor.
    struct Decoded {
        var instruction: X86.Instruction
        var length: Int
    }

    /// Zero-operand kinds in *descending* length order. Longest-prefix-wins
    /// matching is required because several encodings share a leading byte
    /// with shorter ones (`F3 90 pause` vs `90 nop`, `66 CF iret` /
    /// `48 CF iretq` vs `CF iretd`, `48 0F 07 sysretq` vs `0F 07 sysret`).
    private static let zeroOperandTable: [X86.ZeroOperandKind] =
        X86.ZeroOperandKind.allCases.sorted { $0.bytes.count > $1.bytes.count }

    /// Decode a single instruction starting at `bytes[offset]`.
    ///
    /// Any byte sequence that does not match a known instruction raises
    /// `unknownEncoding` with the leading byte so the failure is locatable.
    static func decode(_ bytes: [UInt8], offset: Int) throws -> Decoded {
        guard offset < bytes.count else {
            throw AssemblerError.invalidByteCount(bytes.count)
        }

        if let match = matchZeroOperand(bytes, offset: offset) {
            return Decoded(instruction: .zeroOperand(match.kind), length: match.length)
        }

        throw AssemblerError.unknownEncoding(UInt32(bytes[offset]))
    }

    /// Try to match a zero-operand encoding at `bytes[offset...]`. Returns
    /// the matched kind and consumed length, or `nil` if nothing matches.
    private static func matchZeroOperand(_ bytes: [UInt8], offset: Int) -> (kind: X86.ZeroOperandKind, length: Int)? {
        for kind in zeroOperandTable {
            let pattern = kind.bytes
            guard offset + pattern.count <= bytes.count else { continue }
            var matches = true
            for (i, expected) in pattern.enumerated() where bytes[offset + i] != expected {
                matches = false
                break
            }
            if matches { return (kind, pattern.count) }
        }
        return nil
    }
}
