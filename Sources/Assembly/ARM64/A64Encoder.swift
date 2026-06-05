import Foundation

internal enum A64InstructionEncoder {
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
        case .hint(let immediate):
            try checkRange(Int64(immediate), 0...0x7f, instruction: "hint")
            return A64.Hint.baseWord | A64.Hint.imm.insert(immediate)
        case .branchRegister(let kind, let rn):
            return kind.baseWord | (rn.encodedNumber << 5)
        case .unconditionalBranch(let link, let offset):
            guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: link ? "bl" : "b", value: offset, alignment: 4) }
            let imm26 = offset / 4
            guard (-0x2000000...0x1ffffff).contains(imm26) else {
                throw AssemblerError.branchOutOfRange(instruction: link ? "bl" : "b", label: "#\(offset)", byteOffset: offset)
            }
            return A64.UnconditionalBranchImmediate.baseWord
                | A64.UnconditionalBranchImmediate.op.insert(link ? 1 : 0)
                | A64.UnconditionalBranchImmediate.imm26.insert(UInt32(bitPattern: Int32(imm26)))
        case .conditionalBranch(let condition, let offset):
            guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: "b.\(condition)", value: offset, alignment: 4) }
            let imm19 = offset / 4
            guard (-0x40000...0x3ffff).contains(imm19) else {
                throw AssemblerError.branchOutOfRange(instruction: "b.\(condition)", label: "#\(offset)", byteOffset: offset)
            }
            return A64.ConditionalBranchImmediate.baseWord
                | A64.ConditionalBranchImmediate.imm19.insert(UInt32(bitPattern: Int32(imm19)))
                | A64.ConditionalBranchImmediate.cond.insert(condition.rawValue)
        case .compareAndBranch(let nonzero, let rt, let offset):
            guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: nonzero ? "cbnz" : "cbz", value: offset, alignment: 4) }
            let imm19 = offset / 4
            guard (-0x40000...0x3ffff).contains(imm19) else {
                throw AssemblerError.branchOutOfRange(instruction: nonzero ? "cbnz" : "cbz", label: "#\(offset)", byteOffset: offset)
            }
            return A64.CompareAndBranch.baseWord
            | A64.CompareAndBranch.sf.insert(rt.is64Bit ? 1 : 0)
            | A64.CompareAndBranch.op.insert(nonzero ? 1 : 0)
            | A64.CompareAndBranch.imm19.insert(UInt32(bitPattern: Int32(imm19)))
            | A64.CompareAndBranch.rt.insert(rt.encodedNumber)
        case .testAndBranch(let nonzero, let rt, let bit, let offset):
            try checkRange(bit, 0...(rt.is64Bit ? 63 : 31), instruction: nonzero ? "tbnz" : "tbz")
            guard offset % 4 == 0 else { throw AssemblerError.immediateAlignment(instruction: nonzero ? "tbnz" : "tbz", value: offset, alignment: 4) }
            let imm14 = offset / 4
            guard (-0x2000...0x1fff).contains(imm14) else {
                throw AssemblerError.branchOutOfRange(instruction: nonzero ? "tbnz" : "tbz", label: "#\(offset)", byteOffset: offset)
            }
            return A64.TestAndBranch.baseWord
            | A64.TestAndBranch.b5.insert(UInt32(bit >> 5))
            | A64.TestAndBranch.op.insert(nonzero ? 1 : 0)
            | A64.TestAndBranch.b40.insert(UInt32(bit))
            | A64.TestAndBranch.imm14.insert(UInt32(bitPattern: Int32(imm14)))
            | A64.TestAndBranch.rt.insert(rt.encodedNumber)
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
            return A64.PCRelativeAddressing.baseWord
                | A64.PCRelativeAddressing.op.insert(page ? 1 : 0)
                | A64.PCRelativeAddressing.immlo.insert(imm & 0x3)
                | A64.PCRelativeAddressing.immhi.insert(imm >> 2)
                | A64.PCRelativeAddressing.rd.insert(rd.encodedNumber)
        case .exception(let kind, let immediate):
            return kind.baseWord | (UInt32(immediate) << 5)
        case .exceptionReturn:
            return 0xd69f03e0
        case .barrier(.speculation, _):
            return A64.BarrierKind.speculation.baseWord
        case .barrier(let kind, let option):
            return kind.baseWord | (option << 8)
        case .permanentlyUndefined(let imm16):
            return A64.PermanentlyUndefined.baseWord | A64.PermanentlyUndefined.imm16.insert(imm16)
        case .moveAlias(let destination, let source):
            return try A64MoveEncoder.movAlias(destination: destination, source: source)
        case .moveWide(let kind, let destination, let immediate, let shift):
            return try A64MoveEncoder.moveWide(kind, destination: destination, immediate: immediate, shift: shift)
        case .addSub(let kind, let destination, let first, let operand):
            return try A64AddSubEncoder.addSub(kind, destination: destination, first: first, operand: operand)
        case .compareAlias(let kind, let first, let operand):
            return try A64AddSubEncoder.compareAlias(kind, first: first, operand: operand)
        case .logical(let kind, let destination, let first, let operand):
            return try A64LogicalEncoder.logical(kind, destination: destination, first: first, operand: operand)
        case .mvnAlias(let destination, let source, let shift):
            return try A64LogicalEncoder.mvnAlias(destination: destination, source: source, shift: shift)
        case .shiftAlias(let kind, let destination, let source, let amount):
            return try A64DataProcessingEncoder.shiftAlias(kind, destination: destination, source: source, amount: amount)
        case .extractOrRotateAlias(let kind, let destination, let first, let operand):
            return try A64DataProcessingEncoder.extract(kind, destination: destination, first: first, operand: operand)
        case .multiply(let kind, let destination, let first, let second, let accumulator):
            return try A64DataProcessingEncoder.multiply(kind, destination: destination, first: first, second: second, accumulator: accumulator)
        case .divide(let kind, let destination, let first, let second):
            return try A64DataProcessingEncoder.divide(kind, destination: destination, first: first, second: second)
        case .variableShift(let kind, let destination, let first, let second):
            return try A64DataProcessingEncoder.variableShift(kind, destination: destination, first: first, second: second)
        case .minMaxRegister(let kind, let destination, let first, let second):
            return try A64DataProcessingEncoder.minMaxRegister(kind, destination: destination, first: first, second: second)
        case .minMaxImmediate(let kind, let destination, let source, let immediate):
            return try A64DataProcessingEncoder.minMaxImmediate(kind, destination: destination, source: source, immediate: immediate)
        case .addSubCarry(let kind, let destination, let first, let second):
            return try A64DataProcessingEncoder.addSubCarry(kind, destination: destination, first: first, second: second)
        case .multiplyWide(let kind, let destination, let first, let second, let accumulator):
            return try A64DataProcessingEncoder.multiplyWide(kind, destination: destination, first: first, second: second, accumulator: accumulator)
        case .bitfield(let kind, let destination, let source, let immr, let imms):
            return try A64DataProcessingEncoder.bitfield(kind, destination: destination, source: source, immr: immr, imms: imms)
        case .dataProcessingOneSource(let kind, let destination, let source):
            return try A64DataProcessingEncoder.dataProcessingOneSource(kind, destination: destination, source: source)
        case .crc32(let kind, let destination, let first, let data):
            return try A64DataProcessingEncoder.crc32(kind, destination: destination, first: first, data: data)
        case .conditionalSelect(let kind, let destination, let first, let second, let condition):
            return try A64DataProcessingEncoder.conditionalSelect(kind, destination: destination, first: first, second: second, condition: condition)
        case .conditionalCompare(let kind, let first, let second, let nzcv, let condition):
            return try A64DataProcessingEncoder.conditionalCompare(kind, first: first, second: second, nzcv: nzcv, condition: condition)
        case .conditionalSet(let kind, let destination, let condition):
            return try A64DataProcessingEncoder.conditionalSet(kind, destination: destination, condition: condition)
        case .conditionalSelectAlias(let kind, let destination, let source, let condition):
            return try A64DataProcessingEncoder.conditionalSelectAlias(kind, destination: destination, source: source, condition: condition)
        case .loadStoreExclusive(let kind, let status, let value, let value2, let base):
            return try A64LoadStoreEncoder.exclusive(kind, status: status, value: value, value2: value2, base: base)
        case .compareAndSwap(let kind, let compare, let value, let base):
            return try A64LoadStoreEncoder.compareAndSwap(kind, compare: compare, value: value, base: base)
        case .compareAndSwapPair(let kind, let compare, let value, let base):
            return try A64LoadStoreEncoder.compareAndSwapPair(kind, compare: compare, value: value, base: base)
        case .atomicMemory(let kind, let source, let value, let base):
            return try A64LoadStoreEncoder.atomicMemory(kind, source: source, value: value, base: base)
        case .loadAcquireRCpc(let kind, let value, let base):
            return try A64LoadStoreEncoder.loadAcquireRCpc(kind, value: value, base: base)
        case .clearExclusive(let immediate):
            try checkRange(Int64(immediate), 0...0xf, instruction: "clrex")
            return A64.ClearExclusive.baseWord | A64.ClearExclusive.crm.insert(immediate)
        case .prefetch(let kind, let operation, let memory):
            return try A64LoadStoreEncoder.prefetch(kind, operation: operation, memory: memory)
        case .systemRegisterMove(let read, let register, let value):
            guard value.is64Bit else { throw AssemblerError.invalidRegister(read ? "mrs" : "msr") }
            typealias F = A64.SystemRegisterMove
            return F.baseWord
                | F.l.insert(read ? 1 : 0)
                | F.o0.insert(register.op0 - 2)
                | F.op1.insert(register.op1)
                | F.crn.insert(register.crn)
                | F.crm.insert(register.crm)
                | F.op2.insert(register.op2)
                | F.rt.insert(value.encodedNumber)
        case .pstate(let field, let immediate):
            try checkRange(Int64(immediate), 0...0xf, instruction: "msr")
            typealias F = A64.PStateImmediate
            return F.baseWord | F.op1.insert(field.op1) | F.crm.insert(immediate) | F.op2.insert(field.op2)
        case .pstateFlag(let kind):
            return kind.word
        case .rcpcUnscaled(let kind, let target, let base, let offset):
            if let required = kind.requiredWidth, target.width != required {
                throw AssemblerError.invalidRegister(kind.rawValue)
            }
            guard base.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            try checkRange(offset, -256...255, instruction: kind.rawValue)
            let (size, opc) = kind.fields(is64Bit: target.is64Bit)
            typealias F = A64.RCpcUnscaledImmediate
            return F.baseWord
                | F.size.insert(size)
                | F.opc.insert(opc)
                | F.imm9.insert(UInt32(bitPattern: Int32(offset)))
                | F.rn.insert(base.encodedNumber)
                | F.rt.insert(target.encodedNumber)
        case .systemInstruction(let read, let op1, let crn, let crm, let op2, let register):
            if let register = register, !register.is64Bit {
                throw AssemblerError.invalidRegister(read ? "sysl" : "sys")
            }
            typealias F = A64.SystemInstruction
            let rt = register?.encodedNumber ?? 31
            return F.baseWord
                | F.l.insert(read ? 1 : 0)
                | F.op1.insert(op1)
                | F.crn.insert(crn)
                | F.crm.insert(crm)
                | F.op2.insert(op2)
                | F.rt.insert(rt)
        case .loadStoreSingle(let kind, let target, let memory):
            return try A64LoadStoreEncoder.single(kind, target: target, memory: memory)
        case .loadStoreUnprivileged(let kind, let target, let memory):
            return try A64LoadStoreEncoder.unprivileged(kind, target: target, memory: memory)
        case .loadLiteral(let kind, let target, let offset):
            return try A64LoadStoreEncoder.literal(kind, target: target, offset: offset)
        case .loadLiteralFP(let target, let offset):
            return try A64LoadStoreEncoder.literalFP(target: target, offset: offset)
        case .prefetchLiteral(let operation, let offset):
            return try A64LoadStoreEncoder.prefetchLiteral(operation: operation, offset: offset)
        case .loadStorePair(let kind, let first, let second, let memory):
            return try A64LoadStoreEncoder.pair(kind, first: first, second: second, memory: memory)
        case .loadStoreSingleFP(let kind, let target, let memory):
            return try A64LoadStoreEncoder.singleFP(kind, target: target, memory: memory)
        case .loadStorePairFP(let kind, let first, let second, let memory):
            return try A64LoadStoreEncoder.pairFP(kind, first: first, second: second, memory: memory)
        case .loadStoreMultiple(let kind, let registers, let address):
            return try A64LoadStoreEncoder.multiple(kind, registers: registers, address: address)
        case .loadStoreSingleLane(let kind, let registers, let address):
            return try A64LoadStoreEncoder.singleLane(kind, registers: registers, address: address)
        case .loadStoreReplicate(let kind, let registers, let address):
            return try A64LoadStoreEncoder.replicate(kind, registers: registers, address: address)
        case .pointerAuthentication(let kind, let register, let architecture):
            return try A64PointerAuthenticationEncoder.encode(kind, register: register, architecture: architecture)
        case .pointerAuthData(let kind, let destination, let source, let modifier):
            return try A64PointerAuthenticationEncoder.encodeData(kind, destination: destination, source: source, modifier: modifier)
        case .pointerAuthBranch(let kind, let target, let modifier):
            return try A64PointerAuthenticationEncoder.encodeBranch(kind, target: target, modifier: modifier)
        case .pointerAuthLoad(let kind, let target, let memory):
            return try A64PointerAuthenticationEncoder.encodeLoad(kind, target: target, memory: memory)
        case .mteTag(let kind, let destination, let first, let second):
            return try A64MTEEncoder.tag(kind, destination: destination, first: first, second: second)
        case .mteAddSubTag(let subtract, let destination, let source, let offset, let tag):
            return try A64MTEEncoder.addSubTag(subtract: subtract, destination: destination, source: source, offset: offset, tag: tag)
        case .mteStoreTag(let kind, let source, let memory):
            return try A64MTEEncoder.storeTag(kind, source: source, memory: memory)
        case .mteLoadTag(let target, let memory):
            return try A64MTEEncoder.loadTag(target: target, memory: memory)
        case .mteTagMultiple(let kind, let target, let base):
            return try A64MTEEncoder.tagMultiple(kind, target: target, base: base)
        case .mteStoreTagPair(let first, let second, let memory):
            return try A64MTEEncoder.storeTagPair(first: first, second: second, memory: memory)
        case .rmif(let source, let rotate, let mask):
            return try A64FlagManipulationEncoder.rmif(source: source, rotate: rotate, mask: mask)
        case .evaluateIntoFlags(let kind, let source):
            return try A64FlagManipulationEncoder.evaluateIntoFlags(kind, source: source)
        case .waitWithTimeout(let isEvent, let register):
            guard register.is64Bit else { throw AssemblerError.invalidRegister(isEvent ? "wfet" : "wfit") }
            typealias F = A64.WaitWithTimeout
            return F.baseWord | F.op2.insert(isEvent ? 0 : 1) | F.rt.insert(register.encodedNumber)
        case .fpDataProcessing2(let kind, let destination, let first, let second):
            return try A64FloatEncoder.dataProcessing2(kind, destination: destination, first: first, second: second)
        case .fpDataProcessing1(let kind, let destination, let source):
            return try A64FloatEncoder.dataProcessing1(kind, destination: destination, source: source)
        case .fpDataProcessing3(let kind, let destination, let first, let second, let third):
            return try A64FloatEncoder.dataProcessing3(kind, destination: destination, first: first, second: second, third: third)
        case .fpCompare(let kind, let first, let second):
            return try A64FloatEncoder.compare(kind, first: first, second: second)
        case .fpConvertPrecision(let destination, let source):
            return try A64FloatEncoder.convertPrecision(destination: destination, source: source)
        case .bfloat16Convert(let destination, let source):
            return try A64FloatEncoder.bfloat16Convert(destination: destination, source: source)
        case .fpMoveImmediate(let destination, let value):
            return try A64FloatEncoder.moveImmediate(destination: destination, value: value)
        case .fpMoveToGeneral(let destination, let source):
            return try A64FloatEncoder.moveToGeneral(destination: destination, source: source)
        case .fpMoveFromGeneral(let destination, let source):
            return try A64FloatEncoder.moveFromGeneral(destination: destination, source: source)
        case .fpMoveVectorHighToGeneral(let destination, let source):
            return try A64FloatEncoder.moveVectorHighToGeneral(destination: destination, source: source)
        case .fpMoveGeneralToVectorHigh(let destination, let source):
            return try A64FloatEncoder.moveGeneralToVectorHigh(destination: destination, source: source)
        case .fpConvertToInt(let kind, let destination, let source):
            return try A64FloatEncoder.convertToInt(kind, destination: destination, source: source)
        case .fpConvertFromInt(let kind, let destination, let source):
            return try A64FloatEncoder.convertFromInt(kind, destination: destination, source: source)
        case .fpConvertToFixed(let kind, let destination, let source, let fbits):
            return try A64FloatEncoder.convertToFixed(kind, destination: destination, source: source, fbits: fbits)
        case .fpConvertFromFixed(let kind, let destination, let source, let fbits):
            return try A64FloatEncoder.convertFromFixed(kind, destination: destination, source: source, fbits: fbits)
        case .fjcvtzs(let destination, let source):
            return try A64FloatEncoder.fjcvtzs(destination: destination, source: source)
        case .fpConditionalSelect(let destination, let first, let second, let condition):
            return try A64FloatEncoder.conditionalSelect(destination: destination, first: first, second: second, condition: condition)
        case .fpConditionalCompare(let kind, let first, let second, let nzcv, let condition):
            return try A64FloatEncoder.conditionalCompare(kind, first: first, second: second, nzcv: nzcv, condition: condition)
        case .acrossLanesInteger(let kind, let destination, let source):
            return try A64VectorEncoder.acrossLanesInteger(kind, destination: destination, source: source)
        case .acrossLanesFP(let kind, let destination, let source):
            return try A64VectorEncoder.acrossLanesFP(kind, destination: destination, source: source)
        case .vectorTwoRegisterMisc(let kind, let destination, let source):
            return try A64VectorEncoder.twoRegisterMisc(kind, destination: destination, source: source)
        case .vectorThreeSame(let kind, let destination, let first, let second):
            return try A64VectorEncoder.threeSame(kind, destination: destination, first: first, second: second)
        case .vectorShiftImmediate(let kind, let destination, let source, let shift):
            return try A64VectorEncoder.shiftImmediate(kind, destination: destination, source: source, shift: shift)
        case .vectorShiftLeftLong(let destination, let source, let shift):
            return try A64VectorEncoder.shiftLeftLong(destination: destination, source: source, shift: shift)
        case .vectorModifiedImmediate(let kind, let destination, let imm8, let shift):
            return try A64VectorEncoder.modifiedImmediate(kind, destination: destination, imm8: imm8, shift: shift)
        case .vectorDuplicateElement(let destination, let source):
            return try A64VectorEncoder.duplicateElement(destination: destination, source: source)
        case .vectorDuplicateGeneral(let destination, let source):
            return try A64VectorEncoder.duplicateGeneral(destination: destination, source: source)
        case .vectorMoveToGeneral(let signed, let destination, let source):
            return try A64VectorEncoder.moveToGeneral(signed: signed, destination: destination, source: source)
        case .vectorInsertGeneral(let destination, let source):
            return try A64VectorEncoder.insertGeneral(destination: destination, source: source)
        case .vectorInsertElement(let destination, let source):
            return try A64VectorEncoder.insertElement(destination: destination, source: source)
        case .vectorPermute(let kind, let destination, let first, let second):
            return try A64VectorEncoder.permute(kind, destination: destination, first: first, second: second)
        case .vectorExtract(let destination, let first, let second, let index):
            return try A64VectorEncoder.extract(destination: destination, first: first, second: second, index: index)
        case .vectorThreeDifferent(let kind, let destination, let first, let second):
            return try A64VectorEncoder.threeDifferent(kind, destination: destination, first: first, second: second)
        case .vectorIndexed(let kind, let destination, let first, let element):
            return try A64VectorEncoder.indexed(kind, destination: destination, first: first, element: element)
        case .vectorDotProduct(let kind, let destination, let first, let second):
            return try A64VectorEncoder.dotProduct(kind, destination: destination, first: first, second: second)
        case .vectorDotProductByElement(let kind, let destination, let first, let elementRegister, let index):
            return try A64VectorEncoder.dotProductByElement(kind, destination: destination, first: first, elementRegister: elementRegister, index: index)
        case .vectorUSDotProduct(let destination, let first, let second):
            return try A64VectorEncoder.usDotProduct(destination: destination, first: first, second: second)
        case .vectorMixedDotByElement(let kind, let destination, let first, let elementRegister, let index):
            return try A64VectorEncoder.mixedDotByElement(kind, destination: destination, first: first, elementRegister: elementRegister, index: index)
        case .vectorMatrixMultiply(let kind, let destination, let first, let second):
            return try A64VectorEncoder.matrixMultiply(kind, destination: destination, first: first, second: second)
        case .vectorThreeSameExtra(let kind, let destination, let first, let second):
            return try A64VectorEncoder.threeSameExtra(kind, destination: destination, first: first, second: second)
        case .scalarThreeSameExtra(let kind, let destination, let first, let second):
            return try A64VectorEncoder.scalarThreeSameExtra(kind, destination: destination, first: first, second: second)
        case .vectorComplexAdd(let destination, let first, let second, let rotation):
            return try A64VectorEncoder.complexAdd(destination: destination, first: first, second: second, rotation: rotation)
        case .vectorComplexMultiplyAdd(let destination, let first, let second, let rotation):
            return try A64VectorEncoder.complexMultiplyAdd(destination: destination, first: first, second: second, rotation: rotation)
        case .vectorComplexMultiplyAddByElement(let destination, let first, let elementRegister, let index, let rotation):
            return try A64VectorEncoder.complexMultiplyAddByElement(destination: destination, first: first, elementRegister: elementRegister, index: index, rotation: rotation)
        case .vectorFPMultiplyLong(let kind, let destination, let first, let second):
            return try A64VectorEncoder.fpMultiplyLong(kind, destination: destination, first: first, second: second)
        case .vectorFPMultiplyLongByElement(let kind, let destination, let first, let elementRegister, let index):
            return try A64VectorEncoder.fpMultiplyLongByElement(kind, destination: destination, first: first, elementRegister: elementRegister, index: index)
        case .vectorBFDot(let destination, let first, let second):
            return try A64VectorEncoder.bfDot(destination: destination, first: first, second: second)
        case .vectorBFDotByElement(let destination, let first, let elementRegister, let index):
            return try A64VectorEncoder.bfDotByElement(destination: destination, first: first, elementRegister: elementRegister, index: index)
        case .vectorBFMLAL(let top, let destination, let first, let second):
            return try A64VectorEncoder.bfMultiplyLong(top: top, destination: destination, first: first, second: second)
        case .vectorBFMLALByElement(let top, let destination, let first, let elementRegister, let index):
            return try A64VectorEncoder.bfMultiplyLongByElement(top: top, destination: destination, first: first, elementRegister: elementRegister, index: index)
        case .vectorBFMatrixMultiply(let destination, let first, let second):
            return try A64VectorEncoder.bfMatrixMultiply(destination: destination, first: first, second: second)
        case .vectorBFConvertNarrow(let top, let destination, let source):
            return try A64VectorEncoder.bfConvertNarrow(top: top, destination: destination, source: source)
        case .scalarThreeSame(let kind, let destination, let first, let second):
            return try A64VectorEncoder.scalarThreeSame(kind, destination: destination, first: first, second: second)
        case .scalarPairwise(let kind, let destination, let source):
            return try A64VectorEncoder.scalarPairwise(kind, destination: destination, source: source)
        case .scalarTwoRegisterMisc(let kind, let destination, let source):
            return try A64VectorEncoder.scalarTwoRegisterMisc(kind, destination: destination, source: source)
        case .scalarShiftImmediate(let kind, let destination, let source, let shift):
            return try A64VectorEncoder.scalarShiftImmediate(kind, destination: destination, source: source, shift: shift)
        case .scalarThreeDifferent(let kind, let destination, let first, let second):
            return try A64VectorEncoder.scalarThreeDifferent(kind, destination: destination, first: first, second: second)
        case .scalarIndexed(let kind, let destination, let first, let element):
            return try A64VectorEncoder.scalarIndexed(kind, destination: destination, first: first, element: element)
        case .scalarCopyDuplicate(let destination, let element):
            return try A64VectorEncoder.scalarCopyDuplicate(destination: destination, element: element)
        case .scalarFPTwoRegisterMisc(let kind, let destination, let source):
            return try A64VectorEncoder.scalarFPTwoRegisterMisc(kind, destination: destination, source: source)
        case .scalarThreeSameFP(let kind, let destination, let first, let second):
            return try A64VectorEncoder.scalarThreeSameFP(kind, destination: destination, first: first, second: second)
        case .scalarShiftNarrow(let kind, let destination, let source, let shift):
            return try A64VectorEncoder.scalarShiftNarrow(kind, destination: destination, source: source, shift: shift)
        case .scalarTwoRegisterMiscNarrow(let kind, let destination, let source):
            return try A64VectorEncoder.scalarTwoRegisterMiscNarrow(kind, destination: destination, source: source)
        case .scalarShiftFixedPoint(let kind, let destination, let source, let fbits):
            return try A64VectorEncoder.scalarShiftFixedPoint(kind, destination: destination, source: source, fbits: fbits)
        case .vectorTableLookup(let kind, let destination, let table, let index):
            return try A64VectorEncoder.tableLookup(kind, destination: destination, table: table, index: index)
        case .vectorCompareZero(let kind, let destination, let source):
            return try A64VectorEncoder.compareZero(kind, destination: destination, source: source)
        case .vectorExtractNarrow(let kind, let destination, let source):
            return try A64VectorEncoder.extractNarrow(kind, destination: destination, source: source)
        case .vectorConvert(let kind, let destination, let source):
            return try A64VectorEncoder.convert(kind, destination: destination, source: source)
        case .vectorPairwiseLongAdd(let kind, let destination, let source):
            return try A64VectorEncoder.pairwiseLongAdd(kind, destination: destination, source: source)
        case .vectorRoundReciprocal(let kind, let destination, let source):
            return try A64VectorEncoder.roundReciprocal(kind, destination: destination, source: source)
        case .vectorFPConvertPrecision(let kind, let upper, let destination, let source):
            return try A64VectorEncoder.fpConvertPrecision(kind, upper: upper, destination: destination, source: source)
        case .cryptoAES(let kind, let destination, let source):
            return try A64VectorEncoder.cryptoAES(kind, destination: destination, source: source)
        case .cryptoSHA3(let kind, let d, let n, let m):
            return A64VectorEncoder.cryptoSHA3(kind, d: d, n: n, m: m)
        case .cryptoSHA2(let kind, let d, let n):
            return A64VectorEncoder.cryptoSHA2(kind, d: d, n: n)
        case .cryptoSHA512(let kind, let d, let n, let m):
            return A64VectorEncoder.cryptoSHA512(kind, d: d, n: n, m: m)
        case .cryptoTwoReg(let kind, let d, let n):
            return A64VectorEncoder.cryptoTwoReg(kind, d: d, n: n)
        case .cryptoSM3(let kind, let d, let n, let m):
            return A64VectorEncoder.cryptoSM3(kind, d: d, n: n, m: m)
        case .cryptoSM3Indexed(let kind, let d, let n, let m, let index):
            return A64VectorEncoder.cryptoSM3Indexed(kind, d: d, n: n, m: m, index: index)
        case .cryptoSM3SS1(let d, let n, let m, let a):
            return A64VectorEncoder.cryptoSM3SS1(d: d, n: n, m: m, a: a)
        case .cryptoSHA3Four(let kind, let d, let n, let m, let a):
            return A64VectorEncoder.cryptoSHA3Four(kind, d: d, n: n, m: m, a: a)
        case .cryptoRAX1(let d, let n, let m):
            return A64VectorEncoder.cryptoRAX1(d: d, n: n, m: m)
        case .cryptoXAR(let d, let n, let m, let imm6):
            return try A64VectorEncoder.cryptoXAR(d: d, n: n, m: m, imm6: imm6)
        }
    }
}

