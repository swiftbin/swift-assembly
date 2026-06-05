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

    /// Common discriminator fields shared by the add/subtract families:
    /// `op` (add vs sub) and `s` (sets-flags). `sf` selects the operand width.
    enum AddSubImmediate {
        static let baseWord: UInt32 = 0x1100_0000
        /// Class bits [28:23]=100010 (bit23=0 excludes the min/max immediate space).
        static let classMask: UInt32 = 0x1f80_0000

        static let sf = BitField(offset: 31, width: 1)
        static let op = BitField(offset: 30, width: 1)
        static let s = BitField(offset: 29, width: 1)
        static let sh = BitField(offset: 22, width: 1)
        static let imm12 = BitField(offset: 10, width: 12)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Add/subtract (shifted register). `shift` is the shift type [23:22].
    enum AddSubShiftedRegister {
        static let baseWord: UInt32 = 0x0b00_0000
        static let classMask: UInt32 = 0x1f20_0000

        static let sf = BitField(offset: 31, width: 1)
        static let op = BitField(offset: 30, width: 1)
        static let s = BitField(offset: 29, width: 1)
        static let shift = BitField(offset: 22, width: 2)
        static let rm = BitField(offset: 16, width: 5)
        static let imm6 = BitField(offset: 10, width: 6)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Add/subtract (extended register). `option` is the extend [15:13];
    /// `imm3` the shift amount [12:10].
    enum AddSubExtendedRegister {
        static let baseWord: UInt32 = 0x0b20_0000
        static let classMask: UInt32 = 0x1fe0_0000

        static let sf = BitField(offset: 31, width: 1)
        static let op = BitField(offset: 30, width: 1)
        static let s = BitField(offset: 29, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let option = BitField(offset: 13, width: 3)
        static let imm3 = BitField(offset: 10, width: 3)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Logical (immediate): `AND`/`ORR`/`EOR`/`ANDS` with a bitmask immediate.
    /// `opc` selects the operation; `N`/`immr`/`imms` encode the bitmask.
    enum LogicalImmediate {
        static let baseWord: UInt32 = 0x1200_0000
        static let classMask: UInt32 = 0x1f80_0000

        static let sf = BitField(offset: 31, width: 1)
        static let opc = BitField(offset: 29, width: 2)
        static let n = BitField(offset: 22, width: 1)
        static let immr = BitField(offset: 16, width: 6)
        static let imms = BitField(offset: 10, width: 6)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Logical (shifted register): `AND`/`BIC`/`ORR`/`ORN`/`EOR`/`EON`/`ANDS`/
    /// `BICS`. `opc`+`N` select the operation; `shift`/`imm6` the shift.
    enum LogicalShiftedRegister {
        static let baseWord: UInt32 = 0x0a00_0000
        static let classMask: UInt32 = 0x1f00_0000

        static let sf = BitField(offset: 31, width: 1)
        static let opc = BitField(offset: 29, width: 2)
        static let shift = BitField(offset: 22, width: 2)
        static let n = BitField(offset: 21, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let imm6 = BitField(offset: 10, width: 6)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// FEAT_CSSC min/max (immediate): `SMAX`/`UMAX`/`SMIN`/`UMIN` with `#imm8`.
    /// `opc` selects the variant via `MinMaxKind.immediateOpc`.
    enum MinMaxImmediate {
        static let baseWord: UInt32 = 0x11c0_0000
        static let classMask: UInt32 = 0x7ff0_0000

        static let sf = BitField(offset: 31, width: 1)
        static let opc = BitField(offset: 18, width: 2)
        static let imm8 = BitField(offset: 10, width: 8)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// `RMIF` — rotate, mask, insert into NZCV.
    enum RMIF {
        static let baseWord: UInt32 = 0xba00_0400
        static let classMask: UInt32 = 0xffe0_7c10

        static let rotate = BitField(offset: 15, width: 6)
        static let rn = BitField(offset: 5, width: 5)
        static let mask = BitField(offset: 0, width: 4)
    }

    /// `SETF8`/`SETF16` — evaluate an 8/16-bit value into NZCV. `sz` selects
    /// the width.
    enum EvaluateIntoFlags {
        static let baseWord: UInt32 = 0x3a00_080d
        static let classMask: UInt32 = 0xffff_bc1f

        static let sz = BitField(offset: 14, width: 1)
        static let rn = BitField(offset: 5, width: 5)
    }

    /// `ADDG`/`SUBG` — add/subtract immediate with tag. `op` (bit30) selects
    /// subtract; `uimm6` is the offset/16; `uimm4` the tag.
    enum AddSubTag {
        static let baseWord: UInt32 = 0x9180_0000
        static let classMask: UInt32 = 0xbfc0_c000

        static let op = BitField(offset: 30, width: 1)
        static let uimm6 = BitField(offset: 16, width: 6)
        static let uimm4 = BitField(offset: 10, width: 4)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// PC-relative addressing: `ADR` (`op`=0) / `ADRP` (`op`=1). The 21-bit
    /// immediate is split into `immlo`[30:29] and `immhi`[23:5].
    enum PCRelativeAddressing {
        static let baseWord: UInt32 = 0x1000_0000
        /// Class bits [28:24]=10000 (the `op` bit at [31] is dispatched separately).
        static let classMask: UInt32 = 0x1f00_0000

        static let op = BitField(offset: 31, width: 1)
        static let immlo = BitField(offset: 29, width: 2)
        static let immhi = BitField(offset: 5, width: 19)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Unconditional branch (immediate): `B` (`op`=0) / `BL` (`op`=1).
    enum UnconditionalBranchImmediate {
        static let baseWord: UInt32 = 0x1400_0000
        /// Class bits [30:26]=00101 (the `op` bit at [31] is dispatched separately).
        static let classMask: UInt32 = 0x7c00_0000

        static let op = BitField(offset: 31, width: 1)
        static let imm26 = BitField(offset: 0, width: 26)
    }

    /// Conditional branch (immediate): `B.cond`. `cond` is at [3:0].
    enum ConditionalBranchImmediate {
        static let baseWord: UInt32 = 0x5400_0000
        static let classMask: UInt32 = 0xff00_0010

        static let imm19 = BitField(offset: 5, width: 19)
        static let cond = BitField(offset: 0, width: 4)
    }

    /// Compare and branch: `CBZ` (`op`=0) / `CBNZ` (`op`=1). `sf` selects width.
    enum CompareAndBranch {
        static let baseWord: UInt32 = 0x3400_0000
        static let classMask: UInt32 = 0x7e00_0000

        static let sf = BitField(offset: 31, width: 1)
        static let op = BitField(offset: 24, width: 1)
        static let imm19 = BitField(offset: 5, width: 19)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// Test and branch: `TBZ` (`op`=0) / `TBNZ` (`op`=1). The tested bit number
    /// is `b5`[31] (high bit) and `b40`[23:19].
    enum TestAndBranch {
        static let baseWord: UInt32 = 0x3600_0000
        static let classMask: UInt32 = 0x7e00_0000

        static let b5 = BitField(offset: 31, width: 1)
        static let op = BitField(offset: 24, width: 1)
        static let b40 = BitField(offset: 19, width: 5)
        static let imm14 = BitField(offset: 5, width: 14)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// `MRS`/`MSR` (register). `l` selects read (MRS); `o0`/`op1`/`crn`/`crm`/
    /// `op2` identify the system register.
    enum SystemRegisterMove {
        static let baseWord: UInt32 = 0xd510_0000
        static let classMask: UInt32 = 0xffd0_0000

        static let l = BitField(offset: 21, width: 1)
        static let o0 = BitField(offset: 19, width: 1)
        static let op1 = BitField(offset: 16, width: 3)
        static let crn = BitField(offset: 12, width: 4)
        static let crm = BitField(offset: 8, width: 4)
        static let op2 = BitField(offset: 5, width: 3)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// `SYS`/`SYSL`. `l` selects SYSL (read).
    enum SystemInstruction {
        static let baseWord: UInt32 = 0xd508_0000
        static let classMask: UInt32 = 0xffd8_0000

        static let l = BitField(offset: 21, width: 1)
        static let op1 = BitField(offset: 16, width: 3)
        static let crn = BitField(offset: 12, width: 4)
        static let crm = BitField(offset: 8, width: 4)
        static let op2 = BitField(offset: 5, width: 3)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// `MSR` (immediate) — write a PSTATE field. `crm` carries the immediate.
    enum PStateImmediate {
        static let baseWord: UInt32 = 0xd500_401f
        static let classMask: UInt32 = 0xfff8_f01f

        static let op1 = BitField(offset: 16, width: 3)
        static let crm = BitField(offset: 8, width: 4)
        static let op2 = BitField(offset: 5, width: 3)
    }

    /// `CLREX` — clear exclusive monitor. `crm` carries the (usually 0xf) imm.
    enum ClearExclusive {
        static let baseWord: UInt32 = 0xd503_305f
        static let classMask: UInt32 = 0xffff_f0ff

        static let crm = BitField(offset: 8, width: 4)
    }

    /// `WFET`/`WFIT` — wait for event/interrupt with timeout. `op2` (bit5)
    /// selects WFIT.
    enum WaitWithTimeout {
        static let baseWord: UInt32 = 0xd503_1000
        static let classMask: UInt32 = 0xffff_ffc0

        static let op2 = BitField(offset: 5, width: 1)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// `HINT` space — the 7-bit CRm:op2 immediate at [11:5] selects the hint
    /// (`#0` is NOP).
    enum Hint {
        static let baseWord: UInt32 = 0xd503_201f
        static let classMask: UInt32 = 0xffff_f01f

        static let imm = BitField(offset: 5, width: 7)
    }

    /// `UDF` — permanently undefined; `imm16` at [15:0].
    enum PermanentlyUndefined {
        static let baseWord: UInt32 = 0x0000_0000
        static let classMask: UInt32 = 0xffff_0000

        static let imm16 = BitField(offset: 0, width: 16)
    }

    /// Load/store exclusive (`LDXR`/`STXR`/`LDAXP`/...). `size`/`o2`/`l`/`o1`/
    /// `o0` form the discriminator (carried by `LoadStoreExclusiveKind`).
    enum LoadStoreExclusive {
        static let baseWord: UInt32 = 0x0800_0000
        static let classMask: UInt32 = 0x3f00_0000

        static let size = BitField(offset: 30, width: 2)
        static let o2 = BitField(offset: 23, width: 1)
        static let l = BitField(offset: 22, width: 1)
        static let o1 = BitField(offset: 21, width: 1)
        static let rs = BitField(offset: 16, width: 5)
        static let o0 = BitField(offset: 15, width: 1)
        static let rt2 = BitField(offset: 10, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// Atomic memory operations (`LDADD`/`SWP`/...). `a`/`r` are acquire/release;
    /// `o3`/`opc` select the operation.
    enum AtomicMemory {
        static let baseWord: UInt32 = 0x3820_0000
        static let classMask: UInt32 = 0x3f20_0c00

        static let size = BitField(offset: 30, width: 2)
        static let a = BitField(offset: 23, width: 1)
        static let r = BitField(offset: 22, width: 1)
        static let rs = BitField(offset: 16, width: 5)
        static let o3 = BitField(offset: 15, width: 1)
        static let opc = BitField(offset: 12, width: 3)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// Load-acquire RCpc register (`LDAPR`/`LDAPRH`/`LDAPRB`). `size` selects
    /// the access width.
    enum LoadAcquireRCpc {
        static let baseWord: UInt32 = 0x38bf_c000
        static let classMask: UInt32 = 0x3fff_fc00

        static let size = BitField(offset: 30, width: 2)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }
}
