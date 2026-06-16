import Foundation

internal enum X86Parser {
    /// Lower the parsed source line into an `X86.Instruction`.
    static func parse(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        if let kind = X86.ZeroOperandKind.resolve(mnemonic: instruction.mnemonic) {
            guard instruction.operands.isEmpty else {
                throw AssemblerError.invalidOperandCount(
                    instruction: instruction.mnemonic,
                    expected: "no operands",
                    actual: instruction.operands.count
                )
            }
            return .zeroOperand(kind)
        }
        if instruction.mnemonic == "mov" {
            return try parseMov(instruction)
        }
        if let kind = X86.BinaryAluKind(rawValue: instruction.mnemonic) {
            let (dst, src) = try parseReadWritePair(instruction)
            return .binaryAlu(kind, destination: dst, source: src)
        }
        if let kind = X86.UnaryAluKind(rawValue: instruction.mnemonic) {
            return try parseUnaryAlu(kind, instruction)
        }
        if instruction.mnemonic == "test" {
            let (lhs, rhs) = try parseReadWritePair(instruction)
            return .test(left: lhs, right: rhs)
        }
        if let kind = X86.ShiftKind.resolve(mnemonic: instruction.mnemonic) {
            return try parseShift(kind, instruction)
        }
        if let kind = X86.DoubleShiftKind(rawValue: instruction.mnemonic) {
            return try parseDoubleShift(kind, instruction)
        }
        if instruction.mnemonic == "jmp" {
            return try parseJumpOrCall(instruction, isCall: false)
        }
        if instruction.mnemonic == "call" {
            return try parseJumpOrCall(instruction, isCall: true)
        }
        if instruction.mnemonic == "enter" {
            return try parseEnter(instruction)
        }
        if instruction.mnemonic == "imul" {
            return try parseImul(instruction)
        }
        if let kind = X86.MulDivKind(rawValue: instruction.mnemonic), kind != .imul {
            return try parseMulDivOneOperand(kind, instruction)
        }
        if instruction.mnemonic == "push" {
            return try parsePush(instruction)
        }
        if instruction.mnemonic == "pop" {
            return try parsePop(instruction)
        }
        if instruction.mnemonic == "lea" {
            return try parseLea(instruction)
        }
        if let kind = X86.LoopKind.resolve(mnemonic: instruction.mnemonic) {
            return .loop(kind, try parseSingleBranchTarget(instruction))
        }
        if instruction.mnemonic.hasPrefix("j"),
           let cond = X86.Condition.resolve(suffix: String(instruction.mnemonic.dropFirst())) {
            return .conditionalJump(cond, try parseSingleBranchTarget(instruction))
        }
        throw AssemblerError.unknownInstruction(instruction.mnemonic)
    }

    private static func parseSingleBranchTarget(_ instruction: ParsedInstruction) throws -> X86.BranchTarget {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: instruction.mnemonic,
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let trimmed = instruction.operands[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return try parseRelativeTarget(trimmed, mnemonic: instruction.mnemonic)
    }

    /// `jmp` and `call` accept either a relative branch target (numeric
    /// delta or label name) or an indirect register/memory operand. We
    /// classify the operand here so the parser can dispatch into the
    /// right `Instruction` case.
    private static func parseJumpOrCall(_ instruction: ParsedInstruction, isCall: Bool) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: instruction.mnemonic,
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let operand = instruction.operands[0].trimmingCharacters(in: .whitespacesAndNewlines)

        // Indirect: bracketed memory expression, optionally prefixed by a
        // size hint. Long-mode JMP/CALL is always r/m64, so any hint that
        // disagrees with qword is rejected.
        if let (width, body) = stripSizeHintForIndirect(operand) {
            let memory = try memoryOperand(body)
            try requireIndirectQwordWidth(width, mnemonic: instruction.mnemonic)
            let target: X86.RegisterOrMemory = .memory(memory, width: .qword)
            return isCall ? .callIndirect(target: target) : .jumpIndirect(target: target)
        }
        if operand.hasPrefix("[") {
            let memory = try memoryOperand(operand)
            let target: X86.RegisterOrMemory = .memory(memory, width: .qword)
            return isCall ? .callIndirect(target: target) : .jumpIndirect(target: target)
        }
        if let reg = try? register(operand) {
            guard reg.width == .qword else {
                throw AssemblerError.unsupportedOperand(
                    "\(instruction.mnemonic): indirect target must be 64-bit"
                )
            }
            return isCall ? .callIndirect(target: .register(reg)) : .jumpIndirect(target: .register(reg))
        }

        // Otherwise relative: numeric offset or label.
        let target = try parseRelativeTarget(operand, mnemonic: instruction.mnemonic)
        return isCall ? .call(target) : .jump(target)
    }

