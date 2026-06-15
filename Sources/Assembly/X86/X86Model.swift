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

    /// Zero-operand instructions whose encoding is a single fixed byte
    /// sequence. The mnemonic *is* the encoding: there are no registers,
    /// immediates, or memory operands.
    ///
    /// Cases listed here are the canonical mnemonic used on disassembly.
    /// Surface-level aliases (`fwait` → `wait`, `xlat` → `xlatb`) are
    /// resolved in the parser and never appear on this enum.
    ///
    /// `bytes` is the full long-mode (x86_64) encoding. `iretq`/`sysretq`
    /// include the REX.W prefix; the operand-size-override (`66`) appears
    /// in `iret` to distinguish it from `iretd`.
    enum ZeroOperandKind: String, Equatable, CaseIterable {
        case nop
        case ret, retf
        case iret, iretd, iretq
        case leave
        case int3, ud2
        case clc, stc, cmc, cld, std, cli, sti
        case lahf, sahf
        case pause, hlt, wait, xlatb
        case syscall, sysret, sysretq, swapgs
        case cpuid
        case rdtsc, rdtscp, rdmsr, wrmsr, rdpmc
        case monitor, mwait

        var bytes: [UInt8] {
            switch self {
            case .nop:      return [0x90]
            case .ret:      return [0xC3]
            case .retf:     return [0xCB]
            case .iret:     return [0x66, 0xCF]
            case .iretd:    return [0xCF]
            case .iretq:    return [0x48, 0xCF]
            case .leave:    return [0xC9]
            case .int3:     return [0xCC]
            case .ud2:      return [0x0F, 0x0B]
            case .clc:      return [0xF8]
            case .stc:      return [0xF9]
            case .cmc:      return [0xF5]
            case .cld:      return [0xFC]
            case .std:      return [0xFD]
            case .cli:      return [0xFA]
            case .sti:      return [0xFB]
            case .lahf:     return [0x9F]
            case .sahf:     return [0x9E]
            case .pause:    return [0xF3, 0x90]
            case .hlt:      return [0xF4]
            case .wait:     return [0x9B]
            case .xlatb:    return [0xD7]
            case .syscall:  return [0x0F, 0x05]
            case .sysret:   return [0x0F, 0x07]
            case .sysretq:  return [0x48, 0x0F, 0x07]
            case .swapgs:   return [0x0F, 0x01, 0xF8]
            case .cpuid:    return [0x0F, 0xA2]
            case .rdtsc:    return [0x0F, 0x31]
            case .rdtscp:   return [0x0F, 0x01, 0xF9]
            case .rdmsr:    return [0x0F, 0x32]
            case .wrmsr:    return [0x0F, 0x30]
            case .rdpmc:    return [0x0F, 0x33]
            case .monitor:  return [0x0F, 0x01, 0xC8]
            case .mwait:    return [0x0F, 0x01, 0xC9]
            }
        }

        /// Resolve a parsed mnemonic (already lower-cased by `SourceParser`)
        /// into a canonical kind. Returns `nil` for mnemonics that do not
        /// belong to the zero-operand family.
        static func resolve(mnemonic: String) -> ZeroOperandKind? {
            switch mnemonic {
            case "fwait": return .wait
            case "xlat":  return .xlatb
            default:      return ZeroOperandKind(rawValue: mnemonic)
            }
        }
    }

    /// The set of instructions recognised by the current implementation.
    /// Later phases extend this enum one operand family at a time (see
    /// `X86_CHECKLIST.md`).
    enum Instruction: Equatable {
        case zeroOperand(ZeroOperandKind)
    }
}
