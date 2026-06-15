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
