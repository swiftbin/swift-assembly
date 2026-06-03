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
        case .loadStoreSingle(let kind, let target, let memory):
            return try A64LoadStoreEncoder.single(kind, target: target, memory: memory)
        case .loadStorePair(let kind, let first, let second, let memory):
            return try A64LoadStoreEncoder.pair(kind, first: first, second: second, memory: memory)
        case .pointerAuthentication(let kind, let register, let architecture):
            return try A64PointerAuthenticationEncoder.encode(kind, register: register, architecture: architecture)
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
        case .fpMoveImmediate(let destination, let value):
            return try A64FloatEncoder.moveImmediate(destination: destination, value: value)
        case .fpMoveToGeneral(let destination, let source):
            return try A64FloatEncoder.moveToGeneral(destination: destination, source: source)
        case .fpMoveFromGeneral(let destination, let source):
            return try A64FloatEncoder.moveFromGeneral(destination: destination, source: source)
        case .fpConvertToInt(let kind, let destination, let source):
            return try A64FloatEncoder.convertToInt(kind, destination: destination, source: source)
        case .fpConvertFromInt(let kind, let destination, let source):
            return try A64FloatEncoder.convertFromInt(kind, destination: destination, source: source)
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
        case .xpaci, .xpacd:
            guard let rd = register else {
                throw AssemblerError.invalidOperandCount(instruction: kind.rawValue, expected: "1", actual: 0)
            }
            return (kind == .xpaci ? 0xdac143e0 : 0xdac147e0) | rd.encodedNumber
        }
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
        let opc: UInt32 = kind == .movn ? 0 : kind == .movz ? 2 : 3
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        return (sf << 31) | (opc << 29) | 0x12800000 | (UInt32(shift / 16) << 21) | (UInt32(imm) << 5) | rd.encodedNumber
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
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let head = (sf << 31) | (opc << 29) | 0x12000000
        let fields = (encoding.n << 22) | (encoding.immr << 16) | (encoding.imms << 10)
        return head | fields | (rn.encodedNumber << 5) | rd.encodedNumber
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
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let head = (sf << 31) | (opc << 29) | 0x0a000000 | (shiftKind.rawValue << 22) | (n << 21)
        return head | (rm.encodedNumber << 16) | (UInt32(amount) << 10) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func mvnAlias(destination rd: IntegerRegister, source rm: IntegerRegister, shift: ParsedShift?) throws -> UInt32 {
        try shiftedRegister(.orn, destination: rd, first: zeroRegister(width: rd.width), second: rm, shift: shift)
    }
}

internal enum A64LoadStoreEncoder {
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

    static func pair(_ kind: A64.LoadStorePairKind, first rt: IntegerRegister, second rt2: IntegerRegister, memory: MemoryOperand) throws -> UInt32 {
        let mnemonic = kind.rawValue
        guard rt.width == rt2.width else { throw AssemblerError.invalidRegister(mnemonic) }
        let scale: Int64 = rt.is64Bit ? 8 : 4
        let modeBase: UInt32
        let base: IntegerRegister
        let offset: Int64
        switch memory {
        case .signedUnscaled(let b, let o), .unsignedOffset(let b, let o): modeBase = 0x29000000; base = b; offset = o
        case .postIndexed(let b, let o): modeBase = 0x28800000; base = b; offset = o
        case .preIndexed(let b, let o): modeBase = 0x29800000; base = b; offset = o
        case .registerOffset: throw AssemblerError.unsupportedOperand(mnemonic)
        }
        guard offset % scale == 0 else { throw AssemblerError.immediateAlignment(instruction: mnemonic, value: offset, alignment: scale) }
        let imm7 = offset / scale
        try checkRange(imm7, -64...63, instruction: mnemonic)
        let head = ((rt.is64Bit ? UInt32(2) : 0) << 30) | modeBase | ((kind == .ldp ? UInt32(1) : 0) << 22)
        return head | ((UInt32(bitPattern: Int32(imm7)) & 0x7f) << 15) | (rt2.encodedNumber << 10) | (base.encodedNumber << 5) | rt.encodedNumber
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
        }
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
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let op: UInt32 = (kind == .sub || kind == .subs) ? 1 : 0
        let s: UInt32 = (kind == .adds || kind == .subs) ? 1 : 0
        let shBit: UInt32 = sh == 12 ? 1 : 0
        let head = (sf << 31) | (op << 30) | (s << 29) | 0x11000000
        let fields = (shBit << 22) | (UInt32(value) << 10)
        return head | fields | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    private static func shiftedRegister(_ kind: A64.AddSubKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister, shift: ParsedShift?) throws -> UInt32 {
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let shiftKind = shift?.kind ?? .lsl
        let amount = shift?.amount ?? 0
        guard shiftKind != .ror else { throw AssemblerError.unsupportedShift("ror") }
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let op: UInt32 = (kind == .sub || kind == .subs) ? 1 : 0
        let s: UInt32 = (kind == .adds || kind == .subs) ? 1 : 0
        let head = (sf << 31) | (op << 30) | (s << 29) | 0x0b000000 | (shiftKind.rawValue << 22)
        return head | (rm.encodedNumber << 16) | (UInt32(amount) << 10) | (rn.encodedNumber << 5) | rd.encodedNumber
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
        let head = (sf << 31) | 0x13800000 | (sf << 22)
        return head | (rm.encodedNumber << 16) | (UInt32(amount) << 10) | (rn.encodedNumber << 5) | rd.encodedNumber
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
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let head = (sf << 31) | 0x1b000000
        return head | (rm.encodedNumber << 16) | (o0 << 15) | (ra.encodedNumber << 10) | (rn.encodedNumber << 5) | rd.encodedNumber
    }

    static func divide(_ kind: A64.DivideKind, destination rd: IntegerRegister, first rn: IntegerRegister, second rm: IntegerRegister) throws -> UInt32 {
        guard rd.width == rn.width, rn.width == rm.width else { throw AssemblerError.invalidRegister(kind.rawValue) }
        let sf: UInt32 = rd.is64Bit ? 1 : 0
        let o1: UInt32 = kind == .sdiv ? 1 : 0
        let head = (sf << 31) | 0x1ac00800
        return head | (rm.encodedNumber << 16) | (o1 << 10) | (rn.encodedNumber << 5) | rd.encodedNumber
    }
}