internal enum A64PointerAuthenticationEncoder {
    static func encode(_ kind: A64.PointerAuthenticationKind, register: IntegerRegister?, architecture: ARM64Assembler.Architecture) throws -> UInt32 {
        try requireARM64E(architecture, instruction: kind.rawValue)
        switch kind {
        case .paciasp: return 0xd503233f
        case .autiasp: return 0xd50323bf
        case .pacibsp: return 0xd503237f
        case .autibsp: return 0xd50323ff
        case .pacia1716: return 0xd503211f
        case .pacib1716: return 0xd503215f
        case .autia1716: return 0xd503219f
        case .autib1716: return 0xd50321df
        case .xpaclri: return 0xd50320ff
        case .xpaci, .xpacd:
            guard let rd = register else {
                throw AssemblerError.invalidOperandCount(instruction: kind.rawValue, expected: "1", actual: 0)
            }
            return (kind == .xpaci ? 0xdac143e0 : 0xdac147e0) | rd.encodedNumber
        }
    }

    static func encodeData(_ kind: A64.PointerAuthDataKind, destination: IntegerRegister, source: IntegerRegister?, modifier: IntegerRegister?) throws -> UInt32 {
        guard destination.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        if kind.isGeneric {
            guard let source, let modifier, source.is64Bit, modifier.is64Bit else {
                throw AssemblerError.invalidRegister(kind.rawValue)
            }
            // PACGA: data-processing (2 source).
            return 0x9ac0_3000 | (modifier.encodedNumber << 16) | (source.encodedNumber << 5) | destination.encodedNumber
        }
        // Data-processing (1 source). The `*Z*` forms have an implicit `xzr` source.
        let rn: UInt32
        if kind.isImplicitModifier {
            guard source == nil else { throw AssemblerError.invalidRegister(kind.rawValue) }
            rn = 0b11111
        } else {
            guard let source, source.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            rn = source.encodedNumber
        }
        return 0xdac1_0000 | (kind.opcode << 10) | (rn << 5) | destination.encodedNumber
    }

