import Foundation

/// The X86 / X86-64 instruction-model namespace, mirroring the layering of
/// `A64`. Domain types (registers, memory operands, instruction kinds) live
/// here; the byte-level format descriptors live in `X86InstructionFormats`.
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
        /// One of AH/CH/DH/BH. These occupy `number` 4–7 with no REX prefix
        /// and become invalid the moment a REX prefix appears in the same
        /// instruction.
        var isHighByte: Bool
        /// One of SPL/BPL/SIL/DIL. These occupy `number` 4–7 *with* a REX
        /// prefix and require a REX byte even when no other field needs one.
        var requiresREXForByte: Bool

        init(number: UInt8, width: RegisterWidth, isHighByte: Bool = false, requiresREXForByte: Bool = false) {
            self.number = number
            self.width = width
            self.isHighByte = isHighByte
            self.requiresREXForByte = requiresREXForByte
        }

        /// Low 3 bits of `number`, fitted into a ModR/M `reg` or `rm` field.
        var lowBits: UInt8 { number & 0x7 }

        /// High bit of `number`, fitted into REX.R / REX.B / REX.X.
        var highBit: UInt8 { (number >> 3) & 0x1 }

        /// True iff the register is one of R8..R15 in any width.
        var isExtended: Bool { number >= 8 }

        /// The width tag used in human-readable diagnostics.
        var widthSuffix: String {
            switch width {
            case .byte:  return "byte"
            case .word:  return "word"
            case .dword: return "dword"
            case .qword: return "qword"
            }
        }
    }

    /// A memory operand in long mode.
    ///
    /// Long mode permits at most one base register, at most one index
    /// register scaled by 1/2/4/8, and an optional 32-bit (sign-extended)
    /// displacement. The `RIP+disp32` form is represented by `ripRelative
    /// == true` with no base or index. The `[disp32]` absolute form is
    /// represented by `base == nil && index == nil && ripRelative == false`.
    /// Registers must be 64-bit (the 32-bit `[esi+...]` form requires the
    /// `0x67` address-size override prefix and is deferred).
    struct MemoryOperand: Equatable {
        var base: Register?
        var index: Register?
        var scale: UInt8
        var displacement: Int64
        var ripRelative: Bool

        init(
            base: Register? = nil,
            index: Register? = nil,
            scale: UInt8 = 1,
            displacement: Int64 = 0,
            ripRelative: Bool = false
        ) {
            self.base = base
            self.index = index
            self.scale = scale
            self.displacement = displacement
            self.ripRelative = ripRelative
        }

        /// Encoded value of the SIB.scale field: 00 / 01 / 10 / 11 for scales
        /// 1 / 2 / 4 / 8 respectively.
        var scaleField: UInt8? {
            switch scale {
            case 1: return 0b00
            case 2: return 0b01
            case 4: return 0b10
            case 8: return 0b11
            default: return nil
            }
        }
    }

    /// An operand position that can be written: a register or a memory
    /// reference. Used as the destination of `MOV`, the left-hand side of
    /// binary ALU ops (ADD/SUB/...), and the target of unary ALU ops
    /// (INC/NEG/...).
    enum RegisterOrMemory: Equatable {
        case register(Register)
        case memory(MemoryOperand, width: RegisterWidth)

        var width: RegisterWidth {
            switch self {
            case .register(let r): return r.width
            case .memory(_, let w): return w
            }
        }
    }

    /// An operand position that can be read: register, memory, or
    /// immediate. Used as the right-hand side of `MOV` and binary ALU ops.
    enum Operand: Equatable {
        case register(Register)
        case memory(MemoryOperand, width: RegisterWidth)
        case immediate(Int64)
    }

    /// Zero-operand instructions whose encoding is a single fixed byte
    /// sequence. See `X86_CHECKLIST.md` Phase 1.
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

        static func resolve(mnemonic: String) -> ZeroOperandKind? {
            switch mnemonic {
            case "fwait": return .wait
            case "xlat":  return .xlatb
            default:      return ZeroOperandKind(rawValue: mnemonic)
            }
        }
    }

    /// The set of instructions recognised by the current implementation.
    enum Instruction: Equatable {
        case zeroOperand(ZeroOperandKind)
        case mov(destination: RegisterOrMemory, source: Operand)
    }
}
