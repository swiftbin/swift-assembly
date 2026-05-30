import Foundation

public enum AssemblerError: Error, Equatable, CustomStringConvertible {
    case emptyInput
    case unknownInstruction(String)
    case invalidOperandCount(instruction: String, expected: String, actual: Int)
    case invalidRegister(String)
    case invalidImmediate(String)
    case immediateOutOfRange(instruction: String, value: Int64, range: ClosedRange<Int64>)
    case immediateAlignment(instruction: String, value: Int64, alignment: Int64)
    case unsupportedOperand(String)
    case invalidMemoryOperand(String)
    case unsupportedShift(String)
    case unsupportedExtend(String)
    case unsupportedCondition(String)
    case labelNotFound(String)
    case branchOutOfRange(instruction: String, label: String, byteOffset: Int64)
    case invalidByteCount(Int)
    case unknownEncoding(UInt32)

    public var description: String {
        switch self {
        case .emptyInput: return "Input is empty."
        case .unknownInstruction(let name): return "Unknown instruction: \(name)"
        case .invalidOperandCount(let instruction, let expected, let actual):
            return "Invalid operand count for \(instruction): expected \(expected), actual \(actual)."
        case .invalidRegister(let text): return "Invalid register: \(text)"
        case .invalidImmediate(let text): return "Invalid immediate: \(text)"
        case .immediateOutOfRange(let instruction, let value, let range):
            return "Immediate out of range for \(instruction): \(value), allowed \(range.lowerBound)...\(range.upperBound)."
        case .immediateAlignment(let instruction, let value, let alignment):
            return "Immediate for \(instruction) must be aligned to \(alignment): \(value)."
        case .unsupportedOperand(let text): return "Unsupported operand: \(text)"
        case .invalidMemoryOperand(let text): return "Invalid memory operand: \(text)"
        case .unsupportedShift(let text): return "Unsupported shift: \(text)"
        case .unsupportedExtend(let text): return "Unsupported extend: \(text)"
        case .unsupportedCondition(let text): return "Unsupported condition: \(text)"
        case .labelNotFound(let label): return "Label not found: \(label)"
        case .branchOutOfRange(let instruction, let label, let byteOffset):
            return "Branch target out of range for \(instruction) to \(label): byte offset \(byteOffset)."
        case .invalidByteCount(let count):
            return "Byte input length must be a multiple of 4, got \(count)."
        case .unknownEncoding(let word):
            return "Unknown instruction encoding: 0x\(String(word, radix: 16))."
        }
    }
}

public enum ARM64Assembler {
    public enum Architecture: Equatable, Sendable {
        case arm64
        case arm64e
    }

    public enum Endianness: Equatable, Sendable {
        case little
        case big
    }

    public static func assemble(_ source: String, architecture: Architecture = .arm64, endianness: Endianness = .little) throws -> [UInt8] {
        let words = try assembleWords(source, architecture: architecture)
        return words.flatMap { word in
            switch endianness {
            case .little:
                return [
                    UInt8(truncatingIfNeeded: word),
                    UInt8(truncatingIfNeeded: word >> 8),
                    UInt8(truncatingIfNeeded: word >> 16),
                    UInt8(truncatingIfNeeded: word >> 24),
                ]
            case .big:
                return [
                    UInt8(truncatingIfNeeded: word >> 24),
                    UInt8(truncatingIfNeeded: word >> 16),
                    UInt8(truncatingIfNeeded: word >> 8),
                    UInt8(truncatingIfNeeded: word),
                ]
            }
        }
    }

    public static func assembleWords(_ source: String, architecture: Architecture = .arm64) throws -> [UInt32] {
        let program = try A64SourceParser.program(source)
        return try program.instructions.enumerated().map { index, instruction in
            try encode(instruction, pc: Int64(index * 4), labels: program.labels, architecture: architecture)
        }
    }

    public static func assembleWord(_ instruction: String, architecture: Architecture = .arm64) throws -> UInt32 {
        let words = try assembleWords(instruction, architecture: architecture)
        guard words.count == 1 else {
            throw AssemblerError.invalidOperandCount(instruction: instruction, expected: "exactly one instruction", actual: words.count)
        }
        return words[0]
    }

    public static func disassemble(_ bytes: [UInt8], endianness: Endianness = .little) throws -> String {
        guard bytes.count.isMultiple(of: 4) else { throw AssemblerError.invalidByteCount(bytes.count) }
        var words: [UInt32] = []
        words.reserveCapacity(bytes.count / 4)

        for index in stride(from: 0, to: bytes.count, by: 4) {
            let word: UInt32
            switch endianness {
            case .little:
                word = UInt32(bytes[index])
                | (UInt32(bytes[index + 1]) << 8)
                | (UInt32(bytes[index + 2]) << 16)
                | (UInt32(bytes[index + 3]) << 24)
            case .big:
                word = (UInt32(bytes[index]) << 24)
                | (UInt32(bytes[index + 1]) << 16)
                | (UInt32(bytes[index + 2]) << 8)
                | UInt32(bytes[index + 3])
            }
            words.append(word)
        }

        return try disassembleWords(words).joined(separator: "\n")
    }

    public static func disassembleWords(_ words: [UInt32]) throws -> [String] {
        try words.map(disassembleWord)
    }

    public static func disassembleWord(_ word: UInt32) throws -> String {
        try A64InstructionFormatter.format(A64InstructionDecoder.decode(word))
    }
}

private struct ParsedInstruction: Equatable {
    var mnemonic: String
    var operands: [String]
    var original: String
}

private struct ParsedProgram: Equatable {
    var labels: [String: Int64]
    var instructions: [ParsedInstruction]
}

private enum A64 {
    enum RegisterKind: Equatable {
        case general
        case zero
        case stackPointer
    }

    struct Register: Equatable {
        var number: UInt32
        var width: Int
        var kind: RegisterKind

        var encodedNumber: UInt32 { number & 0x1f }
        var is64Bit: Bool { width == 64 }
    }

    enum Condition: UInt32 {
        case eq = 0x0, ne = 0x1, hs = 0x2, lo = 0x3
        case mi = 0x4, pl = 0x5, vs = 0x6, vc = 0x7
        case hi = 0x8, ls = 0x9, ge = 0xa, lt = 0xb
        case gt = 0xc, le = 0xd, al = 0xe, nv = 0xf
    }

    enum ShiftKind: UInt32 {
        case lsl = 0
        case lsr = 1
        case asr = 2
        case ror = 3
    }

    enum ExtendKind: UInt32 {
        case uxtb = 0
        case uxth = 1
        case uxtw = 2
        case uxtx = 3
        case sxtb = 4
        case sxth = 5
        case sxtw = 6
        case sxtx = 7
    }

    enum MemoryOperand: Equatable {
        case unsignedOffset(base: Register, offset: Int64)
        case signedUnscaled(base: Register, offset: Int64)
        case preIndexed(base: Register, offset: Int64)
        case postIndexed(base: Register, offset: Int64)
        case registerOffset(base: Register, offset: Register, extend: ExtendKind?, shift: Int)
    }

    enum BranchRegisterKind: Equatable {
        case ret
        case br
        case blr
    }

    enum ExceptionKind: Equatable {
        case supervisorCall
        case breakpoint
        case halt
    }

    enum BarrierKind: Equatable {
        case instructionSynchronization
        case dataSynchronization
        case dataMemory
    }

    enum Instruction: Equatable {
        case nop
        case branchRegister(BranchRegisterKind, Register)
        case unconditionalBranch(link: Bool, offset: Int64)
        case conditionalBranch(Condition, offset: Int64)
        case compareAndBranch(nonzero: Bool, Register, offset: Int64)
        case testAndBranch(nonzero: Bool, Register, bit: Int64, offset: Int64)
        case address(page: Bool, Register, offset: Int64)
        case exception(ExceptionKind, immediate: Int64)
        case exceptionReturn
        case barrier(BarrierKind, option: UInt32)
    }
}

private typealias IntegerRegisterKind = A64.RegisterKind
private typealias IntegerRegister = A64.Register
private typealias Condition = A64.Condition
private typealias ShiftKind = A64.ShiftKind
private typealias ExtendKind = A64.ExtendKind
private typealias MemoryOperand = A64.MemoryOperand
private typealias Instruction = A64.Instruction

private enum A64Parser {
    static func immediate(_ text: String) throws -> Int64 {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") { value.removeFirst() }
        value = value.replacingOccurrences(of: "_", with: "")
        let sign: Int64
        if value.hasPrefix("-") { sign = -1; value.removeFirst() }
        else if value.hasPrefix("+") { sign = 1; value.removeFirst() }
        else { sign = 1 }
        guard !value.isEmpty else { throw AssemblerError.invalidImmediate(text) }
        let parsed: Int64?
        if value.hasPrefix("0x") { parsed = Int64(value.dropFirst(2), radix: 16) }
        else if value.hasPrefix("0b") { parsed = Int64(value.dropFirst(2), radix: 2) }
        else { parsed = Int64(value, radix: 10) }
        guard let parsed else { throw AssemblerError.invalidImmediate(text) }
        return sign * parsed
    }