    static func encodeBranch(_ kind: A64.PointerAuthBranchKind, target: IntegerRegister?, modifier: IntegerRegister?) throws -> UInt32 {
        switch kind.form {
        case .twoRegister:
            guard let target, let modifier, target.is64Bit, modifier.is64Bit else {
                throw AssemblerError.invalidRegister(kind.rawValue)
            }
            return kind.baseWord | (target.encodedNumber << 5) | modifier.encodedNumber
        case .oneRegister:
            guard let target, target.is64Bit, modifier == nil else {
                throw AssemblerError.invalidRegister(kind.rawValue)
            }
            return kind.baseWord | (target.encodedNumber << 5)
        case .noOperand:
            guard target == nil, modifier == nil else {
                throw AssemblerError.invalidRegister(kind.rawValue)
            }
            return kind.baseWord
        }
    }

    static func encodeLoad(_ kind: A64.PointerAuthLoadKind, target: IntegerRegister, memory: A64.MemoryOperand) throws -> UInt32 {
        guard target.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let base: IntegerRegister
        let offset: Int64
        let writeback: Bool
        switch memory {
        case .unsignedOffset(let b, let o), .signedUnscaled(let b, let o):
            base = b; offset = o; writeback = false
        case .preIndexed(let b, let o):
            base = b; offset = o; writeback = true
        default:
            throw AssemblerError.invalidMemoryOperand(kind.rawValue)
        }
        guard offset % 8 == 0 else { throw AssemblerError.immediateAlignment(instruction: kind.rawValue, value: offset, alignment: 8) }
        let scaled = offset / 8
        try checkRange(scaled, -512...511, instruction: kind.rawValue)
        let imm10 = UInt32(bitPattern: Int32(scaled)) & 0x3ff
        let s = (imm10 >> 9) & 1
        let imm9 = imm10 & 0x1ff
        let m: UInt32 = kind.isBKey ? 1 : 0
        let w: UInt32 = writeback ? 1 : 0
        return 0xf820_0400 | (m << 23) | (s << 22) | (imm9 << 12) | (w << 11) | (base.encodedNumber << 5) | target.encodedNumber
    }
}

