import Foundation

/// The X86 / X86-64 instruction-model namespace, mirroring the layering of
/// `A64`. Domain types (registers, memory operands, instruction kinds) live
/// here; the byte-level format descriptors live in `X86InstructionFormats`.
///
/// Phase 0 establishes the skeleton: only the `Instruction` enum case for
/// `nop` is present so the encode/decode/format pipeline can round-trip a
/// single instruction. Subsequent phases (see `X86_CHECKLIST.md`) extend
/// this enum with one operand family at a time.
internal enum X86 {
    /// General-purpose register width.
    enum RegisterWidth: Int, Equatable {
        case byte = 8
        case word = 16
        case dword = 32
        case qword = 64
    }

    /// A general-purpose register slot.
    ///
    /// `number` is the 4-bit encoding 0–15 (e.g. RAX=0, RCX=1, ..., R15=15).
    /// For the legacy high-byte registers (AH/CH/DH/BH) `isHighByte == true`;
    /// for SPL/BPL/SIL/DIL the encoder must emit a REX prefix even when
    /// otherwise unnecessary (`requiresREXForByte == true`).
    struct Register: Equatable {
        var number: UInt8
        var width: RegisterWidth
        var isHighByte: Bool
        var requiresREXForByte: Bool

        init(number: UInt8, width: RegisterWidth, isHighByte: Bool = false, requiresREXForByte: Bool = false) {
            self.number = number
            self.width = width
            self.isHighByte = isHighByte
            self.requiresREXForByte = requiresREXForByte
        }
    }

    /// The set of instructions recognised by Phase 0. Later phases extend
    /// this enum (see `X86_CHECKLIST.md`).
    enum Instruction: Equatable {
        case nop
    }
}