    static func integerRegister(_ text: String, allowSP: Bool) throws -> A64.Register {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower == "sp" {
            guard allowSP else { throw AssemblerError.invalidRegister(text) }
            return A64.Register(number: 31, width: 64, kind: .stackPointer)
        }
        if lower == "wsp" {
            guard allowSP else { throw AssemblerError.invalidRegister(text) }
            return A64.Register(number: 31, width: 32, kind: .stackPointer)
        }
        if lower == "xzr" { return A64.Register(number: 31, width: 64, kind: .zero) }
        if lower == "wzr" { return A64.Register(number: 31, width: 32, kind: .zero) }
        if lower == "fp" { return A64.Register(number: 29, width: 64, kind: .general) }
        if lower == "lr" { return A64.Register(number: 30, width: 64, kind: .general) }
        guard lower.count >= 2 else { throw AssemblerError.invalidRegister(text) }
        let prefix = lower.first!
        guard prefix == "x" || prefix == "w", let number = UInt32(lower.dropFirst()), number <= 30 else {
            throw AssemblerError.invalidRegister(text)
        }
        return A64.Register(number: number, width: prefix == "x" ? 64 : 32, kind: .general)
    }

    static func xRegister(_ text: String) throws -> A64.Register {
        let register = try integerRegister(text, allowSP: false)
        guard register.is64Bit else { throw AssemblerError.invalidRegister(text) }
        return register
    }

    static func xRegisterAllowingSP(_ text: String) throws -> A64.Register {
        let register = try integerRegister(text, allowSP: true)
        guard register.is64Bit else { throw AssemblerError.invalidRegister(text) }
        return register
    }

    static func condition(_ text: String) throws -> A64.Condition {
        switch text.lowercased() {
        case "eq": return .eq
        case "ne": return .ne
        case "hs", "cs": return .hs
        case "lo", "cc": return .lo
        case "mi": return .mi
        case "pl": return .pl
        case "vs": return .vs
        case "vc": return .vc
        case "hi": return .hi
        case "ls": return .ls
        case "ge": return .ge
        case "lt": return .lt
        case "gt": return .gt
        case "le": return .le
        case "al": return .al
        case "nv": return .nv
        default: throw AssemblerError.unsupportedCondition(text)
        }
    }

    static func shift(_ text: String) throws -> (A64.ShiftKind, Int) {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true).map { String($0).lowercased() }
        guard parts.count == 2 else { throw AssemblerError.unsupportedShift(text) }
        let kind: A64.ShiftKind
        switch parts[0] {
        case "lsl": kind = .lsl
        case "lsr": kind = .lsr
        case "asr": kind = .asr
        case "ror": kind = .ror
        default: throw AssemblerError.unsupportedShift(text)
        }
        let amount = try immediate(parts[1])
        try checkRange(amount, 0...63, instruction: parts[0])
        return (kind, Int(amount))
    }

    static func extend(_ text: String) throws -> (A64.ExtendKind, Int) {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true).map { String($0).lowercased() }
        guard (1...2).contains(parts.count) else { throw AssemblerError.unsupportedExtend(text) }
        let kind: A64.ExtendKind
        switch parts[0] {
        case "uxtb": kind = .uxtb
        case "uxth": kind = .uxth
        case "uxtw": kind = .uxtw
        case "uxtx", "lsl": kind = .uxtx
        case "sxtb": kind = .sxtb
        case "sxth": kind = .sxth
        case "sxtw": kind = .sxtw
        case "sxtx": kind = .sxtx
        default: throw AssemblerError.unsupportedExtend(text)
        }
        let amount = parts.count == 2 ? try immediate(parts[1]) : 0
        try checkRange(amount, 0...4, instruction: parts[0])
        return (kind, Int(amount))
    }

    static func barrierOption(_ text: String) throws -> UInt32 {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("#") {
            let value = try immediate(lower)
            try checkRange(value, 0...15, instruction: "barrier")
            return UInt32(value)
        }
        switch lower {
        case "sy": return 0xf
        case "st": return 0xe
        case "ld": return 0xd
        case "ish": return 0xb
        case "ishst": return 0xa
        case "ishld": return 0x9
        case "nsh": return 0x7
        case "nshst": return 0x6
        case "nshld": return 0x5
        case "osh": return 0x3
        case "oshst": return 0x2
        case "oshld": return 0x1
        default: throw AssemblerError.unsupportedOperand(text)
        }
    }
}

private enum A64SourceParser {
    static func program(_ source: String) throws -> ParsedProgram {
        var labels: [String: Int64] = [:]
        var instructions: [ParsedInstruction] = []

        for rawLine in source.components(separatedBy: .newlines) {
            var line = stripComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            while let colonIndex = labelColonIndex(in: line) {
                let label = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty { labels[label] = Int64(instructions.count * 4) }
                line = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { break }
            }

            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard let first = parts.first else { continue }
            instructions.append(
                ParsedInstruction(
                    mnemonic: String(first).lowercased(),
                    operands: parts.count == 2 ? splitOperands(String(parts[1])) : [],
                    original: line
                )
            )
        }

        guard !instructions.isEmpty else { throw AssemblerError.emptyInput }
        return ParsedProgram(labels: labels, instructions: instructions)
    }

    static func stripComment(_ line: String) -> String {
        var depth = 0
        for index in line.indices {
            let ch = line[index]
            if ch == "[" { depth += 1 }
            if ch == "]" { depth = max(0, depth - 1) }
            if depth == 0 {
                if ch == ";" { return String(line[..<index]) }
                if ch == "/", line.index(after: index) < line.endIndex, line[line.index(after: index)] == "/" {
                    return String(line[..<index])
                }
            }
        }
        return line
    }

    static func labelColonIndex(in line: String) -> String.Index? {
        var depth = 0
        for index in line.indices {
            let ch = line[index]
            if ch == "[" { depth += 1 }
            if ch == "]" { depth = max(0, depth - 1) }
            if depth == 0, ch == ":" { return index }
            if depth == 0, ch.isWhitespace { return nil }
        }
        return nil
    }

    static func splitOperands(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0

        for ch in text {
            switch ch {
            case "[":
                depth += 1
                current.append(ch)
            case "]":
                depth = max(0, depth - 1)
                current.append(ch)
            case "," where depth == 0:
                let operand = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !operand.isEmpty { result.append(operand) }
                current.removeAll(keepingCapacity: true)
            default:
                current.append(ch)
            }
        }

        let operand = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !operand.isEmpty { result.append(operand) }
        return result
    }
}

private enum A64InstructionEncoder {
    static func encode(
        _ instruction: ParsedInstruction,
        pc: Int64,
        labels: [String: Int64],
        architecture: ARM64Assembler.Architecture
    ) throws -> UInt32 {
        try encodeInstruction(instruction, pc: pc, labels: labels, architecture: architecture)
    }