internal enum A64MTEEncoder {
    static func tag(_ kind: A64.MTETagKind, destination: IntegerRegister, first: IntegerRegister, second: IntegerRegister) throws -> UInt32 {
        guard destination.is64Bit, first.is64Bit, second.is64Bit else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }
        return kind.baseWord | (second.encodedNumber << 16) | (first.encodedNumber << 5) | destination.encodedNumber
    }

    static func addSubTag(subtract: Bool, destination: IntegerRegister, source: IntegerRegister, offset: UInt32, tag: UInt32) throws -> UInt32 {
        let mnemonic = subtract ? "subg" : "addg"
        guard destination.is64Bit, source.is64Bit else { throw AssemblerError.invalidRegister(mnemonic) }
        guard offset % 16 == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: Int64(offset), alignment: 16) }
        let uimm6 = offset / 16
        try checkRange(Int64(uimm6), 0...63, instruction: mnemonic)
        try checkRange(Int64(tag), 0...15, instruction: mnemonic)
        typealias F = A64.AddSubTag
        return F.baseWord
            | F.op.insert(subtract ? 1 : 0)
            | F.uimm6.insert(uimm6)
            | F.uimm4.insert(tag)
            | F.rn.insert(source.encodedNumber)
            | F.rd.insert(destination.encodedNumber)
    }

    /// Base of the "Load/store memory tags" single class (bit21 set, opc/op2 zero).
    private static let memoryTagsBase: UInt32 = 0xd920_0000

    /// Decode a memory operand for the tag-store group into a base register, a
    /// signed offset (scaled by 16) and an `op2` addressing field.
    /// `op2`: signed offset = 0b10, post-index = 0b01, pre-index = 0b11.
    private static func tagAddress(_ memory: A64.MemoryOperand, instruction: String) throws -> (base: IntegerRegister, imm9: UInt32, op2: UInt32) {
        let base: IntegerRegister
        let offset: Int64
        let op2: UInt32
        switch memory {
        case .unsignedOffset(let b, let o), .signedUnscaled(let b, let o):
            base = b; offset = o; op2 = 0b10
        case .preIndexed(let b, let o):
            base = b; offset = o; op2 = 0b11
        case .postIndexed(let b, let o):
            base = b; offset = o; op2 = 0b01
        default:
            throw AssemblerError.invalidMemoryOperand(instruction)
        }
        guard base.is64Bit else { throw AssemblerError.invalidRegister(instruction) }
        guard offset % 16 == 0 else { throw AssemblerError.immediateAlignment(instruction: instruction, value: offset, alignment: 16) }
        let scaled = offset / 16
        try checkRange(scaled, -256...255, instruction: instruction)
        let imm9 = UInt32(bitPattern: Int32(scaled)) & 0x1ff
        return (base, imm9, op2)
    }

    static func storeTag(_ kind: A64.MTEStoreTagKind, source: IntegerRegister, memory: A64.MemoryOperand) throws -> UInt32 {
        guard source.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let address = try tagAddress(memory, instruction: kind.rawValue)
        return memoryTagsBase | (kind.opc << 22) | (address.imm9 << 12) | (address.op2 << 10)
            | (address.base.encodedNumber << 5) | source.encodedNumber
    }

    static func loadTag(target: IntegerRegister, memory: A64.MemoryOperand) throws -> UInt32 {
        guard target.is64Bit else { throw AssemblerError.invalidRegister("ldg") }
        let base: IntegerRegister
        let offset: Int64
        switch memory {
        case .unsignedOffset(let b, let o), .signedUnscaled(let b, let o):
            base = b; offset = o
        default:
            throw AssemblerError.invalidMemoryOperand("ldg")
        }
        guard base.is64Bit else { throw AssemblerError.invalidRegister("ldg") }
        guard offset % 16 == 0 else { throw AssemblerError.immediateAlignment(instruction: "ldg", value: offset, alignment: 16) }
        let scaled = offset / 16
        try checkRange(scaled, -256...255, instruction: "ldg")
        let imm9 = UInt32(bitPattern: Int32(scaled)) & 0x1ff
        // opc = 01, op2 = 00.
        return memoryTagsBase | (1 << 22) | (imm9 << 12) | (base.encodedNumber << 5) | target.encodedNumber
    }

    static func tagMultiple(_ kind: A64.MTETagMultipleKind, target: IntegerRegister, base: IntegerRegister) throws -> UInt32 {
        guard target.is64Bit, base.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        // op2 = 00, imm9 = 0.
        return memoryTagsBase | (kind.opc << 22) | (base.encodedNumber << 5) | target.encodedNumber
    }

    static func storeTagPair(first: IntegerRegister, second: IntegerRegister, memory: A64.MemoryOperand) throws -> UInt32 {
        guard first.is64Bit, second.is64Bit else { throw AssemblerError.invalidRegister("stgp") }
        let base: IntegerRegister
        let offset: Int64
        let modeBase: UInt32
        switch memory {
        case .unsignedOffset(let b, let o), .signedUnscaled(let b, let o):
            base = b; offset = o; modeBase = 0x6900_0000
        case .preIndexed(let b, let o):
            base = b; offset = o; modeBase = 0x6980_0000
        case .postIndexed(let b, let o):
            base = b; offset = o; modeBase = 0x6880_0000
        default:
            throw AssemblerError.invalidMemoryOperand("stgp")
        }
        guard base.is64Bit else { throw AssemblerError.invalidRegister("stgp") }
        guard offset % 16 == 0 else { throw AssemblerError.immediateAlignment(instruction: "stgp", value: offset, alignment: 16) }
        let scaled = offset / 16
        try checkRange(scaled, -64...63, instruction: "stgp")
        let imm7 = UInt32(bitPattern: Int32(scaled)) & 0x7f
        return modeBase | (imm7 << 15) | (second.encodedNumber << 10) | (base.encodedNumber << 5) | first.encodedNumber
    }
}

internal enum A64FlagManipulationEncoder {
    static func rmif(source: IntegerRegister, rotate: UInt32, mask: UInt32) throws -> UInt32 {
        guard source.is64Bit else { throw AssemblerError.invalidRegister("rmif") }
        try checkRange(Int64(rotate), 0...63, instruction: "rmif")
        try checkRange(Int64(mask), 0...15, instruction: "rmif")
        typealias F = A64.RMIF
        return F.baseWord | F.rotate.insert(rotate) | F.rn.insert(source.encodedNumber) | F.mask.insert(mask)
    }

    static func evaluateIntoFlags(_ kind: A64.EvaluateFlagsKind, source: IntegerRegister) throws -> UInt32 {
        guard !source.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        typealias F = A64.EvaluateIntoFlags
        return F.baseWord | F.sz.insert(kind.isSixteen ? 1 : 0) | F.rn.insert(source.encodedNumber)
    }
}

internal enum A64MoveEncoder {
    static func movAlias(destination rd: IntegerRegister, source: A64.MoveAliasSource) throws -> UInt32 {
        switch source {
        case .immediate(let value):
            return try moveImmediateAlias(destination: rd, value: value)
        case .register(let rm):
            guard rd.width == rm.width else { throw AssemblerError.invalidRegister("mov") }
            if rd.kind == .stackPointer || rm.kind == .stackPointer {
                return try A64AddSubEncoder.addSub(.add, destination: rd, first: rm, operand: .immediate(0, shift: nil))
            }
            return try A64LogicalEncoder.logical(.orr, destination: rd, first: zeroRegister(width: rd.width), operand: .shiftedRegister(rm, shift: nil))
        }
    }

    static func moveImmediateAlias(destination rd: IntegerRegister, value: Int64) throws -> UInt32 {
        let width = rd.is64Bit ? 64 : 32
        let mask: UInt64 = width == 64 ? UInt64.max : 0xffff_ffff
        let unsigned = UInt64(bitPattern: value) & mask

        if unsigned <= 0xffff {
            return try moveWide(.movz, destination: rd, immediate: Int64(unsigned), shift: nil)
        }
        for shift in stride(from: 16, through: width - 16, by: 16) {
            if unsigned & ~(UInt64(0xffff) << UInt64(shift)) == 0 {
                return try moveWide(.movz, destination: rd, immediate: Int64((unsigned >> UInt64(shift)) & 0xffff), shift: shift)
            }
        }

        let inverted = (~unsigned) & mask
        if inverted <= 0xffff {
            return try moveWide(.movn, destination: rd, immediate: Int64(inverted), shift: nil)
        }
        for shift in stride(from: 16, through: width - 16, by: 16) {
            if inverted & ~(UInt64(0xffff) << UInt64(shift)) == 0 {
                return try moveWide(.movn, destination: rd, immediate: Int64((inverted >> UInt64(shift)) & 0xffff), shift: shift)
            }
        }

        return try A64LogicalEncoder.logical(.orr, destination: rd, first: zeroRegister(width: width), operand: .immediate(value))
    }

