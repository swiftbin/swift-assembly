import Foundation

internal enum A64Parser {
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

    static func floatRegister(_ text: String) throws -> A64.FPRegister {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.count >= 2 else { throw AssemblerError.invalidRegister(text) }
        let width: Int
        switch lower.first! {
        case "b": width = 8
        case "h": width = 16
        case "s": width = 32
        case "d": width = 64
        case "q": width = 128
        default: throw AssemblerError.invalidRegister(text)
        }
        guard let number = UInt32(lower.dropFirst()), number <= 31 else { throw AssemblerError.invalidRegister(text) }
        return A64.FPRegister(number: number, width: width)
    }

    enum AnyRegister {
        case float(A64.FPRegister)
        case general(A64.Register)
    }

    /// Classifies a register operand as scalar floating-point or general purpose.
    static func anyRegister(_ text: String) throws -> AnyRegister {
        if let register = try? floatRegister(text) {
            return .float(register)
        }
        return .general(try integerRegister(text, allowSP: false))
    }

    static func vectorRegister(_ text: String) throws -> A64.VectorRegister {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = lower.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let prefix = parts[0].first, prefix == "v",
              let number = UInt32(parts[0].dropFirst()), number <= 31,
              let arrangement = A64.VectorArrangement(rawValue: parts[1]) else {
            throw AssemblerError.invalidRegister(text)
        }
        return A64.VectorRegister(number: number, arrangement: arrangement)
    }