    static func encode(_ instruction: Instruction) throws -> UInt32 {
        switch instruction {
        case .nop:
            return 0xd503201f
        case .branchRegister(.ret, let rn):
            return 0xd65f0000 | (rn.encodedNumber << 5)
        case .branchRegister(.br, let rn):
            return 0xd61f0000 | (rn.encodedNumber << 5)
        case .branchRegister(.blr, let rn):
            return 0xd63f0000 | (rn.encodedNumber << 5)
        case .unconditionalBranch(let link, let offset):
            guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: link ? "bl" : "b", value: offset, alignment: 4) }
            let imm26 = offset / 4
            guard (-0x2000000...0x1ffffff).contains(imm26) else {
                throw AssemblerError.branchOutOfRange(instruction: link ? "bl" : "b", label: "#\(offset)", byteOffset: offset)
            }
            return (link ? 0x94000000 : 0x14000000) | (UInt32(bitPattern: Int32(imm26)) & 0x03ff_ffff)
        case .conditionalBranch(let condition, let offset):
            guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: "b.\(condition)", value: offset, alignment: 4) }
            let imm19 = offset / 4
            guard (-0x40000...0x3ffff).contains(imm19) else {
                throw AssemblerError.branchOutOfRange(instruction: "b.\(condition)", label: "#\(offset)", byteOffset: offset)
            }
            return 0x54000000 | ((UInt32(bitPattern: Int32(imm19)) & 0x7ffff) << 5) | condition.rawValue
        case .compareAndBranch(let nonzero, let rt, let offset):
            guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: nonzero ? "cbnz" : "cbz", value: offset, alignment: 4) }
            let imm19 = offset / 4
            guard (-0x40000...0x3ffff).contains(imm19) else {
                throw AssemblerError.branchOutOfRange(instruction: nonzero ? "cbnz" : "cbz", label: "#\(offset)", byteOffset: offset)
            }
            return ((rt.is64Bit ? UInt32(1) : 0) << 31)
            | 0x34000000
            | ((nonzero ? UInt32(1) : 0) << 24)
            | ((UInt32(bitPattern: Int32(imm19)) & 0x7ffff) << 5)
            | rt.encodedNumber
        case .testAndBranch(let nonzero, let rt, let bit, let offset):
            try checkRange(bit, 0...(rt.is64Bit ? 63 : 31), instruction: nonzero ? "tbnz" : "tbz")
            guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: nonzero ? "tbnz" : "tbz", value: offset, alignment: 4) }
            let imm14 = offset / 4
            guard (-0x2000...0x1fff).contains(imm14) else {
                throw AssemblerError.branchOutOfRange(instruction: nonzero ? "tbnz" : "tbz", label: "#\(offset)", byteOffset: offset)
            }
            return ((UInt32(bit >> 5) & 1) << 31)
            | 0x36000000
            | ((nonzero ? UInt32(1) : 0) << 24)
            | ((UInt32(bit) & 0x1f) << 19)
            | ((UInt32(bitPattern: Int32(imm14)) & 0x3fff) << 5)
            | rt.encodedNumber
        case .address(let page, let rd, let offset):
            let mnemonic = page ? "adrp" : "adr"
            let immediate: Int64
            if page {
                guard offset % 4096 == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: offset, alignment: 4096) }
                immediate = offset / 4096
            } else {
                immediate = offset
            }
            guard (-0x100000...0xfffff).contains(immediate) else {
                throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: immediate, range: -0x100000...0xfffff)
            }
            let imm = UInt32(bitPattern: Int32(immediate)) & 0x1f_ffff
            return (page ? 0x90000000 : 0x10000000) | ((imm & 0x3) << 29) | (((imm >> 2) & 0x7ffff) << 5) | rd.encodedNumber
        case .exception(.supervisorCall, let immediate):
            return 0xd4000001 | (UInt32(immediate) << 5)
        case .exception(.breakpoint, let immediate):
            return 0xd4200000 | (UInt32(immediate) << 5)
        case .exception(.halt, let immediate):
            return 0xd4400000 | (UInt32(immediate) << 5)
        case .exceptionReturn:
            return 0xd69f03e0
        case .barrier(.instructionSynchronization, let option):
            return 0xd50330df | (option << 8)
        case .barrier(.dataSynchronization, let option):
            return 0xd503309f | (option << 8)
        case .barrier(.dataMemory, let option):
            return 0xd50330bf | (option << 8)
        }
    }
}

private enum A64InstructionParser {
    static func instruction(_ instruction: ParsedInstruction, pc: Int64, labels: [String: Int64]) throws -> Instruction? {
        let parts = instruction.mnemonic.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let mnemonic = parts[0]

        switch mnemonic {
        case "b" where parts.count == 2:
            try expectOperandCount(instruction, exactly: 1)
            let condition = try A64Parser.condition(parts[1])
            let offset = try labelOrImmediateByteOffset(instruction.operands[0], pc: pc, labels: labels)
            return .conditionalBranch(condition, offset: offset)
        case "b":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 1)
            let offset = try labelOrImmediateByteOffset(instruction.operands[0], pc: pc, labels: labels)
            return .unconditionalBranch(link: false, offset: offset)
        case "bl":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 1)
            let offset = try labelOrImmediateByteOffset(instruction.operands[0], pc: pc, labels: labels)
            return .unconditionalBranch(link: true, offset: offset)
        case "cbz", "cbnz":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let rt = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let offset = try labelOrImmediateByteOffset(instruction.operands[1], pc: pc, labels: labels)
            return .compareAndBranch(nonzero: mnemonic == "cbnz", rt, offset: offset)
        case "tbz", "tbnz":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let rt = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let bit = try A64Parser.immediate(instruction.operands[1])
            let offset = try labelOrImmediateByteOffset(instruction.operands[2], pc: pc, labels: labels)
            return .testAndBranch(nonzero: mnemonic == "tbnz", rt, bit: bit, offset: offset)
        case "adr", "adrp":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let rd = try A64Parser.xRegister(instruction.operands[0])
            let offset = try labelOrImmediateByteOffset(instruction.operands[1], pc: pc, labels: labels)
            return .address(page: mnemonic == "adrp", rd, offset: offset)
        case "nop":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 0)
            return .nop
        case "ret":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 0...1)
            let rn = try instruction.operands.first.map(A64Parser.xRegisterAllowingSP) ?? IntegerRegister(number: 30, width: 64, kind: .general)
            return .branchRegister(.ret, rn)
        case "br":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 1)
            return .branchRegister(.br, try A64Parser.xRegisterAllowingSP(instruction.operands[0]))
        case "blr":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 1)
            return .branchRegister(.blr, try A64Parser.xRegisterAllowingSP(instruction.operands[0]))
        case "svc":
            guard parts.count == 1 else { return nil }
            return try exception(instruction, kind: .supervisorCall, mnemonic: mnemonic)
        case "brk":
            guard parts.count == 1 else { return nil }
            return try exception(instruction, kind: .breakpoint, mnemonic: mnemonic)
        case "hlt":
            guard parts.count == 1 else { return nil }
            return try exception(instruction, kind: .halt, mnemonic: mnemonic)
        case "eret":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 0)
            return .exceptionReturn
        case "isb":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 0...1)
            let option = try instruction.operands.first.map(A64Parser.barrierOption) ?? 0xf
            return .barrier(.instructionSynchronization, option: option)
        case "dsb":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 1)
            return .barrier(.dataSynchronization, option: try A64Parser.barrierOption(instruction.operands[0]))
        case "dmb":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 1)
            return .barrier(.dataMemory, option: try A64Parser.barrierOption(instruction.operands[0]))
        default:
            return nil
        }
    }

    private static func exception(_ instruction: ParsedInstruction, kind: A64.ExceptionKind, mnemonic: String) throws -> Instruction {
        try expectOperandCount(instruction, exactly: 1)
        let immediate = try A64Parser.immediate(instruction.operands[0])
        try checkRange(immediate, 0...0xffff, instruction: mnemonic)
        return .exception(kind, immediate: immediate)
    }
}

private enum A64InstructionDecoder {
    static func decode(_ word: UInt32) throws -> Instruction {
        if word == 0xd503201f { return .nop }
        if word == 0xd69f03e0 { return .exceptionReturn }

        if let instruction = decodeBranchRegister(word) { return instruction }
        if let instruction = decodeUnconditionalBranch(word) { return instruction }
        if let instruction = decodeConditionalBranch(word) { return instruction }
        if let instruction = decodeCompareAndBranch(word) { return instruction }
        if let instruction = decodeTestAndBranch(word) { return instruction }
        if let instruction = decodeAddress(word) { return instruction }
        if let instruction = decodeException(word) { return instruction }
        if let instruction = decodeBarrier(word) { return instruction }

        throw AssemblerError.unknownEncoding(word)
    }

    private static func decodeBranchRegister(_ word: UInt32) -> Instruction? {
        let mask: UInt32 = 0xffff_fc1f
        let rn = xRegister(number: (word >> 5) & 0x1f)
        switch word & mask {
        case 0xd65f0000:
            return .branchRegister(.ret, rn)
        case 0xd61f0000:
            return .branchRegister(.br, rn)
        case 0xd63f0000:
            return .branchRegister(.blr, rn)
        default:
            return nil
        }
    }

    private static func decodeUnconditionalBranch(_ word: UInt32) -> Instruction? {
        switch word & 0xfc00_0000 {
        case 0x14000000:
            return .unconditionalBranch(link: false, offset: signExtend(word & 0x03ff_ffff, bitCount: 26) * 4)
        case 0x94000000:
            return .unconditionalBranch(link: true, offset: signExtend(word & 0x03ff_ffff, bitCount: 26) * 4)
        default:
            return nil
        }
    }

    private static func decodeConditionalBranch(_ word: UInt32) -> Instruction? {
        guard word & 0xff00_0010 == 0x5400_0000 else { return nil }
        guard let condition = Condition(rawValue: word & 0xf) else { return nil }
        let offset = signExtend((word >> 5) & 0x7ffff, bitCount: 19) * 4
        return .conditionalBranch(condition, offset: offset)
    }

    private static func decodeCompareAndBranch(_ word: UInt32) -> Instruction? {
        guard word & 0x7e00_0000 == 0x3400_0000 else { return nil }
        let is64Bit = (word >> 31) & 1 == 1
        let nonzero = (word >> 24) & 1 == 1
        let rt = integerRegister(number: word & 0x1f, width: is64Bit ? 64 : 32)
        let offset = signExtend((word >> 5) & 0x7ffff, bitCount: 19) * 4
        return .compareAndBranch(nonzero: nonzero, rt, offset: offset)
    }

