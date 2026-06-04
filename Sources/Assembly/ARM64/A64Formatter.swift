import Foundation

internal enum A64InstructionFormatter {
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
        case .hint(let immediate):
            if let kind = HintKind.decode(immediate: immediate) { return kind.rawValue }
            return "hint #\(immediate)"
        case .moveAlias(let destination, let source):
            return "mov \(formatRegister(destination)), \(formatMoveAliasSource(source))"
        case .moveWide(let kind, let destination, let immediate, let shift):
            return "\(kind.rawValue) \(([formatRegister(destination), formatImmediate(immediate)] + (shift.map { [formatLSL($0)] } ?? [])).joined(separator: ", "))"
        case .addSub(let kind, let destination, let first, let operand):
            let spInvolved = destination.kind == .stackPointer || first.kind == .stackPointer
            return "\(kind.rawValue) \(([formatRegister(destination), formatRegister(first)] + formatAddSubOperand(operand, stackPointerInvolved: spInvolved, is64Bit: first.is64Bit)).joined(separator: ", "))"
        case .compareAlias(let kind, let first, let operand):
            return "\(kind.rawValue) \(([formatRegister(first)] + formatAddSubOperand(operand, stackPointerInvolved: first.kind == .stackPointer, is64Bit: first.is64Bit)).joined(separator: ", "))"
        case .logical(let kind, let destination, let first, let operand):
            return "\(kind.rawValue) \(([formatRegister(destination), formatRegister(first)] + formatLogicalOperand(operand)).joined(separator: ", "))"
        case .mvnAlias(let destination, let source, let shift):
            return "mvn \(([formatRegister(destination), formatRegister(source)] + (shift.map { [formatShift($0)] } ?? [])).joined(separator: ", "))"
        case .shiftAlias(let kind, let destination, let source, let amount):
            return "\(kind.rawValue) \(formatRegister(destination)), \(formatRegister(source)), \(formatImmediate(amount))"
        case .extractOrRotateAlias(let kind, let destination, let first, let operand):
            switch operand {
            case .extract(let second, let amount):
                return "\(kind.rawValue) \(formatRegister(destination)), \(formatRegister(first)), \(formatRegister(second)), \(formatImmediate(amount))"
            case .rotate(let amount):
                return "\(kind.rawValue) \(formatRegister(destination)), \(formatRegister(first)), \(formatImmediate(amount))"
            }
        case .multiply(let kind, let destination, let first, let second, let accumulator):
            return "\(kind.rawValue) \(([formatRegister(destination), formatRegister(first), formatRegister(second)] + (accumulator.map { [formatRegister($0)] } ?? [])).joined(separator: ", "))"
        case .multiplyWide(let kind, let destination, let first, let second, let accumulator):
            return "\(kind.rawValue) \(([formatRegister(destination), formatRegister(first), formatRegister(second)] + (accumulator.map { [formatRegister($0)] } ?? [])).joined(separator: ", "))"
        case .bitfield(let kind, let destination, let source, let immr, let imms):
            return formatBitfield(kind, destination: destination, source: source, immr: immr, imms: imms)
        case .divide(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatRegister(destination)), \(formatRegister(first)), \(formatRegister(second))"
        case .addSubCarry(let kind, let destination, let first, let second):
            // `sbc`/`sbcs` with the zero register source prefer the ngc/ngcs alias.
            if (kind == .sbc || kind == .sbcs), first.number == 31 {
                let alias = kind == .sbc ? "ngc" : "ngcs"
                return "\(alias) \(formatRegister(destination)), \(formatRegister(second))"
            }
            return "\(kind.rawValue) \(formatRegister(destination)), \(formatRegister(first)), \(formatRegister(second))"
        case .dataProcessingOneSource(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatRegister(destination)), \(formatRegister(source))"
        case .crc32(let kind, let destination, let first, let data):
            return "\(kind.rawValue) \(formatRegister(destination)), \(formatRegister(first)), \(formatRegister(data))"
        case .conditionalSelect(let kind, let destination, let first, let second, let condition):
            return "\(kind.rawValue) \(formatRegister(destination)), \(formatRegister(first)), \(formatRegister(second)), \(formatCondition(condition))"
        case .conditionalCompare(let kind, let first, let second, let nzcv, let condition):
            let secondText: String
            switch second {
            case .register(let rm): secondText = formatRegister(rm)
            case .immediate(let imm): secondText = "#\(imm)"
            }
            return "\(kind.rawValue) \(formatRegister(first)), \(secondText), #\(nzcv), \(formatCondition(condition))"
        case .conditionalSet(let kind, let destination, let condition):
            return "\(kind.rawValue) \(formatRegister(destination)), \(formatCondition(condition))"
        case .conditionalSelectAlias(let kind, let destination, let source, let condition):
            return "\(kind.rawValue) \(formatRegister(destination)), \(formatRegister(source)), \(formatCondition(condition))"
        case .loadStoreSingle(let kind, let target, let memory):
            return "\(kind.rawValue) \(([formatRegister(target)] + formatMemoryOperand(memory)).joined(separator: ", "))"
        case .loadStoreExclusive(let kind, let status, let value, let value2, let base):
            var operands: [String] = []
            if let status { operands.append(formatRegister(status)) }
            operands.append(formatRegister(value))
            if let value2 { operands.append(formatRegister(value2)) }
            operands += formatMemoryOperand(.unsignedOffset(base: base, offset: 0))
            return "\(kind.rawValue) \(operands.joined(separator: ", "))"
        case .compareAndSwap(let kind, let compare, let value, let base):
            let mem = formatMemoryOperand(.unsignedOffset(base: base, offset: 0))
            return "\(kind.rawValue) \(([formatRegister(compare), formatRegister(value)] + mem).joined(separator: ", "))"
        case .compareAndSwapPair(let kind, let compare, let value, let base):
            let compareHigh = IntegerRegister(number: compare.number + 1, width: compare.width, kind: compare.kind)
            let valueHigh = IntegerRegister(number: value.number + 1, width: value.width, kind: value.kind)
            let mem = formatMemoryOperand(.unsignedOffset(base: base, offset: 0))
            let regs = [formatRegister(compare), formatRegister(compareHigh), formatRegister(value), formatRegister(valueHigh)]
            return "\(kind.rawValue) \((regs + mem).joined(separator: ", "))"
        case .atomicMemory(let kind, let source, let value, let base):
            let mem = formatMemoryOperand(.unsignedOffset(base: base, offset: 0))
            var regs = [formatRegister(source)]
            if let value { regs.append(formatRegister(value)) }
            return "\(kind.mnemonic) \((regs + mem).joined(separator: ", "))"
        case .loadStorePair(let kind, let first, let second, let memory):
            return "\(kind.rawValue) \(([formatRegister(first), formatRegister(second)] + formatMemoryOperand(memory)).joined(separator: ", "))"
        case .loadStoreSingleFP(let kind, let target, let memory):
            return "\(kind.rawValue) \(([formatFloatRegister(target)] + formatMemoryOperand(memory)).joined(separator: ", "))"
        case .loadStorePairFP(let kind, let first, let second, let memory):
            return "\(kind.rawValue) \(([formatFloatRegister(first), formatFloatRegister(second)] + formatMemoryOperand(memory)).joined(separator: ", "))"
        case .loadStoreMultiple(let kind, let registers, let address):
            return "\(kind.rawValue) \(formatVectorRegisterList(registers)), \(formatVectorMemoryOperand(address, registers: registers))"
        case .loadStoreSingleLane(let kind, let registers, let address):
            let bytes = registers.count << registers.width.sizeShift
            return "\(kind.rawValue) \(formatVectorLaneList(registers)), \(formatVectorMemoryOperand(address, postImmediateBytes: bytes))"
        case .vectorTableLookup(let kind, let destination, let table, let index):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegisterList(table)), \(formatVectorRegister(index))"
        case .vectorCompareZero(let kind, let destination, let source):
            let zero = kind.isFloat ? "#0.0" : "#0"
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(source)), \(zero)"
        case .vectorExtractNarrow(let kind, let destination, let source):
            let suffix = destination.arrangement.q == 1 ? "2" : ""
            return "\(kind.rawValue)\(suffix) \(formatVectorRegister(destination)), \(formatVectorRegister(source))"
        case .vectorConvert(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(source))"
        case .vectorPairwiseLongAdd(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(source))"
        case .vectorRoundReciprocal(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(source))"
        case .vectorFPConvertPrecision(let kind, let upper, let destination, let source):
            let suffix = upper ? "2" : ""
            return "\(kind.rawValue)\(suffix) \(formatVectorRegister(destination)), \(formatVectorRegister(source))"
        case .cryptoAES(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(source))"
        case .cryptoSHA3(let kind, let d, let n, let m):
            let shape = kind.shape
            return "\(kind.rawValue) \(formatCryptoSHAOperand(d, shape: shape.d)), \(formatCryptoSHAOperand(n, shape: shape.n)), \(formatCryptoSHAOperand(m, shape: shape.m))"
        case .cryptoSHA2(let kind, let d, let n):
            let shape = kind.shape
            return "\(kind.rawValue) \(formatCryptoSHAOperand(d, shape: shape.d)), \(formatCryptoSHAOperand(n, shape: shape.n))"
        case .cryptoSHA512(let kind, let d, let n, let m):
            let shape = kind.shape
            return "\(kind.rawValue) \(formatCryptoSHAOperand(d, shape: shape.d)), \(formatCryptoSHAOperand(n, shape: shape.n)), \(formatCryptoSHAOperand(m, shape: shape.m))"
        case .cryptoTwoReg(let kind, let d, let n):
            let shape = kind.shape
            return "\(kind.rawValue) \(formatCryptoSHAOperand(d, shape: shape.d)), \(formatCryptoSHAOperand(n, shape: shape.n))"
        case .cryptoSM3(let kind, let d, let n, let m):
            return "\(kind.rawValue) v\(d).4s, v\(n).4s, v\(m).4s"
        case .cryptoSM3Indexed(let kind, let d, let n, let m, let index):
            return "\(kind.rawValue) v\(d).4s, v\(n).4s, v\(m).s[\(index)]"
        case .cryptoSM3SS1(let d, let n, let m, let a):
            return "sm3ss1 v\(d).4s, v\(n).4s, v\(m).4s, v\(a).4s"
        case .cryptoSHA3Four(let kind, let d, let n, let m, let a):
            return "\(kind.rawValue) v\(d).16b, v\(n).16b, v\(m).16b, v\(a).16b"
        case .cryptoRAX1(let d, let n, let m):
            return "rax1 v\(d).2d, v\(n).2d, v\(m).2d"
        case .cryptoXAR(let d, let n, let m, let imm6):
            return "xar v\(d).2d, v\(n).2d, v\(m).2d, #\(imm6)"
        case .loadStoreReplicate(let kind, let registers, let address):
            let bytes = registers.count * (registers.arrangement.elementWidth / 8)
            return "\(kind.rawValue) \(formatVectorRegisterList(registers)), \(formatVectorMemoryOperand(address, postImmediateBytes: bytes))"
        case .pointerAuthentication(let kind, let register, _):
            return ([kind.rawValue] + (register.map { [formatRegister($0)] } ?? [])).joined(separator: " ")
        case .fpDataProcessing2(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(first)), \(formatFloatRegister(second))"
        case .fpDataProcessing1(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(source))"
        case .fpDataProcessing3(let kind, let destination, let first, let second, let third):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(first)), \(formatFloatRegister(second)), \(formatFloatRegister(third))"
        case .fpCompare(let kind, let first, let second):
            switch second {
            case .register(let register):
                return "\(kind.rawValue) \(formatFloatRegister(first)), \(formatFloatRegister(register))"
            case .zero:
                return "\(kind.rawValue) \(formatFloatRegister(first)), #0.0"
            }
        case .fpConvertPrecision(let destination, let source):
            return "fcvt \(formatFloatRegister(destination)), \(formatFloatRegister(source))"
        case .fpMoveImmediate(let destination, let value):
            return "fmov \(formatFloatRegister(destination)), \(formatFloatImmediate(value))"
        case .fpMoveToGeneral(let destination, let source):
            return "fmov \(formatRegister(destination)), \(formatFloatRegister(source))"
        case .fpMoveFromGeneral(let destination, let source):
            return "fmov \(formatFloatRegister(destination)), \(formatRegister(source))"
        case .fpMoveVectorHighToGeneral(let destination, let source):
            return "fmov \(formatRegister(destination)), \(formatVectorElement(source))"
        case .fpMoveGeneralToVectorHigh(let destination, let source):
            return "fmov \(formatVectorElement(destination)), \(formatRegister(source))"
        case .fpConvertToInt(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatRegister(destination)), \(formatFloatRegister(source))"
        case .fpConvertFromInt(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatRegister(source))"
        case .fpConvertToFixed(let kind, let destination, let source, let fbits):
            return "\(kind.rawValue) \(formatRegister(destination)), \(formatFloatRegister(source)), #\(fbits)"
        case .fpConvertFromFixed(let kind, let destination, let source, let fbits):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatRegister(source)), #\(fbits)"
        case .fjcvtzs(let destination, let source):
            return "fjcvtzs \(formatRegister(destination)), \(formatFloatRegister(source))"
        case .fpConditionalSelect(let destination, let first, let second, let condition):
            return "fcsel \(formatFloatRegister(destination)), \(formatFloatRegister(first)), \(formatFloatRegister(second)), \(formatCondition(condition))"
        case .fpConditionalCompare(let kind, let first, let second, let nzcv, let condition):
            return "\(kind.rawValue) \(formatFloatRegister(first)), \(formatFloatRegister(second)), #\(nzcv), \(formatCondition(condition))"
        case .acrossLanesInteger(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatVectorRegister(source))"
        case .acrossLanesFP(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatVectorRegister(source))"
        case .vectorTwoRegisterMisc(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(source))"
        case .vectorThreeSame(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .vectorShiftImmediate(let kind, let destination, let source, let shift):
            return formatVectorShiftImmediate(kind, destination: destination, source: source, shift: shift)
        case .vectorShiftLeftLong(let destination, let source, let shift):
            let mnemonic = source.arrangement.q == 1 ? "shll2" : "shll"
            return "\(mnemonic) \(formatVectorRegister(destination)), \(formatVectorRegister(source)), #\(shift)"
        case .vectorModifiedImmediate(let kind, let destination, let imm8, let shift):
            return formatVectorModifiedImmediate(kind, destination: destination, imm8: imm8, shift: shift)
        case .vectorDuplicateElement(let destination, let source):
            return "dup \(formatVectorRegister(destination)), \(formatVectorElement(source))"
        case .vectorDuplicateGeneral(let destination, let source):
            return "dup \(formatVectorRegister(destination)), \(formatRegister(source))"
        case .vectorMoveToGeneral(let signed, let destination, let source):
            return "\(signed ? "smov" : "umov") \(formatRegister(destination)), \(formatVectorElement(source))"
        case .vectorInsertGeneral(let destination, let source):
            return "ins \(formatVectorElement(destination)), \(formatRegister(source))"
        case .vectorInsertElement(let destination, let source):
            return "ins \(formatVectorElement(destination)), \(formatVectorElement(source))"
        case .vectorPermute(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .vectorExtract(let destination, let first, let second, let index):
            return "ext \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second)), #\(index)"
        case .vectorThreeDifferent(let kind, let destination, let first, let second):
            // The narrow operand carries `Q`; `Q=1` prints the `2` upper-half form.
            let narrowQ: UInt32
            switch kind.spec.form {
            case .long: narrowQ = first.arrangement.q
            case .wide: narrowQ = second.arrangement.q
            case .narrow: narrowQ = destination.arrangement.q
            }
            let suffix = narrowQ == 1 ? "2" : ""
            return "\(kind.rawValue)\(suffix) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .vectorIndexed(let kind, let destination, let first, let element):
            // Long forms print the `2` upper-half variant when the source operand is `Q=1`.
            let suffix = (kind.spec.form == .long && first.arrangement.q == 1) ? "2" : ""
            return "\(kind.rawValue)\(suffix) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorElement(element))"
        case .vectorDotProduct(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .vectorDotProductByElement(let kind, let destination, let first, let elementRegister, let index):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), v\(elementRegister).4b[\(index)]"
        case .vectorUSDotProduct(let destination, let first, let second):
            return "usdot \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .vectorMixedDotByElement(let kind, let destination, let first, let elementRegister, let index):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), v\(elementRegister).4b[\(index)]"
        case .vectorMatrixMultiply(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .vectorThreeSameExtra(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .scalarThreeSameExtra(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(first)), \(formatFloatRegister(second))"
        case .vectorComplexAdd(let destination, let first, let second, let rotation):
            return "fcadd \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second)), #\(rotation)"
        case .vectorComplexMultiplyAdd(let destination, let first, let second, let rotation):
            return "fcmla \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second)), #\(rotation)"
        case .vectorComplexMultiplyAddByElement(let destination, let first, let elementRegister, let index, let rotation):
            let elementWidth = destination.arrangement.elementSize == 0b01 ? "h" : "s"
            return "fcmla \(formatVectorRegister(destination)), \(formatVectorRegister(first)), v\(elementRegister).\(elementWidth)[\(index)], #\(rotation)"
        case .vectorFPMultiplyLong(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .vectorFPMultiplyLongByElement(let kind, let destination, let first, let elementRegister, let index):
            return "\(kind.rawValue) \(formatVectorRegister(destination)), \(formatVectorRegister(first)), v\(elementRegister).h[\(index)]"
        case .vectorBFDot(let destination, let first, let second):
            return "bfdot \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .vectorBFDotByElement(let destination, let first, let elementRegister, let index):
            return "bfdot \(formatVectorRegister(destination)), \(formatVectorRegister(first)), v\(elementRegister).2h[\(index)]"
        case .vectorBFMLAL(let top, let destination, let first, let second):
            return "\(top ? "bfmlalt" : "bfmlalb") \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .vectorBFMLALByElement(let top, let destination, let first, let elementRegister, let index):
            return "\(top ? "bfmlalt" : "bfmlalb") \(formatVectorRegister(destination)), \(formatVectorRegister(first)), v\(elementRegister).h[\(index)]"
        case .vectorBFMatrixMultiply(let destination, let first, let second):
            return "bfmmla \(formatVectorRegister(destination)), \(formatVectorRegister(first)), \(formatVectorRegister(second))"
        case .vectorBFConvertNarrow(let top, let destination, let source):
            return "\(top ? "bfcvtn2" : "bfcvtn") \(formatVectorRegister(destination)), \(formatVectorRegister(source))"
        case .scalarThreeSame(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(first)), \(formatFloatRegister(second))"
        case .scalarPairwise(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatVectorRegister(source))"
        case .scalarTwoRegisterMisc(let kind, let destination, let source):
            let zero = kind.spec.comparesZero ? ", #0" : ""
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(source))\(zero)"
        case .scalarShiftImmediate(let kind, let destination, let source, let shift):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(source)), #\(shift)"
        case .scalarThreeDifferent(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(first)), \(formatFloatRegister(second))"
        case .scalarIndexed(let kind, let destination, let first, let element):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(first)), \(formatVectorElement(element))"
        case .scalarCopyDuplicate(let destination, let element):
            return "mov \(formatFloatRegister(destination)), \(formatVectorElement(element))"
        case .scalarFPTwoRegisterMisc(let kind, let destination, let source):
            let zero = kind.spec.category == .compareZero ? ", #0.0" : ""
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(source))\(zero)"
        case .scalarThreeSameFP(let kind, let destination, let first, let second):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(first)), \(formatFloatRegister(second))"
        case .scalarShiftNarrow(let kind, let destination, let source, let shift):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(source)), #\(shift)"
        case .scalarTwoRegisterMiscNarrow(let kind, let destination, let source):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(source))"
        case .scalarShiftFixedPoint(let kind, let destination, let source, let fbits):
            return "\(kind.rawValue) \(formatFloatRegister(destination)), \(formatFloatRegister(source)), #\(fbits)"
        }
    }

    private static func formatVectorElement(_ element: VectorElement) -> String {
        "v\(element.number).\(element.width.rawValue)[\(element.index)]"
    }

    private static func formatVectorModifiedImmediate(_ kind: VectorModifiedImmediateKind, destination: VectorRegister, imm8: UInt8, shift: VectorImmediateShift) -> String {
        let destinationText: String
        if destination.arrangement == .d1 {
            destinationText = "d\(destination.number)"   // scalar `movi d0` form
        } else {
            destinationText = formatVectorRegister(destination)
        }

        let immediateText: String
        if kind == .fmov {
            immediateText = formatFloatImmediate(A64FloatImmediate.decode(UInt32(imm8)))
        } else if destination.arrangement == .d1 || destination.arrangement == .d2 {
            // 64-bit form: expand each bit of `imm8` into a full byte.
            var value: UInt64 = 0
            for index in 0..<8 where (imm8 & (1 << index)) != 0 {
                value |= 0xff << (UInt64(index) * 8)
            }
            immediateText = "#0x\(String(value, radix: 16))"
        } else {
            immediateText = "#0x\(String(imm8, radix: 16))"
        }

        let shiftText: String
        switch shift {
        case .none: shiftText = ""
        case .lsl(let amount): shiftText = ", lsl #\(amount)"
        case .msl(let amount): shiftText = ", msl #\(amount)"
        }

        return "\(kind.rawValue) \(destinationText), \(immediateText)\(shiftText)"
    }

    private static func formatVectorShiftImmediate(_ kind: VectorShiftImmediateKind, destination: VectorRegister, source: VectorRegister, shift: Int) -> String {
        let category = kind.spec.category
        // The `2` suffix marks the form operating on the upper 64 bits.
        let usesUpperHalf: Bool
        switch category {
        case .narrow: usesUpperHalf = destination.arrangement.q == 1
        case .widen: usesUpperHalf = source.arrangement.q == 1
        default: usesUpperHalf = false
        }

        // `sshll`/`ushll` with a zero shift print as the `sxtl`/`uxtl` aliases.
        var mnemonic = kind.rawValue
        var emitShift = true
        if category == .widen, shift == 0 {
            mnemonic = kind == .sshll ? "sxtl" : "uxtl"
            emitShift = false
        }
        if usesUpperHalf { mnemonic += "2" }

        let operands = "\(formatVectorRegister(destination)), \(formatVectorRegister(source))"
        return emitShift ? "\(mnemonic) \(operands), #\(shift)" : "\(mnemonic) \(operands)"
    }

    private static func formatVectorRegister(_ register: VectorRegister) -> String {
        "v\(register.number).\(register.arrangement.rawValue)"
    }

    private static func formatCryptoSHAOperand(_ number: UInt32, shape: A64.CryptoSHAOperand) -> String {
        switch shape {
        case .scalarS:  return "s\(number)"
        case .scalarQ:  return "q\(number)"
        case .vector4s: return "v\(number).4s"
        case .vector2d: return "v\(number).2d"
        case .vector16b: return "v\(number).16b"
        }
    }

    private static func formatVectorRegisterList(_ list: VectorRegisterList) -> String {
        let names = (0..<list.count).map { "v\((list.firstNumber + UInt32($0)) % 32).\(list.arrangement.rawValue)" }
        return "{" + names.joined(separator: ", ") + "}"
    }

    private static func formatVectorLaneList(_ list: VectorLaneList) -> String {
        let names = (0..<list.count).map { "v\((list.firstNumber + UInt32($0)) % 32).\(list.width.rawValue)" }
        return "{" + names.joined(separator: ", ") + "}[\(list.index)]"
    }

    private static func formatVectorMemoryOperand(_ address: VectorMemoryOperand, registers: VectorRegisterList) -> String {
        let bytes = registers.count * (registers.arrangement.q == 1 ? 16 : 8)
        return formatVectorMemoryOperand(address, postImmediateBytes: bytes)
    }

    private static func formatVectorMemoryOperand(_ address: VectorMemoryOperand, postImmediateBytes bytes: Int) -> String {
        switch address {
        case .base(let base):
            return "[\(formatRegister(base))]"
        case .postImmediate(let base):
            return "[\(formatRegister(base))], #\(bytes)"
        case .postRegister(let base, let offset):
            return "[\(formatRegister(base))], \(formatRegister(offset))"
        }
    }

    private static func formatFloatRegister(_ register: FloatRegister) -> String {
        let prefix: String
        switch register.width {
        case 8: prefix = "b"
        case 16: prefix = "h"
        case 32: prefix = "s"
        case 64: prefix = "d"
        case 128: prefix = "q"
        default: prefix = "?"
        }
        return "\(prefix)\(register.number)"
    }

    private static func formatFloatImmediate(_ value: Double) -> String {
        "#\(value)"
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

    private static func formatBitfield(
        _ kind: BitfieldKind,
        destination: IntegerRegister,
        source: IntegerRegister,
        immr: UInt32,
        imms: UInt32
    ) -> String {
        let rd = formatRegister(destination)
        let rn = formatRegister(source)
        let registerSize: UInt32 = destination.is64Bit ? 64 : 32
        let maxShift = registerSize - 1
        let wSource = formatRegister(IntegerRegister(number: source.number, width: 32, kind: source.kind))

        switch kind {
        case .sbfm:
            if immr == 0 && imms == 7 {
                return "sxtb \(rd), \(wSource)"
            }
            if immr == 0 && imms == 15 {
                return "sxth \(rd), \(wSource)"
            }
            if immr == 0 && imms == 31 && destination.is64Bit {
                return "sxtw \(rd), \(wSource)"
            }
            if imms == maxShift {
                return "asr \(rd), \(rn), #\(immr)"
            }
            if imms < immr {
                let lsb = (registerSize - immr) % registerSize
                return "sbfiz \(rd), \(rn), #\(lsb), #\(imms + 1)"
            }
            return "sbfx \(rd), \(rn), #\(immr), #\(imms - immr + 1)"
        case .ubfm:
            if immr == 0 && imms == 7 && !destination.is64Bit {
                return "uxtb \(rd), \(wSource)"
            }
            if immr == 0 && imms == 15 && !destination.is64Bit {
                return "uxth \(rd), \(wSource)"
            }
            if imms == maxShift {
                return "lsr \(rd), \(rn), #\(immr)"
            }
            if immr == imms + 1 {
                return "lsl \(rd), \(rn), #\(maxShift - imms)"
            }
            if imms < immr {
                let lsb = (registerSize - immr) % registerSize
                return "ubfiz \(rd), \(rn), #\(lsb), #\(imms + 1)"
            }
            return "ubfx \(rd), \(rn), #\(immr), #\(imms - immr + 1)"
        case .bfm:
            if imms < immr {
                let lsb = (registerSize - immr) % registerSize
                let width = imms + 1
                if source.number == 31 {
                    return "bfc \(rd), #\(lsb), #\(width)"
                }
                return "bfi \(rd), \(rn), #\(lsb), #\(width)"
            }
            return "bfxil \(rd), \(rn), #\(immr), #\(imms - immr + 1)"
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

    private static func formatImmediate(_ value: Int64) -> String {
        "#\(value)"
    }

    private static func formatLSL(_ amount: Int) -> String {
        "lsl #\(amount)"
    }

    private static func formatShift(_ shift: ParsedShift) -> String {
        "\(formatShiftKind(shift.kind)) #\(shift.amount)"
    }

    private static func formatShiftKind(_ kind: ShiftKind) -> String {
        switch kind {
        case .lsl: return "lsl"
        case .lsr: return "lsr"
        case .asr: return "asr"
        case .ror: return "ror"
        }
    }

    private static func formatMoveAliasSource(_ source: A64.MoveAliasSource) -> String {
        switch source {
        case .immediate(let value): return formatImmediate(value)
        case .register(let register): return formatRegister(register)
        }
    }

    private static func formatAddSubOperand(_ operand: A64.AddSubOperand, stackPointerInvolved: Bool = false, is64Bit: Bool = false) -> [String] {
        switch operand {
        case .immediate(let value, let shift):
            return [formatImmediate(value)] + (shift.map { [formatLSL($0)] } ?? [])
        case .shiftedRegister(let register, let shift):
            return [formatRegister(register)] + (shift.map { [formatShift($0)] } ?? [])
        case .extendedRegister(let register, let extend, let amount):
            let amt = amount ?? 0
            // With a stack-pointer operand the default extend (uxtx/uxtw) and a
            // zero shift are omitted, matching `add x0, sp, x2`.
            let defaultExtend: ExtendKind = is64Bit ? .uxtx : .uxtw
            if stackPointerInvolved && extend == defaultExtend && amt == 0 {
                return [formatRegister(register)]
            }
            var modifier = formatExtendKind(extend)
            if amt != 0 { modifier += " #\(amt)" }
            return [formatRegister(register), modifier]
        }
    }

    private static func formatLogicalOperand(_ operand: A64.LogicalOperand) -> [String] {
        switch operand {
        case .immediate(let value):
            return [formatImmediate(value)]
        case .shiftedRegister(let register, let shift):
            return [formatRegister(register)] + (shift.map { [formatShift($0)] } ?? [])
        }
    }

    private static func formatMemoryOperand(_ memory: MemoryOperand) -> [String] {
        switch memory {
        case .unsignedOffset(let base, 0), .signedUnscaled(let base, 0):
            return ["[\(formatRegister(base))]"]
        case .unsignedOffset(let base, let offset), .signedUnscaled(let base, let offset):
            return ["[\(formatRegister(base)), \(formatImmediate(offset))]"]
        case .preIndexed(let base, let offset):
            return ["[\(formatRegister(base)), \(formatImmediate(offset))]!"]
        case .postIndexed(let base, let offset):
            return ["[\(formatRegister(base))]", formatImmediate(offset)]
        case .registerOffset(let base, let offset, let ext, let shift):
            var components = [formatRegister(base), formatRegister(offset)]
            if let ext {
                components.append("\(formatExtendKind(ext)) #\(shift)")
            } else if shift != 0 {
                components.append(formatLSL(shift))
            }
            return ["[\(components.joined(separator: ", "))]"]
        }
    }

    private static func formatExtendKind(_ kind: ExtendKind) -> String {
        switch kind {
        case .uxtb: return "uxtb"
        case .uxth: return "uxth"
        case .uxtw: return "uxtw"
        case .uxtx: return "uxtx"
        case .sxtb: return "sxtb"
        case .sxth: return "sxth"
        case .sxtw: return "sxtw"
        case .sxtx: return "sxtx"
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