    static func moveWide(_ kind: A64.MoveWideKind, destination rd: IntegerRegister, immediate imm: Int64, shift: Int?) throws -> UInt32 {
        let mnemonic = kind.rawValue
        try checkRange(imm, 0...0xffff, instruction: mnemonic)
        let shift = shift ?? 0
        guard shift % 16 == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: Int64(shift), alignment: 16) }
        guard rd.is64Bit || shift <= 16 else { throw AssemblerError.immediateOutOfRange(instruction: mnemonic, value: Int64(shift), range: 0...16) }
        typealias F = A64.MoveWide
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.opc.insert(kind.opc)
            | F.hw.insert(UInt32(shift / 16))
            | F.imm16.insert(UInt32(imm))
            | F.rd.insert(rd.encodedNumber)
    }
}

internal enum A64LogicalEncoder {
    static func logical(_ kind: A64.LogicalKind, destination rd: IntegerRegister, first rn: IntegerRegister, operand: A64.LogicalOperand) throws -> UInt32 {
        switch operand {
        case .immediate(let value):
            return try immediate(kind, destination: rd, first: rn, value: value)
        case .shiftedRegister(let rm, let shift):
            return try shiftedRegister(kind, destination: rd, first: rn, second: rm, shift: shift)
        }
    }

    static func immediate(_ kind: A64.LogicalKind, destination rd: IntegerRegister, first rn: IntegerRegister, value: Int64) throws -> UInt32 {
        guard rd.width == rn.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let opc: UInt32
        switch kind {
        case .and: opc = 0
        case .orr: opc = 1
        case .eor: opc = 2
        case .ands: opc = 3
        default: throw AssemblerError.unsupportedOperand(kind.rawValue)
        }
        let width = rd.is64Bit ? 64 : 32
        let mask: UInt64 = width == 64 ? UInt64.max : 0xffff_ffff
        guard let encoding = A64BitmaskImmediate.encode(UInt64(bitPattern: value) & mask, width: width) else {
            throw AssemblerError.invalidImmediate("#\(value)")
        }
        typealias F = A64.LogicalImmediate
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.opc.insert(opc)
            | F.n.insert(encoding.n)
            | F.immr.insert(encoding.immr)
            | F.imms.insert(encoding.imms)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func shiftedRegister(_ kind: A64.LogicalKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister, shift: ParsedShift?) throws -> UInt32 {
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let shiftKind = shift?.kind ?? .lsl
        let amount = shift?.amount ?? 0
        guard rd.is64Bit || amount <= 31 else { throw AssemblerError.immediateOutOfRange(instruction: kind.rawValue, value: Int64(amount), range: 0...31) }
        let opc: UInt32
        let n: UInt32
        switch kind {
        case .and: opc = 0; n = 0
        case .bic: opc = 0; n = 1
        case .orr: opc = 1; n = 0
        case .orn: opc = 1; n = 1
        case .eor: opc = 2; n = 0
        case .eon: opc = 2; n = 1
        case .ands: opc = 3; n = 0
        case .bics: opc = 3; n = 1
        }
        typealias F = A64.LogicalShiftedRegister
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.opc.insert(opc)
            | F.shift.insert(shiftKind.rawValue)
            | F.n.insert(n)
            | F.rm.insert(rm.encodedNumber)
            | F.imm6.insert(UInt32(amount))
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func mvnAlias(destination rd: IntegerRegister, source rm: IntegerRegister, shift: ParsedShift?) throws -> UInt32 {
        try shiftedRegister(.orn, destination: rd, first: zeroRegister(width: rd.width), second: rm, shift: shift)
    }
}

internal enum A64LoadStoreEncoder {
    static func exclusive(_ kind: A64.LoadStoreExclusiveKind, status: IntegerRegister?, value rt: IntegerRegister, value2 rt2: IntegerRegister?, base: IntegerRegister) throws -> UInt32 {
        // The base must be a 64-bit address register (X or SP).
        guard base.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }

        // Determine the size field and validate the value register width.
        let size: UInt32
        if let fixed = kind.fixedSize {
            guard !rt.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            size = fixed
        } else {
            size = rt.is64Bit ? 0b11 : 0b10
        }

        // Status register (Ws) for the store-exclusive forms; always 32-bit.
        let rsNum: UInt32
        if kind.hasStatusRegister {
            guard let status, !status.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            rsNum = status.encodedNumber
        } else {
            guard status == nil else { throw AssemblerError.invalidRegister(kind.rawValue) }
            rsNum = 0b11111
        }

        // Second value register (Rt2) for the pair forms; must match Rt width.
        let rt2Num: UInt32
        if kind.isPair {
            guard let rt2, rt2.is64Bit == rt.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            rt2Num = rt2.encodedNumber
        } else {
            guard rt2 == nil else { throw AssemblerError.invalidRegister(kind.rawValue) }
            rt2Num = 0b11111
        }

        typealias F = A64.LoadStoreExclusive
        return F.baseWord
            | F.size.insert(size)
            | F.o2.insert(kind.o2)
            | F.l.insert(kind.l)
            | F.o1.insert(kind.isPair ? 1 : 0)
            | F.rs.insert(rsNum)
            | F.o0.insert(kind.o0)
            | F.rt2.insert(rt2Num)
            | F.rn.insert(base.encodedNumber)
            | F.rt.insert(rt.encodedNumber)
    }

    static func compareAndSwap(_ kind: A64.CompareAndSwapKind, compare rs: IntegerRegister, value rt: IntegerRegister, base: IntegerRegister) throws -> UInt32 {
        guard base.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let size: UInt32
        if let fixed = kind.fixedSize {
            guard !rs.is64Bit, !rt.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            size = fixed
        } else {
            guard rs.is64Bit == rt.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            size = rt.is64Bit ? 0b11 : 0b10
        }
        typealias F = A64.LoadStoreExclusive
        return F.baseWord
            | F.size.insert(size)
            | F.o2.insert(1)
            | F.l.insert(kind.acquire)
            | F.o1.insert(1)
            | F.rs.insert(rs.encodedNumber)
            | F.o0.insert(kind.release)
            | F.rt2.insert(0b11111)
            | F.rn.insert(base.encodedNumber)
            | F.rt.insert(rt.encodedNumber)
    }

    static func compareAndSwapPair(_ kind: A64.CompareAndSwapPairKind, compare rs: IntegerRegister, value rt: IntegerRegister, base: IntegerRegister) throws -> UInt32 {
        guard base.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        guard rs.is64Bit == rt.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        // The pair registers must be even-numbered (the high register is implied).
        guard rs.encodedNumber % 2 == 0, rt.encodedNumber % 2 == 0 else {
            throw AssemblerError.invalidRegister(kind.rawValue)
        }
        let size: UInt32 = rt.is64Bit ? 0b01 : 0b00
        typealias F = A64.LoadStoreExclusive
        return F.baseWord
            | F.size.insert(size)
            | F.l.insert(kind.acquire)
            | F.o1.insert(1)
            | F.rs.insert(rs.encodedNumber)
            | F.o0.insert(kind.release)
            | F.rt2.insert(0b11111)
            | F.rn.insert(base.encodedNumber)
            | F.rt.insert(rt.encodedNumber)
    }

    static func atomicMemory(_ kind: A64.AtomicMemoryKind, source rs: IntegerRegister, value rt: IntegerRegister?, base: IntegerRegister) throws -> UInt32 {
        guard base.is64Bit else { throw AssemblerError.invalidRegister(kind.mnemonic) }

        let size: UInt32
        if let fixed = kind.fixedSize {
            guard !rs.is64Bit else { throw AssemblerError.invalidRegister(kind.mnemonic) }
            if let rt { guard !rt.is64Bit else { throw AssemblerError.invalidRegister(kind.mnemonic) } }
            size = fixed
        } else {
            if let rt { guard rt.is64Bit == rs.is64Bit else { throw AssemblerError.invalidRegister(kind.mnemonic) } }
            size = rs.is64Bit ? 0b11 : 0b10
        }

        let rtNum: UInt32
        if kind.isStore {
            guard rt == nil else { throw AssemblerError.invalidRegister(kind.mnemonic) }
            rtNum = 0b11111
        } else {
            guard let rt else { throw AssemblerError.invalidRegister(kind.mnemonic) }
            rtNum = rt.encodedNumber
        }

        typealias F = A64.AtomicMemory
        return F.baseWord
            | F.size.insert(size)
            | F.a.insert(kind.acquire ? 1 : 0)
            | F.r.insert(kind.release ? 1 : 0)
            | F.rs.insert(rs.encodedNumber)
            | F.o3.insert(kind.operation.o3)
            | F.opc.insert(kind.operation.opc)
            | F.rn.insert(base.encodedNumber)
            | F.rt.insert(rtNum)
    }

    static func loadAcquireRCpc(_ kind: A64.LoadAcquireRCpcKind, value rt: IntegerRegister, base: IntegerRegister) throws -> UInt32 {
        guard base.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let size: UInt32
        if let fixed = kind.fixedSize {
            guard !rt.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            size = fixed
        } else {
            size = rt.is64Bit ? 0b11 : 0b10
        }
        typealias F = A64.LoadAcquireRCpc
        return F.baseWord | F.size.insert(size) | F.rn.insert(base.encodedNumber) | F.rt.insert(rt.encodedNumber)
    }

    static func prefetch(_ kind: A64.PrefetchKind, operation: UInt32, memory: MemoryOperand) throws -> UInt32 {
        try checkRange(Int64(operation), 0...0x1f, instruction: kind.rawValue)
        let op = operation & 0x1f
        switch (kind, memory) {
        case (.prfm, .unsignedOffset(let base, let offset)):
            guard base.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            guard offset >= 0, offset % 8 == 0 else {
                throw AssemblerError.immediateAlignment(instruction: kind.rawValue, value: offset, alignment: 8)
            }
            let scaled = offset / 8
            try checkRange(scaled, 0...0xfff, instruction: kind.rawValue)
            return 0xf980_0000 | (UInt32(scaled) << 10) | (base.encodedNumber << 5) | op

        case (.prfm, .registerOffset(let base, let rm, let ext, let shift)):
            guard base.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            let option = ext ?? (rm.is64Bit ? ExtendKind.uxtx : ExtendKind.uxtw)
            guard shift == 0 || shift == 3 else { throw AssemblerError.unsupportedShift("lsl #\(shift)") }
            return 0xf8a0_0800 | (rm.encodedNumber << 16) | (option.rawValue << 13)
                | (UInt32(shift == 0 ? 0 : 1) << 12) | (base.encodedNumber << 5) | op

        case (.prfum, .unsignedOffset(let base, let offset)), (.prfum, .signedUnscaled(let base, let offset)):
            guard base.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
            try checkRange(offset, -256...255, instruction: kind.rawValue)
            return 0xf880_0000 | ((UInt32(bitPattern: Int32(offset)) & 0x1ff) << 12) | (base.encodedNumber << 5) | op

        default:
            throw AssemblerError.unsupportedOperand(kind.rawValue)
        }
    }

    static func single(_ kind: A64.LoadStoreSingleKind, target rt: IntegerRegister, memory: MemoryOperand) throws -> UInt32 {
        let mnemonic = kind.rawValue
        let descriptor = SingleDescriptor(kind: kind, rt: rt)

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

    static func unprivileged(_ kind: A64.LoadStoreUnprivilegedKind, target rt: IntegerRegister, memory: MemoryOperand) throws -> UInt32 {
        let mnemonic = kind.rawValue
        let descriptor = SingleDescriptor(kind: kind.unscaledEquivalent, rt: rt)
        let base: IntegerRegister
        let offset: Int64
        switch memory {
        case .unsignedOffset(let b, let o), .signedUnscaled(let b, let o):
            base = b; offset = o
        case .preIndexed, .postIndexed, .registerOffset:
            // The unprivileged form only supports the unscaled signed-offset shape.
            throw AssemblerError.unsupportedOperand(mnemonic)
        }
        try checkRange(offset, -256...255, instruction: mnemonic)
        // size/opc come from the unscaled descriptor's base word; the
        // unprivileged class word adds bits[11:10]=10.
        typealias F = A64.LoadStoreUnprivileged
        let size = (descriptor.unscaledBase >> 30) & 3
        let opc = (descriptor.unscaledBase >> 22) & 3
        return F.baseWord
            | F.size.insert(size)
            | F.opc.insert(opc)
            | F.imm9.insert(UInt32(bitPattern: Int32(offset)))
            | F.rn.insert(base.encodedNumber)
            | F.rt.insert(rt.encodedNumber)
    }

    static func literal(_ kind: A64.LoadLiteralKind, target rt: IntegerRegister, offset: Int64) throws -> UInt32 {
        let mnemonic = kind.rawValue
        let opc: UInt32
        switch kind {
        case .ldr: opc = rt.is64Bit ? 0b01 : 0b00
        case .ldrsw:
            guard rt.is64Bit else { throw AssemblerError.invalidRegister(mnemonic) }
            opc = 0b10
        }
        typealias F = A64.LoadLiteral
        guard offset % F.scale == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: offset, alignment: F.scale) }
        let imm19 = offset / F.scale
        try checkRange(imm19, F.imm19Range, instruction: mnemonic)
        return F.baseWord | F.opc.insert(opc) | F.imm19.insert(UInt32(bitPattern: Int32(imm19))) | F.rt.insert(rt.encodedNumber)
    }