    private static func decodeTestAndBranch(_ word: UInt32) -> Instruction? {
        guard word & 0x7e00_0000 == 0x3600_0000 else { return nil }
        let bit = Int64(((word >> 31) & 1) << 5) | Int64((word >> 19) & 0x1f)
        let nonzero = (word >> 24) & 1 == 1
        let rt = integerRegister(number: word & 0x1f, width: bit >= 32 ? 64 : 32)
        let offset = signExtend((word >> 5) & 0x3fff, bitCount: 14) * 4
        return .testAndBranch(nonzero: nonzero, rt, bit: bit, offset: offset)
    }

    private static func decodeAddress(_ word: UInt32) -> Instruction? {
        let page: Bool
        switch word & 0x9f00_0000 {
        case 0x1000_0000:
            page = false
        case 0x9000_0000:
            page = true
        default:
            return nil
        }
        let immlo = (word >> 29) & 0x3
        let immhi = (word >> 5) & 0x7ffff
        let immediate = signExtend((immhi << 2) | immlo, bitCount: 21)
        return .address(page: page, xRegister(number: word & 0x1f), offset: page ? immediate * 4096 : immediate)
    }

    private static func decodeException(_ word: UInt32) -> Instruction? {
        let mask: UInt32 = 0xffe0_001f
        let immediate = Int64((word >> 5) & 0xffff)
        switch word & mask {
        case 0xd4000001:
            return .exception(.supervisorCall, immediate: immediate)
        case 0xd4200000:
            return .exception(.breakpoint, immediate: immediate)
        case 0xd4400000:
            return .exception(.halt, immediate: immediate)
        default:
            return nil
        }
    }

    private static func decodeBarrier(_ word: UInt32) -> Instruction? {
        let mask: UInt32 = 0xffff_f0ff
        let option = (word >> 8) & 0xf
        switch word & mask {
        case 0xd50330df:
            return .barrier(.instructionSynchronization, option: option)
        case 0xd503309f:
            return .barrier(.dataSynchronization, option: option)
        case 0xd50330bf:
            return .barrier(.dataMemory, option: option)
        default:
            return nil
        }
    }

    private static func xRegister(number: UInt32) -> IntegerRegister {
        IntegerRegister(number: number, width: 64, kind: number == 31 ? .stackPointer : .general)
    }

    private static func integerRegister(number: UInt32, width: Int) -> IntegerRegister {
        IntegerRegister(number: number, width: width, kind: number == 31 ? .zero : .general)
    }

    private static func signExtend(_ value: UInt32, bitCount: Int) -> Int64 {
        let signBit = UInt32(1) << UInt32(bitCount - 1)
        let mask = (UInt32(1) << UInt32(bitCount)) - 1
        let value = value & mask
        if value & signBit == 0 { return Int64(value) }
        return Int64(Int32(bitPattern: value | ~mask))
    }
}

private enum A64InstructionFormatter {
    static func format(_ instruction: Instruction) throws -> String {
        switch instruction {
        case .nop:
            return "nop"
        case .branchRegister(.ret, let rn):
            return rn.number == 30 ? "ret" : "ret \(formatRegister(rn))"
        case .branchRegister(.br, let rn):
            return "br \(formatRegister(rn))"
        case .branchRegister(.blr, let rn):
            return "blr \(formatRegister(rn))"
        case .unconditionalBranch(let link, let offset):
            return "\(link ? "bl" : "b") #\(offset)"
        case .conditionalBranch(let condition, let offset):
            return "b.\(formatCondition(condition)) #\(offset)"
        case .compareAndBranch(let nonzero, let rt, let offset):
            return "\(nonzero ? "cbnz" : "cbz") \(formatRegister(rt)), #\(offset)"
        case .testAndBranch(let nonzero, let rt, let bit, let offset):
            return "\(nonzero ? "tbnz" : "tbz") \(formatRegister(rt)), #\(bit), #\(offset)"
        case .address(let page, let rd, let offset):
            return "\(page ? "adrp" : "adr") \(formatRegister(rd)), #\(offset)"
        case .exception(.supervisorCall, let immediate):
            return "svc #\(immediate)"
        case .exception(.breakpoint, let immediate):
            return "brk #\(immediate)"
        case .exception(.halt, let immediate):
            return "hlt #\(immediate)"
        case .exceptionReturn:
            return "eret"
        case .barrier(.instructionSynchronization, let option):
            return option == 0xf ? "isb" : "isb \(formatBarrierOption(option))"
        case .barrier(.dataSynchronization, let option):
            return "dsb \(formatBarrierOption(option))"
        case .barrier(.dataMemory, let option):
            return "dmb \(formatBarrierOption(option))"
        }
    }

    private static func formatRegister(_ register: IntegerRegister) -> String {
        if register.kind == .stackPointer {
            return register.is64Bit ? "sp" : "wsp"
        }
        switch register.number {
        case 29 where register.is64Bit:
            return "fp"
        case 30 where register.is64Bit:
            return "lr"
        case 31:
            return register.is64Bit ? "xzr" : "wzr"
        default:
            return "\(register.is64Bit ? "x" : "w")\(register.number)"
        }
    }

    private static func formatCondition(_ condition: Condition) -> String {
        switch condition {
        case .eq: return "eq"
        case .ne: return "ne"
        case .hs: return "hs"
        case .lo: return "lo"
        case .mi: return "mi"
        case .pl: return "pl"
        case .vs: return "vs"
        case .vc: return "vc"
        case .hi: return "hi"
        case .ls: return "ls"
        case .ge: return "ge"
        case .lt: return "lt"
        case .gt: return "gt"
        case .le: return "le"
        case .al: return "al"
        case .nv: return "nv"
        }
    }

    private static func formatBarrierOption(_ option: UInt32) -> String {
        switch option {
        case 0xf: return "sy"
        case 0xe: return "st"
        case 0xd: return "ld"
        case 0xb: return "ish"
        case 0xa: return "ishst"
        case 0x9: return "ishld"
        case 0x7: return "nsh"
        case 0x6: return "nshst"
        case 0x5: return "nshld"
        case 0x3: return "osh"
        case 0x2: return "oshst"
        case 0x1: return "oshld"
        default: return "#\(option)"
        }
    }
}

private enum A64BitmaskImmediate {
    static func encode(_ value: UInt64, width: Int) -> (n: UInt32, immr: UInt32, imms: UInt32)? {
        let fullMask: UInt64 = width == 64 ? UInt64.max : 0xffff_ffff
        let value = value & fullMask
        guard value != 0, value != fullMask else { return nil }

        for elementSize in [2, 4, 8, 16, 32, 64] where elementSize <= width {
            let elementMask = mask(width: elementSize)
            let element = value & elementMask
            guard replicate(element, elementSize: elementSize, width: width) == value else { continue }

            for onesLength in 1..<elementSize {
                let ones = mask(width: onesLength)
                for rotation in 0..<elementSize {
                    if rotateRight(ones, by: rotation, width: elementSize) == element {
                        let immr = UInt32(rotation)
                        let immsValue = (((~(elementSize - 1)) << 1) | (onesLength - 1)) & 0x3f
                        let imms = UInt32(immsValue)
                        let n: UInt32 = elementSize == 64 ? 1 : 0
                        return (n, immr, imms)
                    }
                }
            }
        }

        return nil
    }

    static func mask(width: Int) -> UInt64 {
        width >= 64 ? UInt64.max : ((UInt64(1) << UInt64(width)) - 1)
    }

    static func replicate(_ value: UInt64, elementSize: Int, width: Int) -> UInt64 {
        var result: UInt64 = 0
        let element = value & mask(width: elementSize)
        var shift = 0
        while shift < width {
            result |= element << UInt64(shift)
            shift += elementSize
        }
        return result & mask(width: width)
    }

    static func rotateRight(_ value: UInt64, by amount: Int, width: Int) -> UInt64 {
        let amount = amount % width
        let value = value & mask(width: width)
        if amount == 0 { return value }
        return ((value >> UInt64(amount)) | (value << UInt64(width - amount))) & mask(width: width)
    }
}


private enum A64SystemEncoder {
    static func barrier(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        let option: UInt32
        if mnemonic == "isb" {
            try expectOperandCount(instruction, 0...1)
            option = try instruction.operands.first.map(A64Parser.barrierOption) ?? 0xf
            return 0xd50330df | (option << 8)
        }

        try expectOperandCount(instruction, exactly: 1)
        option = try A64Parser.barrierOption(instruction.operands[0])
        switch mnemonic {
        case "dsb": return 0xd503309f | (option << 8)
        case "dmb": return 0xd50330bf | (option << 8)
        default: throw AssemblerError.unknownInstruction(mnemonic)
        }
    }
}

