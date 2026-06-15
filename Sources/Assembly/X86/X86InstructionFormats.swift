import Foundation

extension X86 {
    /// A contiguous run of bits within a single x86 byte (e.g. the `mod`,
    /// `reg`, and `r/m` fields of a ModR/M byte). The analogue of A64's
    /// `BitField`, but parameterised over `UInt8` because x86 builds its
    /// instructions byte by byte rather than as a fixed 32-bit word.
    struct ByteField {
        let offset: Int
        let width: Int

        private var fieldMask: UInt8 { (UInt8(1) << UInt8(width)) - 1 }

        /// The field's bits in their final position within the byte.
        var mask: UInt8 { fieldMask << UInt8(offset) }

        /// Place a field value into a byte (the value is truncated to `width`).
        func insert(_ value: UInt8) -> UInt8 { (value & fieldMask) << UInt8(offset) }

        /// Extract a field value from a byte (zero-extended).
        func extract(_ byte: UInt8) -> UInt8 { (byte >> UInt8(offset)) & fieldMask }
    }

    /// Byte-level descriptor for the legacy REX prefix (`0100 WRXB`).
    ///
    /// Phase 0 carries the descriptor but does not yet emit a REX prefix
    /// (the only encoded instruction is `nop = 0x90`). Phase 2 will start
    /// using it when MOV introduces 64-bit registers and R8–R15.
    enum REX {
        /// The fixed high nibble `0100`.
        static let baseByte: UInt8 = 0x40

        static let w = ByteField(offset: 3, width: 1)
        static let r = ByteField(offset: 2, width: 1)
        static let x = ByteField(offset: 1, width: 1)
        static let b = ByteField(offset: 0, width: 1)

        /// True iff `byte` is a REX prefix (`0x40`–`0x4F`).
        static func matches(_ byte: UInt8) -> Bool { (byte & 0xF0) == baseByte }
    }

    /// Byte-level descriptor for the ModR/M byte (`mod[7:6] | reg[5:3] | rm[2:0]`).
    enum ModRM {
        static let mod = ByteField(offset: 6, width: 2)
        static let reg = ByteField(offset: 3, width: 3)
        static let rm = ByteField(offset: 0, width: 3)

        /// `mod` values.
        static let modIndirect: UInt8 = 0b00
        static let modDisp8: UInt8 = 0b01
        static let modDisp32: UInt8 = 0b10
        static let modRegister: UInt8 = 0b11
    }

    /// Byte-level descriptor for the SIB byte (`scale[7:6] | index[5:3] | base[2:0]`).
    enum SIB {
        static let scale = ByteField(offset: 6, width: 2)
        static let index = ByteField(offset: 3, width: 3)
        static let base = ByteField(offset: 0, width: 3)
    }

}
