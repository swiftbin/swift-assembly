import Foundation

extension A64 {
    /// A contiguous run of bits within a 32-bit A64 instruction word.
    ///
    /// Shared building block for byte-level format descriptors: a field is
    /// described once (its position and width) and used by both the encoder
    /// (`insert`) and the decoder (`extract`), so the two sides cannot drift.
    struct BitField {
        let offset: Int
        let width: Int

        private var fieldMask: UInt32 { (UInt32(1) << UInt32(width)) - 1 }

        /// The field's bits in their final position within the word.
        var mask: UInt32 { fieldMask << UInt32(offset) }

        /// Place a field value into a word (the value is truncated to `width`).
        func insert(_ value: UInt32) -> UInt32 { (value & fieldMask) << UInt32(offset) }

        /// Extract a field value from a word (zero-extended).
        func extract(_ word: UInt32) -> UInt32 { (word >> UInt32(offset)) & fieldMask }
    }

    /// Byte-level format descriptor for the data-processing (2-source, register)
    /// class. The single source of truth for the fixed opcode bits and the
    /// field layout shared by `LSLV`/`LSRV`/`ASRV`/`RORV`, the register form of
    /// `SMAX`/`SMIN`/`UMAX`/`UMIN`, and the `CRC32*` family.
    ///
    /// This is the *byte* layer. The *model* layer (which concrete instruction
    /// a word is) is carried by the per-instruction `opcode` field, which each
    /// `Kind` already provides (e.g. `VariableShiftKind.opcode`). Both the
    /// encoder and the decoder reference this descriptor.
    enum DataProcessing2Source {
        /// Fixed bits: `sf 0 0 11010110 ...` with `Rm`/`opcode`/`Rn`/`Rd` clear.
        static let baseWord: UInt32 = 0x1ac0_0000

        /// Bits identifying the class for decode: `op[30]`, `S[29]` and
        /// `[28:21]`. Excludes `sf`, the `opcode` field and the registers, so
        /// the concrete instruction is selected by decoding `opcode`.
        static let classMask: UInt32 = 0x7fe0_0000

        static let sf = BitField(offset: 31, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let opcode = BitField(offset: 10, width: 6)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Byte-level format descriptor for the data-processing (1-source) class
    /// (`RBIT`/`REV*`/`CLZ`/`CLS`, and the FEAT_CSSC `CTZ`/`CNT`/`ABS`).
    /// The concrete instruction is selected by the `opcode` field, carried by
    /// `DataProcessingOneSourceKind`.
    enum DataProcessing1Source {
        /// Fixed bits: `sf 1 0 11010110 00000 ...` (includes `opcode2[20:16]=0`).
        static let baseWord: UInt32 = 0x5ac0_0000
        static let classMask: UInt32 = 0x7fff_0000

        static let sf = BitField(offset: 31, width: 1)
        static let opcode = BitField(offset: 10, width: 6)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }
}
