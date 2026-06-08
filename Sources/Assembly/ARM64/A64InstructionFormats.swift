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

    /// Load/store register pair (`LDP`/`STP`/`LDNP`/`STNP`/`LDPSW`). `opc`
    /// selects width/signedness; `mode`[24:23] selects the addressing form;
    /// `l` selects load.
    enum LoadStorePair {
        static let baseWord: UInt32 = 0x2800_0000
        static let classMask: UInt32 = 0x3e00_0000

        static let opc = BitField(offset: 30, width: 2)
        /// `V`[26] selects the SIMD&FP register file (the integer forms use 0).
        static let v = BitField(offset: 26, width: 1)
        static let mode = BitField(offset: 23, width: 2)
        static let l = BitField(offset: 22, width: 1)
        static let imm7 = BitField(offset: 15, width: 7)
        static let rt2 = BitField(offset: 10, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// Load/store unprivileged (`LDTR`/`STTR`/...). `size`/`opc` select the
    /// variant; `imm9` is the signed unscaled offset.
    enum LoadStoreUnprivileged {
        static let baseWord: UInt32 = 0x3800_0800
        static let classMask: UInt32 = 0x3f20_0c00

        static let size = BitField(offset: 30, width: 2)
        static let opc = BitField(offset: 22, width: 2)
        static let imm9 = BitField(offset: 12, width: 9)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// RCpc unscaled (`LDAPUR`/`STLUR`/...). `size`/`opc` select the variant;
    /// `imm9` is the signed unscaled offset.
    enum RCpcUnscaledImmediate {
        static let baseWord: UInt32 = 0x1900_0000
        static let classMask: UInt32 = 0x3f20_0c00

        static let size = BitField(offset: 30, width: 2)
        static let opc = BitField(offset: 22, width: 2)
        static let imm9 = BitField(offset: 12, width: 9)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// Advanced SIMD two-register misc (`REV*`/`CNT`/`ABS`/`FABS`/...).
    /// `q`/`u`/`size`/`opcode`[16:12] select; the main (non-FP16) page uses base
    /// `0x0e20_0800`.
    enum VectorTwoRegisterMisc {
        static let baseWord: UInt32 = 0x0e20_0800
        static let classMask: UInt32 = 0x9f20_0c00

        static let q = BitField(offset: 30, width: 1)
        static let u = BitField(offset: 29, width: 1)
        static let size = BitField(offset: 22, width: 2)
        static let opcode = BitField(offset: 12, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Advanced SIMD across-lanes (`ADDV`/`SMAXV`/`FMAXV`/...). `opcode`[16:12].
    enum VectorAcrossLanes {
        static let baseWord: UInt32 = 0x0e30_0800
        static let classMask: UInt32 = 0x9f3e_0c00

        static let q = BitField(offset: 30, width: 1)
        static let u = BitField(offset: 29, width: 1)
        static let size = BitField(offset: 22, width: 2)
        static let opcode = BitField(offset: 12, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Base words for the remaining one-off Advanced SIMD classes (each used by
    /// a single instruction group). Centralized here so the encoder and decoder
    /// reference the same constant instead of duplicating the literal.
    enum AdvSIMD {
        static let vectorImmediate: UInt32 = 0x0f00_0000          // modified-immediate / by-element indexed
        static let dotProduct: UInt32 = 0x0e80_9400
        static let dotProductByElement: UInt32 = 0x0f80_e000
        static let matrixMultiply: UInt32 = 0x4e80_a400
        static let threeSameExtra: UInt32 = 0x0e00_8400
        static let scalarThreeSameExtra: UInt32 = 0x5e00_8400
        static let complexAdd: UInt32 = 0x2e00_e400
        static let complexMultiplyAdd: UInt32 = 0x2e00_c400
        static let complexMultiplyAddByElement: UInt32 = 0x2f00_1000
        static let fpMultiplyLongByElement: UInt32 = 0x0f80_0000
        static let bfDot: UInt32 = 0x2e40_fc00
        static let bfDotByElement: UInt32 = 0x0f40_f000
        static let bfMultiplyLong: UInt32 = 0x2ec0_fc00
        static let bfMultiplyLongByElement: UInt32 = 0x0fc0_f000
        static let bfMatrixMultiply: UInt32 = 0x6e40_ec00
        static let bfConvertNarrow: UInt32 = 0x0ea1_6800
        static let scalarShift: UInt32 = 0x5f00_0400              // scalar shift immediate/narrow/fixed-point
        static let scalarThreeSameFP16: UInt32 = 0x5e40_0400
        static let scalarFPTwoRegisterMiscFP16: UInt32 = 0x5e78_0800
        static let scalarCopy: UInt32 = 0x5e00_0400
        static let scalarIndexed: UInt32 = 0x5f00_0000
        static let threeSameFP16: UInt32 = 0x0e40_0400
        static let usDotProduct: UInt32 = 0x0e80_9c00
        static let mixedDotByElement: UInt32 = 0x0f00_f000
    }

    /// Pointer-authentication data-processing base words. `PACGA` is a
    /// data-processing (2-source) form; the `PAC*`/`AUT*` data forms are
    /// data-processing (1-source) with the key/op in the `opcode` field.
    enum PointerAuthData {
        static let pacga: UInt32 = 0x9ac0_3000
        static let dataBase: UInt32 = 0xdac1_0000
    }

    /// Scalar Advanced SIMD instructions. Like the vector forms but with
    /// scalar operands; the classes share the register fields and each has its
    /// own base word. `opcode`/`size` positions differ per class (kept at the
    /// call sites).
    enum ScalarAdvSIMD {
        static let rd = BitField(offset: 0, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rm = BitField(offset: 16, width: 5)
        static let u = BitField(offset: 29, width: 1)
        static let size = BitField(offset: 22, width: 2)

        static let threeSameBase: UInt32 = 0x5e20_0400
        static let threeDifferentBase: UInt32 = 0x5e20_0000
        static let twoRegisterMiscBase: UInt32 = 0x5e20_0800
        static let pairwiseBase: UInt32 = 0x5e30_0800
    }

    /// Cryptographic extension instructions. The classes share the register
    /// fields (`Rd`/`Rn`/`Rm`/`Ra`) but each has its own base word; opcode/imm
    /// positions differ per class and stay at their call sites.
    enum Crypto {
        static let rd = BitField(offset: 0, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let ra = BitField(offset: 10, width: 5)
        static let rm = BitField(offset: 16, width: 5)

        static let sha3Base: UInt32 = 0x5e00_0000        // three-register SHA1/SHA256
        static let sha2Base: UInt32 = 0x5e28_0800        // two-register SHA
        static let aesBase: UInt32 = 0x4e28_0800         // AES (opcode adds into [16:12])
        static let sha512Base: UInt32 = 0xce60_8000      // three-register SHA512
        static let twoRegBase: UInt32 = 0xcec0_8000      // two-register SHA512/SM4
        static let sm3Base: UInt32 = 0xce60_c000         // three-register SM3/SM4
        static let sm3IndexedBase: UInt32 = 0xce40_8000  // SM3 imm2-indexed
        static let sm3ss1Base: UInt32 = 0xce40_0000      // four-register SM3SS1
        static let sha3FourBase: UInt32 = 0xce00_0000     // four-register SHA3
        static let rax1Base: UInt32 = 0xce60_8c00        // SHA3 RAX1
        static let xarBase: UInt32 = 0xce80_0000         // SHA3 XAR
    }

    /// Advanced SIMD copy (`DUP`/`INS`/`SMOV`/`UMOV`). `imm5`[20:16] selects the
    /// element/lane; `imm4`[14:11] selects the operation; `op`[29] is INS-element.
    enum VectorCopy {
        static let baseWord: UInt32 = 0x0e00_0400
        static let classMask: UInt32 = 0x9fe0_8400

        static let q = BitField(offset: 30, width: 1)
        static let op = BitField(offset: 29, width: 1)
        static let imm5 = BitField(offset: 16, width: 5)
        static let imm4 = BitField(offset: 11, width: 4)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Advanced SIMD table lookup (`TBL`/`TBX`). `len`[14:13] = table size − 1;
    /// `op`[12] selects TBX.
    enum VectorTableLookup {
        static let baseWord: UInt32 = 0x0e00_0000
        static let classMask: UInt32 = 0xbfe0_8c00

        static let q = BitField(offset: 30, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let len = BitField(offset: 13, width: 2)
        static let op = BitField(offset: 12, width: 1)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Advanced SIMD shift-by-immediate (`SHL`/`SSHR`/`SHRN`/`SSHLL`/...).
    /// `immh`[22:19]:`immb`[18:16] encode the element size and shift amount;
    /// `opcode`[15:11] selects the operation.
    enum VectorShiftImmediate {
        static let baseWord: UInt32 = 0x0f00_0400
        static let classMask: UInt32 = 0x9f80_0400

        static let q = BitField(offset: 30, width: 1)
        static let u = BitField(offset: 29, width: 1)
        static let immh = BitField(offset: 19, width: 4)
        static let immb = BitField(offset: 16, width: 3)
        static let opcode = BitField(offset: 11, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Advanced SIMD permute (`ZIP`/`UZP`/`TRN`). `opcode`[14:12] selects.
    enum VectorPermute {
        static let baseWord: UInt32 = 0x0e00_0800
        static let classMask: UInt32 = 0xbf20_8c00

        static let q = BitField(offset: 30, width: 1)
        static let size = BitField(offset: 22, width: 2)
        static let rm = BitField(offset: 16, width: 5)
        static let opcode = BitField(offset: 12, width: 3)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Advanced SIMD `EXT` — extract byte vector. `index`[14:11] is the lane.
    enum VectorExtract {
        static let baseWord: UInt32 = 0x2e00_0000
        static let classMask: UInt32 = 0xbfe0_8400

        static let q = BitField(offset: 30, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let index = BitField(offset: 11, width: 4)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Advanced SIMD three-same (`ADD`/`AND`/`FADD`/...). `q`/`u`/`size`(or the
    /// FP `a`/`sz` packed into the same [23:22] field)/`opcode`[15:11] select.
    enum VectorThreeSame {
        static let baseWord: UInt32 = 0x0e20_0400
        static let classMask: UInt32 = 0x9f20_0400

        static let q = BitField(offset: 30, width: 1)
        static let u = BitField(offset: 29, width: 1)
        static let size = BitField(offset: 22, width: 2)
        static let opcode = BitField(offset: 11, width: 5)
        static let rm = BitField(offset: 16, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Advanced SIMD three-different (`SADDL`/`UMULL`/`PMULL`/...). `opcode` is
    /// at [15:12].
    enum VectorThreeDifferent {
        static let baseWord: UInt32 = 0x0e20_0000
        static let classMask: UInt32 = 0x9f20_0c00

        static let q = BitField(offset: 30, width: 1)
        static let u = BitField(offset: 29, width: 1)
        static let size = BitField(offset: 22, width: 2)
        static let opcode = BitField(offset: 12, width: 4)
        static let rm = BitField(offset: 16, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Floating-point data-processing (2 source): `FMUL`/`FADD`/`FMAX`/...
    /// `type`[23:22] is the precision; `opcode`[15:12] the operation.
    enum FPDataProcessing2 {
        static let baseWord: UInt32 = 0x1e20_0800
        static let classMask: UInt32 = 0xff20_0c00

        static let type = BitField(offset: 22, width: 2)
        static let rm = BitField(offset: 16, width: 5)
        static let opcode = BitField(offset: 12, width: 4)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Floating-point data-processing (1 source): `FMOV`/`FABS`/`FNEG`/`FSQRT`/
    /// `FRINT*` and the `FCVT` precision conversions. `opcode`[20:15] selects.
    enum FPDataProcessing1 {
        static let baseWord: UInt32 = 0x1e20_4000
        static let classMask: UInt32 = 0xff20_7c00

        static let type = BitField(offset: 22, width: 2)
        static let opcode = BitField(offset: 15, width: 6)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Floating-point data-processing (3 source): `FMADD`/`FMSUB`/`FNMADD`/
    /// `FNMSUB`. `o1`[21]+`o0`[15] select; `Ra` is the addend.
    enum FPDataProcessing3 {
        static let baseWord: UInt32 = 0x1f00_0000
        static let classMask: UInt32 = 0xff00_0000

        static let type = BitField(offset: 22, width: 2)
        static let o1 = BitField(offset: 21, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let o0 = BitField(offset: 15, width: 1)
        static let ra = BitField(offset: 10, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Floating-point compare (`FCMP`/`FCMPE`). `opcode2`[4:0] selects the
    /// zero/register form and the E variant.
    enum FPCompare {
        static let baseWord: UInt32 = 0x1e20_2000
        static let classMask: UInt32 = 0xff20_fc07

        static let type = BitField(offset: 22, width: 2)
        static let rm = BitField(offset: 16, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let opcode2 = BitField(offset: 0, width: 5)
    }

    /// `FCSEL` — floating-point conditional select.
    enum FPConditionalSelect {
        static let baseWord: UInt32 = 0x1e20_0c00
        static let classMask: UInt32 = 0xff20_0c00

        static let type = BitField(offset: 22, width: 2)
        static let rm = BitField(offset: 16, width: 5)
        static let cond = BitField(offset: 12, width: 4)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// `FCCMP`/`FCCMPE` — floating-point conditional compare. `op`[4] selects E.
    enum FPConditionalCompare {
        static let baseWord: UInt32 = 0x1e20_0400
        static let classMask: UInt32 = 0xff20_0c00

        static let type = BitField(offset: 22, width: 2)
        static let rm = BitField(offset: 16, width: 5)
        static let cond = BitField(offset: 12, width: 4)
        static let rn = BitField(offset: 5, width: 5)
        static let op = BitField(offset: 4, width: 1)
        static let nzcv = BitField(offset: 0, width: 4)
    }

    /// `FMOV` (scalar, immediate). `imm8`[20:13] is the modified FP immediate.
    enum FPMoveImmediate {
        static let baseWord: UInt32 = 0x1e20_1000
        static let classMask: UInt32 = 0xff20_1fe0

        static let type = BitField(offset: 22, width: 2)
        static let imm8 = BitField(offset: 13, width: 8)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Fixed-encoding floating-point conversions/moves whose only operands are
    /// `Rn`/`Rd`: `BFCVT`, `FJCVTZS`, and `FMOV` to/from a vector high half.
    enum FPMisc {
        static let bfcvt: UInt32 = 0x1e63_4000
        static let fjcvtzs: UInt32 = 0x1e7e_0000
        static let fmovVectorHighToGeneral: UInt32 = 0x9eae_0000
        static let fmovGeneralToVectorHigh: UInt32 = 0x9eaf_0000

        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Floating-point ↔ integer conversion and `FMOV` general↔FP (`SCVTF`/
    /// `FCVTZS`/`FMOV`/`FJCVTZS`/...). `rmode`+`opcode` select the operation.
    enum FPIntegerConversion {
        static let baseWord: UInt32 = 0x1e20_0000
        static let classMask: UInt32 = 0x7f20_fc00

        static let sf = BitField(offset: 31, width: 1)
        static let type = BitField(offset: 22, width: 2)
        static let rmode = BitField(offset: 19, width: 2)
        static let opcode = BitField(offset: 16, width: 3)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Floating-point ↔ fixed-point conversion (`SCVTF`/`UCVTF`/`FCVTZS`/
    /// `FCVTZU`, fixed-point forms). `scale` = 64 − fbits.
    enum FPFixedConversion {
        static let baseWord: UInt32 = 0x1e00_0000
        static let classMask: UInt32 = 0x7f20_0000

        static let sf = BitField(offset: 31, width: 1)
        static let type = BitField(offset: 22, width: 2)
        static let rmode = BitField(offset: 19, width: 2)
        static let opcode = BitField(offset: 16, width: 3)
        static let scale = BitField(offset: 10, width: 6)
        static let rn = BitField(offset: 5, width: 5)
        static let rd = BitField(offset: 0, width: 5)
    }

    /// Load/store a single register. The family spans three addressing forms
    /// that share `size`/`opc`/`Rn`/`Rt` but differ in base word and offset
    /// encoding: unsigned-offset (`imm12`), unscaled/indexed (`imm9`+`mode`)
    /// and register-offset (`Rm`/`option`/`s`).
    enum LoadStoreSingle {
        static let size = BitField(offset: 30, width: 2)
        /// `V`[26] selects the SIMD&FP register file (the integer forms use 0).
        static let v = BitField(offset: 26, width: 1)
        static let opc = BitField(offset: 22, width: 2)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)

        /// Unsigned immediate offset (scaled). Base `0x3900_0000`.
        static let unsignedBase: UInt32 = 0x3900_0000
        static let imm12 = BitField(offset: 10, width: 12)

        /// Unscaled / pre / post indexed. Base `0x3800_0000`; `mode`[11:10]
        /// selects 0=unscaled, 1=post, 3=pre.
        static let unscaledBase: UInt32 = 0x3800_0000
        static let imm9 = BitField(offset: 12, width: 9)
        static let mode = BitField(offset: 10, width: 2)

        /// Register offset. Base `0x3820_0800`.
        static let registerOffsetBase: UInt32 = 0x3820_0800
        static let rm = BitField(offset: 16, width: 5)
        static let option = BitField(offset: 13, width: 3)
        static let s = BitField(offset: 12, width: 1)
    }

    /// Advanced SIMD load/store multiple structures (`LD1`..`LD4`/`ST1`..`ST4`).
    /// `post`[23] selects the post-indexed form; `opcode`[15:12] the structure.
    enum LoadStoreMultiple {
        static let baseWord: UInt32 = 0x0c00_0000
        static let classMask: UInt32 = 0xbf00_0000

        static let q = BitField(offset: 30, width: 1)
        static let post = BitField(offset: 23, width: 1)
        static let l = BitField(offset: 22, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let opcode = BitField(offset: 12, width: 4)
        static let size = BitField(offset: 10, width: 2)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// Advanced SIMD load/store single structure & replicate (`LD1`..`LD4`
    /// single-lane and `LD1R`..`LD4R`). `opcode`[15:13]+`s`[12] form the
    /// size-class/lane discriminator; `r`[21] is part of the structure count.
    enum LoadStoreSingleStructure {
        static let baseWord: UInt32 = 0x0d00_0000
        static let classMask: UInt32 = 0xbf00_0000

        static let q = BitField(offset: 30, width: 1)
        static let post = BitField(offset: 23, width: 1)
        static let l = BitField(offset: 22, width: 1)
        static let r = BitField(offset: 21, width: 1)
        static let rm = BitField(offset: 16, width: 5)
        static let opcode = BitField(offset: 13, width: 3)
        static let s = BitField(offset: 12, width: 1)
        static let size = BitField(offset: 10, width: 2)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// MTE load/store memory tags single (`STG`/`STZG`/`ST2G`/`STZ2G`/`LDG`/
    /// `STGM`/...). `opc` selects the operation; `op2`[11:10] the addressing
    /// form; `imm9` the (×16-scaled) signed offset.
    enum MTEMemoryTag {
        static let baseWord: UInt32 = 0xd920_0000
        static let classMask: UInt32 = 0xff20_0000

        static let opc = BitField(offset: 22, width: 2)
        static let imm9 = BitField(offset: 12, width: 9)
        static let op2 = BitField(offset: 10, width: 2)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// `STGP` — store allocation-tag and pair of registers. `mode`[24:23]
    /// selects the addressing form; `imm7` the (×16-scaled) signed offset.
    enum MTEStoreTagPair {
        static let baseWord: UInt32 = 0x6800_0000
        static let classMask: UInt32 = 0xfe40_0000

        static let mode = BitField(offset: 23, width: 2)
        static let imm7 = BitField(offset: 15, width: 7)
        static let rt2 = BitField(offset: 10, width: 5)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// `LDRAA`/`LDRAB` — load register with pointer authentication. `m`[23]
    /// selects the B key; `s`+`imm9` form the signed offset; `w`[11] writeback.
    enum PointerAuthLoad {
        static let baseWord: UInt32 = 0xf820_0400
        static let classMask: UInt32 = 0xff20_0400

        static let m = BitField(offset: 23, width: 1)
        static let s = BitField(offset: 22, width: 1)
        static let imm9 = BitField(offset: 12, width: 9)
        static let w = BitField(offset: 11, width: 1)
        static let rn = BitField(offset: 5, width: 5)
        static let rt = BitField(offset: 0, width: 5)
    }

    /// Load register (literal): integer `LDR`/`LDRSW`, the FP `LDR` (`v`=1) and
    /// `PRFM` (literal, `opc`=11). `opc`/`v` select the variant; `imm19` is the
    /// PC-relative word offset.
    enum LoadLiteral {
        static let baseWord: UInt32 = 0x1800_0000
        static let classMask: UInt32 = 0x3b00_0000

        static let opc = BitField(offset: 30, width: 2)
        static let v = BitField(offset: 26, width: 1)
        static let imm19 = BitField(offset: 5, width: 19)
        static let rt = BitField(offset: 0, width: 5)
        static let scale: Int64 = 4
        static let imm19Range: ClosedRange<Int64> = -262144...262143
    }
}
