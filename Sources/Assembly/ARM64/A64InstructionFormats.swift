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

    /// Byte-level format descriptor for the conditional-select class
    /// (`CSEL`/`CSINC`/`CSINV`/`CSNEG` and the cset/cinc/... aliases).
    /// The concrete instruction is selected by `op`/`o2` via
    /// `ConditionalSelectKind`.
    enum ConditionalSelect {
        static let baseWord: UInt32 = 0x1a80_0000
        static let classMask: UInt32 = 0x3fe0_0800

        static let sf = BitField(offset: 31, width: 1)
        static let op = BitField(offset: 30, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let cond = BitField(offset: 12, width: 4)
        static let o2 = BitField(offset: 10, width: 1)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Byte-level format descriptor for the conditional-compare class
    /// (`CCMN`/`CCMP`, register and immediate forms). `op` selects ccmn/ccmp;
    /// `immFlag` selects the immediate form.
    enum ConditionalCompare {
        static let baseWord: UInt32 = 0x3a40_0000
        static let classMask: UInt32 = 0x3fe0_0410

        static let sf = BitField(offset: 31, width: 1)
        static let op = BitField(offset: 30, width: 1)
        /// Rm (register form) or imm5 (immediate form), both at [20:16].
        static let imm5OrRm = BitField(offset: 16, width: 5)
        static let cond = BitField(offset: 12, width: 4)
        static let immFlag = BitField(offset: 11, width: 1)
        static let rn = BitField(offset: 5, width: 5)
        static let nzcv = BitField(offset: 0, width: 4)
    }

    /// Byte-level format descriptor for the data-processing (3-source) class:
    /// `MADD`/`MSUB` (op31=000) and the wide `SMADDL`/`UMULH`/... multiplies
    /// (op31 ≠ 000). `op31`/`o0` select the variant; `Ra` is the accumulator.
    enum DataProcessing3Source {
        static let baseWord: UInt32 = 0x1b00_0000
        /// Class bits [30:24]=0011011 (op31/o0/registers excluded).
        static let classMask: UInt32 = 0x7f00_0000

        static let sf = BitField(offset: 31, width: 1)
        static let op31 = BitField(offset: 21, width: 3)
        static let rm = BitField(offset: 16, width: 5)
        static let o0 = BitField(offset: 15, width: 1)
        static let ra = BitField(offset: 10, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Byte-level format descriptor for add/subtract with carry
    /// (`ADC`/`ADCS`/`SBC`/`SBCS`). `op`/`s` select the variant via
    /// `AddSubCarryKind`.
    enum AddSubWithCarry {
        static let baseWord: UInt32 = 0x1a00_0000
        static let classMask: UInt32 = 0x1fe0_fc00

        static let sf = BitField(offset: 31, width: 1)
        static let op = BitField(offset: 30, width: 1)
        static let s = BitField(offset: 29, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Byte-level format descriptor for the bitfield class
    /// (`SBFM`/`BFM`/`UBFM` and their many aliases). `opc` selects the variant;
    /// `N` mirrors `sf`.
    enum Bitfield {
        static let baseWord: UInt32 = 0x1300_0000
        /// Class bits [28:23]=100110 (sf/opc/N/immr/imms/registers excluded).
        static let classMask: UInt32 = 0x1f80_0000

        static let sf = BitField(offset: 31, width: 1)
        static let opc = BitField(offset: 29, width: 2)
        static let n = BitField(offset: 22, width: 1)
        static let immr = BitField(offset: 16, width: 6)
        static let imms = BitField(offset: 10, width: 6)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Byte-level format descriptor for the extract class (`EXTR`, and the
    /// `ROR` immediate alias). `N` mirrors `sf`; `imms` carries the rotate.
    enum Extract {
        static let baseWord: UInt32 = 0x1380_0000
        static let classMask: UInt32 = 0x7fa0_0000

        static let sf = BitField(offset: 31, width: 1)
        static let n = BitField(offset: 22, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let imms = BitField(offset: 10, width: 6)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Byte-level format descriptor for the move-wide-immediate class
    /// (`MOVN`/`MOVZ`/`MOVK`). `opc` selects the variant via `MoveWideKind`;
    /// `hw` is the shift/16.
    enum MoveWide {
        static let baseWord: UInt32 = 0x1280_0000
        static let classMask: UInt32 = 0x1f80_0000

        static let sf = BitField(offset: 31, width: 1)
        static let opc = BitField(offset: 29, width: 2)
        static let hw = BitField(offset: 21, width: 2)
        static let imm16 = BitField(offset: 5, width: 16)
        static let rd = BitField(offset: 0, width: 5)
    }
}