private enum A64BranchRegisterEncoder {
    static func ret(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, 0...1)
        let rn = try instruction.operands.first.map(A64Parser.xRegisterAllowingSP) ?? IntegerRegister(number: 30, width: 64, kind: .general)
        return 0xd65f0000 | (rn.encodedNumber << 5)
    }

    static func br(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 1)
        let rn = try A64Parser.xRegisterAllowingSP(instruction.operands[0])
        return 0xd61f0000 | (rn.encodedNumber << 5)
    }

    static func blr(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 1)
        let rn = try A64Parser.xRegisterAllowingSP(instruction.operands[0])
        return 0xd63f0000 | (rn.encodedNumber << 5)
    }
}

private enum A64ExceptionEncoder {
    static func supervisorCall(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 1)
        let imm = try A64Parser.immediate(instruction.operands[0])
        try checkRange(imm, 0...0xffff, instruction: "svc")
        return 0xd4000001 | (UInt32(imm) << 5)
    }

    static func breakpoint(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 1)
        let imm = try A64Parser.immediate(instruction.operands[0])
        try checkRange(imm, 0...0xffff, instruction: "brk")
        return 0xd4200000 | (UInt32(imm) << 5)
    }

    static func halt(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 1)
        let imm = try A64Parser.immediate(instruction.operands[0])
        try checkRange(imm, 0...0xffff, instruction: "hlt")
        return 0xd4400000 | (UInt32(imm) << 5)
    }

    static func exceptionReturn(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 0)
        return 0xd69f03e0
    }
}

private enum A64AddressEncoder {
    static func adr(_ instruction: ParsedInstruction, mnemonic: String, pc: Int64, labels: [String: Int64]) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 2)
        let rd = try A64Parser.xRegister(instruction.operands[0])
        let byteOffset = try labelOrImmediateByteOffset(instruction.operands[1], pc: pc, labels: labels)
        let immediate: Int64
        if mnemonic == "adrp" {
            guard byteOffset % 4096 == 0 else { throw AssemblerError.immediateAlignment(instruction: "adrp", value: byteOffset, alignment: 4096) }
            immediate = byteOffset / 4096
        } else {
            immediate = byteOffset
        }
        guard (-0x100000...0xfffff).contains(immediate) else {
            throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: immediate, range: -0x100000...0xfffff)
        }
        let imm = UInt32(bitPattern: Int32(immediate)) & 0x1f_ffff
        return (mnemonic == "adrp" ? 0x90000000 : 0x10000000) | ((imm & 0x3) << 29) | (((imm >> 2) & 0x7ffff) << 5) | rd.encodedNumber
    }
}

private enum A64PointerAuthenticationEncoder {
    static func encode(_ instruction: ParsedInstruction, mnemonic: String, architecture: ARM64Assembler.Architecture) throws -> UInt32 {
        try requireARM64E(architecture, instruction: mnemonic)
        switch mnemonic {
        case "paciasp":
            try expectOperandCount(instruction, exactly: 0)
            return 0xd503233f
        case "autiasp":
            try expectOperandCount(instruction, exactly: 0)
            return 0xd50323bf
        case "pacibsp":
            try expectOperandCount(instruction, exactly: 0)
            return 0xd503237f
        case "autibsp":
            try expectOperandCount(instruction, exactly: 0)
            return 0xd50323ff
        case "xpaci", "xpacd":
            try expectOperandCount(instruction, exactly: 1)
            let rd = try A64Parser.xRegister(instruction.operands[0])
            return (mnemonic == "xpaci" ? 0xdac143e0 : 0xdac147e0) | rd.encodedNumber
        default:
            throw AssemblerError.unknownInstruction(mnemonic)
        }
    }
}

private enum A64MoveEncoder {
    static func movAlias(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 2)
        let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: true)
        let source = instruction.operands[1].trimmingCharacters(in: .whitespacesAndNewlines)

        if source.hasPrefix("#") {
            return try moveImmediateAlias(instruction, destination: rd)
        }

        let rm = try A64Parser.integerRegister(source, allowSP: true)
        guard rd.width == rm.width else { throw AssemblerError.invalidRegister(instruction.original) }
        if rd.kind == .stackPointer || rm.kind == .stackPointer {
            return try A64AddSubEncoder.addSub(ParsedInstruction(mnemonic: "add", operands: [instruction.operands[0], instruction.operands[1], "#0"], original: instruction.original), mnemonic: "add")
        }
        return try A64LogicalEncoder.shiftedRegister(
            ParsedInstruction(mnemonic: "orr", operands: [instruction.operands[0], rd.is64Bit ? "xzr" : "wzr", instruction.operands[1]], original: instruction.original),
            mnemonic: "orr"
        )
    }

    static func moveImmediateAlias(_ instruction: ParsedInstruction, destination rd: IntegerRegister) throws -> UInt32 {
        let value = try A64Parser.immediate(instruction.operands[1])
        let width = rd.is64Bit ? 64 : 32
        let mask: UInt64 = width == 64 ? UInt64.max : 0xffff_ffff
        let unsigned = UInt64(bitPattern: value) & mask

        if unsigned <= 0xffff {
            return try moveWide(ParsedInstruction(mnemonic: "movz", operands: instruction.operands, original: instruction.original), mnemonic: "movz")
        }

        for shift in stride(from: 0, through: width - 16, by: 16) {
            if unsigned & ~(UInt64(0xffff) << UInt64(shift)) == 0 {
                return try moveWide(
                    ParsedInstruction(mnemonic: "movz", operands: [instruction.operands[0], "#\((unsigned >> UInt64(shift)) & 0xffff)", "lsl #\(shift)"], original: instruction.original),
                    mnemonic: "movz"
                )
            }
        }

        let inverted = (~unsigned) & mask
        if inverted <= 0xffff {
            return try moveWide(ParsedInstruction(mnemonic: "movn", operands: [instruction.operands[0], "#\(inverted)"], original: instruction.original), mnemonic: "movn")
        }

        for shift in stride(from: 0, through: width - 16, by: 16) {
            if inverted & ~(UInt64(0xffff) << UInt64(shift)) == 0 {
                return try moveWide(
                    ParsedInstruction(mnemonic: "movn", operands: [instruction.operands[0], "#\((inverted >> UInt64(shift)) & 0xffff)", "lsl #\(shift)"], original: instruction.original),
                    mnemonic: "movn"
                )
            }
        }

        return try A64LogicalEncoder.immediate(
            ParsedInstruction(mnemonic: "orr", operands: [instruction.operands[0], rd.is64Bit ? "xzr" : "wzr", instruction.operands[1]], original: instruction.original),
            mnemonic: "orr"
        )
    }

    static func moveWide(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        try expectOperandCount(instruction, 2...3)
        let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        let imm = try A64Parser.immediate(instruction.operands[1])
        try checkRange(imm, 0...0xffff, instruction: mnemonic)
        var shift = 0
        if instruction.operands.count == 3 {
            let parsed = try A64Parser.shift(instruction.operands[2])
            guard parsed.0 == .lsl else { throw AssemblerError.unsupportedShift(instruction.operands[2]) }
            shift = parsed.1
        }
        guard shift % 16 == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: Int64(shift), alignment: 16) }
        guard rd.is64Bit || shift <= 16 else { throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: Int64(shift), range: 0...16) }
        let opc: UInt32 = mnemonic == "movn" ? 0 : mnemonic == "movz" ? 2 : 3
        return ((rd.is64Bit ? UInt32(1) : 0) << 31) | (opc << 29) | 0x12800000 | (UInt32(shift / 16) << 21) | (UInt32(imm) << 5) | rd.encodedNumber
    }
}

private enum A64LogicalEncoder {
    static func immediate(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 3)
        let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
        guard rd.width == rn.width else { throw AssemblerError.invalidRegister(instruction.original) }
        let imm = try A64Parser.immediate(instruction.operands[2])
        let width = rd.is64Bit ? 64 : 32
        let mask: UInt64 = width == 64 ? UInt64.max : 0xffff_ffff
        let value = UInt64(bitPattern: imm) & mask
        guard let encoding = A64BitmaskImmediate.encode(value, width: width) else {
            throw AssemblerError.invalidImmediate(instruction.operands[2])
        }

        let opc: UInt32
        switch mnemonic {
        case "and": opc = 0
        case "orr": opc = 1
        case "eor": opc = 2
        case "ands": opc = 3
        default: throw AssemblerError.unknownInstruction(mnemonic)
        }