    static func floatImmediate(_ text: String) throws -> Double {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard let parsed = Double(value) else { throw AssemblerError.invalidImmediate(text) }
        return parsed
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

internal enum A64InstructionParser {
    static func instruction(
        _ instruction: ParsedInstruction,
        pc: Int64,
        labels: [String: Int64],
        architecture: ARM64Assembler.Architecture
    ) throws -> Instruction? {
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
        case "mov":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let destination = try A64Parser.integerRegister(instruction.operands[0], allowSP: true)
            let sourceText = instruction.operands[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let source: A64.MoveAliasSource = sourceText.hasPrefix("#")
                ? .immediate(try A64Parser.immediate(sourceText))
                : .register(try A64Parser.integerRegister(sourceText, allowSP: true))
            return .moveAlias(destination: destination, source: source)
        case "movz", "movn", "movk":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 2...3)
            let shift = try instruction.operands.count == 3 ? moveWideShift(instruction.operands[2]) : nil
            return .moveWide(
                A64.MoveWideKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                immediate: try A64Parser.immediate(instruction.operands[1]),
                shift: shift
            )
        case "add", "adds", "sub", "subs":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 3...4)
            return .addSub(
                A64.AddSubKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: mnemonic == "add" || mnemonic == "sub"),
                first: try A64Parser.integerRegister(instruction.operands[1], allowSP: true),
                operand: try addSubOperand(instruction, startIndex: 2)
            )
        case "cmp", "cmn":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 2...3)
            return .compareAlias(
                A64.CompareAliasKind(rawValue: mnemonic)!,
                first: try A64Parser.integerRegister(instruction.operands[0], allowSP: true),
                operand: try addSubOperand(instruction, startIndex: 1)
            )
        case "and", "ands", "orr", "eor", "bic", "bics", "orn", "eon":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 3...4)
            return .logical(
                A64.LogicalKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                first: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                operand: try logicalOperand(instruction)
            )
        case "mvn":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 2...3)
            if instruction.operands.count == 2, operandsAreVectorRegisters(instruction) {
                return .vectorTwoRegisterMisc(
                    .mvn,
                    destination: try A64Parser.vectorRegister(instruction.operands[0]),
                    source: try A64Parser.vectorRegister(instruction.operands[1])
                )
            }
            return .mvnAlias(
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                shift: try instruction.operands.count == 3 ? shift(instruction.operands[2]) : nil
            )
        case "lsl", "lsr", "asr":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            return .shiftAlias(
                A64.ShiftAliasKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                amount: try A64Parser.immediate(instruction.operands[2])
            )
        case "extr", "ror":
            guard parts.count == 1 else { return nil }
            let kind = A64.ExtractKind(rawValue: mnemonic)!
            try expectOperandCount(instruction, exactly: kind == .ror ? 3 : 4)
            let destination = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let first = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            let operand: A64.ExtractOperand
            if kind == .ror {
                operand = .rotate(amount: try A64Parser.immediate(instruction.operands[2]))
            } else {
                operand = .extract(try A64Parser.integerRegister(instruction.operands[2], allowSP: false), amount: try A64Parser.immediate(instruction.operands[3]))
            }
            return .extractOrRotateAlias(kind, destination: destination, first: first, operand: operand)
        case "mul", "mneg", "madd", "msub":
            guard parts.count == 1 else { return nil }
            let kind = A64.MultiplyKind(rawValue: mnemonic)!
            try expectOperandCount(instruction, exactly: (kind == .madd || kind == .msub) ? 4 : 3)
            return .multiply(
                kind,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                first: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                second: try A64Parser.integerRegister(instruction.operands[2], allowSP: false),
                accumulator: try instruction.operands.count == 4 ? A64Parser.integerRegister(instruction.operands[3], allowSP: false) : nil
            )
        case "udiv", "sdiv":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            return .divide(
                A64.DivideKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                first: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                second: try A64Parser.integerRegister(instruction.operands[2], allowSP: false)
            )
        case "ldr", "ldrb", "ldrh", "ldrsb", "ldrsh", "ldrsw", "str", "strb", "strh", "ldur", "ldurb", "ldurh", "ldursb", "ldursh", "ldursw", "stur", "sturb", "sturh":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 2...3)
            return .loadStoreSingle(
                A64.LoadStoreSingleKind(rawValue: mnemonic)!,
                target: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                memory: try A64MemoryOperandParser.parse(instruction.operands, startIndex: 1)
            )
        case "ldp", "stp":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 3...4)
            return .loadStorePair(
                A64.LoadStorePairKind(rawValue: mnemonic)!,
                first: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                second: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                memory: try A64MemoryOperandParser.parse(instruction.operands, startIndex: 2)
            )
        case "paciasp", "autiasp", "pacibsp", "autibsp", "xpaci", "xpacd":
            guard parts.count == 1 else { return nil }
            let kind = A64.PointerAuthenticationKind(rawValue: mnemonic)!
            try expectOperandCount(instruction, exactly: (kind == .xpaci || kind == .xpacd) ? 1 : 0)
            return .pointerAuthentication(
                kind,
                register: try instruction.operands.first.map(A64Parser.xRegister),
                architecture: architecture
            )
        case "fadd", "fsub", "fmul", "fdiv", "fmax", "fmin", "fmaxnm", "fminnm", "fnmul":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            return .fpDataProcessing2(
                A64.FPDataProcessing2Kind(rawValue: mnemonic)!,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                first: try A64Parser.floatRegister(instruction.operands[1]),
                second: try A64Parser.floatRegister(instruction.operands[2])
            )
        case "fabs", "fneg", "fsqrt":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            if operandsAreVectorRegisters(instruction) {
                return .vectorTwoRegisterMisc(
                    A64.VectorTwoRegisterMiscKind(rawValue: mnemonic)!,
                    destination: try A64Parser.vectorRegister(instruction.operands[0]),
                    source: try A64Parser.vectorRegister(instruction.operands[1])
                )
            }
            return .fpDataProcessing1(
                A64.FPDataProcessing1Kind(rawValue: mnemonic)!,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1])
            )
        case "fcvt":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .fpConvertPrecision(
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1])
            )
        case "fmadd", "fmsub", "fnmadd", "fnmsub":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            return .fpDataProcessing3(
                A64.FPDataProcessing3Kind(rawValue: mnemonic)!,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                first: try A64Parser.floatRegister(instruction.operands[1]),
                second: try A64Parser.floatRegister(instruction.operands[2]),
                third: try A64Parser.floatRegister(instruction.operands[3])
            )
        case "fcmp", "fcmpe":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let first = try A64Parser.floatRegister(instruction.operands[0])
            let secondText = instruction.operands[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let second: A64.FPCompareOperand
            if secondText.hasPrefix("#") {
                guard try A64Parser.floatImmediate(secondText) == 0 else { throw AssemblerError.invalidImmediate(secondText) }
                second = .zero
            } else {
                second = .register(try A64Parser.floatRegister(secondText))
            }
            return .fpCompare(A64.FPCompareKind(rawValue: mnemonic)!, first: first, second: second)
        case "fmov":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let destinationText = instruction.operands[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceText = instruction.operands[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if sourceText.hasPrefix("#") {
                return .fpMoveImmediate(
                    destination: try A64Parser.floatRegister(destinationText),
                    value: try A64Parser.floatImmediate(sourceText)
                )
            }
            switch (try A64Parser.anyRegister(destinationText), try A64Parser.anyRegister(sourceText)) {
            case (.float(let rd), .float(let rn)):
                return .fpDataProcessing1(.fmov, destination: rd, source: rn)
            case (.general(let rd), .float(let rn)):
                return .fpMoveToGeneral(destination: rd, source: rn)
            case (.float(let rd), .general(let rn)):
                return .fpMoveFromGeneral(destination: rd, source: rn)
            case (.general, .general):
                throw AssemblerError.invalidRegister("fmov")
            }
        case "fcvtzs", "fcvtzu":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .fpConvertToInt(
                A64.FPConvertToIntKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                source: try A64Parser.floatRegister(instruction.operands[1])
            )
        case "scvtf", "ucvtf":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .fpConvertFromInt(
                A64.FPConvertFromIntKind(rawValue: mnemonic)!,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            )
        case "saddlv", "uaddlv", "smaxv", "umaxv", "sminv", "uminv", "addv":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .acrossLanesInteger(
                A64.AcrossLanesIntegerKind(rawValue: mnemonic)!,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
        case "fmaxv", "fminv", "fmaxnmv", "fminnmv":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .acrossLanesFP(
                A64.AcrossLanesFPKind(rawValue: mnemonic)!,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
        case "rev64", "rev32", "rev16", "abs", "neg", "not", "rbit", "cnt", "cls", "clz", "sqabs", "sqneg":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let kind = mnemonic == "not" ? A64.VectorTwoRegisterMiscKind.mvn : A64.VectorTwoRegisterMiscKind(rawValue: mnemonic)!
            return .vectorTwoRegisterMisc(
                kind,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
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

    private static func moveWideShift(_ text: String) throws -> Int {
        let parsed = try A64Parser.shift(text)
        guard parsed.0 == .lsl else { throw AssemblerError.unsupportedShift(text) }
        return parsed.1
    }

    private static func shift(_ text: String) throws -> ParsedShift {
        let parsed = try A64Parser.shift(text)
        return ParsedShift(kind: parsed.0, amount: parsed.1)
    }

    private static func addSubOperand(_ instruction: ParsedInstruction, startIndex: Int) throws -> A64.AddSubOperand {
        if instruction.operands[startIndex].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") {
            let immediate = try A64Parser.immediate(instruction.operands[startIndex])
            let shift = try instruction.operands.count > startIndex + 1 ? moveWideShift(instruction.operands[startIndex + 1]) : nil
            return .immediate(immediate, shift: shift)
        }

        let register = try A64Parser.integerRegister(instruction.operands[startIndex], allowSP: false)
        let parsedShift = try instruction.operands.count > startIndex + 1 ? shift(instruction.operands[startIndex + 1]) : nil
        return .shiftedRegister(register, shift: parsedShift)
    }

    private static func logicalOperand(_ instruction: ParsedInstruction) throws -> A64.LogicalOperand {
        if instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") {
            return .immediate(try A64Parser.immediate(instruction.operands[2]))
        }

        return .shiftedRegister(
            try A64Parser.integerRegister(instruction.operands[2], allowSP: false),
            shift: try instruction.operands.count == 4 ? shift(instruction.operands[3]) : nil
        )
    }

    private static func operandsAreVectorRegisters(_ instruction: ParsedInstruction) -> Bool {
        guard instruction.operands.count == 2 else { return false }
        return instruction.operands.allSatisfy {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.hasPrefix("v") && trimmed.contains(".")
        }
    }
}

internal enum A64MemoryOperandParser {
    static func parse(_ operands: [String], startIndex: Int) throws -> MemoryOperand {
        guard startIndex < operands.count else { throw AssemblerError.invalidMemoryOperand(operands.joined(separator: ", ")) }
        let first = operands[startIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard first.hasPrefix("["), let close = first.lastIndex(of: "]") else { throw AssemblerError.invalidMemoryOperand(first) }
        let inside = String(first[first.index(after: first.startIndex)..<close])
        let after = String(first[first.index(after: close)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let components = SourceParser.splitOperands(inside)
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