    static func literalFP(target rt: A64.FPRegister, offset: Int64) throws -> UInt32 {
        let opc: UInt32
        switch rt.width {
        case 32: opc = 0b00
        case 64: opc = 0b01
        case 128: opc = 0b10
        default: throw AssemblerError.invalidRegister("ldr")
        }
        typealias F = A64.LoadLiteral
        guard offset % F.scale == 0 else { throw AssemblerError.immediateAlignment(instruction: "ldr", value: offset, alignment: F.scale) }
        let imm19 = offset / F.scale
        try checkRange(imm19, F.imm19Range, instruction: "ldr")
        return F.baseWord | F.opc.insert(opc) | F.v.insert(1) | F.imm19.insert(UInt32(bitPattern: Int32(imm19))) | F.rt.insert(rt.encodedNumber)
    }

    static func prefetchLiteral(operation: UInt32, offset: Int64) throws -> UInt32 {
        guard operation <= 0x1f else { throw AssemblerError.invalidImmediate("prfm") }
        typealias F = A64.LoadLiteral
        guard offset % F.scale == 0 else { throw AssemblerError.immediateAlignment(instruction: "prfm", value: offset, alignment: F.scale) }
        let imm19 = offset / F.scale
        try checkRange(imm19, F.imm19Range, instruction: "prfm")
        return F.baseWord | F.opc.insert(0b11) | F.imm19.insert(UInt32(bitPattern: Int32(imm19))) | F.rt.insert(operation)
    }

