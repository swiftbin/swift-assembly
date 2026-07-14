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
            if let sysMov = try parseMovSystemRegister(instruction) {
                return sysMov
            }
            return try parseMov(instruction)
        }
        if let kind = X86.SSEMovKind(rawValue: instruction.mnemonic) {
            // `movsd` doubles as the SSE scalar form and the string-op
            // mnemonic; with no operands it's still the string form.
            if kind == .movsd && instruction.operands.isEmpty {
                return .stringOp(.movsd, prefix: nil)
            }
            return try parseSSEMov(kind, instruction)
        }
        if let kind = X86.SSEArithmeticKind(rawValue: instruction.mnemonic) {
            return try parseSSEArithmetic(kind, instruction)
        }
        if let kind = X86.SSEIntToFloatKind(rawValue: instruction.mnemonic) {
            return try parseSSEIntToFloat(kind, instruction)
        }
        if let kind = X86.SSEFloatToIntKind(rawValue: instruction.mnemonic) {
            return try parseSSEFloatToInt(kind, instruction)
        }
        if let kind = X86.MovDQKind(rawValue: instruction.mnemonic) {
            return try parseMovDQ(kind, instruction)
        }
        if let kind = X86.SSEShuffleKind(rawValue: instruction.mnemonic) {
            return try parseSSEShuffle(kind, instruction)
        }
        if let kind = X86.SSEHalfMoveKind(rawValue: instruction.mnemonic) {
            return try parseSSEHalfMove(kind, instruction)
        }
        if let kind = X86.SSEMaskExtractKind(rawValue: instruction.mnemonic) {
            return try parseSSEMaskExtract(kind, instruction)
        }
        if instruction.mnemonic == "maskmovdqu" {
            return try parseMaskMovDqu(instruction)
        }
        if let kind = X86.MXCSRKind(rawValue: instruction.mnemonic) {
            return try parseMXCSR(kind, instruction)
        }
        if let kind = X86.SSENonTemporalKind(rawValue: instruction.mnemonic) {
            return try parseSSENonTemporalStore(kind, instruction)
        }
        if instruction.mnemonic == "movnti" {
            return try parseMovnti(instruction)
        }
        if let kind = X86.PrefetchKind(rawValue: instruction.mnemonic) {
            return try parsePrefetch(kind, instruction)
        }
        if let kind = X86.SSE3Kind(rawValue: instruction.mnemonic) {
            return try parseSSE3(kind, instruction)
        }
        if let kind = X86.SSSE3Kind(rawValue: instruction.mnemonic) {
            return try parseSSSE3(kind, instruction)
        }
        if instruction.mnemonic == "palignr" {
            return try parsePalignr(instruction)
        }
        if let kind = X86.SSEPackExtendKind(rawValue: instruction.mnemonic) {
            return try parseSSEPackExtend(kind, instruction)
        }
        if let kind = X86.SSE41PackedKind(rawValue: instruction.mnemonic) {
            return try parseSSE41Packed(kind, instruction)
        }
        if instruction.mnemonic == "movntdqa" {
            return try parseMovntdqa(instruction)
        }
        if let kind = X86.SSE41ImmediateKind(rawValue: instruction.mnemonic) {
            return try parseSSE41Immediate(kind, instruction)
        }
        if let kind = X86.SSEInsertLaneKind(rawValue: instruction.mnemonic) {
            return try parseSSEInsertLane(kind, instruction)
        }
        if let kind = X86.SSEExtractLaneKind(rawValue: instruction.mnemonic) {
            return try parseSSEExtractLane(kind, instruction)
        }
        if instruction.mnemonic == "insertps" {
            return try parseInsertps(instruction)
        }
        if instruction.mnemonic == "extractps" {
            return try parseExtractps(instruction)
        }
        if let kind = X86.SSEBlendvKind(rawValue: instruction.mnemonic) {
            return try parseSSEBlendv(kind, instruction)
        }
        if instruction.mnemonic == "crc32" {
            return try parseCrc32(instruction)
        }
        if let kind = X86.VexArithmeticKind(rawValue: instruction.mnemonic) {
            return try parseVexArithmetic(kind, instruction)
        }
        if let kind = X86.VexPackedIntegerKind(rawValue: instruction.mnemonic) {
            return try parseVexPackedInteger(kind, instruction)
        }
        if let kind = X86.VexUnaryKind(rawValue: instruction.mnemonic) {
            return try parseVexUnary(kind, instruction)
        }
        if let kind = X86.VexMovKind(rawValue: instruction.mnemonic) {
            return try parseVexMov(kind, instruction)
        }
        if let kind = X86.VexImmediateShiftKind(rawValue: instruction.mnemonic) {
            return try parseVexShiftImmediate(kind, instruction)
        }
        if let kind = X86.VexShuffleImmKind(rawValue: instruction.mnemonic) {
            return try parseVexShuffleImm(kind, instruction)
        }
        if let kind = X86.VexThreeOpImmKind(rawValue: instruction.mnemonic) {
            return try parseVexThreeOpImm(kind, instruction)
        }
        if let kind = X86.VexMaskExtractKind(rawValue: instruction.mnemonic) {
            return try parseVexMaskExtract(kind, instruction)
        }
        if instruction.mnemonic == "andn" {
            return try parseBmiAndn(instruction)
        }
        if let kind = X86.BMI1UnaryKind(rawValue: instruction.mnemonic) {
            return try parseBmiUnary(kind, instruction)
        }
        if let kind = X86.BMI2ShiftLikeKind(rawValue: instruction.mnemonic) {
            return try parseBmiShiftLike(kind, instruction)
        }
        if instruction.mnemonic == "rorx" {
            return try parseRorx(instruction)
        }
        if let kind = X86.BMI2PextDepKind(rawValue: instruction.mnemonic) {
            return try parseBmi2PextDep(kind, instruction)
        }
        if instruction.mnemonic == "mulx" {
            return try parseMulx(instruction)
        }
        if let kind = X86.AdxKind(rawValue: instruction.mnemonic) {
            return try parseAdx(kind, instruction)
        }
        if instruction.mnemonic == "vmovd" || instruction.mnemonic == "vmovq" {
            let kind: X86.MovDQKind = instruction.mnemonic == "vmovq" ? .movq : .movd
            return try parseVexMovDQ(kind, instruction)
        }
        if let kind = X86.VexHalfMoveRegKind(rawValue: instruction.mnemonic) {
            return try parseVexHalfMoveReg(kind, instruction)
        }
        if let kind = X86.VexSSSE3Kind(rawValue: instruction.mnemonic) {
            return try parseVexSSSE3(kind, instruction)
        }
        if let kind = X86.FMA3Kind(rawValue: instruction.mnemonic) {
            return try parseFma3(kind, instruction)
        }
        if let kind = X86.VexSSE41PackedKind(rawValue: instruction.mnemonic) {
            return try parseVexSSE41Packed(kind, instruction)
        }
        if let kind = X86.VexSSE41UnaryKind(rawValue: instruction.mnemonic) {
            return try parseVexSSE41Unary(kind, instruction)
        }
        if let kind = X86.VexPackExtendKind(rawValue: instruction.mnemonic) {
            return try parseVexPackExtend(kind, instruction)
        }
        if instruction.mnemonic == "vaeskeygenassist" {
            return try parseVaesKeygenAssist(instruction)
        }
        if let kind = X86.VexCmpStrKind(rawValue: instruction.mnemonic) {
            return try parseVexCmpStr(kind, instruction)
        }
        if let kind = X86.VexRoundPackedKind(rawValue: instruction.mnemonic) {
            return try parseVexRoundPacked(kind, instruction)
        }
        if let kind = X86.VexNonTemporalKind(rawValue: instruction.mnemonic) {
            return try parseVexNonTemporal(kind, instruction)
        }
        if instruction.mnemonic == "vldmxcsr" || instruction.mnemonic == "vstmxcsr" {
            let kind: X86.MXCSRKind = instruction.mnemonic == "vldmxcsr" ? .ldmxcsr : .stmxcsr
            return try parseVexMxcsr(kind, instruction)
        }
        if let kind = X86.VexBroadcastKind(rawValue: instruction.mnemonic) {
            return try parseVexBroadcast(kind, instruction)
        }
        if let kind = X86.VexVarShiftKind(rawValue: instruction.mnemonic) {
            return try parseVexVarShift(kind, instruction)
        }
        if let kind = X86.RandomBitsKind(rawValue: instruction.mnemonic) {
            return try parseRandomBits(kind, instruction)
        }
        if let kind = X86.CacheLineKind(rawValue: instruction.mnemonic) {
            return try parseCacheLineOp(kind, instruction)
        }
        if instruction.mnemonic == "invpcid" {
            return try parseInvpcid(instruction)
        }
        if instruction.mnemonic == "movdiri" {
            return try parseMovdiri(instruction)
        }
        if instruction.mnemonic == "movdir64b" {
            return try parseMovdir64b(instruction)
        }
        if let kind = X86.SHAKind(rawValue: instruction.mnemonic) {
            return try parseShani(kind, instruction)
        }
        if instruction.mnemonic == "sha1rnds4" {
            return try parseSha1rnds4(instruction)
        }
        if instruction.mnemonic == "vpinsrd" || instruction.mnemonic == "vpinsrq" {
            let width: X86.RegisterWidth = instruction.mnemonic == "vpinsrq" ? .qword : .dword
            return try parseVexInsertLaneDQ(width: width, instruction)
        }
        if instruction.mnemonic == "vpextrd" || instruction.mnemonic == "vpextrq" {
            let width: X86.RegisterWidth = instruction.mnemonic == "vpextrq" ? .qword : .dword
            return try parseVexExtractLaneDQ(width: width, instruction)
        }
        if let kind = X86.WaitpkgKind(rawValue: instruction.mnemonic) {
            return try parseWaitpkg(kind, instruction)
        }
        if instruction.mnemonic == "vcvtph2ps" {
            return try parseVcvtph2ps(instruction)
        }
        if instruction.mnemonic == "vcvtps2ph" {
            return try parseVcvtps2ph(instruction)
        }
        if instruction.mnemonic == "xbegin" {
            return .xbegin(target: try parseSingleBranchTarget(instruction))
        }
        if let kind = X86.EnqcmdKind(rawValue: instruction.mnemonic) {
            return try parseEnqcmd(kind, instruction)
        }
        if instruction.mnemonic == "vinsertps" {
            return try parseVinsertps(instruction)
        }
        if instruction.mnemonic == "vextractps" {
            return try parseVextractps(instruction)
        }
        if let kind = X86.VexInsertLaneBWKind(rawValue: instruction.mnemonic) {
            return try parseVexInsertLaneBW(kind, instruction)
        }
        if let kind = X86.VexExtractLaneBWKind(rawValue: instruction.mnemonic) {
            return try parseVexExtractLaneBW(kind, instruction)
        }
        if instruction.mnemonic == "xabort" {
            guard instruction.operands.count == 1 else {
                throw AssemblerError.invalidOperandCount(instruction: "xabort", expected: "1 operand", actual: instruction.operands.count)
            }
            let imm = try immediateAny(instruction.operands[0])
            guard imm >= 0 && imm <= 255 else {
                throw AssemblerError.immediateOutOfRange(instruction: "xabort", value: imm, range: 0...255)
            }
            return .xabort(immediate: UInt8(truncatingIfNeeded: imm))
        }
        // `cmpsd` overlaps with the string-op CMPSD; route to the SSE
        // form only when it carries the SSE shape (3 operands).
        if let kind = X86.SSECompareKind(rawValue: instruction.mnemonic),
           instruction.operands.count == 3 {
            return try parseSSECompare(kind, instruction)
        }
        if instruction.mnemonic == "pslldq" || instruction.mnemonic == "psrldq" {
            // These only have an imm8 form — no variable shift partner
            // in SSEPackedIntegerKind.
            let kind = X86.SSEImmediateShiftKind(rawValue: instruction.mnemonic)!
            return try parseSSEImmediateShift(kind, instruction)
        }
        if let kind = X86.SSEPackedIntegerKind(rawValue: instruction.mnemonic) {
            return try parseSSEPackedInteger(kind, instruction)
        }
        if instruction.mnemonic == "lar" {
            let (destination, source) = try parseRegisterMemoryPair(mnemonic: "lar", instruction: instruction)
            return .lar(destination: destination, source: source)
        }
        if instruction.mnemonic == "lsl" {
            let (destination, source) = try parseRegisterMemoryPair(mnemonic: "lsl", instruction: instruction)
            return .lsl(destination: destination, source: source)
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
        if let kind = X86.ExtendingMoveKind(rawValue: instruction.mnemonic) {
            return try parseExtendingMove(kind, instruction)
        }
        if instruction.mnemonic == "bswap" {
            return try parseBswap(instruction)
        }
        if instruction.mnemonic == "xchg" {
            return try parseXchg(instruction)
        }
        if instruction.mnemonic == "xadd" {
            return try parseXaddOrCmpxchg(instruction, isCmpxchg: false)
        }
        if instruction.mnemonic == "cmpxchg" {
            return try parseXaddOrCmpxchg(instruction, isCmpxchg: true)
        }
        if let kind = X86.CmpxchgWideKind(rawValue: instruction.mnemonic) {
            return try parseCmpxchgWide(kind, instruction)
        }
        if instruction.mnemonic.hasPrefix("cmov"),
           let cond = X86.Condition.resolve(suffix: String(instruction.mnemonic.dropFirst(4))) {
            return try parseCmovcc(cond, instruction)
        }
        if instruction.mnemonic.hasPrefix("set"), instruction.mnemonic.count > 3,
           let cond = X86.Condition.resolve(suffix: String(instruction.mnemonic.dropFirst(3))) {
            return try parseSetcc(cond, instruction)
        }
        if let kind = X86.BitTestKind(rawValue: instruction.mnemonic) {
            return try parseBitTest(kind, instruction)
        }
        if let kind = X86.BitScanKind(rawValue: instruction.mnemonic) {
            let (destination, source) = try parseRegisterMemoryPair(mnemonic: kind.rawValue, instruction: instruction)
            return .bitScan(kind, destination: destination, source: source)
        }
        if let kind = X86.BitCountKind(rawValue: instruction.mnemonic) {
            let (destination, source) = try parseRegisterMemoryPair(mnemonic: kind.rawValue, instruction: instruction)
            return .bitCount(kind, destination: destination, source: source)
        }
        if let kind = X86.StringOpKind(rawValue: instruction.mnemonic) {
            guard instruction.operands.isEmpty else {
                throw AssemblerError.invalidOperandCount(
                    instruction: instruction.mnemonic,
                    expected: "no operands",
                    actual: instruction.operands.count
                )
            }
            return .stringOp(kind, prefix: nil)
        }
        if let prefix = parseStringRepetitionPrefix(instruction.mnemonic) {
            return try parseStringWithPrefix(prefix, mnemonic: instruction.mnemonic, instruction: instruction)
        }
        if instruction.mnemonic == "in" {
            return try parseInFromPort(instruction)
        }
        if instruction.mnemonic == "out" {
            return try parseOutToPort(instruction)
        }
        if instruction.mnemonic == "int" {
            return try parseInterrupt(instruction)
        }
        if instruction.mnemonic == "clflush" {
            return .clflush(try parseSingleMemoryOperand(mnemonic: "clflush", instruction: instruction))
        }
        if instruction.mnemonic == "invlpg" {
            return .invlpg(try parseSingleMemoryOperand(mnemonic: "invlpg", instruction: instruction))
        }
        if let kind = X86.DescriptorTableKind(rawValue: instruction.mnemonic) {
            return .descriptorTable(kind, memory: try parseSingleMemoryOperand(mnemonic: kind.rawValue, instruction: instruction))
        }
        if let kind = X86.SystemRMKind(rawValue: instruction.mnemonic) {
            return try parseSystemRM(kind, instruction)
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

    private static func parseExtendingMove(_ kind: X86.ExtendingMoveKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let destination = try register(instruction.operands[0])
        let classified = try classifyOperand(instruction.operands[1])
        let source: X86.RegisterOrMemory
        let sourceWidth: X86.RegisterWidth
        switch classified {
        case .register(let r):
            source = .register(r)
            sourceWidth = r.width
        case .memory(let m, let explicit):
            guard let width = explicit else {
                throw AssemblerError.unsupportedOperand(
                    "\(kind.rawValue): memory source requires an explicit size hint (e.g. `byte ptr [...]`)"
                )
            }
            source = .memory(m, width: width)
            sourceWidth = width
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): source cannot be an immediate")
        }
        try validateExtendingMoveShape(kind: kind, destinationWidth: destination.width, sourceWidth: sourceWidth)
        return .extendingMove(kind, destination: destination, source: source)
    }

    private static func validateExtendingMoveShape(kind: X86.ExtendingMoveKind, destinationWidth dst: X86.RegisterWidth, sourceWidth src: X86.RegisterWidth) throws {
        switch kind {
        case .movsx:
            // 0F BE: byte → 16/32/64. 0F BF: word → 32/64.
            switch (dst, src) {
            case (.word, .byte), (.dword, .byte), (.qword, .byte),
                 (.dword, .word), (.qword, .word):
                return
            default:
                throw AssemblerError.unsupportedOperand("movsx: invalid width combination")
            }
        case .movzx:
            switch (dst, src) {
            case (.word, .byte), (.dword, .byte), (.qword, .byte),
                 (.dword, .word), (.qword, .word):
                return
            default:
                throw AssemblerError.unsupportedOperand("movzx: invalid width combination")
            }
        case .movsxd:
            guard dst == .qword, src == .dword else {
                throw AssemblerError.unsupportedOperand("movsxd: requires r64 destination and r/m32 source")
            }
        }
    }

    private static func parseBswap(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "bswap",
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let reg = try register(instruction.operands[0])
        guard reg.width == .dword || reg.width == .qword else {
            throw AssemblerError.unsupportedOperand("bswap: requires 32- or 64-bit register")
        }
        return .bswap(reg)
    }

    private static func parseXchg(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "xchg",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let a = try classifyOperand(instruction.operands[0])
        let b = try classifyOperand(instruction.operands[1])

        if case .immediate = a { throw AssemblerError.unsupportedOperand("xchg: immediate not allowed") }
        if case .immediate = b { throw AssemblerError.unsupportedOperand("xchg: immediate not allowed") }

        switch (a, b) {
        case (.register(let ar), .register(let br)):
            try checkWidthsMatch(ar.width, br.width, mnemonic: "xchg")
            return .xchg(target: .register(ar), register: br)
        case (.register(let ar), .memory(let m, let explicit)):
            let width = try resolveMemoryWidth(explicit: explicit, paired: ar.width, mnemonic: "xchg")
            return .xchg(target: .memory(m, width: width), register: ar)
        case (.memory(let m, let explicit), .register(let br)):
            let width = try resolveMemoryWidth(explicit: explicit, paired: br.width, mnemonic: "xchg")
            return .xchg(target: .memory(m, width: width), register: br)
        case (.memory, .memory):
            throw AssemblerError.unsupportedOperand("xchg: cannot have two memory operands")
        default:
            throw AssemblerError.unsupportedOperand("xchg: invalid operands")
        }
    }

    private static func parseXaddOrCmpxchg(_ instruction: ParsedInstruction, isCmpxchg: Bool) throws -> X86.Instruction {
        let mnemonic = instruction.mnemonic
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: mnemonic,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let dstClassified = try classifyOperand(instruction.operands[0])
        let source = try register(instruction.operands[1])
        let target: X86.RegisterOrMemory
        switch dstClassified {
        case .register(let r):
            try checkWidthsMatch(r.width, source.width, mnemonic: mnemonic)
            target = .register(r)
        case .memory(let m, let explicit):
            let width = try resolveMemoryWidth(explicit: explicit, paired: source.width, mnemonic: mnemonic)
            target = .memory(m, width: width)
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(mnemonic): destination cannot be immediate")
        }
        return isCmpxchg ? .cmpxchg(target: target, source: source) : .xadd(target: target, source: source)
    }

    /// CMPXCHG8B / CMPXCHG16B — operand is bare memory; width is
    /// implicit in the mnemonic and any user-supplied size hint is
    /// silently accepted (and ignored).
    private static func parseCmpxchgWide(_ kind: X86.CmpxchgWideKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "1 memory operand",
                actual: instruction.operands.count
            )
        }
        let classified = try classifyOperand(instruction.operands[0])
        guard case .memory(let mem, _) = classified else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): operand must be a memory reference")
        }
        return .cmpxchgWide(kind, mem)
    }

    private static func parseCmovcc(_ condition: X86.Condition, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        let mnemonic = "cmov\(condition.rawValue)"
        let (destination, source) = try parseRegisterMemoryPair(mnemonic: mnemonic, instruction: instruction)
        return .cmovcc(condition, destination: destination, source: source)
    }

    private static func parseSetcc(_ condition: X86.Condition, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        let mnemonic = "set\(condition.rawValue)"
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: mnemonic,
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let classified = try classifyOperand(instruction.operands[0])
        switch classified {
        case .register(let r):
            guard r.width == .byte else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): operand must be 8-bit")
            }
            return .setcc(condition, target: .register(r))
        case .memory(let m, let explicit):
            let width = explicit ?? .byte
            guard width == .byte else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): operand must be 8-bit")
            }
            return .setcc(condition, target: .memory(m, width: width))
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(mnemonic): target cannot be an immediate")
        }
    }

    /// Shared helper for the `r, r/m` (RM-direction, non-byte) pattern
    /// used by CMOVcc, BSF/BSR, and POPCNT/LZCNT/TZCNT.
    private static func parseRegisterMemoryPair(mnemonic: String, instruction: ParsedInstruction) throws -> (X86.Register, X86.RegisterOrMemory) {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: mnemonic,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let destination = try register(instruction.operands[0])
        guard destination.width != .byte else {
            throw AssemblerError.unsupportedOperand("\(mnemonic): byte destination not supported")
        }
        let classified = try classifyOperand(instruction.operands[1])
        switch classified {
        case .register(let r):
            try checkWidthsMatch(destination.width, r.width, mnemonic: mnemonic)
            return (destination, .register(r))
        case .memory(let m, let explicit):
            let width = try resolveMemoryWidth(explicit: explicit, paired: destination.width, mnemonic: mnemonic)
            return (destination, .memory(m, width: width))
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(mnemonic): source cannot be an immediate")
        }
    }

    private static func parseBitTest(_ kind: X86.BitTestKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        let mnemonic = kind.rawValue
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: mnemonic,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let dstClassified = try classifyOperand(instruction.operands[0])
        let srcClassified = try classifyOperand(instruction.operands[1])

        // Determine the target's width — from a paired register, an
        // explicit size hint on memory, or default qword for memory + imm.
        let target: X86.RegisterOrMemory
        let targetWidth: X86.RegisterWidth
        switch (dstClassified, srcClassified) {
        case (.register(let dst), _):
            guard dst.width != .byte else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): byte operand not supported")
            }
            target = .register(dst)
            targetWidth = dst.width
        case (.memory(let m, let explicit), .register(let s)):
            let width = try resolveMemoryWidth(explicit: explicit, paired: s.width, mnemonic: mnemonic)
            target = .memory(m, width: width)
            targetWidth = width
        case (.memory(let m, let explicit), .immediate):
            let width = explicit ?? .qword
            target = .memory(m, width: width)
            targetWidth = width
        case (.memory, .memory):
            throw AssemblerError.unsupportedOperand("\(mnemonic): cannot have two memory operands")
        default:
            throw AssemblerError.unsupportedOperand("\(mnemonic): invalid destination")
        }
        guard targetWidth != .byte else {
            throw AssemblerError.unsupportedOperand("\(mnemonic): operand must be 16/32/64-bit")
        }

        let source: X86.BitTestSource
        switch srcClassified {
        case .register(let r):
            try checkWidthsMatch(r.width, targetWidth, mnemonic: mnemonic)
            source = .register(r)
        case .immediate(let imm):
            guard imm >= 0 && imm <= 255 else {
                throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: imm, range: 0...255)
            }
            source = .immediate(UInt8(truncatingIfNeeded: imm))
        case .memory:
            throw AssemblerError.unsupportedOperand("\(mnemonic): source cannot be memory")
        }
        return .bitTest(kind, target: target, source: source)
    }

    /// `rep` / `repe` / `repz` map to the F3 prefix; `repne` / `repnz`
    /// map to F2. Anything else is not a string repetition prefix.
    private static func parseStringRepetitionPrefix(_ mnemonic: String) -> X86.StringPrefix? {
        switch mnemonic {
        case "rep", "repe", "repz":   return .f3
        case "repne", "repnz":        return .f2
        default:                      return nil
        }
    }

    private static func parseStringWithPrefix(_ prefix: X86.StringPrefix, mnemonic: String, instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: mnemonic,
                expected: "1 string-operation mnemonic",
                actual: instruction.operands.count
            )
        }
        let stringMnemonic = instruction.operands[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let kind = X86.StringOpKind(rawValue: stringMnemonic) else {
            throw AssemblerError.unsupportedOperand("\(mnemonic): unknown string operation `\(stringMnemonic)`")
        }
        if prefix == .f2 {
            guard kind.isComparison else {
                throw AssemblerError.unsupportedOperand("repne/repnz only applies to CMPS/SCAS")
            }
        }
        return .stringOp(kind, prefix: prefix)
    }

    private static func parseInFromPort(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "in",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let target = try parsePortRegister(instruction.operands[0], mnemonic: "in")
        let port = try parsePortSource(instruction.operands[1], mnemonic: "in")
        return .inFromPort(target: target, port: port)
    }

    private static func parseOutToPort(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "out",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let port = try parsePortSource(instruction.operands[0], mnemonic: "out")
        let source = try parsePortRegister(instruction.operands[1], mnemonic: "out")
        return .outToPort(source: source, port: port)
    }

    /// IN/OUT only accept AL/AX/EAX (the accumulator) as the data
    /// register — no qword form exists.
    private static func parsePortRegister(_ text: String, mnemonic: String) throws -> X86.Register {
        let reg = try register(text)
        guard reg.number == 0 else {
            throw AssemblerError.unsupportedOperand("\(mnemonic): data register must be AL / AX / EAX")
        }
        guard reg.width != .qword else {
            throw AssemblerError.unsupportedOperand("\(mnemonic): no 64-bit port I/O form")
        }
        return reg
    }

    /// The port operand of IN/OUT is either DX or an 8-bit immediate.
    private static func parsePortSource(_ text: String, mnemonic: String) throws -> X86.PortSource {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "dx" {
            return .dx
        }
        let value = try immediateAny(text)
        guard value >= 0 && value <= 0xFF else {
            throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: value, range: 0...0xFF)
        }
        return .immediate(UInt8(truncatingIfNeeded: value))
    }

    /// Pull a single bracketed memory expression out of an instruction
    /// whose operand width is intrinsic to the mnemonic (CLFLUSH,
    /// INVLPG, the upcoming LGDT/SIDT family). A user-supplied size
    /// hint is accepted and ignored.
    private static func parseSingleMemoryOperand(mnemonic: String, instruction: ParsedInstruction) throws -> X86.MemoryOperand {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: mnemonic,
                expected: "1 memory operand",
                actual: instruction.operands.count
            )
        }
        let classified = try classifyOperand(instruction.operands[0])
        guard case .memory(let mem, _) = classified else {
            throw AssemblerError.unsupportedOperand("\(mnemonic): operand must be a memory reference")
        }
        return mem
    }

    /// Recognise a `crN` / `drN` mnemonic (N = 0..15). Returns `nil`
    /// when the text is anything else (a regular GPR, a memory
    /// expression, etc.), letting MOV fall through to its standard
    /// parsing.
    private static func parseSystemRegisterName(_ text: String) -> (kind: X86.SystemRegisterKind, number: UInt8)? {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.count >= 3 else { return nil }
        let prefix = lower.prefix(2)
        let suffix = lower.dropFirst(2)
        let kind: X86.SystemRegisterKind
        switch prefix {
        case "cr": kind = .cr
        case "dr": kind = .dr
        default:   return nil
        }
        guard let number = UInt8(suffix), number <= 15 else { return nil }
        return (kind, number)
    }

    /// Detect and parse `MOV r, CR/DR` and `MOV CR/DR, r`. Returns nil
    /// when neither operand names a system register so the caller falls
    /// through to the regular MOV parsing.
    private static func parseMovSystemRegister(_ instruction: ParsedInstruction) throws -> X86.Instruction? {
        guard instruction.operands.count == 2 else { return nil }
        let op0 = instruction.operands[0]
        let op1 = instruction.operands[1]
        if let sys = parseSystemRegisterName(op0) {
            let source = try register(op1)
            guard source.width == .qword else {
                throw AssemblerError.unsupportedOperand("mov \(sys.kind.rawValue)\(sys.number), reg: register must be 64-bit")
            }
            return .movToSystemRegister(sys.kind, number: sys.number, source: source)
        }
        if let sys = parseSystemRegisterName(op1) {
            let destination = try register(op0)
            guard destination.width == .qword else {
                throw AssemblerError.unsupportedOperand("mov reg, \(sys.kind.rawValue)\(sys.number): register must be 64-bit")
            }
            return .movFromSystemRegister(sys.kind, destination: destination, number: sys.number)
        }
        return nil
    }

    private static func parseSystemRM(_ kind: X86.SystemRMKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
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
            // Read variants accept wider registers (zero-extending the
            // 16-bit source). Load / verify variants are r16-only.
            if kind.allowsWideRegister {
                guard r.width != .byte else {
                    throw AssemblerError.unsupportedOperand("\(kind.rawValue): byte register not supported")
                }
            } else {
                guard r.width == .word else {
                    throw AssemblerError.unsupportedOperand("\(kind.rawValue): operand must be r/m16")
                }
            }
            return .systemRM(kind, target: .register(r))
        case .memory(let m, let explicit):
            // Memory width is always 16-bit for these instructions.
            let width = explicit ?? .word
            guard width == .word else {
                throw AssemblerError.unsupportedOperand("\(kind.rawValue): memory operand must be 16-bit")
            }
            return .systemRM(kind, target: .memory(m, width: width))
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): target cannot be an immediate")
        }
    }

    /// Recognise `xmm0` ... `xmm15` as an XMM register name. Returns
    /// `nil` for anything else so the caller falls through to GPR /
    /// memory / immediate parsing.
    static func parseXMMRegister(_ text: String) -> X86.XMMRegister? {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasPrefix("xmm") else { return nil }
        let suffix = lower.dropFirst(3)
        guard let number = UInt8(suffix), number <= 15 else { return nil }
        return X86.XMMRegister(number: number)
    }

    /// Parse the source-level operand of an SSE MOV variant: an XMM
    /// register, or a memory expression whose width must match the
    /// kind's intrinsic operand size (m32 for MOVSS, m64 for MOVSD,
    /// m128 for the rest).
    private static func parseXMMOperand(_ text: String, kind: X86.SSEMovKind) throws -> X86.XMMOrMemory {
        if let xmm = parseXMMRegister(text) {
            return .register(xmm)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (width, body) = stripSizeHint(trimmed) {
            guard width == kind.memoryWidth else {
                throw AssemblerError.unsupportedOperand(
                    "\(kind.rawValue): memory operand width disagrees with mnemonic"
                )
            }
            return .memory(try memoryOperand(body))
        }
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed))
        }
        throw AssemblerError.unsupportedOperand("\(kind.rawValue): expected xmm register or memory operand")
    }

    /// Pull an XMM source operand for the SSE arithmetic family. The
    /// destination is always an XMM register; the source is an XMM
    /// register or memory of the kind's intrinsic width.
    private static func parseSSEPackedInteger(_ kind: X86.SSEPackedIntegerKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        // The shift mnemonics overlap between the variable form and the
        // imm8 form. If the second operand is an immediate and this
        // kind has an imm8 partner, route there instead.
        if let immKind = X86.SSEImmediateShiftKind(rawValue: kind.rawValue),
           let immValue = try? immediateAny(instruction.operands[1]) {
            return try makeImmediateShift(kind: immKind, register: instruction.operands[0], imm: immValue)
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: .xmmword,
            mnemonic: kind.rawValue
        )
        return .ssePackedInteger(kind, destination: destination, source: source)
    }

    private static func parseSSEImmediateShift(_ kind: X86.SSEImmediateShiftKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let imm = try immediateAny(instruction.operands[1])
        return try makeImmediateShift(kind: kind, register: instruction.operands[0], imm: imm)
    }

    private static func makeImmediateShift(kind: X86.SSEImmediateShiftKind, register text: String, imm: Int64) throws -> X86.Instruction {
        guard let target = parseXMMRegister(text) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): target must be an XMM register")
        }
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .sseShiftImmediate(kind, target: target, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// PSHUFD/PSHUFLW/PSHUFHW/SHUFPS/SHUFPD — `xmm, xmm/m128, imm8`.
    private static func parseSSEShuffle(_ kind: X86.SSEShuffleKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: .xmmword,
            mnemonic: kind.rawValue
        )
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .sseShuffle(kind, destination: destination, source: source, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// AVX V-prefixed three-operand FP arithmetic
    /// (VADD/VSUB/VMUL/VDIV PS/PD/SS/SD).
    private static func parseVexArithmetic(_ kind: X86.VexArithmeticKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: kind.isScalar)
        let (size1, src1) = try parseVectorRegister(instruction.operands[1], mnemonic: kind.rawValue, scalarOnly: kind.isScalar)
        guard size == size1 else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): vector size of operands must match")
        }
        let src2 = try parseVectorOrMemory(
            instruction.operands[2],
            size: size,
            memoryWidth: kind.memoryWidth(size: size),
            mnemonic: kind.rawValue
        )
        return .vexArithmetic(kind, size: size, destination: dst, source1: src1, source2: src2)
    }

    /// ANDN — `r32/64, r32/64, r/m32/64`.
    private static func parseBmiAndn(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "andn",
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try register(instruction.operands[0])
        let src1 = try register(instruction.operands[1])
        let src2 = try parseGPROrSizedMemory(instruction.operands[2], expectedWidth: dst.width, mnemonic: "andn")
        return .bmiAndn(destination: dst, source1: src1, source2: src2)
    }

    /// BLSI/BLSMSK/BLSR — `r32/64, r/m32/64`.
    private static func parseBmiUnary(_ kind: X86.BMI1UnaryKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try register(instruction.operands[0])
        let src = try parseGPROrSizedMemory(instruction.operands[1], expectedWidth: dst.width, mnemonic: kind.rawValue)
        return .bmiUnary(kind, destination: dst, source: src)
    }

    /// UMONITOR / UMWAIT / TPAUSE — single GPR operand.
    private static func parseWaitpkg(_ kind: X86.WaitpkgKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(instruction: kind.rawValue, expected: "1 operand", actual: instruction.operands.count)
        }
        let reg = try register(instruction.operands[0])
        return .waitpkg(kind, register: reg)
    }

    /// F16C VCVTPH2PS — `xmm/ymm, xmm/m64|m128`. The memory source is
    /// half the destination width (m64 for xmm dst, m128 for ymm dst).
    private static func parseVcvtph2ps(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(instruction: "vcvtph2ps", expected: "2 operands", actual: instruction.operands.count)
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: "vcvtph2ps", scalarOnly: false)
        let sourceMemoryWidth: X86.RegisterWidth = size == .xmm ? .qword : .xmmword
        // The register form is always an XMM (the low 128 bits carry 8 halves).
        let src = try parseVectorOrMemory(instruction.operands[1], size: .xmm, memoryWidth: sourceMemoryWidth, mnemonic: "vcvtph2ps")
        return .vcvtph2ps(size: size, destination: dst, source: src)
    }

    /// F16C VCVTPS2PH — `xmm/m64|m128, xmm/ymm, imm8`. The memory
    /// destination is half the source vector width.
    private static func parseVcvtps2ph(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(instruction: "vcvtps2ph", expected: "3 operands", actual: instruction.operands.count)
        }
        let (size, src) = try parseVectorRegister(instruction.operands[1], mnemonic: "vcvtps2ph", scalarOnly: false)
        let destMemoryWidth: X86.RegisterWidth = size == .xmm ? .qword : .xmmword
        let dst = try parseVectorOrMemory(instruction.operands[0], size: .xmm, memoryWidth: destMemoryWidth, mnemonic: "vcvtps2ph")
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "vcvtps2ph", value: imm, range: 0...255)
        }
        return .vcvtps2ph(size: size, destination: dst, source: src, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// VPINSRD / VPINSRQ — `xmm, xmm, r/m, imm8`.
    private static func parseVexInsertLaneDQ(width: X86.RegisterWidth, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 4 else {
            throw AssemblerError.invalidOperandCount(instruction: width == .qword ? "vpinsrq" : "vpinsrd", expected: "4 operands", actual: instruction.operands.count)
        }
        guard let dst = parseXMMRegister(instruction.operands[0]),
              let src1 = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("vpinsr: first two operands must be XMM registers")
        }
        let src2 = try parseGPROrSizedMemory(instruction.operands[2], expectedWidth: width, mnemonic: "vpinsr")
        let imm = try immediateAny(instruction.operands[3])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "vpinsr", value: imm, range: 0...255)
        }
        return .vexInsertLaneDQ(width: width, destination: dst.number, source1: src1.number, source2: src2, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// VPEXTRD / VPEXTRQ — `r/m, xmm, imm8`.
    private static func parseVexExtractLaneDQ(width: X86.RegisterWidth, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(instruction: width == .qword ? "vpextrq" : "vpextrd", expected: "3 operands", actual: instruction.operands.count)
        }
        let dst = try parseGPROrSizedMemory(instruction.operands[0], expectedWidth: width, mnemonic: "vpextr")
        guard let src = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("vpextr: source must be an XMM register")
        }
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "vpextr", value: imm, range: 0...255)
        }
        return .vexExtractLaneDQ(width: width, destination: dst, source: src.number, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// SHA-NI 2-op family.
    private static func parseShani(_ kind: X86.SHAKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(instruction: kind.rawValue, expected: "2 operands", actual: instruction.operands.count)
        }
        guard let dst = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let src = try parseXMMOrMemorySource(instruction.operands[1], width: .xmmword, mnemonic: kind.rawValue)
        return .shani(kind, destination: dst, source: src)
    }

    /// SHA1RNDS4 — `xmm, xmm/m128, imm8`.
    private static func parseSha1rnds4(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(instruction: "sha1rnds4", expected: "3 operands", actual: instruction.operands.count)
        }
        guard let dst = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("sha1rnds4: destination must be an XMM register")
        }
        let src = try parseXMMOrMemorySource(instruction.operands[1], width: .xmmword, mnemonic: "sha1rnds4")
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "sha1rnds4", value: imm, range: 0...255)
        }
        return .sha1rnds4(destination: dst, source: src, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// INVPCID r64, m128.
    private static func parseInvpcid(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(instruction: "invpcid", expected: "2 operands", actual: instruction.operands.count)
        }
        let dst = try register(instruction.operands[0])
        let mem = try parseSizedMemory(instruction.operands[1], expected: .xmmword, mnemonic: "invpcid")
        return .invpcid(destination: dst, memory: mem)
    }

    /// MOVDIRI m, r32/64.
    private static func parseMovdiri(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(instruction: "movdiri", expected: "2 operands", actual: instruction.operands.count)
        }
        let src = try register(instruction.operands[1])
        let mem = try parseSizedMemory(instruction.operands[0], expected: src.width, mnemonic: "movdiri")
        return .movdiri(memory: mem, source: src)
    }

    /// MOVDIR64B r64, m512.
    /// VEX VPINSRB / VPINSRW — `xmm, xmm, r32/m{8|16}, imm8`.
    private static func parseVexInsertLaneBW(_ kind: X86.VexInsertLaneBWKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 4 else {
            throw AssemblerError.invalidOperandCount(instruction: kind.rawValue, expected: "4 operands", actual: instruction.operands.count)
        }
        guard let dst = parseXMMRegister(instruction.operands[0]),
              let src1 = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): first two operands must be XMM registers")
        }
        // GPR form is r32 (low bits used); memory form is m8/m16.
        let src2 = try parseInsertBWSource(instruction.operands[2], memoryWidth: kind.memoryWidth, mnemonic: kind.rawValue)
        let imm = try immediateAny(instruction.operands[3])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .vexInsertLaneBW(kind, destination: dst.number, source1: src1.number, source2: src2, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// VEX VPEXTRB / VPEXTRW — `r32/m{8|16}, xmm, imm8`.
    private static func parseVexExtractLaneBW(_ kind: X86.VexExtractLaneBWKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(instruction: kind.rawValue, expected: "3 operands", actual: instruction.operands.count)
        }
        let dst = try parseInsertBWSource(instruction.operands[0], memoryWidth: kind.memoryWidth, mnemonic: kind.rawValue)
        guard let src = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): source must be an XMM register")
        }
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .vexExtractLaneBW(kind, destination: dst, source: src.number, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// Shared helper for VPINSRB/W and VPEXTRB/W: accept an r32 register
    /// or a size-hinted memory operand at the mnemonic's memoryWidth.
    private static func parseInsertBWSource(_ text: String, memoryWidth: X86.RegisterWidth, mnemonic: String) throws -> X86.RegisterOrMemory {
        if let r = try? register(text) {
            guard r.width == .dword else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): register operand must be r32")
            }
            return .register(r)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (w, body) = stripSizeHint(trimmed) {
            guard w == memoryWidth else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): memory operand width disagrees with mnemonic")
            }
            return .memory(try memoryOperand(body), width: w)
        }
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed), width: memoryWidth)
        }
        throw AssemblerError.unsupportedOperand("\(mnemonic): expected a register or memory operand")
    }

    /// VEX VINSERTPS — `xmm, xmm, xmm/m32, imm8`.
    private static func parseVinsertps(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 4 else {
            throw AssemblerError.invalidOperandCount(instruction: "vinsertps", expected: "4 operands", actual: instruction.operands.count)
        }
        guard let dst = parseXMMRegister(instruction.operands[0]),
              let src1 = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("vinsertps: first two operands must be XMM registers")
        }
        let src2 = try parseVectorOrMemory(instruction.operands[2], size: .xmm, memoryWidth: .dword, mnemonic: "vinsertps")
        let imm = try immediateAny(instruction.operands[3])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "vinsertps", value: imm, range: 0...255)
        }
        return .vinsertps(destination: dst.number, source1: src1.number, source2: src2, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// VEX VEXTRACTPS — `r/m32, xmm, imm8`.
    private static func parseVextractps(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(instruction: "vextractps", expected: "3 operands", actual: instruction.operands.count)
        }
        let dst = try parseGPROrSizedMemory(instruction.operands[0], expectedWidth: .dword, mnemonic: "vextractps")
        guard let src = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("vextractps: source must be an XMM register")
        }
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "vextractps", value: imm, range: 0...255)
        }
        return .vextractps(destination: dst, source: src.number, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// ENQCMD / ENQCMDS — `r64, m512`. The memory width is m512 which
    /// isn't part of the size-hint vocabulary, so we accept the bare
    /// `[...]` form (matching movdir64b).
    private static func parseEnqcmd(_ kind: X86.EnqcmdKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(instruction: kind.rawValue, expected: "2 operands", actual: instruction.operands.count)
        }
        let dst = try register(instruction.operands[0])
        let text = instruction.operands[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("[") else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): expected a memory operand")
        }
        let mem = try memoryOperand(text)
        return .enqcmd(kind, destination: dst, memory: mem)
    }

    private static func parseMovdir64b(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(instruction: "movdir64b", expected: "2 operands", actual: instruction.operands.count)
        }
        let dst = try register(instruction.operands[0])
        // Source memory width is m512; we accept the bare `[...]` form
        // since the m512 size hint isn't currently part of the parser.
        let text = instruction.operands[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("[") else {
            throw AssemblerError.unsupportedOperand("movdir64b: expected a memory operand")
        }
        let mem = try memoryOperand(text)
        return .movdir64b(destination: dst, memory: mem)
    }

    /// CLFLUSHOPT / CLWB / CLDEMOTE — single byte-pointer operand.
    private static func parseCacheLineOp(_ kind: X86.CacheLineKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let memory = try parseSizedMemory(instruction.operands[0], expected: .byte, mnemonic: kind.rawValue)
        return .cacheLineOp(kind, memory: memory)
    }

    /// RDRAND / RDSEED — single GPR destination.
    private static func parseRandomBits(_ kind: X86.RandomBitsKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let dst = try register(instruction.operands[0])
        return .randomBits(kind, destination: dst)
    }

    /// VPSLLVD/Q VPSRLVD/Q VPSRAVD — `xmm/ymm, xmm/ymm, xmm/ymm/m`.
    private static func parseVexVarShift(_ kind: X86.VexVarShiftKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let (size1, src1) = try parseVectorRegister(instruction.operands[1], mnemonic: kind.rawValue, scalarOnly: false)
        guard size == size1 else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): vector size of operands must match")
        }
        let src2 = try parseVectorOrMemory(
            instruction.operands[2],
            size: size,
            memoryWidth: size.packedMemoryWidth,
            mnemonic: kind.rawValue
        )
        return .vexVarShift(kind, size: size, destination: dst, source1: src1, source2: src2)
    }

    /// VPBROADCAST{B,W,D,Q} — `xmm/ymm, xmm/m{element-width}`.
    private static func parseVexBroadcast(_ kind: X86.VexBroadcastKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let src = try parseVectorOrMemory(
            instruction.operands[1],
            size: .xmm,        // source is always 128-bit form even when dst is ymm
            memoryWidth: kind.elementWidth,
            mnemonic: kind.rawValue
        )
        return .vexBroadcast(kind, size: size, destination: dst, source: src)
    }

    /// VLDMXCSR / VSTMXCSR — single m32 operand.
    private static func parseVexMxcsr(_ kind: X86.MXCSRKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "v" + kind.rawValue,
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let mem = try parseSizedMemory(instruction.operands[0], expected: .dword, mnemonic: "v" + kind.rawValue)
        return .vexMxcsr(kind, memory: mem)
    }

    /// VMOVNT* — `m128/m256, xmm/ymm`.
    private static func parseVexNonTemporal(_ kind: X86.VexNonTemporalKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        // The second operand is the XMM/YMM source.
        let (size, src) = try parseVectorRegister(instruction.operands[1], mnemonic: kind.rawValue, scalarOnly: false)
        let mem = try parseSizedMemory(instruction.operands[0], expected: size.packedMemoryWidth, mnemonic: kind.rawValue)
        return .vexNonTemporalStore(kind, size: size, memory: mem, source: src)
    }

    /// VROUNDPS / VROUNDPD — `xmm/ymm, xmm/ymm/m, imm8`.
    private static func parseVexRoundPacked(_ kind: X86.VexRoundPackedKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let src = try parseVectorOrMemory(
            instruction.operands[1],
            size: size,
            memoryWidth: size.packedMemoryWidth,
            mnemonic: kind.rawValue
        )
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .vroundPacked(kind, size: size, destination: dst, source: src, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// VPCMPESTRI/M, VPCMPISTRI/M — `xmm, xmm/m128, imm8`.
    private static func parseVexCmpStr(_ kind: X86.VexCmpStrKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        guard size == .xmm else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): only the 128-bit form is defined")
        }
        let src = try parseVectorOrMemory(
            instruction.operands[1],
            size: .xmm,
            memoryWidth: .xmmword,
            mnemonic: kind.rawValue
        )
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .vexCmpStr(kind, destination: dst, source: src, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// VAESKEYGENASSIST — `xmm, xmm/m128, imm8`.
    private static func parseVaesKeygenAssist(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "vaeskeygenassist",
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: "vaeskeygenassist", scalarOnly: false)
        guard size == .xmm else {
            throw AssemblerError.unsupportedOperand("vaeskeygenassist: only the 128-bit form is defined")
        }
        let src = try parseVectorOrMemory(
            instruction.operands[1],
            size: .xmm,
            memoryWidth: .xmmword,
            mnemonic: "vaeskeygenassist"
        )
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "vaeskeygenassist", value: imm, range: 0...255)
        }
        return .vaeskeygenassist(destination: dst, source: src, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// VEX widening pack moves — `xmm/ymm, xmm/ymm/m{w|d|q|m128}`.
    private static func parseVexPackExtend(_ kind: X86.VexPackExtendKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let src = try parseVectorOrMemory(
            instruction.operands[1],
            size: size,
            memoryWidth: kind.sourceWidth(size: size),
            mnemonic: kind.rawValue
        )
        return .vexPackExtend(kind, size: size, destination: dst, source: src)
    }

    /// VEX SSE4.1 3-op packed integer.
    private static func parseVexSSE41Packed(_ kind: X86.VexSSE41PackedKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let (size1, src1) = try parseVectorRegister(instruction.operands[1], mnemonic: kind.rawValue, scalarOnly: false)
        guard size == size1 else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): vector size of operands must match")
        }
        let src2 = try parseVectorOrMemory(
            instruction.operands[2],
            size: size,
            memoryWidth: size.packedMemoryWidth,
            mnemonic: kind.rawValue
        )
        return .vexSSE41Packed(kind, size: size, destination: dst, source1: src1, source2: src2)
    }

    /// VEX SSE4.1 2-op (VPTEST / VPHMINPOSUW).
    private static func parseVexSSE41Unary(_ kind: X86.VexSSE41UnaryKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let src = try parseVectorOrMemory(
            instruction.operands[1],
            size: size,
            memoryWidth: size.packedMemoryWidth,
            mnemonic: kind.rawValue
        )
        return .vexSSE41Unary(kind, size: size, destination: dst, source: src)
    }

    /// FMA3 — `xmm/ymm, xmm/ymm, xmm/ymm/m{128|256|32|64}`.
    private static func parseFma3(_ kind: X86.FMA3Kind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: kind.isScalar)
        let (size1, src1) = try parseVectorRegister(instruction.operands[1], mnemonic: kind.rawValue, scalarOnly: kind.isScalar)
        guard size == size1 else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): vector size of operands must match")
        }
        let src2 = try parseVectorOrMemory(
            instruction.operands[2],
            size: size,
            memoryWidth: kind.memoryWidth(size: size),
            mnemonic: kind.rawValue
        )
        return .fma3(kind, size: size, destination: dst, source1: src1, source2: src2)
    }

    /// VEX-prefixed SSSE3 — `xmm/ymm, xmm/ymm, xmm/ymm/m128|m256`.
    private static func parseVexSSSE3(_ kind: X86.VexSSSE3Kind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let (size1, src1) = try parseVectorRegister(instruction.operands[1], mnemonic: kind.rawValue, scalarOnly: false)
        guard size == size1 else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): vector size of operands must match")
        }
        let src2 = try parseVectorOrMemory(
            instruction.operands[2],
            size: size,
            memoryWidth: size.packedMemoryWidth,
            mnemonic: kind.rawValue
        )
        return .vexSSSE3(kind, size: size, destination: dst, source1: src1, source2: src2)
    }

    /// VMOVHLPS / VMOVLHPS — 3-operand register-only.
    private static func parseVexHalfMoveReg(_ kind: X86.VexHalfMoveRegKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        guard let dst = parseXMMRegister(instruction.operands[0]),
              let src1 = parseXMMRegister(instruction.operands[1]),
              let src2 = parseXMMRegister(instruction.operands[2]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): all operands must be XMM registers")
        }
        return .vexHalfMoveReg(kind, destination: dst.number, source1: src1.number, source2: src2.number)
    }

    /// VMOVD / VMOVQ — XMM ↔ GPR/memory.
    private static func parseVexMovDQ(_ kind: X86.MovDQKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "v" + kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let lhs = instruction.operands[0]
        let rhs = instruction.operands[1]
        let gprWidth: X86.RegisterWidth = kind == .movq ? .qword : .dword

        if let xmm = parseXMMRegister(lhs) {
            // load form: xmm ← GPR/mem
            let gpr = try parseGPROrSizedMemory(rhs, expectedWidth: gprWidth, mnemonic: "v" + kind.rawValue)
            return .vexMovDQ(kind, direction: .load, xmm: xmm, gpr: gpr)
        }
        if let xmm = parseXMMRegister(rhs) {
            // store form: GPR/mem ← xmm
            let gpr = try parseGPROrSizedMemory(lhs, expectedWidth: gprWidth, mnemonic: "v" + kind.rawValue)
            return .vexMovDQ(kind, direction: .store, xmm: xmm, gpr: gpr)
        }
        throw AssemblerError.unsupportedOperand("v\(kind.rawValue): one operand must be an XMM register")
    }

    /// ADCX / ADOX — `r32/64, r/m32/64`.
    private static func parseAdx(_ kind: X86.AdxKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try register(instruction.operands[0])
        let src = try parseGPROrSizedMemory(instruction.operands[1], expectedWidth: dst.width, mnemonic: kind.rawValue)
        return .adx(kind, destination: dst, source: src)
    }

    /// PDEP/PEXT — `dst, src1, r/m`.
    private static func parseBmi2PextDep(_ kind: X86.BMI2PextDepKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try register(instruction.operands[0])
        let src1 = try register(instruction.operands[1])
        let src2 = try parseGPROrSizedMemory(instruction.operands[2], expectedWidth: dst.width, mnemonic: kind.rawValue)
        return .bmi2PextDep(kind, destination: dst, source1: src1, source2: src2)
    }

    /// MULX — `dstHigh, dstLow, r/m`. The other multiplicand is
    /// implicit RDX/EDX.
    private static func parseMulx(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "mulx",
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let dstH = try register(instruction.operands[0])
        let dstL = try register(instruction.operands[1])
        let src = try parseGPROrSizedMemory(instruction.operands[2], expectedWidth: dstH.width, mnemonic: "mulx")
        return .mulx(destinationHigh: dstH, destinationLow: dstL, source: src)
    }

    /// RORX — `dst, r/m, imm8`.
    private static func parseRorx(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "rorx",
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try register(instruction.operands[0])
        let src = try parseGPROrSizedMemory(instruction.operands[1], expectedWidth: dst.width, mnemonic: "rorx")
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "rorx", value: imm, range: 0...255)
        }
        return .rorx(destination: dst, source: src, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// BEXTR/BZHI/SARX/SHLX/SHRX — `dst, r/m (value), reg (control)`.
    private static func parseBmiShiftLike(_ kind: X86.BMI2ShiftLikeKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try register(instruction.operands[0])
        let src1 = try parseGPROrSizedMemory(instruction.operands[1], expectedWidth: dst.width, mnemonic: kind.rawValue)
        let src2 = try register(instruction.operands[2])
        return .bmiShiftLike(kind, destination: dst, source1: src1, source2: src2)
    }

    private static func parseGPROrSizedMemory(_ text: String, expectedWidth: X86.RegisterWidth, mnemonic: String) throws -> X86.RegisterOrMemory {
        if let r = try? register(text) {
            guard r.width == expectedWidth else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): operand widths must match")
            }
            return .register(r)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (w, body) = stripSizeHint(trimmed) {
            guard w == expectedWidth else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): memory operand width disagrees with mnemonic")
            }
            return .memory(try memoryOperand(body), width: w)
        }
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed), width: expectedWidth)
        }
        throw AssemblerError.unsupportedOperand("\(mnemonic): expected a register or memory operand")
    }

    /// VMOVMSKPS/PD and VPMOVMSKB — `r32/r64, xmm/ymm`.
    private static func parseVexMaskExtract(_ kind: X86.VexMaskExtractKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let destination = try register(instruction.operands[0])
        guard destination.width == .dword || destination.width == .qword else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be a 32- or 64-bit GPR")
        }
        let (size, src) = try parseVectorRegister(instruction.operands[1], mnemonic: kind.rawValue, scalarOnly: false)
        // VPMOVMSKB allows YMM under AVX2; the others allow either.
        return .vexMaskExtract(kind, size: size, destination: destination, source: src)
    }

    /// VPSHUFD/LW/HW — 2-operand `xmm/ymm, xmm/ymm/m, imm8`.
    private static func parseVexShuffleImm(_ kind: X86.VexShuffleImmKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let src = try parseVectorOrMemory(
            instruction.operands[1],
            size: size,
            memoryWidth: size.packedMemoryWidth,
            mnemonic: kind.rawValue
        )
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .vexShuffleImm(kind, size: size, destination: dst, source: src, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// VSHUFPS/PD and VPALIGNR — 3-operand
    /// `xmm/ymm, xmm/ymm, xmm/ymm/m, imm8`.
    private static func parseVexThreeOpImm(_ kind: X86.VexThreeOpImmKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 4 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "4 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: kind.isScalar)
        let (size1, src1) = try parseVectorRegister(instruction.operands[1], mnemonic: kind.rawValue, scalarOnly: kind.isScalar)
        guard size == size1 else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): vector size of operands must match")
        }
        let src2 = try parseVectorOrMemory(
            instruction.operands[2],
            size: size,
            memoryWidth: kind.memoryWidth(size: size),
            mnemonic: kind.rawValue
        )
        let imm = try immediateAny(instruction.operands[3])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .vexThreeOpImm(kind, size: size, destination: dst, source1: src1, source2: src2, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// VPSLLW/D/Q imm8 etc. — `xmm/ymm dst, xmm/ymm src, imm8`.
    private static func parseVexShiftImmediate(_ kind: X86.VexImmediateShiftKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let (size1, src) = try parseVectorRegister(instruction.operands[1], mnemonic: kind.rawValue, scalarOnly: false)
        guard size == size1 else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): vector size of operands must match")
        }
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .vexShiftImmediate(kind, size: size, destination: dst, source: src, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// VMOV family — two operands; either side may be memory.
    private static func parseVexMov(_ kind: X86.VexMovKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let lhs = try parseVexMovOperand(instruction.operands[0], mnemonic: kind.rawValue)
        let rhs = try parseVexMovOperand(instruction.operands[1], mnemonic: kind.rawValue)
        // Vector sizes must agree.
        let size: X86.AVXVectorSize
        switch (lhs.size, rhs.size) {
        case let (.some(a), .some(b)):
            guard a == b else { throw AssemblerError.unsupportedOperand("\(kind.rawValue): vector size of operands must match") }
            size = a
        case let (.some(a), nil): size = a
        case let (nil, .some(b)): size = b
        case (nil, nil):
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): need at least one register operand to pick vector size")
        }
        return .vexMov(kind, size: size, destination: lhs.operand, source: rhs.operand)
    }

    private static func parseVexMovOperand(_ text: String, mnemonic: String) throws -> (operand: X86.VectorOrMemory, size: X86.AVXVectorSize?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let xmm = parseXMMRegister(trimmed) { return (.register(xmm.number), .xmm) }
        if let ymm = parseYMMRegister(trimmed) { return (.register(ymm.number), .ymm) }
        if let (width, body) = stripSizeHint(trimmed) {
            let size: X86.AVXVectorSize
            switch width {
            case .xmmword: size = .xmm
            case .ymmword: size = .ymm
            default: throw AssemblerError.unsupportedOperand("\(mnemonic): memory operand width must be xmmword or ymmword")
            }
            return (.memory(try memoryOperand(body)), size)
        }
        if trimmed.hasPrefix("[") {
            // Width is implied by the other operand.
            return (.memory(try memoryOperand(trimmed)), nil)
        }
        throw AssemblerError.unsupportedOperand("\(mnemonic): expected an XMM/YMM register or memory operand")
    }

    /// VSQRTPS/PD, VRSQRTPS, VRCPPS — `xmm/ymm` two-op shape (the VEX
    /// vvvv slot is reserved and must be all-ones).
    private static func parseVexUnary(_ kind: X86.VexUnaryKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let src = try parseVectorOrMemory(
            instruction.operands[1],
            size: size,
            memoryWidth: kind.memoryWidth(size: size),
            mnemonic: kind.rawValue
        )
        return .vexUnary(kind, size: size, destination: dst, source: src)
    }

    /// VPADD/VPSUB/VPAND/VPANDN/VPOR/VPXOR — `xmm/ymm` three-op shape.
    private static func parseVexPackedInteger(_ kind: X86.VexPackedIntegerKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        // VPSLLW/VPSRLW/... share the mnemonic with their imm8 form
        // (VexImmediateShiftKind). Route to the imm8 case when the
        // third operand parses as an immediate.
        if let immKind = X86.VexImmediateShiftKind(rawValue: kind.rawValue),
           let immValue = try? immediateAny(instruction.operands[2]) {
            return try makeVexShiftImmediate(immKind, dstText: instruction.operands[0], srcText: instruction.operands[1], imm: immValue)
        }
        let (size, dst) = try parseVectorRegister(instruction.operands[0], mnemonic: kind.rawValue, scalarOnly: false)
        let (size1, src1) = try parseVectorRegister(instruction.operands[1], mnemonic: kind.rawValue, scalarOnly: false)
        guard size == size1 else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): vector size of operands must match")
        }
        let src2 = try parseVectorOrMemory(
            instruction.operands[2],
            size: size,
            memoryWidth: size.packedMemoryWidth,
            mnemonic: kind.rawValue
        )
        return .vexPackedInteger(kind, size: size, destination: dst, source1: src1, source2: src2)
    }

    private static func makeVexShiftImmediate(_ kind: X86.VexImmediateShiftKind, dstText: String, srcText: String, imm: Int64) throws -> X86.Instruction {
        let (size, dst) = try parseVectorRegister(dstText, mnemonic: kind.rawValue, scalarOnly: false)
        let (size1, src) = try parseVectorRegister(srcText, mnemonic: kind.rawValue, scalarOnly: false)
        guard size == size1 else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): vector size of operands must match")
        }
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .vexShiftImmediate(kind, size: size, destination: dst, source: src, immediate: UInt8(truncatingIfNeeded: imm))
    }

    private static func parseVectorRegister(_ text: String, mnemonic: String, scalarOnly: Bool) throws -> (X86.AVXVectorSize, UInt8) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let xmm = parseXMMRegister(trimmed) {
            return (.xmm, xmm.number)
        }
        if let ymm = parseYMMRegister(trimmed) {
            guard !scalarOnly else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): YMM operands are not allowed for scalar instructions")
            }
            return (.ymm, ymm.number)
        }
        throw AssemblerError.unsupportedOperand("\(mnemonic): expected an XMM or YMM register")
    }

    static func parseYMMRegister(_ text: String) -> X86.YMMRegister? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("ymm") else { return nil }
        guard let n = UInt8(trimmed.dropFirst(3)), n < 16 else { return nil }
        return X86.YMMRegister(number: n)
    }

    private static func parseVectorOrMemory(_ text: String, size: X86.AVXVectorSize, memoryWidth: X86.RegisterWidth, mnemonic: String) throws -> X86.VectorOrMemory {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let xmm = parseXMMRegister(trimmed) {
            guard size == .xmm else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): expected a YMM register")
            }
            return .register(xmm.number)
        }
        if let ymm = parseYMMRegister(trimmed) {
            guard size == .ymm else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): expected an XMM register")
            }
            return .register(ymm.number)
        }
        if let (width, body) = stripSizeHint(trimmed) {
            guard width == memoryWidth else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): memory operand width disagrees with mnemonic")
            }
            return .memory(try memoryOperand(body))
        }
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed))
        }
        throw AssemblerError.unsupportedOperand("\(mnemonic): expected a vector register or memory operand")
    }

    /// CRC32 — `r32_or_r64, r/m{8|16|32|64}`. The destination width is
    /// dictated by the source: r32 for byte/word/dword sources, r64
    /// for qword sources.
    private static func parseCrc32(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "crc32",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let destination = try register(instruction.operands[0])
        guard destination.width == .dword || destination.width == .qword else {
            throw AssemblerError.unsupportedOperand("crc32: destination must be a 32- or 64-bit GPR")
        }
        let source = try parseCrc32Source(instruction.operands[1])
        return .crc32(destination: destination, source: source)
    }

    private static func parseCrc32Source(_ text: String) throws -> X86.RegisterOrMemory {
        if let reg = try? register(text) {
            return .register(reg)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (width, body) = stripSizeHint(trimmed) {
            return .memory(try memoryOperand(body), width: width)
        }
        if trimmed.hasPrefix("[") {
            throw AssemblerError.unsupportedOperand("crc32: memory source requires an explicit size hint")
        }
        throw AssemblerError.unsupportedOperand("crc32: unrecognized source")
    }

    /// PINSR{B,W,D,Q} — `xmm, r/m, imm8`.
    private static func parseSSEInsertLane(_ kind: X86.SSEInsertLaneKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseGPRMemoryWithWidth(
            instruction.operands[1],
            gprWidth: kind.gprWidth,
            memoryWidth: kind.memoryWidth,
            mnemonic: kind.rawValue
        )
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .sseInsertLane(kind, destination: destination, source: source, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// PEXTR{B,W,D,Q} — `r/m, xmm, imm8`.
    private static func parseSSEExtractLane(_ kind: X86.SSEExtractLaneKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let destination = try parseGPRMemoryWithWidth(
            instruction.operands[0],
            gprWidth: kind.gprWidth,
            memoryWidth: kind.memoryWidth,
            mnemonic: kind.rawValue
        )
        guard let source = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): source must be an XMM register")
        }
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .sseExtractLane(kind, destination: destination, source: source, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// INSERTPS — `xmm, xmm/m32, imm8`.
    private static func parseInsertps(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "insertps",
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("insertps: destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: .dword,
            mnemonic: "insertps"
        )
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "insertps", value: imm, range: 0...255)
        }
        return .insertps(destination: destination, source: source, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// EXTRACTPS — `r32/r64/m32, xmm, imm8`.
    private static func parseExtractps(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "extractps",
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        let destination = try parseExtractpsDestination(instruction.operands[0])
        guard let source = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("extractps: source must be an XMM register")
        }
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "extractps", value: imm, range: 0...255)
        }
        return .extractps(destination: destination, source: source, immediate: UInt8(truncatingIfNeeded: imm))
    }

    private static func parseExtractpsDestination(_ text: String) throws -> X86.RegisterOrMemory {
        if let reg = try? register(text) {
            return .register(reg)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (width, body) = stripSizeHint(trimmed) {
            guard width == .dword else {
                throw AssemblerError.unsupportedOperand("extractps: memory destination must be 32-bit")
            }
            return .memory(try memoryOperand(body), width: width)
        }
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed), width: .dword)
        }
        throw AssemblerError.unsupportedOperand("extractps: unrecognized destination")
    }

    /// BLENDVPS/BLENDVPD/PBLENDVB — `xmm, xmm/m128 [, xmm0]`. The third
    /// operand is optional; when present it must literally be `xmm0`.
    private static func parseSSEBlendv(_ kind: X86.SSEBlendvKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 || instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 or 3 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: .xmmword,
            mnemonic: kind.rawValue
        )
        if instruction.operands.count == 3 {
            guard let mask = parseXMMRegister(instruction.operands[2]), mask.number == 0 else {
                throw AssemblerError.unsupportedOperand("\(kind.rawValue): mask operand must be xmm0")
            }
        }
        return .sseBlendv(kind, destination: destination, source: source)
    }

    /// Helper for PINSR/PEXTR: accept a GPR of `gprWidth` or memory of
    /// `memoryWidth`.
    private static func parseGPRMemoryWithWidth(_ text: String, gprWidth: X86.RegisterWidth, memoryWidth: X86.RegisterWidth, mnemonic: String) throws -> X86.RegisterOrMemory {
        if let reg = try? register(text) {
            guard reg.width == gprWidth else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): GPR operand width disagrees with mnemonic")
            }
            return .register(reg)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (width, body) = stripSizeHint(trimmed) {
            guard width == memoryWidth else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): memory operand width disagrees with mnemonic")
            }
            return .memory(try memoryOperand(body), width: width)
        }
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed), width: memoryWidth)
        }
        throw AssemblerError.unsupportedOperand("\(mnemonic): expected a register or memory operand")
    }

    /// SSE4.1 imm8 ops (ROUND/BLEND/DPP/MPSADBW etc.).
    private static func parseSSE41Immediate(_ kind: X86.SSE41ImmediateKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: kind.sourceWidth,
            mnemonic: kind.rawValue
        )
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .sse41Imm(kind, destination: destination, source: source, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// SSE4.1 PMUL/PMIN/PMAX/PACKUSDW/PCMPEQQ/PHMINPOSUW/PTEST.
    private static func parseSSE41Packed(_ kind: X86.SSE41PackedKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: .xmmword,
            mnemonic: kind.rawValue
        )
        return .sse41Packed(kind, destination: destination, source: source)
    }

    /// MOVNTDQA — `xmm, m128`.
    private static func parseMovntdqa(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "movntdqa",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("movntdqa: destination must be an XMM register")
        }
        let memory = try parseSizedMemory(instruction.operands[1], expected: .xmmword, mnemonic: "movntdqa")
        return .movntdqa(destination: destination, memory: memory)
    }

    /// PMOVSX*/PMOVZX* — `xmm, xmm/m{16|32|64}` widening pack move.
    private static func parseSSEPackExtend(_ kind: X86.SSEPackExtendKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: kind.sourceWidth,
            mnemonic: kind.rawValue
        )
        return .ssePackExtend(kind, destination: destination, source: source)
    }

    /// SSSE3 `xmm, xmm/m128`.
    private static func parseSSSE3(_ kind: X86.SSSE3Kind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: .xmmword,
            mnemonic: kind.rawValue
        )
        return .ssse3(kind, destination: destination, source: source)
    }

    /// PALIGNR — `xmm, xmm/m128, imm8`.
    private static func parsePalignr(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "palignr",
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("palignr: destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: .xmmword,
            mnemonic: "palignr"
        )
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: "palignr", value: imm, range: 0...255)
        }
        return .palignr(destination: destination, source: source, immediate: UInt8(truncatingIfNeeded: imm))
    }

    /// SSE3 `xmm, xmm/m128` (MOVDDUP uses m64).
    private static func parseSSE3(_ kind: X86.SSE3Kind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: kind.sourceWidth,
            mnemonic: kind.rawValue
        )
        if kind == .lddqu, case .register = source {
            throw AssemblerError.unsupportedOperand("lddqu: source must be a memory operand")
        }
        return .sse3(kind, destination: destination, source: source)
    }

    /// PREFETCH* — single byte-pointer memory operand.
    private static func parsePrefetch(_ kind: X86.PrefetchKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let memory = try parseSizedMemory(instruction.operands[0], expected: .byte, mnemonic: kind.rawValue)
        return .prefetch(kind, memory: memory)
    }

    /// LDMXCSR / STMXCSR — single memory operand (m32).
    private static func parseMXCSR(_ kind: X86.MXCSRKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let memory = try parseSizedMemory(instruction.operands[0], expected: .dword, mnemonic: kind.rawValue)
        return .mxcsr(kind, memory: memory)
    }

    /// MOVNTPS/MOVNTPD/MOVNTDQ — `m128, xmm` (non-temporal store).
    private static func parseSSENonTemporalStore(_ kind: X86.SSENonTemporalKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let memory = try parseSizedMemory(instruction.operands[0], expected: .xmmword, mnemonic: kind.rawValue)
        guard let source = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): source must be an XMM register")
        }
        return .sseNonTemporalStore(kind, memory: memory, source: source)
    }

    /// MOVNTI — `m32/m64, r32/r64`. Width must match between operands.
    private static func parseMovnti(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "movnti",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let source = try register(instruction.operands[1])
        guard source.width == .dword || source.width == .qword else {
            throw AssemblerError.unsupportedOperand("movnti: source must be a 32- or 64-bit GPR")
        }
        let memory = try parseSizedMemory(instruction.operands[0], expected: source.width, mnemonic: "movnti")
        return .movnti(memory: memory, source: source)
    }

    /// Helper: parse a memory operand requiring the given size hint.
    /// Accepts a hint-less `[...]` only when it cannot be confused
    /// with a missing hint (callers force a hint by passing `expected`).
    private static func parseSizedMemory(_ text: String, expected: X86.RegisterWidth, mnemonic: String) throws -> X86.MemoryOperand {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (width, body) = stripSizeHint(trimmed) {
            guard width == expected else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): memory operand width disagrees with mnemonic")
            }
            return try memoryOperand(body)
        }
        if trimmed.hasPrefix("[") {
            return try memoryOperand(trimmed)
        }
        throw AssemblerError.unsupportedOperand("\(mnemonic): expected a memory operand")
    }

    /// PMOVMSKB/MOVMSKPS/MOVMSKPD — `r32_or_r64, xmm`.
    private static func parseSSEMaskExtract(_ kind: X86.SSEMaskExtractKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let destination = try register(instruction.operands[0])
        guard destination.width == .dword || destination.width == .qword else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be a 32- or 64-bit GPR")
        }
        guard let source = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): source must be an XMM register")
        }
        return .sseMaskExtract(kind, destination: destination, source: source)
    }

    /// MASKMOVDQU — `xmm_source, xmm_mask`. Destination is the
    /// implicit `[RDI]`.
    private static func parseMaskMovDqu(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "maskmovdqu",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        guard let source = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("maskmovdqu: source must be an XMM register")
        }
        guard let mask = parseXMMRegister(instruction.operands[1]) else {
            throw AssemblerError.unsupportedOperand("maskmovdqu: mask must be an XMM register")
        }
        return .maskMovDqu(source: source, mask: mask)
    }

    /// MOVLPS/MOVHPS/MOVLPD/MOVHPD/MOVHLPS/MOVLHPS — two operands of
    /// type XMM or m64. The encoder picks the load/store opcode based
    /// on which side is memory.
    private static func parseSSEHalfMove(_ kind: X86.SSEHalfMoveKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try parseHalfMoveOperand(instruction.operands[0], kind: kind)
        let src = try parseHalfMoveOperand(instruction.operands[1], kind: kind)
        return .sseHalfMove(kind, destination: dst, source: src)
    }

    private static func parseHalfMoveOperand(_ text: String, kind: X86.SSEHalfMoveKind) throws -> X86.XMMOrMemory {
        if let xmm = parseXMMRegister(text) {
            return .register(xmm)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (width, body) = stripSizeHint(trimmed) {
            guard width == kind.partnerWidth else {
                throw AssemblerError.unsupportedOperand(
                    "\(kind.rawValue): memory operand width disagrees with mnemonic"
                )
            }
            return .memory(try memoryOperand(body))
        }
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed))
        }
        throw AssemblerError.unsupportedOperand("\(kind.rawValue): expected xmm register or memory operand")
    }

    /// CMPPS/CMPPD/CMPSS/CMPSD — `xmm, xmm/m128, imm8`. Same shape as
    /// the shuffle family.
    private static func parseSSECompare(_ kind: X86.SSECompareKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 3 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "3 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: kind.sourceWidth,
            mnemonic: kind.rawValue
        )
        let imm = try immediateAny(instruction.operands[2])
        guard imm >= 0 && imm <= 255 else {
            throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: imm, range: 0...255)
        }
        return .sseCompare(kind, destination: destination, source: source, predicate: UInt8(truncatingIfNeeded: imm))
    }

    /// `MOVD` / `MOVQ` between an XMM register and a GPR or memory
    /// operand. The first operand's type (XMM vs GPR/memory)
    /// determines whether it's the load or store direction.
    private static func parseMovDQ(_ kind: X86.MovDQKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let lhs = instruction.operands[0]
        let rhs = instruction.operands[1]

        if let xmm = parseXMMRegister(lhs) {
            let source = try parseMovDQGPROperand(rhs, width: kind.gprWidth, mnemonic: kind.rawValue)
            return .movDQ(kind, direction: .load, xmm: xmm, gpr: source)
        }
        if let xmm = parseXMMRegister(rhs) {
            let destination = try parseMovDQGPROperand(lhs, width: kind.gprWidth, mnemonic: kind.rawValue)
            return .movDQ(kind, direction: .store, xmm: xmm, gpr: destination)
        }
        throw AssemblerError.unsupportedOperand("\(kind.rawValue): one operand must be an XMM register")
    }

    private static func parseMovDQGPROperand(_ text: String, width: X86.RegisterWidth, mnemonic: String) throws -> X86.RegisterOrMemory {
        let classified = try classifyOperand(text)
        switch classified {
        case .register(let r):
            guard r.width == width else {
                throw AssemblerError.unsupportedOperand("\(mnemonic): register operand must be \(width.rawValue)-bit")
            }
            return .register(r)
        case .memory(let m, let explicit):
            let resolved = try resolveMemoryWidth(explicit: explicit, paired: width, mnemonic: mnemonic)
            return .memory(m, width: resolved)
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(mnemonic): operand cannot be an immediate")
        }
    }

    /// `CVTSI2SS xmm, r/m32-or-64` and `CVTSI2SD xmm, r/m32-or-64`.
    /// Destination is XMM; source is a GPR or memory of dword/qword.
    private static func parseSSEIntToFloat(_ kind: X86.SSEIntToFloatKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let classified = try classifyOperand(instruction.operands[1])
        switch classified {
        case .register(let r):
            guard r.width == .dword || r.width == .qword else {
                throw AssemblerError.unsupportedOperand("\(kind.rawValue): source register must be 32- or 64-bit")
            }
            return .sseIntToFloat(kind, destination: destination, source: .register(r))
        case .memory(let m, let explicit):
            guard let width = explicit, width == .dword || width == .qword else {
                throw AssemblerError.unsupportedOperand("\(kind.rawValue): memory source needs an explicit `dword ptr` or `qword ptr` hint")
            }
            return .sseIntToFloat(kind, destination: destination, source: .memory(m, width: width))
        case .immediate:
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): source cannot be an immediate")
        }
    }

    /// `CVTSx2SI` / `CVTTSx2SI r32-or-64, xmm/m32-or-m64`.
    private static func parseSSEFloatToInt(_ kind: X86.SSEFloatToIntKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let destination = try register(instruction.operands[0])
        guard destination.width == .dword || destination.width == .qword else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination register must be 32- or 64-bit")
        }
        let source = try parseXMMOrMemorySource(
            instruction.operands[1],
            width: kind.sourceMemoryWidth,
            mnemonic: kind.rawValue
        )
        return .sseFloatToInt(kind, destination: destination, source: source)
    }

    private static func parseSSEArithmetic(_ kind: X86.SSEArithmeticKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        guard let destination = parseXMMRegister(instruction.operands[0]) else {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): destination must be an XMM register")
        }
        let source = try parseXMMOrMemorySource(instruction.operands[1], width: kind.memoryWidth, mnemonic: kind.rawValue)
        return .sseArithmetic(kind, destination: destination, source: source)
    }

    /// Parse an XMM register or a memory operand of the given width.
    /// Shared between SSE MOV (the load form), SSE arithmetic, and any
    /// future SSE op that takes an `xmm, xmm/m` shape.
    private static func parseXMMOrMemorySource(_ text: String, width: X86.RegisterWidth, mnemonic: String) throws -> X86.XMMOrMemory {
        if let xmm = parseXMMRegister(text) {
            return .register(xmm)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (hintedWidth, body) = stripSizeHint(trimmed) {
            guard hintedWidth == width else {
                throw AssemblerError.unsupportedOperand(
                    "\(mnemonic): memory operand width disagrees with mnemonic"
                )
            }
            return .memory(try memoryOperand(body))
        }
        if trimmed.hasPrefix("[") {
            return .memory(try memoryOperand(trimmed))
        }
        throw AssemblerError.unsupportedOperand("\(mnemonic): expected xmm register or memory operand")
    }

    private static func parseSSEMov(_ kind: X86.SSEMovKind, _ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: kind.rawValue,
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let dst = try parseXMMOperand(instruction.operands[0], kind: kind)
        let src = try parseXMMOperand(instruction.operands[1], kind: kind)
        if case .memory = dst, case .memory = src {
            throw AssemblerError.unsupportedOperand("\(kind.rawValue): cannot have two memory operands")
        }
        return .sseMov(kind, destination: dst, source: src)
    }

    private static func parseInterrupt(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 1 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "int",
                expected: "1 operand",
                actual: instruction.operands.count
            )
        }
        let value = try immediateAny(instruction.operands[0])
        guard value >= 0 && value <= 0xFF else {
            throw AssemblerError.immediateOutOfRange(instruction: "int", value: value, range: 0...0xFF)
        }
        // INT 3 has a dedicated single-byte opcode (0xCC) that's
        // semantically identical to the general form `CD 03`; pick the
        // shorter encoding so disassembly canonicalises to "int 3".
        if value == 3 {
            return .zeroOperand(.int3)
        }
        return .interrupt(vector: UInt8(truncatingIfNeeded: value))
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
            ("ymmword ptr", .ymmword),
            ("xmmword ptr", .xmmword),
            ("byte ptr",    .byte),
            ("word ptr",    .word),
            ("dword ptr",   .dword),
            ("qword ptr",   .qword),
            ("ymmword",     .ymmword),
            ("xmmword",     .xmmword),
            ("byte",        .byte),
            ("word",        .word),
            ("dword",       .dword),
            ("qword",       .qword),
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
        case .xmmword, .ymmword:
            throw AssemblerError.unsupportedOperand("\(mnemonic): immediate with vector width not supported")
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
