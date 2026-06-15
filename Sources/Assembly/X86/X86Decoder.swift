import Foundation

internal enum X86InstructionDecoder {
    /// One decoded instruction plus the number of bytes it consumed.
    /// x86 instructions are variable-length (1–15 bytes), so the decoder
    /// must report its progress to the caller's cursor.
    struct Decoded {
        var instruction: X86.Instruction
        var length: Int
    }

    /// Decode a single instruction starting at `bytes[offset]`.
    ///
    /// Phase 0 only recognises `0x90` (`nop`). Any other leading byte raises
    /// `unknownEncoding` so that the pipeline reports the failure with the
    /// offending byte. Subsequent phases will branch on prefixes (REX, 66,
    /// 67, F2/F3, ...) and then on the primary opcode byte(s).
    static func decode(_ bytes: [UInt8], offset: Int) throws -> Decoded {
        guard offset < bytes.count else {
            throw AssemblerError.invalidByteCount(bytes.count)
        }

        let byte = bytes[offset]
        switch byte {
        case 0x90:
            return Decoded(instruction: .nop, length: 1)
        default:
            throw AssemblerError.unknownEncoding(UInt32(byte))
        }
    }
}