    static func pair(_ kind: A64.LoadStorePairKind, first rt: IntegerRegister, second rt2: IntegerRegister, memory: MemoryOperand) throws -> UInt32 {
        let mnemonic = kind.rawValue
        guard rt.width == rt2.width else { throw AssemblerError.invalidRegister(mnemonic) }
        // LDPSW always uses 64-bit destinations with a word (4-byte) scale.
        if kind.isSignedWord { guard rt.is64Bit else { throw AssemblerError.invalidRegister(mnemonic) } }
        let scale: Int64 = kind.isSignedWord ? 4 : (rt.is64Bit ? 8 : 4)
        // `mode`[24:23]: 00=no-allocate, 01=post-indexed, 10=signed offset, 11=pre-indexed.
        let mode: UInt32
        let base: IntegerRegister
        let offset: Int64
        switch memory {
        case .signedUnscaled(let b, let o), .unsignedOffset(let b, let o): mode = kind.isNoAllocate ? 0 : 2; base = b; offset = o
        case .postIndexed(let b, let o):
            guard !kind.isNoAllocate else { throw AssemblerError.unsupportedOperand(mnemonic) }
            mode = 1; base = b; offset = o
        case .preIndexed(let b, let o):
            guard !kind.isNoAllocate else { throw AssemblerError.unsupportedOperand(mnemonic) }
            mode = 3; base = b; offset = o
        case .registerOffset: throw AssemblerError.unsupportedOperand(mnemonic)
        }
        guard offset % scale == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: offset, alignment: scale) }
        let imm7 = offset / scale
        try checkRange(imm7, -64...63, instruction: mnemonic)
        // `opc`: 00=word, 10=doubleword, 01=signed word (LDPSW).
        let opc: UInt32 = kind.isSignedWord ? 1 : (rt.is64Bit ? 2 : 0)
        typealias F = A64.LoadStorePair
        return F.baseWord
            | F.opc.insert(opc)
            | F.mode.insert(mode)
            | F.l.insert(kind.isLoad ? 1 : 0)
            | F.imm7.insert(UInt32(bitPattern: Int32(imm7)))
            | F.rt2.insert(rt2.encodedNumber)
            | F.rn.insert(base.encodedNumber)
            | F.rt.insert(rt.encodedNumber)
    }

    static func singleFP(_ kind: A64.LoadStoreSingleKind, target rt: A64.FPRegister, memory: MemoryOperand) throws -> UInt32 {
        let mnemonic = kind.rawValue
        let descriptor = try FPSingleDescriptor(kind: kind, rt: rt)

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

    static func pairFP(_ kind: A64.LoadStorePairKind, first rt: A64.FPRegister, second rt2: A64.FPRegister, memory: MemoryOperand) throws -> UInt32 {
        let mnemonic = kind.rawValue
        guard rt.width == rt2.width else { throw AssemblerError.invalidRegister(mnemonic) }
        // opc field (bits[31:30]): S=00, D=01, Q=10. Scale follows the access width.
        let opc: UInt32
        let scale: Int64
        switch rt.width {
        case 32:  opc = 0; scale = 4
        case 64:  opc = 1; scale = 8
        case 128: opc = 2; scale = 16
        default: throw AssemblerError.invalidRegister(mnemonic)
        }
        let modeBase: UInt32
        let base: IntegerRegister
        let offset: Int64
        switch memory {
        case .signedUnscaled(let b, let o), .unsignedOffset(let b, let o): modeBase = kind.isNoAllocate ? 0x2c000000 : 0x2d000000; base = b; offset = o
        case .postIndexed(let b, let o):
            guard !kind.isNoAllocate else { throw AssemblerError.unsupportedOperand(mnemonic) }
            modeBase = 0x2c800000; base = b; offset = o
        case .preIndexed(let b, let o):
            guard !kind.isNoAllocate else { throw AssemblerError.unsupportedOperand(mnemonic) }
            modeBase = 0x2d800000; base = b; offset = o
        case .registerOffset: throw AssemblerError.unsupportedOperand(mnemonic)
        }
        guard offset % scale == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: offset, alignment: scale) }
        let imm7 = offset / scale
        try checkRange(imm7, -64...63, instruction: mnemonic)
        let head = (opc << 30) | modeBase | ((kind.isLoad ? UInt32(1) : 0) << 22)
        return head | ((UInt32(bitPattern: Int32(imm7)) & 0x7f) << 15) | (rt2.encodedNumber << 10) | (base.encodedNumber << 5) | rt.encodedNumber
    }

    static func multiple(_ kind: A64.LoadStoreMultipleKind, registers list: A64.VectorRegisterList, address: A64.VectorMemoryOperand) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        guard kind.allows(count: list.count), let opcode = kind.opcode(count: list.count) else { throw fail() }
        let q = list.arrangement.q
        let size = list.arrangement.elementSize
        let l: UInt32 = kind.isLoad ? 1 : 0
        let common = (q << 30) | (l << 22) | (opcode << 12) | (size << 10) | list.encodedNumber

        switch address {
        case .base(let rn):
            return 0x0c00_0000 | common | (rn.encodedNumber << 5)
        case .postImmediate(let rn):
            // Immediate post-index: Rm = 0b11111, the transfer size is implicit.
            return 0x0c80_0000 | common | (0x1f << 16) | (rn.encodedNumber << 5)
        case .postRegister(let rn, let rm):
            return 0x0c80_0000 | common | (rm.encodedNumber << 16) | (rn.encodedNumber << 5)
        }
    }

    static func singleLane(_ kind: A64.LoadStoreMultipleKind, registers list: A64.VectorLaneList, address: A64.VectorMemoryOperand) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        let selem = kind.structure
        guard kind.structure == list.count, (1...4).contains(selem) else { throw fail() }
        guard list.index >= 0, list.index <= list.width.maxIndex else { throw fail() }

        let opcode0 = UInt32((selem - 1) >> 1)
        let r = UInt32((selem - 1) & 1)
        let index = UInt32(list.index)

        // The lane index is spread across Q (bit30), S (bit12), and size (bits[11:10])
        // differently for each element width.
        let q: UInt32
        let s: UInt32
        let size: UInt32
        let sizeClass: UInt32
        switch list.width {
        case .b:
            q = (index >> 3) & 1
            s = (index >> 2) & 1
            size = index & 0b11
            sizeClass = 0b00
        case .h:
            q = (index >> 2) & 1
            s = (index >> 1) & 1
            size = (index & 1) << 1
            sizeClass = 0b01
        case .s:
            q = (index >> 1) & 1
            s = index & 1
            size = 0b00
            sizeClass = 0b10
        case .d:
            q = index & 1
            s = 0
            size = 0b01
            sizeClass = 0b10
        }
        let opcode = (sizeClass << 1) | opcode0
        let l: UInt32 = kind.isLoad ? 1 : 0
        let common = (q << 30) | (l << 22) | (r << 21) | (opcode << 13) | (s << 12) | (size << 10) | list.encodedNumber

        switch address {
        case .base(let rn):
            return 0x0d00_0000 | common | (rn.encodedNumber << 5)
        case .postImmediate(let rn):
            return 0x0d80_0000 | common | (0x1f << 16) | (rn.encodedNumber << 5)
        case .postRegister(let rn, let rm):
            return 0x0d80_0000 | common | (rm.encodedNumber << 16) | (rn.encodedNumber << 5)
        }
    }

    static func replicate(_ kind: A64.LoadStoreReplicateKind, registers list: A64.VectorRegisterList, address: A64.VectorMemoryOperand) throws -> UInt32 {
        func fail() -> AssemblerError { .invalidRegister(kind.rawValue) }
        let selem = kind.structure
        guard selem == list.count else { throw fail() }

        let opcode0 = UInt32((selem - 1) >> 1)
        let r = UInt32((selem - 1) & 1)
        let opcode = (0b11 << 1) | opcode0   // sizeClass = 0b11 marks the replicate form.
        let q = list.arrangement.q
        let size = list.arrangement.elementSize
        // Replicate is load-only (L = 1) with S = 0.
        let common = (q << 30) | (1 << 22) | (r << 21) | (opcode << 13) | (size << 10) | list.encodedNumber

        switch address {
        case .base(let rn):
            return 0x0d00_0000 | common | (rn.encodedNumber << 5)
        case .postImmediate(let rn):
            return 0x0d80_0000 | common | (0x1f << 16) | (rn.encodedNumber << 5)
        case .postRegister(let rn, let rm):
            return 0x0d80_0000 | common | (rm.encodedNumber << 16) | (rn.encodedNumber << 5)
        }
    }

    private struct FPSingleDescriptor {
        let forceUnscaled: Bool
        let byteSize: Int64
        let size: UInt32
        let opc: UInt32

        init(kind: A64.LoadStoreSingleKind, rt: A64.FPRegister) throws {
            let isLoad: Bool
            switch kind {
            case .ldr:  isLoad = true;  forceUnscaled = false
            case .str:  isLoad = false; forceUnscaled = false
            case .ldur: isLoad = true;  forceUnscaled = true
            case .stur: isLoad = false; forceUnscaled = true
            default: throw AssemblerError.unsupportedOperand(kind.rawValue)
            }
            // size/opc: B/H/S/D use size=log2(bytes) and opc=01(load)/00(store);
            // Q (128-bit) uses size=00 and opc=11(load)/10(store).
            switch rt.width {
            case 8:   byteSize = 1;  size = 0; opc = isLoad ? 0b01 : 0b00
            case 16:  byteSize = 2;  size = 1; opc = isLoad ? 0b01 : 0b00
            case 32:  byteSize = 4;  size = 2; opc = isLoad ? 0b01 : 0b00
            case 64:  byteSize = 8;  size = 3; opc = isLoad ? 0b01 : 0b00
            case 128: byteSize = 16; size = 0; opc = isLoad ? 0b11 : 0b10
            default: throw AssemblerError.invalidRegister(kind.rawValue)
            }
        }

        var unsignedBase: UInt32 {
            (size << 30) | 0x3d000000 | (opc << 22)
        }

        var unscaledBase: UInt32 {
            (size << 30) | 0x3c000000 | (opc << 22)
        }

        var registerOffsetBase: UInt32 {
            (size << 30) | 0x3c200800 | (opc << 22)
        }
    }

    private struct SingleDescriptor {
        let forceUnscaled: Bool
        let byteSize: Int64
        let size: UInt32
        let opc: UInt32

        init(kind: A64.LoadStoreSingleKind, rt: IntegerRegister) {
            let normalizedMnemonic: String
            switch kind {
            case .ldur: normalizedMnemonic = "ldr"; forceUnscaled = true
            case .ldurb: normalizedMnemonic = "ldrb"; forceUnscaled = true
            case .ldurh: normalizedMnemonic = "ldrh"; forceUnscaled = true
            case .ldursb: normalizedMnemonic = "ldrsb"; forceUnscaled = true
            case .ldursh: normalizedMnemonic = "ldrsh"; forceUnscaled = true
            case .ldursw: normalizedMnemonic = "ldrsw"; forceUnscaled = true
            case .stur: normalizedMnemonic = "str"; forceUnscaled = true
            case .sturb: normalizedMnemonic = "strb"; forceUnscaled = true
            case .sturh: normalizedMnemonic = "strh"; forceUnscaled = true
            default: normalizedMnemonic = kind.rawValue; forceUnscaled = false
            }

            let isLoad = normalizedMnemonic.hasPrefix("ldr")
            switch normalizedMnemonic {
            case "strb", "ldrb": byteSize = 1; size = 0; opc = isLoad ? 1 : 0
            case "strh", "ldrh": byteSize = 2; size = 1; opc = isLoad ? 1 : 0
            case "str", "ldr": byteSize = rt.is64Bit ? 8 : 4; size = rt.is64Bit ? 3 : 2; opc = isLoad ? 1 : 0
            case "ldrsb": byteSize = 1; size = 0; opc = rt.is64Bit ? 2 : 3
            case "ldrsh": byteSize = 2; size = 1; opc = rt.is64Bit ? 2 : 3
            case "ldrsw": byteSize = 4; size = 2; opc = 2
            default: byteSize = 0; size = 0; opc = 0
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

internal enum A64AddSubEncoder {
    static func addSub(_ kind: A64.AddSubKind, destination rd: IntegerRegister, first rn: IntegerRegister, operand: A64.AddSubOperand) throws -> UInt32 {
        switch operand {
        case .immediate(let value, let shift):
            return try immediate(kind, destination: rd, first: rn, value: value, shift: shift)
        case .shiftedRegister(let rm, let shift):
            return try shiftedRegister(kind, destination: rd, first: rn, second: rm, shift: shift)
        case .extendedRegister(let rm, let extend, let amount):
            return try extendedRegister(kind, destination: rd, first: rn, second: rm, extend: extend, amount: amount)
        }
    }

    private static func extendedRegister(_ kind: A64.AddSubKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister, extend: A64.ExtendKind, amount: Int?) throws -> UInt32 {
        let amt = amount ?? 0
        guard amt >= 0, amt <= 4 else { throw AssemblerError.unsupportedShift("\(extend) #\(amt)") }
        // The shifted operand register width follows the extend: 64-bit for the
        // `*x` extends, 32-bit otherwise.
        let expectedRmWidth = (extend == .uxtx || extend == .sxtx) ? 64 : 32
        guard rm.width == expectedRmWidth else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let op: UInt32 = (kind == .sub || kind == .subs) ? 1 : 0
        let s: UInt32 = (kind == .adds || kind == .subs) ? 1 : 0
        typealias F = A64.AddSubExtendedRegister
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.op.insert(op)
            | F.s.insert(s)
            | F.rm.insert(rm.encodedNumber)
            | F.option.insert(extend.rawValue)
            | F.imm3.insert(UInt32(amt))
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func compareAlias(_ kind: A64.CompareAliasKind, first rn: IntegerRegister, operand: A64.AddSubOperand) throws -> UInt32 {
        try addSub(kind == .cmp ? .subs : .adds, destination: zeroRegister(width: rn.width), first: rn, operand: operand)
    }

    private static func immediate(_ kind: A64.AddSubKind, destination rd: IntegerRegister, first rn: IntegerRegister, value: Int64, shift: Int?) throws -> UInt32 {
        var sh = 0
        if let shift {
            guard shift == 12 else { throw AssemblerError.unsupportedShift("lsl #\(shift)") }
            sh = 12
        }
        try checkRange(value, 0...0xfff, instruction: kind.rawValue)
        let op: UInt32 = (kind == .sub || kind == .subs) ? 1 : 0
        let s: UInt32 = (kind == .adds || kind == .subs) ? 1 : 0
        typealias F = A64.AddSubImmediate
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.op.insert(op)
            | F.s.insert(s)
            | F.sh.insert(sh == 12 ? 1 : 0)
            | F.imm12.insert(UInt32(value))
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    private static func shiftedRegister(_ kind: A64.AddSubKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister, shift: ParsedShift?) throws -> UInt32 {
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let shiftKind = shift?.kind ?? .lsl
        let amount = shift?.amount ?? 0
        guard shiftKind != .ror else { throw AssemblerError.unsupportedShift("ror") }
        let op: UInt32 = (kind == .sub || kind == .subs) ? 1 : 0
        let s: UInt32 = (kind == .adds || kind == .subs) ? 1 : 0
        typealias F = A64.AddSubShiftedRegister
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.op.insert(op)
            | F.s.insert(s)
            | F.shift.insert(shiftKind.rawValue)
            | F.rm.insert(rm.encodedNumber)
            | F.imm6.insert(UInt32(amount))
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }
}

internal enum A64DataProcessingEncoder {
    static func shiftAlias(_ kind: A64.ShiftAliasKind, destination rd: IntegerRegister, source rn: IntegerRegister, amount: Int64) throws -> UInt32 {
        guard rd.width == rn.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let maxShift: Int64 = rd.is64Bit ? 63 : 31
        try checkRange(amount, 0...maxShift, instruction: kind.rawValue)
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let n: UInt32 = rd.is64Bit ? 1 : 0
        let immr: UInt32
        let imms: UInt32
        let opcBase: UInt32
        switch kind {
        case .lsl:
            immr = UInt32((Int(maxShift) + 1 - Int(amount)) & Int(maxShift))
            imms = UInt32(maxShift - amount)
            opcBase = 0x53000000
        case .lsr:
            immr = UInt32(amount)
            imms = UInt32(maxShift)
            opcBase = 0x53000000
        case .asr:
            immr = UInt32(amount)
            imms = UInt32(maxShift)
            opcBase = 0x13000000
        }
        let head = (sf << 31) | opcBase | (n << 22)
        return head | (immr << 16) | (imms << 10) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func extract(_ kind: A64.ExtractKind, destination rd: IntegerRegister, first rn: IntegerRegister, operand: A64.ExtractOperand) throws -> UInt32 {
        let rm: IntegerRegister
        let amount: Int64
        switch operand {
        case .extract(let second, let amt):
            rm = second
            amount = amt
        case .rotate(let amt):
            rm = rn
            amount = amt
        }
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        try checkRange(amount, 0...(rd.is64Bit ? 63 : 31), instruction: "extr")
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        typealias F = A64.Extract
        return F.baseWord
            | F.sf.insert(sf)
            | F.n.insert(sf)
            | F.rm.insert(rm.encodedNumber)
            | F.imms.insert(UInt32(amount))
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func multiply(_ kind: A64.MultiplyKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister, accumulator: IntegerRegister?) throws -> UInt32 {
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let ra: IntegerRegister
        let o0: UInt32
        switch kind {
        case .mul:
            ra = zeroRegister(width: rd.width); o0 = 0
        case .mneg:
            ra = zeroRegister(width: rd.width); o0 = 1
        case .madd:
            guard let accumulator else { throw AssemblerError.invalidOperandCount(instruction: "madd", expected: "4", actual: 3) }
            ra = accumulator; o0 = 0
        case .msub:
            guard let accumulator else { throw AssemblerError.invalidOperandCount(instruction: "msub", expected: "4", actual: 3) }
            ra = accumulator; o0 = 1
        }
        guard ra.width == rd.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        typealias F = A64.DataProcessing3Source
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.rm.insert(rm.encodedNumber)
            | F.o0.insert(o0)
            | F.ra.insert(ra.encodedNumber)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func divide(_ kind: A64.DivideKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister) throws -> UInt32 {
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        typealias F = A64.DataProcessing2Source
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.rm.insert(rm.encodedNumber)
            | F.opcode.insert(kind.opcode)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func variableShift(_ kind: A64.VariableShiftKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister) throws -> UInt32 {
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        typealias F = A64.DataProcessing2Source
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.rm.insert(rm.encodedNumber)
            | F.opcode.insert(kind.opcode)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func minMaxRegister(_ kind: A64.MinMaxKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister) throws -> UInt32 {
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        typealias F = A64.DataProcessing2Source
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.rm.insert(rm.encodedNumber)
            | F.opcode.insert(kind.registerOpcode)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func minMaxImmediate(_ kind: A64.MinMaxKind, destination rd: IntegerRegister, source rn: IntegerRegister, immediate: Int64) throws -> UInt32 {
        guard rd.width == rn.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let imm8: UInt32
        if kind.isSigned {
            try checkRange(immediate, -128...127, instruction: kind.rawValue)
            imm8 = UInt32(bitPattern: Int32(truncatingIfNeeded: immediate)) & 0xff
        } else {
            try checkRange(immediate, 0...255, instruction: kind.rawValue)
            imm8 = UInt32(immediate) & 0xff
        }
        typealias F = A64.MinMaxImmediate
        return F.baseWord
            | F.sf.insert(sf)
            | F.opc.insert(kind.immediateOpc)
            | F.imm8.insert(imm8)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func addSubCarry(_ kind: A64.AddSubCarryKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister) throws -> UInt32 {
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        typealias F = A64.AddSubWithCarry
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.op.insert(kind.op)
            | F.s.insert(kind.setsFlags)
            | F.rm.insert(rm.encodedNumber)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func bitfield(_ kind: A64.BitfieldKind, destination rd: IntegerRegister, source rn: IntegerRegister, immr: UInt32, imms: UInt32) throws -> UInt32 {
        // The destination width drives `sf` (and `N`); the source register
        // number is taken as-is (the extend aliases pass a 32-bit source).
        let registerSize: UInt32 = rd.is64Bit ? 64 : 32
        guard immr < registerSize, imms < registerSize else { throw AssemblerError.invalidImmediate(kind.rawValue) }
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        typealias F = A64.Bitfield
        return F.baseWord
            | F.sf.insert(sf)
            | F.opc.insert(kind.opc)
            | F.n.insert(sf)
            | F.immr.insert(immr)
            | F.imms.insert(imms)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func multiplyWide(_ kind: A64.MultiplyWideKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister, accumulator: IntegerRegister?) throws -> UInt32 {
        // The destination is always 64-bit. High-half multiplies take 64-bit
        // multiplicands; the long forms take 32-bit multiplicands.
        guard rd.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        if kind.isHigh {
            guard rn.is64Bit, rm.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        } else {
            guard !rn.is64Bit, !rm.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        }
        let ra: UInt32
        if kind.hasAccumulator {
            guard let accumulator, accumulator.is64Bit else {
                throw AssemblerError.invalidOperandCount(instruction: kind.rawValue, expected: "4", actual: 3)
            }
            ra = accumulator.encodedNumber
        } else {
            guard accumulator == nil else { throw AssemblerError.invalidRegister(kind.rawValue) }
            ra = 31
        }
        typealias F = A64.DataProcessing3Source
        return F.baseWord
            | F.sf.insert(1)
            | F.op31.insert(kind.op31)
            | F.rm.insert(rm.encodedNumber)
            | F.o0.insert(kind.o0)
            | F.ra.insert(ra)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func crc32(_ kind: A64.CRC32Kind, destination rd: IntegerRegister, first rn: IntegerRegister, data rm: IntegerRegister) throws -> UInt32 {
        // Rd and Rn are always 32-bit; Rm is 64-bit only for the `x` variants.
        guard !rd.is64Bit, !rn.is64Bit else { throw AssemblerError.invalidRegister(kind.rawValue) }
        guard rm.is64Bit == kind.usesDoubleWordSource else { throw AssemblerError.invalidRegister(kind.rawValue) }
        typealias F = A64.DataProcessing2Source
        return F.baseWord
            | F.sf.insert(kind.sf)
            | F.rm.insert(rm.encodedNumber)
            | F.opcode.insert(kind.opcode)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func dataProcessingOneSource(_ kind: A64.DataProcessingOneSourceKind, destination rd: IntegerRegister, source rn: IntegerRegister) throws -> UInt32 {
        guard rd.width == rn.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        if kind.is64BitOnly, !rd.is64Bit { throw AssemblerError.invalidRegister(kind.rawValue) }
        typealias F = A64.DataProcessing1Source
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.opcode.insert(kind.opcode(is64Bit: rd.is64Bit))
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func conditionalSelect(_ kind: A64.ConditionalSelectKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister, condition: A64.Condition) throws -> UInt32 {
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        typealias F = A64.ConditionalSelect
        return F.baseWord
            | F.sf.insert(rd.is64Bit ? 1 : 0)
            | F.op.insert(kind.op)
            | F.rm.insert(rm.encodedNumber)
            | F.cond.insert(condition.rawValue)
            | F.o2.insert(kind.o2)
            | F.rn.insert(rn.encodedNumber)
            | F.rd.insert(rd.encodedNumber)
    }

    static func conditionalCompare(_ kind: A64.ConditionalCompareKind, first rn: IntegerRegister, second: A64.ConditionalCompareOperand, nzcv: UInt32, condition: A64.Condition) throws -> UInt32 {
        guard nzcv <= 0xf else { throw AssemblerError.invalidImmediate("#\(nzcv)") }
        typealias F = A64.ConditionalCompare
        var word = F.baseWord | F.sf.insert(rn.is64Bit ? 1 : 0) | F.op.insert(kind.op)
        switch second {
        case .register(let rm):
            guard rm.width == rn.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
            word |= F.imm5OrRm.insert(rm.encodedNumber)
        case .immediate(let imm5):
            guard imm5 <= 31 else { throw AssemblerError.invalidImmediate("#\(imm5)") }
            word |= F.immFlag.insert(1) | F.imm5OrRm.insert(imm5)
        }
        return word | F.cond.insert(condition.rawValue) | F.rn.insert(rn.encodedNumber) | F.nzcv.insert(nzcv)
    }

    static func conditionalSet(_ kind: A64.ConditionalSetKind, destination rd: IntegerRegister, condition: A64.Condition) throws -> UInt32 {
        // `cset`/`csetm` lower to `csinc`/`csinv` of the zero register with the
        // inverted condition; the inversion is undefined for AL/NV.
        guard condition.rawValue < 0b1110 else { throw AssemblerError.unsupportedCondition(kind.rawValue) }
        let base = kind.base
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let head = (sf << 31) | (base.op << 30) | 0x1a80_0000
        let invertedCondition = condition.rawValue ^ 1
        let zr: UInt32 = 31
        return head | (zr << 16) | (invertedCondition << 12) | (base.o2 << 10) | (zr << 5) | rd.encodedNumber
    }

    static func conditionalSelectAlias(_ kind: A64.ConditionalSelectAliasKind, destination rd: IntegerRegister, source rn: IntegerRegister, condition: A64.Condition) throws -> UInt32 {
        // `cinc`/`cinv`/`cneg` lower to `csinc`/`csinv`/`csneg` with the source
        // register in both source positions and the inverted condition.
        guard rd.width == rn.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        guard condition.rawValue < 0b1110 else { throw AssemblerError.unsupportedCondition(kind.rawValue) }
        let base = kind.base
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let head = (sf << 31) | (base.op << 30) | 0x1a80_0000
        let invertedCondition = condition.rawValue ^ 1
        return head | (rn.encodedNumber << 16) | (invertedCondition << 12) | (base.o2 << 10) | (rn.encodedNumber << 5) | rd.encodedNumber
    }
}
