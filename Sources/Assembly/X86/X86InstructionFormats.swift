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

        var mask: UInt8 { fieldMask << UInt8(offset) }
        func insert(_ value: UInt8) -> UInt8 { (value & fieldMask) << UInt8(offset) }
        func extract(_ byte: UInt8) -> UInt8 { (byte >> UInt8(offset)) & fieldMask }
    }

    /// Byte-level descriptor for the legacy REX prefix (`0100 WRXB`).
    enum REX {
        /// The fixed high nibble `0100`.
        static let baseByte: UInt8 = 0x40

        static let w = ByteField(offset: 3, width: 1)
        static let r = ByteField(offset: 2, width: 1)
        static let x = ByteField(offset: 1, width: 1)
        static let b = ByteField(offset: 0, width: 1)

        /// True iff `byte` is a REX prefix (`0x40`–`0x4F`).
        static func matches(_ byte: UInt8) -> Bool { (byte & 0xF0) == baseByte }

        /// Build a REX prefix byte. Returns `nil` when no bit is set and the
        /// caller hasn't asked for a forced REX (the empty `0x40` byte is
        /// only emitted when SPL/BPL/SIL/DIL are present, indicated by
        /// `forceEmit`).
        static func build(w: UInt8 = 0, r: UInt8 = 0, x: UInt8 = 0, b: UInt8 = 0, forceEmit: Bool = false) -> UInt8? {
            let byte = baseByte | Self.w.insert(w) | Self.r.insert(r) | Self.x.insert(x) | Self.b.insert(b)
            return (byte == baseByte && !forceEmit) ? nil : byte
        }
    }

    /// Byte-level descriptors for the AVX VEX prefix. Two layouts:
    /// `C5 byte2` (2-byte) and `C4 byte2 byte3` (3-byte). Both encode
    /// REX.R/X/B (inverted), a 4-bit second-source register selector
    /// (vvvv, also inverted), a vector-length bit (L), the mandatory
    /// prefix slot (pp), and — for the 3-byte form — REX.W and the
    /// opcode escape (mmmmm: 1=0F, 2=0F 38, 3=0F 3A).
    enum VEX {
        static let twoByteByte: UInt8 = 0xC5
        static let threeByteByte: UInt8 = 0xC4

        static func matches2(_ byte: UInt8) -> Bool { byte == twoByteByte }
        static func matches3(_ byte: UInt8) -> Bool { byte == threeByteByte }

        /// Escape-map values for the 3-byte VEX `mmmmm` field.
        static let escape0F:   UInt8 = 0b00001
        static let escape0F38: UInt8 = 0b00010
        static let escape0F3A: UInt8 = 0b00011

        /// Build a 2-byte VEX prefix when all three of REX.X/B and W
        /// are zero and the escape map is 0F. `r`/`vvvv`/`l`/`pp` are
        /// passed in their natural (non-inverted) sense; this builder
        /// flips R and vvvv before packing.
        static func build2(r: UInt8, vvvv: UInt8, l: UInt8, pp: UInt8) -> [UInt8] {
            let byte2 = (((~r) & 1) << 7) | ((((~vvvv) & 0xF) & 0xF) << 3) | ((l & 1) << 2) | (pp & 0b11)
            return [twoByteByte, byte2]
        }

        /// Build a 3-byte VEX prefix. All inversions (R/X/B/vvvv) are
        /// handled here; the caller passes natural-sense fields.
        static func build3(r: UInt8, x: UInt8, b: UInt8, escape: UInt8, w: UInt8, vvvv: UInt8, l: UInt8, pp: UInt8) -> [UInt8] {
            let byte2 = (((~r) & 1) << 7) | (((~x) & 1) << 6) | (((~b) & 1) << 5) | (escape & 0b11111)
            let byte3 = ((w & 1) << 7) | ((((~vvvv) & 0xF) & 0xF) << 3) | ((l & 1) << 2) | (pp & 0b11)
            return [threeByteByte, byte2, byte3]
        }

        /// Choose the shortest VEX form that fits. Use 2-byte VEX when
        /// X=B=W=0 and escape=0F; otherwise use the 3-byte form.
        static func build(r: UInt8, x: UInt8, b: UInt8, escape: UInt8, w: UInt8, vvvv: UInt8, l: UInt8, pp: UInt8) -> [UInt8] {
            if x == 0 && b == 0 && w == 0 && escape == escape0F {
                return build2(r: r, vvvv: vvvv, l: l, pp: pp)
            }
            return build3(r: r, x: x, b: b, escape: escape, w: w, vvvv: vvvv, l: l, pp: pp)
        }

        /// Decoded VEX fields, with R/X/B/vvvv already un-inverted.
        struct Decoded {
            let r: UInt8
            let x: UInt8
            let b: UInt8
            let w: UInt8
            let vvvv: UInt8
            let l: UInt8
            let pp: UInt8
            let escape: UInt8
        }

        /// Parse a 2-byte VEX given its second byte.
        static func parse2(byte2: UInt8) -> Decoded {
            Decoded(
                r: (~(byte2 >> 7)) & 1,
                x: 0,
                b: 0,
                w: 0,
                vvvv: (~(byte2 >> 3)) & 0xF,
                l: (byte2 >> 2) & 1,
                pp: byte2 & 0b11,
                escape: escape0F
            )
        }

        /// Parse a 3-byte VEX given its second and third bytes.
        static func parse3(byte2: UInt8, byte3: UInt8) -> Decoded {
            Decoded(
                r: (~(byte2 >> 7)) & 1,
                x: (~(byte2 >> 6)) & 1,
                b: (~(byte2 >> 5)) & 1,
                w: (byte3 >> 7) & 1,
                vvvv: (~(byte3 >> 3)) & 0xF,
                l: (byte3 >> 2) & 1,
                pp: byte3 & 0b11,
                escape: byte2 & 0b11111
            )
        }
    }

    /// Byte-level descriptor for the ModR/M byte (`mod[7:6] | reg[5:3] | rm[2:0]`).
    enum ModRM {
        static let mod = ByteField(offset: 6, width: 2)
        static let reg = ByteField(offset: 3, width: 3)
        static let rm = ByteField(offset: 0, width: 3)

        static let modIndirect: UInt8 = 0b00
        static let modDisp8: UInt8 = 0b01
        static let modDisp32: UInt8 = 0b10
        static let modRegister: UInt8 = 0b11

        /// Compose a ModR/M byte from `mod`, `reg`, and `rm` fields.
        static func make(mod: UInt8, reg: UInt8, rm: UInt8) -> UInt8 {
            Self.mod.insert(mod) | Self.reg.insert(reg) | Self.rm.insert(rm)
        }
    }

    /// Byte-level descriptor for the SIB byte (`scale[7:6] | index[5:3] | base[2:0]`).
    enum SIB {
        static let scale = ByteField(offset: 6, width: 2)
        static let index = ByteField(offset: 3, width: 3)
        static let base = ByteField(offset: 0, width: 3)

        /// `index == 4` (`0b100`) in the SIB byte means "no index". The
        /// `[rsp+...]` form uses this to reach RSP via the base field with
        /// the index slot left empty.
        static let noIndex: UInt8 = 0b100

        /// `base == 5` (`0b101`) in the SIB byte, combined with `mod == 00`
        /// in the ModR/M byte, means "no base" — the address resolves to
        /// the displacement alone (or `index*scale + disp32`).
        static let noBase: UInt8 = 0b101

        static func make(scale: UInt8, index: UInt8, base: UInt8) -> UInt8 {
            Self.scale.insert(scale) | Self.index.insert(index) | Self.base.insert(base)
        }
    }

    /// The operand-size override prefix (`0x66`). In 64-bit mode it selects
    /// 16-bit operands for instructions that default to 32-bit.
    static let operandSizeOverride: UInt8 = 0x66

    /// Static lookup table for general-purpose register names. The table is
    /// the single source of truth for both parsing (name → `Register`) and
    /// formatting (`Register` → name); maintaining one canonical mapping
    /// here prevents the two sides from drifting.
    enum RegisterTable {
        /// Canonical name for each `(number, width, isHighByte)` triple. The
        /// table is sized so that index `0..<16` for each width is dense.
        struct Entry {
            let name: String
            let register: Register
        }

        /// Ordered such that the canonical name is the first entry for each
        /// `Register`. Aliases (e.g. `r8l` for `r8b`) come after.
        static let entries: [Entry] = {
            var entries: [Entry] = []

            // 8-bit low (number 0-3)
            for (name, number) in [("al", 0), ("cl", 1), ("dl", 2), ("bl", 3)] {
                entries.append(.init(name: name, register: Register(number: UInt8(number), width: .byte)))
            }
            // 8-bit high (number 4-7, no REX allowed)
            for (name, number) in [("ah", 4), ("ch", 5), ("dh", 6), ("bh", 7)] {
                entries.append(.init(name: name, register: Register(number: UInt8(number), width: .byte, isHighByte: true)))
            }
            // 8-bit REX-only (number 4-7, REX forced)
            for (name, number) in [("spl", 4), ("bpl", 5), ("sil", 6), ("dil", 7)] {
                entries.append(.init(name: name, register: Register(number: UInt8(number), width: .byte, requiresREXForByte: true)))
            }
            // 8-bit extended (number 8-15)
            for n in 8...15 {
                entries.append(.init(name: "r\(n)b", register: Register(number: UInt8(n), width: .byte)))
            }

            // 16-bit
            let words: [(String, Int)] = [
                ("ax", 0), ("cx", 1), ("dx", 2), ("bx", 3),
                ("sp", 4), ("bp", 5), ("si", 6), ("di", 7),
            ]
            for (name, number) in words {
                entries.append(.init(name: name, register: Register(number: UInt8(number), width: .word)))
            }
            for n in 8...15 {
                entries.append(.init(name: "r\(n)w", register: Register(number: UInt8(n), width: .word)))
            }

            // 32-bit
            let dwords: [(String, Int)] = [
                ("eax", 0), ("ecx", 1), ("edx", 2), ("ebx", 3),
                ("esp", 4), ("ebp", 5), ("esi", 6), ("edi", 7),
            ]
            for (name, number) in dwords {
                entries.append(.init(name: name, register: Register(number: UInt8(number), width: .dword)))
            }
            for n in 8...15 {
                entries.append(.init(name: "r\(n)d", register: Register(number: UInt8(n), width: .dword)))
            }

            // 64-bit
            let qwords: [(String, Int)] = [
                ("rax", 0), ("rcx", 1), ("rdx", 2), ("rbx", 3),
                ("rsp", 4), ("rbp", 5), ("rsi", 6), ("rdi", 7),
            ]
            for (name, number) in qwords {
                entries.append(.init(name: name, register: Register(number: UInt8(number), width: .qword)))
            }
            for n in 8...15 {
                entries.append(.init(name: "r\(n)", register: Register(number: UInt8(n), width: .qword)))
            }

            return entries
        }()

        /// Name → register lookup, including the `r8l..r15l` aliases for
        /// the byte forms of R8..R15 (which `r8b..r15b` is the canonical
        /// name for).
        static let lookup: [String: Register] = {
            var map: [String: Register] = [:]
            for entry in entries { map[entry.name] = entry.register }
            // GAS-style aliases for R8..R15 byte forms.
            for n in 8...15 {
                map["r\(n)l"] = Register(number: UInt8(n), width: .byte)
            }
            return map
        }()

        /// Register → canonical name for formatting.
        static func canonicalName(for register: Register) -> String {
            for entry in entries where entry.register == register {
                return entry.name
            }
            // Should be unreachable for any register the parser produced;
            // returning a descriptive placeholder keeps the formatter total.
            return "?\(register.widthSuffix)\(register.number)"
        }
    }
}