        return ((rd.is64Bit ? UInt32(1) : 0) << 31)
        | (opc << 29)
        | 0x12000000
        | (encoding.n << 22)
        | (encoding.immr << 16)
        | (encoding.imms << 10)
        | (rn.encodedNumber << 5)
        | rd.encodedNumber
    }

    static func shiftedRegister(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        try expectOperandCount(instruction, 3...4)
        let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
        let rm = try A64Parser.integerRegister(instruction.operands[2], allowSP: false)
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(instruction.original) }
        var shiftKind: ShiftKind = .lsl
        var amount = 0
        if instruction.operands.count == 4 {
            let parsed = try A64Parser.shift(instruction.operands[3])
            shiftKind = parsed.0
            amount = parsed.1
        }
        guard rd.is64Bit || amount <= 31 else { throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: Int64(amount), range: 0...31) }
        let opc: UInt32
        let n: UInt32
        switch mnemonic {
        case "and": opc = 0; n = 0
        case "bic": opc = 0; n = 1
        case "orr": opc = 1; n = 0
        case "orn": opc = 1; n = 1
        case "eor": opc = 2; n = 0
        case "eon": opc = 2; n = 1
        case "ands": opc = 3; n = 0
        case "bics": opc = 3; n = 1
        default: throw AssemblerError.unknownInstruction(mnemonic)
        }
        return ((rd.is64Bit ? UInt32(1) : 0) << 31) | (opc << 29) | 0x0a000000 | (shiftKind.rawValue << 22) | (n << 21) | (rm.encodedNumber << 16) | (UInt32(amount) << 10) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func mvnAlias(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, 2...3)
        let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        return try shiftedRegister(
            ParsedInstruction(mnemonic: "orn", operands: [instruction.operands[0], rd.is64Bit ? "xzr" : "wzr"] + Array(instruction.operands.dropFirst()), original: instruction.original),
            mnemonic: "orn"
        )
    }
}

private enum A64MemoryOperandParser {
    static func parse(_ operands: [String], startIndex: Int) throws -> MemoryOperand {
        guard startIndex < operands.count else { throw AssemblerError.invalidMemoryOperand(operands.joined(separator: ", ")) }
        let first = operands[startIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard first.hasPrefix("["), let close = first.lastIndex(of: "]") else { throw AssemblerError.invalidMemoryOperand(first) }
        let inside = String(first[first.index(after: first.startIndex)..<close])
        let after = String(first[first.index(after: close)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let components = A64SourceParser.splitOperands(inside)
        guard let baseText = components.first else { throw AssemblerError.invalidMemoryOperand(first) }
        let base = try A64Parser.xRegisterAllowingSP(baseText)

        if !after.isEmpty {
            guard after == "!" else { throw AssemblerError.invalidMemoryOperand(first) }
            return .preIndexed(base: base, offset: components.count >= 2 ? try A64Parser.immediate(components[1]) : 0)
        }
        if operands.count > startIndex + 1 { return .postIndexed(base: base, offset: try A64Parser.immediate(operands[startIndex + 1])) }
        if components.count == 1 { return .unsignedOffset(base: base, offset: 0) }
        if components.count == 2 {
            if components[1].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") {
                let offset = try A64Parser.immediate(components[1])
                return offset >= 0 ? .unsignedOffset(base: base, offset: offset) : .signedUnscaled(base: base, offset: offset)
            }
            return .registerOffset(base: base, offset: try A64Parser.integerRegister(components[1], allowSP: false), extend: nil, shift: 0)
        }
        if components.count == 3 {
            let rm = try A64Parser.integerRegister(components[1], allowSP: false)
            if let first = components[2].split(separator: " ").first?.lowercased(), first == "lsl" {
                let parsed = try A64Parser.shift(components[2])
                return .registerOffset(base: base, offset: rm, extend: nil, shift: parsed.1)
            }
            let parsed = try A64Parser.extend(components[2])
            return .registerOffset(base: base, offset: rm, extend: parsed.0, shift: parsed.1)
        }
        throw AssemblerError.invalidMemoryOperand(first)
    }
}

private enum A64LoadStoreEncoder {
    static func single(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        try expectOperandCount(instruction, 2...3)
        let descriptor = try SingleDescriptor(mnemonic: mnemonic, rtText: instruction.operands[0])
        let rt = descriptor.rt
        let memory = try A64MemoryOperandParser.parse(instruction.operands, startIndex: 1)

        switch memory {
        case .unsignedOffset(let base, let offset):
            if descriptor.forceUnscaled {
                try checkRange(offset, -256...255, instruction: mnemonic)
                return descriptor.unscaledBase | ((UInt32(bitPattern: Int32(offset)) & 0x1ff) << 12) | (base.encodedNumber << 5) | rt.encodedNumber
            }
            guard offset >= 0, offset % descriptor.byteSize == 0 else {
                throw AssemblerError.immediateAlignment(instruction: mnemonic, value: offset, alignment: descriptor.byteSize)
            }
            let scaled = offset / descriptor.byteSize
            try checkRange(scaled, 0...0xfff, instruction: mnemonic)
            return descriptor.unsignedBase | (UInt32(scaled) << 10) | (base.encodedNumber << 5) | rt.encodedNumber

        case .signedUnscaled(let base, let offset), .preIndexed(let base, let offset), .postIndexed(let base, let offset):
            try checkRange(offset, -256...255, instruction: mnemonic)
            let mode: UInt32
            switch memory {
            case .signedUnscaled: mode = 0
            case .postIndexed: mode = 1
            case .preIndexed: mode = 3
            default: mode = 0
            }
            return descriptor.unscaledBase | ((UInt32(bitPattern: Int32(offset)) & 0x1ff) << 12) | (mode << 10) | (base.encodedNumber << 5) | rt.encodedNumber

        case .registerOffset(let base, let offset, let ext, let shift):
            let option = ext ?? (offset.is64Bit ? ExtendKind.uxtx : ExtendKind.uxtw)
            let naturalShift = Int(log2(Double(descriptor.byteSize)))
            guard shift == 0 || shift == naturalShift else { throw AssemblerError.unsupportedShift("lsl #\(shift)") }
            return descriptor.registerOffsetBase | (offset.encodedNumber << 16) | (option.rawValue << 13) | (UInt32(shift == 0 ? 0 : 1) << 12) | (base.encodedNumber << 5) | rt.encodedNumber
        }
    }

    static func pair(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        try expectOperandCount(instruction, 3...4)
        let rt = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        let rt2 = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
        guard rt.width == rt2.width else { throw AssemblerError.invalidRegister(instruction.original) }
        let memory = try A64MemoryOperandParser.parse(instruction.operands, startIndex: 2)
        let scale: Int64 = rt.is64Bit ? 8 : 4
        let modeBase: UInt32
        let base: IntegerRegister
        let offset: Int64
        switch memory {
        case .signedUnscaled(let b, let o), .unsignedOffset(let b, let o): modeBase = 0x29000000; base = b; offset = o
        case .postIndexed(let b, let o): modeBase = 0x28800000; base = b; offset = o
        case .preIndexed(let b, let o): modeBase = 0x29800000; base = b; offset = o
        case .registerOffset: throw AssemblerError.unsupportedOperand(instruction.original)
        }
        guard offset % scale == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: offset, alignment: scale) }
        let imm7 = offset / scale
        try checkRange(imm7, -64...63, instruction: mnemonic)
        return ((rt.is64Bit ? UInt32(2) : 0) << 30) | modeBase | ((mnemonic == "ldp" ? UInt32(1) : 0) << 22) | ((UInt32(bitPattern: Int32(imm7)) & 0x7f) << 15) | (rt2.encodedNumber << 10) | (base.encodedNumber << 5) | rt.encodedNumber
    }

    private struct SingleDescriptor {
        let rt: IntegerRegister
        let normalizedMnemonic: String
        let forceUnscaled: Bool
        let byteSize: Int64
        let size: UInt32
        let opc: UInt32

        init(mnemonic: String, rtText: String) throws {
            switch mnemonic {
            case "ldur": normalizedMnemonic = "ldr"; forceUnscaled = true
            case "ldurb": normalizedMnemonic = "ldrb"; forceUnscaled = true
            case "ldurh": normalizedMnemonic = "ldrh"; forceUnscaled = true
            case "ldursb": normalizedMnemonic = "ldrsb"; forceUnscaled = true
            case "ldursh": normalizedMnemonic = "ldrsh"; forceUnscaled = true
            case "ldursw": normalizedMnemonic = "ldrsw"; forceUnscaled = true
            case "stur": normalizedMnemonic = "str"; forceUnscaled = true
            case "sturb": normalizedMnemonic = "strb"; forceUnscaled = true
            case "sturh": normalizedMnemonic = "strh"; forceUnscaled = true
            default: normalizedMnemonic = mnemonic; forceUnscaled = false
            }

            rt = try A64Parser.integerRegister(rtText, allowSP: false)
            let isLoad = normalizedMnemonic.hasPrefix("ldr")
            switch normalizedMnemonic {
            case "strb", "ldrb": byteSize = 1; size = 0; opc = isLoad ? 1 : 0
            case "strh", "ldrh": byteSize = 2; size = 1; opc = isLoad ? 1 : 0
            case "str", "ldr": byteSize = rt.is64Bit ? 8 : 4; size = rt.is64Bit ? 3 : 2; opc = isLoad ? 1 : 0
            case "ldrsb": byteSize = 1; size = 0; opc = rt.is64Bit ? 2 : 3
            case "ldrsh": byteSize = 2; size = 1; opc = rt.is64Bit ? 2 : 3
            case "ldrsw": byteSize = 4; size = 2; opc = 2
            default: throw AssemblerError.unknownInstruction(mnemonic)
            }
        }