    private static func stripSizeHintForIndirect(_ text: String) -> (width: X86.RegisterWidth, body: String)? {
        guard let (width, rest) = stripSizeHint(text) else { return nil }
        return (width, rest)
    }

    private static func requireIndirectQwordWidth(_ width: X86.RegisterWidth, mnemonic: String) throws {
        guard width == .qword else {
            throw AssemblerError.unsupportedOperand(
                "\(mnemonic): indirect target must be 64-bit (got \(width.rawValue)-bit)"
            )
        }
    }

    /// Parse a relative branch operand. A numeric immediate is interpreted
    /// as a rel field — the byte delta from the end of the instruction,
    /// the exact value written into the encoding. Anything else is taken
    /// as a label name.
    private static func parseRelativeTarget(_ text: String, mnemonic: String) throws -> X86.BranchTarget {
        if let value = try? immediateAny(text) {
            return .offset(value)
        }
        guard isLabelName(text) else {
            throw AssemblerError.unsupportedOperand("\(mnemonic): invalid branch target `\(text)`")
        }
        return .label(text)
    }

    private static func parseMulDivOneOperand(_ kind: X86.MulDivKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let classified = try classifyOperand(instruction.operands[0])
        switch classified {
        case .register(let r):
            return .mulDiv(kind, target: .register(r))
        case .memory(let m, let explicit):
            guard let width = explicit else {
                throw AssemblerError.unsupportedOperand(
                    "\(kind.rawValue) mem requires an explicit size hint (e.g. `qword ptr [...]`)"
                )
            }
            return .mulDiv(kind, target: .memory(m, width: width))
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): target cannot be an immediate")
        }
    }

    /// IMUL dispatches by operand count: 1 → mulDiv; 2 → 0F AF /r;
    /// 3 → 6B/69 /r imm.
    private static func parseImul(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        switch instruction.operands.count {
        case 1:
            return try parseMulDivOneOperand(.imul, instruction)
        case 2:
            return try parseImulTwoOperand(instruction)
        case 3:
            return try parseImulThreeOperand(instruction)
        default:
            throw AssemblerError.invalidOperandCount(
                instruction: "imul",
                expected: "1, 2, or 3 operands",
                actual: instruction.operands.count
            )
        }
    }

    private static func parseImulTwoOperand(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        let destination = try register(instruction.operands[0])
        guard destination.width != .byte else {
            throw AssemblerError.unsupportedOperand("imul: 2-operand form requires word/dword/qword")
        }
        let source = try parseImulSource(instruction.operands[1], paired: destination.width)
        return .imulRegister(destination: destination, source: source)
    }

    private static func parseImulThreeOperand(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        let destination = try register(instruction.operands[0])
        guard destination.width != .byte else {
            throw AssemblerError.unsupportedOperand("imul: 3-operand form requires word/dword/qword")
        }
        let source = try parseImulSource(instruction.operands[1], paired: destination.width)
        let immediate = try immediateAny(instruction.operands[2])
        try validateImmediateRange(immediate, width: destination.width, mnemonic: "imul")
        return .imulImmediate(destination: destination, source: source, immediate: immediate)
    }

    private static func parseImulSource(_ text: String, paired: X86.RegisterWidth) throws -> X86.RegisterOrMemory {
        let classified = try classifyOperand(text)
        switch classified {
        case .register(let r):
            try checkWidthsMatch(r.width, paired, mnemonic: "imul")
            return .register(r)
        case .memory(let m, let explicit):
            let width = try resolveMemoryWidth(explicit: explicit, paired: paired, mnemonic: "imul")
            return .memory(m, width: width)
        case .immediate:
            throw AssemblerError.unsupportedOperand("imul: source cannot be an immediate")
        }
    }

    private static func parsePush(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "push",
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let classified = try classifyOperand(instruction.operands[0])
        switch classified {
        case .register(let r):
            try validatePushPopWidth(r.width, mnemonic: "push")
            return .push(.register(r))
        case .memory(let m, let explicit):
            // Long-mode default is qword; the 0x66 prefix selects word.
            let width = explicit ?? .qword
            try validatePushPopWidth(width, mnemonic: "push")
            return .push(.memory(m, width: width))
        case .immediate(let imm):
            // No imm64 form. Sign-extended imm32 is the widest available.
            guard imm >= Int64(Int32.min) && imm <= Int64(Int32.max) else {
                throw AssemblerError.immediateOutOfRange(
                    instruction: "push",
                    value: imm,
                    range: Int64(Int32.min)...Int64(Int32.max)
                )
            }
            return .push(.immediate(imm))
        }
    }

    private static func parsePop(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "pop",
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let classified = try classifyOperand(instruction.operands[0])
        switch classified {
        case .register(let r):
            try validatePushPopWidth(r.width, mnemonic: "pop")
            return .pop(.register(r))
        case .memory(let m, let explicit):
            let width = explicit ?? .qword
            try validatePushPopWidth(width, mnemonic: "pop")
            return .pop(.memory(m, width: width))
        case .immediate:
            throw AssemblerError.unsupportedOperand("pop: target cannot be an immediate")
        }
    }

    private static func validatePushPopWidth(_ width: X86.RegisterWidth, mnemonic: String) throws {
        guard width == .word || width == .qword else {
            throw AssemblerError.unsupportedOperand(
                "\(mnemonic): operand must be 16- or 64-bit in long mode"
            )
        }
    }

    private static func parseLea(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "lea",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try register(instruction.operands[0])
        guard dst.width != .byte else {
            throw AssemblerError.unsupportedOperand("lea: destination cannot be 8-bit")
        }
        let classified = try classifyOperand(instruction.operands[1])
        guard case .memory(let mem, _) = classified else {
            throw AssemblerError.unsupportedOperand("lea: source must be a memory reference")
        }
        return .lea(destination: dst, source: mem)
    }

    private static func parseEnter(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "enter",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let allocation = try immediateAny(instruction.operands[0])
        let nesting = try immediateAny(instruction.operands[1])
        guard allocation >= 0 && allocation <= 0xFFFF else {
            throw AssemblerError.immediateOutOfRange(instruction: "enter", value: allocation, range: 0...0xFFFF)
        }
        guard nesting >= 0 && nesting <= 0xFF else {
            throw AssemblerError.immediateOutOfRange(instruction: "enter", value: nesting, range: 0...0xFF)
        }
        return .enter(
            allocation: UInt16(truncatingIfNeeded: allocation),
            nestingLevel: UInt8(truncatingIfNeeded: nesting)
        )
    }

    private static func isLabelName(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        guard first.isLetter || first == "_" || first == "." else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "$" }
    }

    private static func parseShift(_ kind: X86.ShiftKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let target = try parseShiftTarget(instruction.operands[0], mnemonic: kind.rawValue)
        let count = try parseShiftCount(instruction.operands[1], mnemonic: kind.rawValue)
        return .shift(kind, target: target, count: count)
    }

    private static func parseDoubleShift(_ kind: X86.DoubleShiftKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let dstClassified = try classifyOperand(instruction.operands[0])
        let source = try register(instruction.operands[1])
        guard source.width != .byte else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): only word/dword/qword supported")
        }
        let target: X86.RegisterOrMemory
        switch dstClassified {
        case .register(let r):
            try checkWidthsMatch(r.width, source.width, mnemonic: kind.rawValue)
            target = .register(r)
        case .memory(let m, let explicit):
            let width = try resolveMemoryWidth(explicit: explicit, paired: source.width, mnemonic: kind.rawValue)
            target = .memory(m, width: width)
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination cannot be an immediate")
        }
        let count = try parseShiftCount(instruction.operands[2], mnemonic: kind.rawValue)
        if case .one = count {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): count must be CL or an explicit imm8")
        }
        return .doubleShift(kind, target: target, source: source, count: count)
    }

    private static func parseShiftTarget(_ text: String, mnemonic: String) throws -> X86.RegisterOrMemory {
        let classified = try classifyOperand(text)
        switch classified {
        case .register(let r):
            return .register(r)
        case .memory(let m, let explicit):
            guard let width = explicit else {
                throw AssemblerError.unsupportedOperand(
                    "\(mnemonic) mem requires an explicit size hint (e.g. `qword ptr [...]`)"
                )
            }
            return .memory(m, width: width)
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(mnemonic): target cannot be an immediate")
        }
    }

    private static func parseShiftCount(_ text: String, mnemonic: String) throws -> X86.ShiftCount {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "cl" { return .cl }
        let value = try immediateAny(text)
        guard value >= 0 && value <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: value, range: 0...255)
        }
        if value == 1 { return .one }
        return .immediate(UInt8(truncatingIfNeeded: value))
    }

    private static func parseUnaryAlu(_ kind: X86.UnaryAluKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let classified = try classifyOperand(instruction.operands[0])
        switch classified {
        case .register(let r):
            return .unaryAlu(kind, target: .register(r))
        case .memory(let m, let explicit):
            guard let width = explicit else {
                throw AssemblerError.unsupportedOperand(
                    "\(kind.rawValue) mem requires an explicit size hint (e.g. `qword ptr [...]`)"
                )
            }
            return .unaryAlu(kind, target: .memory(m, width: width))
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): target cannot be an immediate")
        }
    }

    // MARK: - MOV

    /// One of the three operand shapes that can appear in a 2-operand
    /// instruction. Memory operands may carry an explicit size hint from
    /// the source (`byte ptr [...]`, `qword ptr [...]`, etc.); when none
    /// is present, the width is inferred from the paired register.
    enum ClassifiedOperand {
        case register(X86.Register)
        case memory(X86.MemoryOperand, explicitWidth: X86.RegisterWidth?)
        case immediate(Int64)
    }

    private static func parseMov(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        let (dst, src) = try parseReadWritePair(instruction)
        return .mov(destination: dst, source: src)
    }

    /// Classify and validate the two operands of any instruction whose
    /// destination is `r/m` and source is `r/m/imm`: MOV, the 8 binary
    /// ALU ops, and TEST share this shape. Width inference and the
    /// "mem,imm needs a size hint" rule live here in one place.
    static func parseReadWritePair(_ instruction: ParsedInstruction) throws -> (X86.RegisterOrMemory, X86.Operand) {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: instruction.mnemonic,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try classifyOperand(instruction.operands[0])
        let src = try classifyOperand(instruction.operands[1])
        let mnemonic = instruction.mnemonic

        switch (dst, src) {
        case (.register(let d), .register(let s)):
            try checkWidthsMatch(d.width, s.width, mnemonic: mnemonic)
            return (.register(d), .register(s))

        case (.register(let d), .memory(let m, let explicit)):
            let width = try resolveMemoryWidth(explicit: explicit, paired: d.width, mnemonic: mnemonic)
            return (.register(d), .memory(m, width: width))

        case (.register(let d), .immediate(let v)):
            try validateImmediateRange(v, width: d.width, mnemonic: mnemonic)
            return (.register(d), .immediate(v))

        case (.memory(let m, let explicit), .register(let s)):
            let width = try resolveMemoryWidth(explicit: explicit, paired: s.width, mnemonic: mnemonic)
            return (.memory(m, width: width), .register(s))

        case (.memory(let m, let explicit), .immediate(let v)):
            guard let width = explicit else {
                throw AssemblerError.unsupportedOperand(
                    "\(mnemonic) mem, imm requires an explicit size hint (e.g. `qword ptr [...]`)"
                )
            }
            try validateImmediateRange(v, width: width, mnemonic: mnemonic)
            return (.memory(m, width: width), .immediate(v))

        case (.memory, .memory):
            throw AssemblerError.unsupportedOperand("\(mnemonic): cannot have two memory operands")

        case (.immediate, _):
            throw AssemblerError.unsupportedOperand("\(mnemonic): destination cannot be an immediate")
        }
    }

    /// Classify a single operand string. Recognises bracketed memory
    /// expressions (optionally prefixed by a size hint), registers, and
    /// numeric immediates.
    static func classifyOperand(_ text: String) throws -> ClassifiedOperand {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (width, memoryText) = stripSizeHint(trimmed) {
            return .memory(try memoryOperand(memoryText), explicitWidth: width)
        }
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed), explicitWidth: nil)
        }
        if let register = try? register(trimmed) {
            return .register(register)
        }
        let immediate = try immediateAny(trimmed)
        return .immediate(immediate)
    }

    /// Detect and strip a leading size hint such as `byte ptr` or `qword`.
    /// Returns `nil` if no recognised hint is present.
    private static func stripSizeHint(_ text: String) -> (width: X86.RegisterWidth, rest: String)? {
        let lower = text.lowercased()
        let hints: [(prefix: String, width: X86.RegisterWidth)] = [
            ("byte ptr",  .byte),
            ("word ptr",  .word),
            ("dword ptr", .dword),
            ("qword ptr", .qword),
            ("byte",  .byte),
            ("word",  .word),
            ("dword", .dword),
            ("qword", .qword),
        ]
        for (prefix, width) in hints {
            guard lower.hasPrefix(prefix) else { continue }
            let prefixEnd = text.index(text.startIndex, offsetBy: prefix.count)
            // The hint must be followed by whitespace and then a `[...]` body.
            guard prefixEnd < text.endIndex, text[prefixEnd].isWhitespace else { continue }
            let rest = text[prefixEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.hasPrefix("[") { return (width, rest) }
        }
        return nil
    }

    private static func checkWidthsMatch(_ a: X86.RegisterWidth, _ b: X86.RegisterWidth, mnemonic: String) throws {
        guard a == b else {
            throw AssemblerError.unsupportedOperand(
                "\(mnemonic) requires matching operand widths"
            )
        }
    }

    /// Reconcile an optional size hint with the width implied by a paired
    /// register. When both are present they must agree.
    private static func resolveMemoryWidth(
        explicit: X86.RegisterWidth?,
        paired: X86.RegisterWidth,
        mnemonic: String
    ) throws -> X86.RegisterWidth {
        if let explicit, explicit != paired {
            throw AssemblerError.unsupportedOperand(
                "\(mnemonic): size hint disagrees with register width"
            )
        }
        return explicit ?? paired
    }

    // MARK: - Operand parsing

    static func register(_ text: String) throws -> X86.Register {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let register = X86.RegisterTable.lookup[key] {
            return register
        }
        throw AssemblerError.invalidRegister(text)
    }

    static func immediateAny(_ text: String) throws -> Int64 {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") { value.removeFirst() }
        value = value.replacingOccurrences(of: "_", with: "")
        let negative: Bool
        if value.hasPrefix("-") { negative = true; value.removeFirst() }
        else if value.hasPrefix("+") { negative = false; value.removeFirst() }
        else { negative = false }
        guard !value.isEmpty else { throw AssemblerError.invalidImmediate(text) }
        let radix: Int
        if value.hasPrefix("0x") { radix = 16; value.removeFirst(2) }
        else if value.hasPrefix("0b") { radix = 2; value.removeFirst(2) }
        else { radix = 10 }
        guard let magnitude = UInt64(value, radix: radix) else {
            throw AssemblerError.invalidImmediate(text)
        }
        if negative {
            guard magnitude <= (UInt64(Int64.max) + 1) else {
                throw AssemblerError.invalidImmediate(text)
            }
            return Int64(bitPattern: 0 &- magnitude)
        }
        return Int64(bitPattern: magnitude)
    }

    static func validateImmediateRange(_ value: Int64, width: X86.RegisterWidth, mnemonic: String) throws {
        switch width {
        case .byte:
            guard value >= -0x80 && value <= 0xFF else {
                throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: value, range: -0x80...0xFF)
            }
        case .word:
            guard value >= -0x8000 && value <= 0xFFFF else {
                throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: value, range: -0x8000...0xFFFF)
            }
        case .dword:
            guard value >= -0x8000_0000 && value <= 0xFFFF_FFFF else {
                throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: value, range: -0x8000_0000...0xFFFF_FFFF)
            }
        case .qword:
            break
        }
    }

    // MARK: - Memory operand parsing

    /// Parse a bracketed Intel-syntax memory expression, e.g. `[rax]`,
    /// `[rax + 8]`, `[rax + rbx*4 + 0x10]`, `[rip + 0x100]`, `[0x1000]`.
    /// Only 64-bit base/index registers are accepted; the 32-bit address
    /// form (`[esi+...]` with the 0x67 override) is deferred.
    static func memoryOperand(_ text: String) throws -> X86.MemoryOperand {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            throw AssemblerError.invalidMemoryOperand(text)
        }
        let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty else { throw AssemblerError.invalidMemoryOperand(text) }

        var base: X86.Register? = nil
        var index: X86.Register? = nil
        var scale: UInt8 = 1
        var displacement: Int64 = 0
        var ripRelative = false

        for (sign, atom) in splitAtomsBySign(inner) {
            let term = atom.trimmingCharacters(in: .whitespacesAndNewlines)
            if term.isEmpty { throw AssemblerError.invalidMemoryOperand(text) }

            // `reg * scale` or `scale * reg`
            if term.contains("*") {
                guard sign == 1 else { throw AssemblerError.invalidMemoryOperand(text) }
                guard index == nil else {
                    throw AssemblerError.invalidMemoryOperand("\(text): too many scaled index terms")
                }
                let (reg, factor) = try parseScaledTerm(term, original: text)
                guard reg.width == .qword else {
                    throw AssemblerError.invalidMemoryOperand("\(text): index must be 64-bit")
                }
                guard reg.number != 4 else {
                    throw AssemblerError.invalidMemoryOperand("\(text): rsp cannot be used as an index")
                }
                index = reg
                scale = factor
                continue
            }

            // Bare `rip` for RIP-relative addressing.
            if term.lowercased() == "rip" {
                guard sign == 1, base == nil, index == nil, !ripRelative else {
                    throw AssemblerError.invalidMemoryOperand(text)
                }
                ripRelative = true
                continue
            }

            // Bare register: base if absent, otherwise index with scale 1.
            if let reg = try? register(term) {
                guard sign == 1 else { throw AssemblerError.invalidMemoryOperand(text) }
                guard reg.width == .qword else {
                    throw AssemblerError.invalidMemoryOperand("\(text): base/index must be 64-bit")
                }
                if base == nil {
                    base = reg
                } else if index == nil {
                    guard reg.number != 4 else {
                        throw AssemblerError.invalidMemoryOperand("\(text): rsp cannot be used as an index")
                    }
                    index = reg
                    scale = 1
                } else {
                    throw AssemblerError.invalidMemoryOperand("\(text): too many registers")
                }
                continue
            }

            // Otherwise, displacement.
            let value = try immediateAny(term)
            displacement &+= sign * value
        }

        if ripRelative && (base != nil || index != nil) {
            throw AssemblerError.invalidMemoryOperand("\(text): rip cannot combine with base/index")
        }

        return X86.MemoryOperand(
            base: base,
            index: index,
            scale: scale,
            displacement: displacement,
            ripRelative: ripRelative
        )
    }

    /// Split an inner address expression into signed atoms. Each atom is a
    /// register, `reg*scale`, or an integer literal; `+`/`-` between atoms
    /// applies to the immediate value (signs against registers raise an
    /// error during atom interpretation).
    private static func splitAtomsBySign(_ text: String) -> [(sign: Int64, atom: String)] {
        var result: [(Int64, String)] = []
        var current = ""
        var sign: Int64 = 1
        for ch in text {
            if ch == "+" || ch == "-" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result.append((sign, trimmed))
                    current = ""
                    sign = (ch == "-") ? -1 : 1
                } else if ch == "-" {
                    // Leading or consecutive `-`: flip sign of the next atom.
                    sign = -sign
                }
                continue
            }
            current.append(ch)
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { result.append((sign, trimmed)) }
        return result
    }

    private static func parseScaledTerm(_ term: String, original: String) throws -> (register: X86.Register, scale: UInt8) {
        let parts = term.split(separator: "*", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2 else { throw AssemblerError.invalidMemoryOperand(original) }
        // Either `reg * scale` or `scale * reg`.
        let (regText, scaleText): (String, String)
        if let _ = try? register(parts[0]) {
            (regText, scaleText) = (parts[0], parts[1])
        } else if let _ = try? register(parts[1]) {
            (regText, scaleText) = (parts[1], parts[0])
        } else {
            throw AssemblerError.invalidMemoryOperand(original)
        }
        let reg = try register(regText)
        let scale = try immediateAny(scaleText)
        guard scale == 1 || scale == 2 || scale == 4 || scale == 8 else {
            throw AssemblerError.invalidMemoryOperand("\(original): scale must be 1, 2, 4, or 8")
        }
        return (reg, UInt8(scale))
    }
}
