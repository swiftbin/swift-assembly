import Foundation

internal enum X86InstructionFormatter {
    /// Render a decoded instruction as Intel-syntax text.
    static func format(_ instruction: X86.Instruction) -> String {
        switch instruction {
        case .zeroOperand(let kind):
            return kind.rawValue
        case .mov(let destination, let source):
            return formatReadWrite(mnemonic: "mov", destination: destination, source: source)
        case .binaryAlu(let kind, let destination, let source):
            return formatReadWrite(mnemonic: kind.rawValue, destination: destination, source: source)
        case .unaryAlu(let kind, let target):
            return "\(kind.rawValue) \(formatStandaloneTarget(target))"
        case .test(let left, let right):
            return formatReadWrite(mnemonic: "test", destination: left, source: right)
        case .shift(let kind, let target, let count):
            return "\(kind.rawValue) \(formatStandaloneTarget(target)), \(formatShiftCount(count))"
        case .doubleShift(let kind, let target, let source, let count):
            // The source register supplies the width, so the memory target
            // doesn't need an explicit size hint.
            let dst = formatPairedTarget(target)
            let src = X86.RegisterTable.canonicalName(for: source)
            return "\(kind.rawValue) \(dst), \(src), \(formatShiftCount(count))"
        case .jump(let target):
            return "jmp \(formatBranchTarget(target))"
        case .conditionalJump(let cond, let target):
            return "j\(cond.rawValue) \(formatBranchTarget(target))"
        case .call(let target):
            return "call \(formatBranchTarget(target))"
        case .loop(let kind, let target):
            return "\(kind.rawValue) \(formatBranchTarget(target))"
        case .jumpIndirect(let target):
            return "jmp \(formatIndirectTarget(target))"
        case .callIndirect(let target):
            return "call \(formatIndirectTarget(target))"
        case .enter(let alloc, let nesting):
            return "enter \(alloc), \(nesting)"
        case .mulDiv(let kind, let target):
            return "\(kind.rawValue) \(formatStandaloneTarget(target))"
        case .imulRegister(let dst, let source):
            return "imul \(X86.RegisterTable.canonicalName(for: dst)), \(formatPairedTarget(source))"
        case .imulImmediate(let dst, let source, let imm):
            return "imul \(X86.RegisterTable.canonicalName(for: dst)), \(formatPairedTarget(source)), \(imm)"
        case .push(let operand):
            return "push \(formatPushOperand(operand))"
        case .pop(let target):
            return "pop \(formatStandaloneTarget(target))"
        case .lea(let dst, let mem):
            return "lea \(X86.RegisterTable.canonicalName(for: dst)), \(formatMemory(mem))"
        case .extendingMove(let kind, let dst, let source):
            let dstName = X86.RegisterTable.canonicalName(for: dst)
            return "\(kind.rawValue) \(dstName), \(formatExtendingSource(source))"
        case .bswap(let reg):
            return "bswap \(X86.RegisterTable.canonicalName(for: reg))"
        case .xchg(let target, let register):
            return "xchg \(formatPairedTarget(target)), \(X86.RegisterTable.canonicalName(for: register))"
        case .xadd(let target, let source):
            return "xadd \(formatPairedTarget(target)), \(X86.RegisterTable.canonicalName(for: source))"
        case .cmpxchg(let target, let source):
            return "cmpxchg \(formatPairedTarget(target)), \(X86.RegisterTable.canonicalName(for: source))"
        case .cmpxchgWide(let kind, let mem):
            return "\(kind.rawValue) \(formatMemory(mem))"
        case .cmovcc(let cond, let dst, let source):
            return "cmov\(cond.rawValue) \(X86.RegisterTable.canonicalName(for: dst)), \(formatPairedTarget(source))"
        case .setcc(let cond, let target):
            return "set\(cond.rawValue) \(formatStandaloneTarget(target))"
        case .bitTest(let kind, let target, let source):
            let sourceStr: String
            switch source {
            case .register(let r): sourceStr = X86.RegisterTable.canonicalName(for: r)
            case .immediate(let v): sourceStr = String(v)
            }
            // If source is immediate, target needs a size hint for memory
            // since the width isn't carried by a paired register.
            let needsHint: Bool
            if case .immediate = source { needsHint = true } else { needsHint = false }
            let targetStr = needsHint ? formatStandaloneTarget(target) : formatPairedTarget(target)
            return "\(kind.rawValue) \(targetStr), \(sourceStr)"
        case .bitScan(let kind, let dst, let source):
            return "\(kind.rawValue) \(X86.RegisterTable.canonicalName(for: dst)), \(formatPairedTarget(source))"
        case .bitCount(let kind, let dst, let source):
            return "\(kind.rawValue) \(X86.RegisterTable.canonicalName(for: dst)), \(formatPairedTarget(source))"
        case .stringOp(let kind, let prefix):
            switch prefix {
            case .none:
                return kind.rawValue
            case .some(.f3):
                // F3 reads as REPE on CMPS/SCAS, REP on the others.
                return "\(kind.isComparison ? "repe" : "rep") \(kind.rawValue)"
            case .some(.f2):
                return "repne \(kind.rawValue)"
            }
        case .inFromPort(let target, let port):
            return "in \(X86.RegisterTable.canonicalName(for: target)), \(formatPort(port))"
        case .outToPort(let source, let port):
            return "out \(formatPort(port)), \(X86.RegisterTable.canonicalName(for: source))"
        case .interrupt(let vector):
            return "int \(vector)"
        case .clflush(let mem):
            return "clflush \(formatMemory(mem))"
        case .invlpg(let mem):
            return "invlpg \(formatMemory(mem))"
        case .descriptorTable(let kind, let mem):
            return "\(kind.rawValue) \(formatMemory(mem))"
        case .systemRM(let kind, let target):
            return "\(kind.rawValue) \(formatPairedTarget(target))"
        case .movFromSystemRegister(let kind, let dst, let number):
            return "mov \(X86.RegisterTable.canonicalName(for: dst)), \(kind.rawValue)\(number)"
        case .movToSystemRegister(let kind, let number, let source):
            return "mov \(kind.rawValue)\(number), \(X86.RegisterTable.canonicalName(for: source))"
        case .lar(let dst, let source):
            return "lar \(X86.RegisterTable.canonicalName(for: dst)), \(formatPairedTarget(source))"
        case .lsl(let dst, let source):
            return "lsl \(X86.RegisterTable.canonicalName(for: dst)), \(formatPairedTarget(source))"
        case .sseMov(let kind, let dst, let src):
            return "\(kind.rawValue) \(formatXMMOrMemory(dst, width: kind.memoryWidth)), \(formatXMMOrMemory(src, width: kind.memoryWidth))"
        case .sseArithmetic(let kind, let dst, let src):
            return "\(kind.rawValue) xmm\(dst.number), \(formatXMMOrMemory(src, width: kind.memoryWidth))"
        case .sseIntToFloat(let kind, let dst, let src):
            let srcStr: String
            switch src {
            case .register(let r):
                srcStr = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, let w):
                srcStr = "\(sizeHintPrefix(w)) \(formatMemory(m))"
            }
            return "\(kind.rawValue) xmm\(dst.number), \(srcStr)"
        case .sseFloatToInt(let kind, let dst, let src):
            return "\(kind.rawValue) \(X86.RegisterTable.canonicalName(for: dst)), \(formatXMMOrMemory(src, width: kind.sourceMemoryWidth))"
        case .ssePackedInteger(let kind, let dst, let src):
            return "\(kind.rawValue) xmm\(dst.number), \(formatXMMOrMemory(src, width: .xmmword))"
        case .sseShiftImmediate(let kind, let target, let imm):
            return "\(kind.rawValue) xmm\(target.number), \(imm)"
        case .sseShuffle(let kind, let dst, let src, let imm):
            return "\(kind.rawValue) xmm\(dst.number), \(formatXMMOrMemory(src, width: .xmmword)), \(imm)"
        case .sseCompare(let kind, let dst, let src, let pred):
            return "\(kind.rawValue) xmm\(dst.number), \(formatXMMOrMemory(src, width: kind.sourceWidth)), \(pred)"
        case .sseHalfMove(let kind, let dst, let src):
            return "\(kind.rawValue) \(formatXMMOrMemory(dst, width: kind.partnerWidth)), \(formatXMMOrMemory(src, width: kind.partnerWidth))"
        case .sseMaskExtract(let kind, let dst, let src):
            return "\(kind.rawValue) \(X86.RegisterTable.canonicalName(for: dst)), xmm\(src.number)"
        case .maskMovDqu(let source, let mask):
            return "maskmovdqu xmm\(source.number), xmm\(mask.number)"
        case .mxcsr(let kind, let memory):
            return "\(kind.rawValue) \(formatSizedMemory(memory, width: .dword))"
        case .sseNonTemporalStore(let kind, let memory, let source):
            return "\(kind.rawValue) \(formatSizedMemory(memory, width: .xmmword)), xmm\(source.number)"
        case .movnti(let memory, let source):
            return "movnti \(formatSizedMemory(memory, width: source.width)), \(X86.RegisterTable.canonicalName(for: source))"
        case .prefetch(let kind, let memory):
            return "\(kind.rawValue) \(formatSizedMemory(memory, width: .byte))"
        case .sse3(let kind, let dst, let src):
            return "\(kind.rawValue) xmm\(dst.number), \(formatXMMOrMemory(src, width: kind.sourceWidth))"
        case .ssse3(let kind, let dst, let src):
            return "\(kind.rawValue) xmm\(dst.number), \(formatXMMOrMemory(src, width: .xmmword))"
        case .palignr(let dst, let src, let imm):
            return "palignr xmm\(dst.number), \(formatXMMOrMemory(src, width: .xmmword)), \(imm)"
        case .ssePackExtend(let kind, let dst, let src):
            return "\(kind.rawValue) xmm\(dst.number), \(formatXMMOrMemory(src, width: kind.sourceWidth))"
        case .sse41Packed(let kind, let dst, let src):
            return "\(kind.rawValue) xmm\(dst.number), \(formatXMMOrMemory(src, width: .xmmword))"
        case .movntdqa(let dst, let mem):
            return "movntdqa xmm\(dst.number), \(formatSizedMemory(mem, width: .xmmword))"
        case .sse41Imm(let kind, let dst, let src, let imm):
            return "\(kind.rawValue) xmm\(dst.number), \(formatXMMOrMemory(src, width: kind.sourceWidth)), \(imm)"
        case .sseInsertLane(let kind, let dst, let src, let imm):
            let srcStr: String
            switch src {
            case .register(let r): srcStr = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, _): srcStr = "\(sizeHintPrefix(kind.memoryWidth)) \(formatMemory(m))"
            }
            return "\(kind.rawValue) xmm\(dst.number), \(srcStr), \(imm)"
        case .sseExtractLane(let kind, let dst, let src, let imm):
            let dstStr: String
            switch dst {
            case .register(let r): dstStr = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, _): dstStr = "\(sizeHintPrefix(kind.memoryWidth)) \(formatMemory(m))"
            }
            return "\(kind.rawValue) \(dstStr), xmm\(src.number), \(imm)"
        case .insertps(let dst, let src, let imm):
            return "insertps xmm\(dst.number), \(formatXMMOrMemory(src, width: .dword)), \(imm)"
        case .extractps(let dst, let src, let imm):
            let dstStr: String
            switch dst {
            case .register(let r): dstStr = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, _): dstStr = "\(sizeHintPrefix(.dword)) \(formatMemory(m))"
            }
            return "extractps \(dstStr), xmm\(src.number), \(imm)"
        case .sseBlendv(let kind, let dst, let src):
            return "\(kind.rawValue) xmm\(dst.number), \(formatXMMOrMemory(src, width: .xmmword)), xmm0"
        case .crc32(let dst, let src):
            let srcStr: String
            switch src {
            case .register(let r): srcStr = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, let w): srcStr = "\(sizeHintPrefix(w)) \(formatMemory(m))"
            }
            return "crc32 \(X86.RegisterTable.canonicalName(for: dst)), \(srcStr)"
        case .vexArithmetic(let kind, let size, let dst, let src1, let src2):
            let prefix = (kind.isScalar || size == .xmm) ? "xmm" : "ymm"
            let memWidth = kind.memoryWidth(size: size)
            let src2Str: String
            switch src2 {
            case .register(let n): src2Str = "\(prefix)\(n)"
            case .memory(let m):   src2Str = "\(sizeHintPrefix(memWidth)) \(formatMemory(m))"
            }
            return "\(kind.rawValue) \(prefix)\(dst), \(prefix)\(src1), \(src2Str)"
        case .vexPackedInteger(let kind, let size, let dst, let src1, let src2):
            let prefix = size == .xmm ? "xmm" : "ymm"
            let memWidth = size.packedMemoryWidth
            let src2Str: String
            switch src2 {
            case .register(let n): src2Str = "\(prefix)\(n)"
            case .memory(let m):   src2Str = "\(sizeHintPrefix(memWidth)) \(formatMemory(m))"
            }
            return "\(kind.rawValue) \(prefix)\(dst), \(prefix)\(src1), \(src2Str)"
        case .vexUnary(let kind, let size, let dst, let src):
            let prefix = size == .xmm ? "xmm" : "ymm"
            let srcStr: String
            switch src {
            case .register(let n): srcStr = "\(prefix)\(n)"
            case .memory(let m):   srcStr = "\(sizeHintPrefix(kind.memoryWidth(size: size))) \(formatMemory(m))"
            }
            return "\(kind.rawValue) \(prefix)\(dst), \(srcStr)"
        case .vexMov(let kind, let size, let dst, let src):
            let prefix = size == .xmm ? "xmm" : "ymm"
            let w = size.packedMemoryWidth
            func render(_ op: X86.VectorOrMemory) -> String {
                switch op {
                case .register(let n): return "\(prefix)\(n)"
                case .memory(let m):   return "\(sizeHintPrefix(w)) \(formatMemory(m))"
                }
            }
            return "\(kind.rawValue) \(render(dst)), \(render(src))"
        case .vexShiftImmediate(let kind, let size, let dst, let src, let imm):
            let prefix = size == .xmm ? "xmm" : "ymm"
            return "\(kind.rawValue) \(prefix)\(dst), \(prefix)\(src), \(imm)"
        case .vexShuffleImm(let kind, let size, let dst, let src, let imm):
            let prefix = size == .xmm ? "xmm" : "ymm"
            let srcStr: String
            switch src {
            case .register(let n): srcStr = "\(prefix)\(n)"
            case .memory(let m):   srcStr = "\(sizeHintPrefix(size.packedMemoryWidth)) \(formatMemory(m))"
            }
            return "\(kind.rawValue) \(prefix)\(dst), \(srcStr), \(imm)"
        case .vexThreeOpImm(let kind, let size, let dst, let src1, let src2, let imm):
            let prefix = (kind.isScalar || size == .xmm) ? "xmm" : "ymm"
            let src2Str: String
            switch src2 {
            case .register(let n): src2Str = "\(prefix)\(n)"
            case .memory(let m):   src2Str = "\(sizeHintPrefix(kind.memoryWidth(size: size))) \(formatMemory(m))"
            }
            return "\(kind.rawValue) \(prefix)\(dst), \(prefix)\(src1), \(src2Str), \(imm)"
        case .vexMaskExtract(let kind, let size, let dst, let src):
            let prefix = size == .xmm ? "xmm" : "ymm"
            return "\(kind.rawValue) \(X86.RegisterTable.canonicalName(for: dst)), \(prefix)\(src)"
        case .bmiAndn(let dst, let src1, let src2):
            let src2Str: String
            switch src2 {
            case .register(let r): src2Str = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, let w): src2Str = "\(sizeHintPrefix(w)) \(formatMemory(m))"
            }
            return "andn \(X86.RegisterTable.canonicalName(for: dst)), \(X86.RegisterTable.canonicalName(for: src1)), \(src2Str)"
        case .bmiUnary(let kind, let dst, let src):
            let srcStr: String
            switch src {
            case .register(let r): srcStr = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, let w): srcStr = "\(sizeHintPrefix(w)) \(formatMemory(m))"
            }
            return "\(kind.rawValue) \(X86.RegisterTable.canonicalName(for: dst)), \(srcStr)"
        case .bmiShiftLike(let kind, let dst, let src1, let src2):
            let src1Str: String
            switch src1 {
            case .register(let r): src1Str = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, let w): src1Str = "\(sizeHintPrefix(w)) \(formatMemory(m))"
            }
            return "\(kind.rawValue) \(X86.RegisterTable.canonicalName(for: dst)), \(src1Str), \(X86.RegisterTable.canonicalName(for: src2))"
        case .rorx(let dst, let src, let imm):
            let srcStr: String
            switch src {
            case .register(let r): srcStr = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, let w): srcStr = "\(sizeHintPrefix(w)) \(formatMemory(m))"
            }
            return "rorx \(X86.RegisterTable.canonicalName(for: dst)), \(srcStr), \(imm)"
        case .bmi2PextDep(let kind, let dst, let src1, let src2):
            let src2Str: String
            switch src2 {
            case .register(let r): src2Str = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, let w): src2Str = "\(sizeHintPrefix(w)) \(formatMemory(m))"
            }
            return "\(kind.rawValue) \(X86.RegisterTable.canonicalName(for: dst)), \(X86.RegisterTable.canonicalName(for: src1)), \(src2Str)"
        case .mulx(let dstH, let dstL, let src):
            let srcStr: String
            switch src {
            case .register(let r): srcStr = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, let w): srcStr = "\(sizeHintPrefix(w)) \(formatMemory(m))"
            }
            return "mulx \(X86.RegisterTable.canonicalName(for: dstH)), \(X86.RegisterTable.canonicalName(for: dstL)), \(srcStr)"
        case .adx(let kind, let dst, let src):
            let srcStr: String
            switch src {
            case .register(let r): srcStr = X86.RegisterTable.canonicalName(for: r)
            case .memory(let m, let w): srcStr = "\(sizeHintPrefix(w)) \(formatMemory(m))"
            }
            return "\(kind.rawValue) \(X86.RegisterTable.canonicalName(for: dst)), \(srcStr)"
        case .movDQ(let kind, let direction, let xmm, let gpr):
            let xmmStr = "xmm\(xmm.number)"
            let gprStr = formatMovDQGPROperand(gpr, width: kind.gprWidth)
            switch direction {
            case .load:  return "\(kind.rawValue) \(xmmStr), \(gprStr)"
            case .store: return "\(kind.rawValue) \(gprStr), \(xmmStr)"
            }
        }
    }

    private static func formatMovDQGPROperand(_ operand: X86.RegisterOrMemory, width: X86.RegisterWidth) -> String {
        switch operand {
        case .register(let r): return X86.RegisterTable.canonicalName(for: r)
        case .memory(let m, _): return "\(sizeHintPrefix(width)) \(formatMemory(m))"
        }
    }

    /// Render a memory operand with an explicit size hint.
    private static func formatSizedMemory(_ memory: X86.MemoryOperand, width: X86.RegisterWidth) -> String {
        "\(sizeHintPrefix(width)) \(formatMemory(memory))"
    }

    /// Render an SSE operand. XMM registers are bare; memory references
    /// show the size hint that matches the mnemonic's intrinsic width.
    private static func formatXMMOrMemory(_ operand: X86.XMMOrMemory, width: X86.RegisterWidth) -> String {
        switch operand {
        case .register(let r): return "xmm\(r.number)"
        case .memory(let m):
            return "\(sizeHintPrefix(width)) \(formatMemory(m))"
        }
    }

    private static func formatPort(_ port: X86.PortSource) -> String {
        switch port {
        case .immediate(let value): return String(value)
        case .dx: return "dx"
        }
    }

    /// MOVSX/MOVZX/MOVSXD memory sources need an explicit size hint
    /// because the source width is intrinsic to the opcode but not
    /// inferable from the destination register.
    private static func formatExtendingSource(_ source: X86.RegisterOrMemory) -> String {
        switch source {
        case .register(let r): return X86.RegisterTable.canonicalName(for: r)
        case .memory(let m, let w): return "\(sizeHintPrefix(w)) \(formatMemory(m))"
        }
    }

    private static func formatPushOperand(_ operand: X86.Operand) -> String {
        switch operand {
        case .register(let r): return X86.RegisterTable.canonicalName(for: r)
        case .memory(let m, let w): return "\(sizeHintPrefix(w)) \(formatMemory(m))"
        case .immediate(let v): return String(v)
        }
    }

    /// Render the operand of an indirect `jmp` / `call`. A register is
    /// unambiguous; a memory reference is shown bare (qword is the only
    /// legal width in long mode, so no size hint is needed).
    private static func formatIndirectTarget(_ target: X86.RegisterOrMemory) -> String {
        switch target {
        case .register(let r): return X86.RegisterTable.canonicalName(for: r)
        case .memory(let m, _): return formatMemory(m)
        }
    }

    private static func formatBranchTarget(_ target: X86.BranchTarget) -> String {
        switch target {
        case .offset(let delta): return String(delta)
        case .label(let name):   return name
        }
    }

    private static func formatPairedTarget(_ target: X86.RegisterOrMemory) -> String {
        switch target {
        case .register(let r): return X86.RegisterTable.canonicalName(for: r)
        case .memory(let m, _): return formatMemory(m)
        }
    }

    private static func formatShiftCount(_ count: X86.ShiftCount) -> String {
        switch count {
        case .one: return "1"
        case .cl: return "cl"
        case .immediate(let n): return String(n)
        }
    }

    /// Render a single-operand target. When the target is memory the width
    /// would otherwise be unknown, so a size hint is always prepended.
    private static func formatStandaloneTarget(_ target: X86.RegisterOrMemory) -> String {
        switch target {
        case .register(let r):
            return X86.RegisterTable.canonicalName(for: r)
        case .memory(let m, let w):
            return "\(sizeHintPrefix(w)) \(formatMemory(m))"
        }
    }

    /// Render a 2-operand "destination, source" line, prefixing the
    /// destination with a `byte ptr` / ... size hint when the source is
    /// an immediate and the destination is memory.
    private static func formatReadWrite(mnemonic: String, destination: X86.RegisterOrMemory, source: X86.Operand) -> String {
        let dst = formatDestination(destination, sizeHintWhenImmediate: source)
        return "\(mnemonic) \(dst), \(formatSource(source))"
    }

    // MARK: - Operands

    /// Render a destination operand. When `sizeHintWhenImmediate` is an
    /// `.immediate` and the destination is memory, the rendering is
    /// prefixed with `byte ptr` / `word ptr` / `dword ptr` / `qword ptr`
    /// so the width is unambiguous on re-assembly.
    static func formatDestination(_ destination: X86.RegisterOrMemory, sizeHintWhenImmediate source: X86.Operand?) -> String {
        switch destination {
        case .register(let register):
            return X86.RegisterTable.canonicalName(for: register)
        case .memory(let memory, let width):
            if case .immediate = source {
                return "\(sizeHintPrefix(width)) \(formatMemory(memory))"
            }
            return formatMemory(memory)
        }
    }

    static func formatSource(_ source: X86.Operand) -> String {
        switch source {
        case .register(let register):
            return X86.RegisterTable.canonicalName(for: register)
        case .memory(let memory, _):
            return formatMemory(memory)
        case .immediate(let value):
            return String(value)
        }
    }

    static func sizeHintPrefix(_ width: X86.RegisterWidth) -> String {
        switch width {
        case .byte:    return "byte ptr"
        case .word:    return "word ptr"
        case .dword:   return "dword ptr"
        case .qword:   return "qword ptr"
        case .xmmword: return "xmmword ptr"
        case .ymmword: return "ymmword ptr"
        }
    }

    /// Render a memory operand in canonical Intel syntax:
    /// `[base + index*scale + disp]`, with terms omitted when absent and
    /// the displacement printed as a signed decimal so positive vs.
    /// negative is visible at a glance.
    static func formatMemory(_ memory: X86.MemoryOperand) -> String {
        var parts: [String] = []
        if memory.ripRelative {
            parts.append("rip")
        } else if let base = memory.base {
            parts.append(X86.RegisterTable.canonicalName(for: base))
        }
        if let index = memory.index {
            let name = X86.RegisterTable.canonicalName(for: index)
            parts.append(memory.scale == 1 ? name : "\(name)*\(memory.scale)")
        }

        let body: String
        if parts.isEmpty {
            body = String(memory.displacement)
        } else {
            body = parts.joined(separator: " + ")
        }

        if memory.displacement == 0 && !parts.isEmpty {
            return "[\(body)]"
        }
        if parts.isEmpty {
            return "[\(body)]"
        }
        if memory.displacement >= 0 {
            return "[\(body) + \(memory.displacement)]"
        } else {
            return "[\(body) - \(-memory.displacement)]"
        }
    }
}