        var unsignedBase: UInt32 {
            (size << 30) | 0x39000000 | (opc << 22)
        }

        var unscaledBase: UInt32 {
            (size << 30) | 0x38000000 | (opc << 22)
        }

        var registerOffsetBase: UInt32 {
            (size << 30) | 0x38200800 | (opc << 22)
        }
    }
}

private enum A64BranchEncoder {
    static func unconditional(_ instruction: ParsedInstruction, mnemonic: String, pc: Int64, labels: [String: Int64]) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 1)
        let offset = try labelOrImmediateByteOffset(instruction.operands[0], pc: pc, labels: labels)
        guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: offset, alignment: 4) }
        let imm26 = offset / 4
        guard (-0x2000000...0x1ffffff).contains(imm26) else {
            throw AssemblerError.branchOutOfRange(instruction: mnemonic, label: instruction.operands[0], byteOffset: offset)
        }
        let base: UInt32 = mnemonic == "bl" ? 0x94000000 : 0x14000000
        return base | (UInt32(bitPattern: Int32(imm26)) & 0x03ff_ffff)
    }

    static func conditional(_ instruction: ParsedInstruction, conditionSuffix: String, pc: Int64, labels: [String: Int64]) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 1)
        let condition = try A64Parser.condition(conditionSuffix)
        let offset = try labelOrImmediateByteOffset(instruction.operands[0], pc: pc, labels: labels)
        guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: instruction.mnemonic, value: offset, alignment: 4) }
        let imm19 = offset / 4
        guard (-0x40000...0x3ffff).contains(imm19) else {
            throw AssemblerError.branchOutOfRange(instruction: instruction.mnemonic, label: instruction.operands[0], byteOffset: offset)
        }
        return 0x54000000 | ((UInt32(bitPattern: Int32(imm19)) & 0x7ffff) << 5) | condition.rawValue
    }

    static func compareAndBranch(_ instruction: ParsedInstruction, mnemonic: String, pc: Int64, labels: [String: Int64]) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 2)
        let rt = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        let offset = try labelOrImmediateByteOffset(instruction.operands[1], pc: pc, labels: labels)
        guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: offset, alignment: 4) }
        let imm19 = offset / 4
        guard (-0x40000...0x3ffff).contains(imm19) else {
            throw AssemblerError.branchOutOfRange(instruction: mnemonic, label: instruction.operands[1], byteOffset: offset)
        }
        return ((rt.is64Bit ? UInt32(1) : 0) << 31)
        | 0x34000000
        | ((mnemonic == "cbnz" ? UInt32(1) : 0) << 24)
        | ((UInt32(bitPattern: Int32(imm19)) & 0x7ffff) << 5)
        | rt.encodedNumber
    }

    static func testAndBranch(_ instruction: ParsedInstruction, mnemonic: String, pc: Int64, labels: [String: Int64]) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 3)
        let rt = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        let bit = try A64Parser.immediate(instruction.operands[1])
        try checkRange(bit, 0...(rt.is64Bit ? 63 : 31), instruction: mnemonic)
        let offset = try labelOrImmediateByteOffset(instruction.operands[2], pc: pc, labels: labels)
        guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: offset, alignment: 4) }
        let imm14 = offset / 4
        guard (-0x2000...0x1fff).contains(imm14) else {
            throw AssemblerError.branchOutOfRange(instruction: mnemonic, label: instruction.operands[2], byteOffset: offset)
        }
        return ((UInt32(bit >> 5) & 1) << 31)
        | 0x36000000
        | ((mnemonic == "tbnz" ? UInt32(1) : 0) << 24)
        | ((UInt32(bit) & 0x1f) << 19)
        | ((UInt32(bitPattern: Int32(imm14)) & 0x3fff) << 5)
        | rt.encodedNumber
    }
}

private enum A64AddSubEncoder {
    static func addSub(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        try expectOperandCount(instruction, 3...4)
        let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: mnemonic == "add" || mnemonic == "sub")
        let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: true)

        if instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") {
            return try immediate(instruction, mnemonic: mnemonic, rd: rd, rn: rn)
        }

        return try shiftedRegister(instruction, mnemonic: mnemonic, rd: rd, rn: rn)
    }

    static func compareAlias(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        try expectOperandCount(instruction, 2...3)
        let rn = try A64Parser.integerRegister(instruction.operands[0], allowSP: true)
        let zr = rn.is64Bit ? "xzr" : "wzr"
        let realMnemonic = mnemonic == "cmp" ? "subs" : "adds"
        return try addSub(
            ParsedInstruction(mnemonic: realMnemonic, operands: [zr] + instruction.operands, original: instruction.original),
            mnemonic: realMnemonic
        )
    }

    private static func immediate(_ instruction: ParsedInstruction, mnemonic: String, rd: IntegerRegister, rn: IntegerRegister) throws -> UInt32 {
        let imm = try A64Parser.immediate(instruction.operands[2])
        var shift = 0
        if instruction.operands.count == 4 {
            let parsed = try A64Parser.shift(instruction.operands[3])
            guard parsed.0 == .lsl, parsed.1 == 12 else { throw AssemblerError.unsupportedShift(instruction.operands[3]) }
            shift = 12
        }
        try checkRange(imm, 0...0xfff, instruction: mnemonic)
        return ((rd.is64Bit ? UInt32(1) : 0) << 31)
        | (((mnemonic == "sub" || mnemonic == "subs") ? UInt32(1) : 0) << 30)
        | (((mnemonic == "adds" || mnemonic == "subs") ? UInt32(1) : 0) << 29)
        | 0x11000000
        | (UInt32(shift == 12 ? 1 : 0) << 22)
        | (UInt32(imm) << 10)
        | (rn.encodedNumber << 5)
        | rd.encodedNumber
    }

    private static func shiftedRegister(_ instruction: ParsedInstruction, mnemonic: String, rd: IntegerRegister, rn: IntegerRegister) throws -> UInt32 {
        let rm = try A64Parser.integerRegister(instruction.operands[2], allowSP: false)
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(instruction.original) }
        var shiftKind: ShiftKind = .lsl
        var amount = 0
        if instruction.operands.count == 4 {
            let parsed = try A64Parser.shift(instruction.operands[3])
            shiftKind = parsed.0
            amount = parsed.1
        }
        guard shiftKind != .ror else { throw AssemblerError.unsupportedShift(instruction.operands.last ?? "") }
        return ((rd.is64Bit ? UInt32(1) : 0) << 31)
        | (((mnemonic == "sub" || mnemonic == "subs") ? UInt32(1) : 0) << 30)
        | (((mnemonic == "adds" || mnemonic == "subs") ? UInt32(1) : 0) << 29)
        | 0x0b000000
        | (shiftKind.rawValue << 22)
        | (rm.encodedNumber << 16)
        | (UInt32(amount) << 10)
        | (rn.encodedNumber << 5)
        | rd.encodedNumber
    }
}

private enum A64DataProcessingEncoder {
    static func shiftAlias(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 3)
        let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
        guard rd.width == rn.width else { throw AssemblerError.invalidRegister(instruction.original) }
        let amount = try A64Parser.immediate(instruction.operands[2])
        let maxShift: Int64 = rd.is64Bit ? 63 : 31
        try checkRange(amount, 0...maxShift, instruction: mnemonic)
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let n: UInt32 = rd.is64Bit ? 1 : 0
        let immr: UInt32
        let imms: UInt32
        switch mnemonic {
        case "lsl":
            immr = UInt32((Int(maxShift) + 1 - Int(amount)) & Int(maxShift))
            imms = UInt32(maxShift - amount)
        case "lsr":
            immr = UInt32(amount)
            imms = UInt32(maxShift)
        case "asr":
            immr = UInt32(amount)
            imms = UInt32(maxShift)
            return (sf << 31) | 0x13000000 | (n << 22) | (immr << 16) | (imms << 10) | (rn.encodedNumber << 5) | rd.encodedNumber
        default:
            throw AssemblerError.unknownInstruction(mnemonic)
        }
        return (sf << 31) | 0x53000000 | (n << 22) | (immr << 16) | (imms << 10) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func extract(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 4)
        let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
        let rm = try A64Parser.integerRegister(instruction.operands[2], allowSP: false)
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(instruction.original) }
        let amount = try A64Parser.immediate(instruction.operands[3])
        try checkRange(amount, 0...(rd.is64Bit ? 63 : 31), instruction: "extr")
        return ((rd.is64Bit ? UInt32(1) : 0) << 31)
        | 0x13800000
        | ((rd.is64Bit ? UInt32(1) : 0) << 22)
        | (rm.encodedNumber << 16)
        | (UInt32(amount) << 10)
        | (rn.encodedNumber << 5)
        | rd.encodedNumber
    }

    static func rorAlias(_ instruction: ParsedInstruction) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 3)
        return try extract(
            ParsedInstruction(mnemonic: "extr", operands: [instruction.operands[0], instruction.operands[1], instruction.operands[1], instruction.operands[2]], original: instruction.original)
        )
    }

    static func multiply(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        switch mnemonic {
        case "mul", "mneg":
            try expectOperandCount(instruction, exactly: 3)
            let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            let rm = try A64Parser.integerRegister(instruction.operands[2], allowSP: false)
            guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(instruction.original) }
            return ((rd.is64Bit ? UInt32(1) : 0) << 31)
            | 0x1b000000
            | (rm.encodedNumber << 16)
            | ((mnemonic == "mneg" ? UInt32(1) : 0) << 15)
            | (31 << 10)
            | (rn.encodedNumber << 5)
            | rd.encodedNumber
        case "madd", "msub":
            try expectOperandCount(instruction, exactly: 4)
            let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            let rm = try A64Parser.integerRegister(instruction.operands[2], allowSP: false)
            let ra = try A64Parser.integerRegister(instruction.operands[3], allowSP: false)
            guard rd.width == rn.width, rn.width == rm.width, rm.width == ra.width else { throw AssemblerError.invalidRegister(instruction.original) }
            return ((rd.is64Bit ? UInt32(1) : 0) << 31)
            | 0x1b000000
            | (rm.encodedNumber << 16)
            | ((mnemonic == "msub" ? UInt32(1) : 0) << 15)
            | (ra.encodedNumber << 10)
            | (rn.encodedNumber << 5)
            | rd.encodedNumber
        default:
            throw AssemblerError.unknownInstruction(mnemonic)
        }
    }

    static func divide(_ instruction: ParsedInstruction, mnemonic: String) throws -> UInt32 {
        try expectOperandCount(instruction, exactly: 3)
        let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
        let rm = try A64Parser.integerRegister(instruction.operands[2], allowSP: false)
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(instruction.original) }
        return ((rd.is64Bit ? UInt32(1) : 0) << 31)
        | 0x1ac00800
        | ((mnemonic == "sdiv" ? UInt32(1) : 0) << 10)
        | (rm.encodedNumber << 16)
        | (rn.encodedNumber << 5)
        | rd.encodedNumber
    }
}

private func encodeInstruction(_ instruction: ParsedInstruction, pc: Int64, labels: [String: Int64], architecture: ARM64Assembler.Architecture) throws -> UInt32 {
    let parts = instruction.mnemonic.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    let mnemonic = parts[0]
    let suffix = parts.count > 1 ? parts[1] : nil

    if let structuredInstruction = try A64InstructionParser.instruction(instruction, pc: pc, labels: labels) {
        return try A64InstructionEncoder.encode(structuredInstruction)
    }

    switch mnemonic {
    case "nop":
        try expectOperandCount(instruction, exactly: 0)
        return 0xd503201f
    case "ret":
        return try A64BranchRegisterEncoder.ret(instruction)
    case "br":
        return try A64BranchRegisterEncoder.br(instruction)
    case "blr":
        return try A64BranchRegisterEncoder.blr(instruction)
    case "svc":
        return try A64ExceptionEncoder.supervisorCall(instruction)
    case "brk":
        return try A64ExceptionEncoder.breakpoint(instruction)
    case "hlt":
        return try A64ExceptionEncoder.halt(instruction)
    case "eret":
        return try A64ExceptionEncoder.exceptionReturn(instruction)
    case "isb", "dsb", "dmb":
        return try A64SystemEncoder.barrier(instruction, mnemonic: mnemonic)
    case "b":
        if let suffix {
            return try A64BranchEncoder.conditional(instruction, conditionSuffix: suffix, pc: pc, labels: labels)
        }
        return try A64BranchEncoder.unconditional(instruction, mnemonic: mnemonic, pc: pc, labels: labels)
    case "bl":
        return try A64BranchEncoder.unconditional(instruction, mnemonic: mnemonic, pc: pc, labels: labels)
    case "cbz", "cbnz":
        return try A64BranchEncoder.compareAndBranch(instruction, mnemonic: mnemonic, pc: pc, labels: labels)
    case "tbz", "tbnz":
        return try A64BranchEncoder.testAndBranch(instruction, mnemonic: mnemonic, pc: pc, labels: labels)
    case "mov":
        return try A64MoveEncoder.movAlias(instruction)
    case "movz", "movn", "movk":
        return try A64MoveEncoder.moveWide(instruction, mnemonic: mnemonic)
    case "adr", "adrp":
        return try A64AddressEncoder.adr(instruction, mnemonic: mnemonic, pc: pc, labels: labels)
    case "add", "adds", "sub", "subs":
        return try A64AddSubEncoder.addSub(instruction, mnemonic: mnemonic)
    case "cmp", "cmn":
        return try A64AddSubEncoder.compareAlias(instruction, mnemonic: mnemonic)
    case "and", "ands", "orr", "eor", "bic", "bics", "orn", "eon":
        if instruction.operands.count >= 3, instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") {
            guard ["and", "ands", "orr", "eor"].contains(mnemonic) else {
                throw AssemblerError.unsupportedOperand(instruction.original)
            }
            return try A64LogicalEncoder.immediate(instruction, mnemonic: mnemonic)
        }
        return try A64LogicalEncoder.shiftedRegister(instruction, mnemonic: mnemonic)
    case "mvn":
        return try A64LogicalEncoder.mvnAlias(instruction)
    case "lsl", "lsr", "asr":
        return try A64DataProcessingEncoder.shiftAlias(instruction, mnemonic: mnemonic)
    case "extr", "ror":
        return try mnemonic == "ror" ? A64DataProcessingEncoder.rorAlias(instruction) : A64DataProcessingEncoder.extract(instruction)
    case "mul", "mneg", "madd", "msub":
        return try A64DataProcessingEncoder.multiply(instruction, mnemonic: mnemonic)
    case "udiv", "sdiv":
        return try A64DataProcessingEncoder.divide(instruction, mnemonic: mnemonic)
    case "ldr", "ldrb", "ldrh", "ldrsb", "ldrsh", "ldrsw", "str", "strb", "strh", "ldur", "ldurb", "ldurh", "ldursb", "ldursh", "ldursw", "stur", "sturb", "sturh":
        return try A64LoadStoreEncoder.single(instruction, mnemonic: mnemonic)
    case "ldp", "stp":
        return try A64LoadStoreEncoder.pair(instruction, mnemonic: mnemonic)
    case "paciasp", "autiasp", "pacibsp", "autibsp", "xpaci", "xpacd":
        return try A64PointerAuthenticationEncoder.encode(instruction, mnemonic: mnemonic, architecture: architecture)
    default:
        throw AssemblerError.unknownInstruction(instruction.mnemonic)
    }
}

private func encode(_ instruction: ParsedInstruction, pc: Int64, labels: [String: Int64], architecture: ARM64Assembler.Architecture) throws -> UInt32 {
    try A64InstructionEncoder.encode(instruction, pc: pc, labels: labels, architecture: architecture)
}

private func requireARM64E(_ architecture: ARM64Assembler.Architecture, instruction: String) throws {
    guard architecture == .arm64e else { throw AssemblerError.unknownInstruction("\(instruction) requires arm64e") }
}

private func expectOperandCount(_ instruction: ParsedInstruction, exactly count: Int) throws {
    guard instruction.operands.count == count else {
        throw AssemblerError.invalidOperandCount(instruction: instruction.mnemonic, expected: "\(count)", actual: instruction.operands.count)
    }
}

private func expectOperandCount(_ instruction: ParsedInstruction, _ range: ClosedRange<Int>) throws {
    guard range.contains(instruction.operands.count) else {
        throw AssemblerError.invalidOperandCount(instruction: instruction.mnemonic, expected: "\(range.lowerBound)...\(range.upperBound)", actual: instruction.operands.count)
    }
}

private func checkRange(_ value: Int64, _ range: ClosedRange<Int64>, instruction: String) throws {
    guard range.contains(value) else { throw AssemblerError.immediateOutOfRange(instruction: instruction, value: value, range: range) }
}

private func labelOrImmediateByteOffset(_ text: String, pc: Int64, labels: [String: Int64]) throws -> Int64 {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let target = labels[trimmed] { return target - pc }
    return try A64Parser.immediate(trimmed)
}
