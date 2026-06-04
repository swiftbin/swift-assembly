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

    /// Parses an immediate that may use the full unsigned 64-bit range (e.g. the
    /// `movi Vd.2D, #imm64` bit pattern), where `Int64` parsing would overflow.
    static func unsignedImmediate64(_ text: String) throws -> UInt64 {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") { value.removeFirst() }
        value = value.replacingOccurrences(of: "_", with: "")
        let negative = value.hasPrefix("-")
        if negative || value.hasPrefix("+") { value.removeFirst() }
        guard !value.isEmpty else { throw AssemblerError.invalidImmediate(text) }
        let parsed: UInt64?
        if value.hasPrefix("0x") { parsed = UInt64(value.dropFirst(2), radix: 16) }
        else if value.hasPrefix("0b") { parsed = UInt64(value.dropFirst(2), radix: 2) }
        else { parsed = UInt64(value, radix: 10) }
        guard let parsed else { throw AssemblerError.invalidImmediate(text) }
        return negative ? ~parsed &+ 1 : parsed
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

    /// Parses one cryptographic SHA operand according to the shape required by the
    /// mnemonic, returning its register number. Rejects operands of the wrong type.
    static func cryptoSHAOperandNumber(_ text: String, shape: A64.CryptoSHAOperand) throws -> UInt32 {
        switch shape {
        case .scalarS:
            let register = try floatRegister(text)
            guard register.width == 32 else { throw AssemblerError.invalidRegister(text) }
            return register.number
        case .scalarQ:
            let register = try floatRegister(text)
            guard register.width == 128 else { throw AssemblerError.invalidRegister(text) }
            return register.number
        case .vector4s:
            let register = try vectorRegister(text)
            guard register.arrangement == .s4 else { throw AssemblerError.invalidRegister(text) }
            return register.number
        case .vector2d:
            let register = try vectorRegister(text)
            guard register.arrangement == .d2 else { throw AssemblerError.invalidRegister(text) }
            return register.number
        case .vector16b:
            let register = try vectorRegister(text)
            guard register.arrangement == .b16 else { throw AssemblerError.invalidRegister(text) }
            return register.number
        }
    }

    /// Parses a brace-delimited register list such as `{v0.16b, v1.16b}`. The registers must
    /// share an arrangement and be numbered consecutively (wrapping at v31).
    static func vectorRegisterList(_ text: String) throws -> A64.VectorRegisterList {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { throw AssemblerError.invalidRegister(text) }
        let inner = String(trimmed.dropFirst().dropLast())
        let items = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !items.isEmpty, items.count <= 4 else { throw AssemblerError.invalidRegister(text) }
        let registers = try items.map { try vectorRegister($0) }
        let arrangement = registers[0].arrangement
        guard registers.allSatisfy({ $0.arrangement == arrangement }) else { throw AssemblerError.invalidRegister(text) }
        let first = registers[0].number
        for (offset, register) in registers.enumerated() {
            guard register.number == (first + UInt32(offset)) % 32 else { throw AssemblerError.invalidRegister(text) }
        }
        return A64.VectorRegisterList(firstNumber: first, count: registers.count, arrangement: arrangement)
    }

    /// Parses a brace-delimited single-lane register list such as `{v0.s, v1.s}[1]`. The registers
    /// must share an element width and be numbered consecutively (wrapping at v31), and the trailing
    /// `[index]` selects the lane.
    static func vectorLaneList(_ text: String) throws -> A64.VectorLaneList {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let close = trimmed.firstIndex(of: "}"), trimmed.hasPrefix("{"),
              trimmed.hasSuffix("]") else { throw AssemblerError.invalidRegister(text) }
        let inner = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        let after = trimmed[trimmed.index(after: close)...]
        guard after.hasPrefix("["), let bracket = after.firstIndex(of: "[") else {
            throw AssemblerError.invalidRegister(text)
        }
        let indexText = String(after[after.index(after: bracket)..<after.index(before: after.endIndex)])
        guard let index = Int(indexText), index >= 0 else { throw AssemblerError.invalidRegister(text) }

        let items = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !items.isEmpty, items.count <= 4 else { throw AssemblerError.invalidRegister(text) }
        var widths: [A64.VectorElementWidth] = []
        var numbers: [UInt32] = []
        for item in items {
            let parts = item.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let prefix = parts[0].first, prefix == "v",
                  let number = UInt32(parts[0].dropFirst()), number <= 31,
                  let width = A64.VectorElementWidth(rawValue: parts[1]) else {
                throw AssemblerError.invalidRegister(text)
            }
            widths.append(width)
            numbers.append(number)
        }
        let width = widths[0]
        guard widths.allSatisfy({ $0 == width }) else { throw AssemblerError.invalidRegister(text) }
        let first = numbers[0]
        for (offset, number) in numbers.enumerated() {
            guard number == (first + UInt32(offset)) % 32 else { throw AssemblerError.invalidRegister(text) }
        }
        return A64.VectorLaneList(firstNumber: first, count: numbers.count, width: width, index: index)
    }

    /// Parses the addressing form for structured load/store: `[Xn]`, `[Xn], #imm`, or `[Xn], Xm`.
    /// For the immediate post-index form the literal must equal `expectedPostImmediate`.
    static func vectorMemoryOperand(_ operands: [String], baseIndex: Int, expectedPostImmediate: Int64) throws -> A64.VectorMemoryOperand {
        let baseText = operands[baseIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard baseText.hasPrefix("["), baseText.hasSuffix("]") else { throw AssemblerError.invalidRegister(baseText) }
        let inner = String(baseText.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = try integerRegister(inner, allowSP: true)
        guard operands.count > baseIndex + 1 else { return .base(base) }

        let post = operands[baseIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        if post.hasPrefix("#") {
            let value = try immediate(post)
            guard value == expectedPostImmediate else { throw AssemblerError.invalidImmediate(post) }
            return .postImmediate(base)
        }
        return .postRegister(base, offset: try integerRegister(post, allowSP: false))
    }

    /// Parses an addressed vector lane such as `v1.s[2]`.
    static func vectorElement(_ text: String) throws -> A64.VectorElement {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasSuffix("]"), let bracket = lower.firstIndex(of: "[") else {
            throw AssemblerError.invalidRegister(text)
        }
        let head = String(lower[lower.startIndex..<bracket])               // v1.s
        let indexText = String(lower[lower.index(after: bracket)..<lower.index(before: lower.endIndex)])
        let parts = head.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let prefix = parts[0].first, prefix == "v",
              let number = UInt32(parts[0].dropFirst()), number <= 31,
              let width = A64.VectorElementWidth(rawValue: parts[1]),
              let index = Int(indexText), index >= 0 else {
            throw AssemblerError.invalidRegister(text)
        }
        return A64.VectorElement(number: number, width: width, index: index)
    }

    /// Parses a dot-product 4-byte group element such as `v2.4b[3]`, returning
    /// the register number and the group index (0–3).
    static func dotProductElement(_ text: String) throws -> (number: UInt32, index: UInt32) {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasSuffix("]"), let bracket = lower.firstIndex(of: "[") else {
            throw AssemblerError.invalidRegister(text)
        }
        let head = String(lower[lower.startIndex..<bracket])               // v2.4b
        let indexText = String(lower[lower.index(after: bracket)..<lower.index(before: lower.endIndex)])
        let parts = head.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let prefix = parts[0].first, prefix == "v",
              let number = UInt32(parts[0].dropFirst()), number <= 31,
              parts[1] == "4b",
              let index = UInt32(indexText), index <= 3 else {
            throw AssemblerError.invalidRegister(text)
        }
        return (number, index)
    }

    /// Parses a BFloat16 dot-product pair element such as `v2.2h[3]`, returning
    /// the register number (0–31) and the pair index (0–3).
    static func bfdotElement(_ text: String) throws -> (number: UInt32, index: UInt32) {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasSuffix("]"), let bracket = lower.firstIndex(of: "[") else {
            throw AssemblerError.invalidRegister(text)
        }
        let head = String(lower[lower.startIndex..<bracket])               // v2.2h
        let indexText = String(lower[lower.index(after: bracket)..<lower.index(before: lower.endIndex)])
        let parts = head.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let prefix = parts[0].first, prefix == "v",
              let number = UInt32(parts[0].dropFirst()), number <= 31,
              parts[1] == "2h",
              let index = UInt32(indexText), index <= 3 else {
            throw AssemblerError.invalidRegister(text)
        }
        return (number, index)
    }

    static func isVectorElementOperand(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("v") && lower.contains(".") && lower.hasSuffix("]")
    }

    /// True when the operand is a bare scalar floating-point register (`b0`, `h1`, `s2`, `d3`).
    static func isScalarFloatRegisterOperand(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let first = lower.first, "bhsd".contains(first) else { return false }
        return UInt32(lower.dropFirst()) != nil
    }

    static func floatImmediate(_ text: String) throws -> Double {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard let parsed = Double(value) else { throw AssemblerError.invalidImmediate(text) }
        return parsed
    }

    /// Parses a raw bitfield `immr`/`imms` field, valid in `0..<registerSize`.
    static func bitfieldField(_ text: String, mnemonic: String, registerSize: Int64) throws -> UInt32 {
        let value = try immediate(text)
        guard value >= 0, value < registerSize else { throw AssemblerError.invalidImmediate(mnemonic) }
        return UInt32(value)
    }

    /// Computes `(immr, imms)` for the bitfield *extract* aliases
    /// (`sbfx`/`ubfx`/`bfxil`): `Rd, Rn, #lsb, #width`.
    static func bitfieldExtract(_ instruction: ParsedInstruction, mnemonic: String, registerSize: Int64) throws -> (UInt32, UInt32) {
        let lsb = try immediate(instruction.operands[2])
        let width = try immediate(instruction.operands[3])
        guard lsb >= 0, lsb < registerSize, width >= 1, lsb + width <= registerSize else {
            throw AssemblerError.invalidImmediate(mnemonic)
        }
        return (UInt32(lsb), UInt32(lsb + width - 1))
    }

    /// Computes `(immr, imms)` for the bitfield *insert* aliases
    /// (`sbfiz`/`ubfiz`/`bfi`): `Rd, Rn, #lsb, #width`.
    static func bitfieldInsert(_ instruction: ParsedInstruction, mnemonic: String, registerSize: Int64) throws -> (UInt32, UInt32) {
        let lsb = try immediate(instruction.operands[2])
        let width = try immediate(instruction.operands[3])
        guard lsb >= 0, lsb < registerSize, width >= 1, lsb + width <= registerSize else {
            throw AssemblerError.invalidImmediate(mnemonic)
        }
        return (UInt32((registerSize - lsb) % registerSize), UInt32(width - 1))
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

        // Advanced SIMD scalar x indexed element: scalar FP destination/first, vector
        // element third operand. Checked before the vector form because the operands
        // are bare scalar FP registers rather than arranged vectors.
        if parts.count == 1,
           instruction.operands.count == 3,
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[0]),
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[1]),
           A64Parser.isVectorElementOperand(instruction.operands[2]),
           let kind = A64.VectorIndexedKind(rawValue: mnemonic) {
            return .scalarIndexed(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                first: try A64Parser.floatRegister(instruction.operands[1]),
                element: try A64Parser.vectorElement(instruction.operands[2])
            )
        }

        // Advanced SIMD vector x indexed element: any of these mnemonics whose third
        // operand is a vector element (`v2.s[1]`) routes here regardless of the per-mnemonic
        // handling below (which assumes a vector-register or scalar third operand).
        if parts.count == 1,
           instruction.operands.count == 3,
           A64Parser.isVectorElementOperand(instruction.operands[2]) {
            let base = mnemonic.hasSuffix("2") ? String(mnemonic.dropLast()) : mnemonic
            if let kind = A64.VectorIndexedKind(rawValue: base) {
                return .vectorIndexed(
                    kind,
                    destination: try A64Parser.vectorRegister(instruction.operands[0]),
                    first: try A64Parser.vectorRegister(instruction.operands[1]),
                    element: try A64Parser.vectorElement(instruction.operands[2])
                )
            }
        }

        // Advanced SIMD scalar three-same: shares mnemonics with the vector
        // three-same forms, distinguished by bare scalar FP register operands.
        if parts.count == 1,
           instruction.operands.count == 3,
           instruction.operands.allSatisfy(A64Parser.isScalarFloatRegisterOperand),
           let kind = A64.ScalarThreeSameKind(rawValue: mnemonic) {
            return .scalarThreeSame(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                first: try A64Parser.floatRegister(instruction.operands[1]),
                second: try A64Parser.floatRegister(instruction.operands[2])
            )
        }

        // Advanced SIMD scalar floating-point three-same: three scalar FP registers.
        if parts.count == 1,
           instruction.operands.count == 3,
           instruction.operands.allSatisfy(A64Parser.isScalarFloatRegisterOperand),
           let kind = A64.ScalarThreeSameFPKind(rawValue: mnemonic) {
            return .scalarThreeSameFP(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                first: try A64Parser.floatRegister(instruction.operands[1]),
                second: try A64Parser.floatRegister(instruction.operands[2])
            )
        }

        // Advanced SIMD scalar pairwise: scalar FP destination, single vector source.
        if parts.count == 1,
           instruction.operands.count == 2,
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[0]),
           isVectorRegisterOperand(instruction.operands[1]),
           let kind = A64.ScalarPairwiseKind(rawValue: mnemonic) {
            return .scalarPairwise(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
        }

        // Advanced SIMD scalar two-register misc, narrowing: two scalar FP registers.
        if parts.count == 1,
           instruction.operands.count == 2,
           instruction.operands.allSatisfy(A64Parser.isScalarFloatRegisterOperand),
           let kind = A64.ScalarTwoRegisterMiscNarrowKind(rawValue: mnemonic) {
            return .scalarTwoRegisterMiscNarrow(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1])
            )
        }

        // Advanced SIMD scalar two-register misc: two scalar FP registers.
        if parts.count == 1,
           instruction.operands.count == 2,
           instruction.operands.allSatisfy(A64Parser.isScalarFloatRegisterOperand),
           let kind = A64.ScalarTwoRegisterMiscKind(rawValue: mnemonic),
           !kind.spec.comparesZero {
            return .scalarTwoRegisterMisc(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1])
            )
        }

        // Advanced SIMD scalar compare against zero (`Vd, Vn, #0`).
        if parts.count == 1,
           instruction.operands.count == 3,
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[0]),
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[1]),
           instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines) == "#0",
           let kind = A64.ScalarTwoRegisterMiscKind(rawValue: mnemonic),
           kind.spec.comparesZero {
            return .scalarTwoRegisterMisc(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1])
            )
        }

        // Advanced SIMD two-register-misc FP ↔ integer convert (`Vd.T, Vn.T`).
        // The two-vector-register shape distinguishes it from the fixed-point shift
        // forms (which take a `#fbits` operand) and the scalar/general-register forms.
        if parts.count == 1,
           instruction.operands.count == 2,
           isVectorRegisterOperand(instruction.operands[0]),
           isVectorRegisterOperand(instruction.operands[1]),
           let kind = A64.VectorConvertKind(rawValue: mnemonic) {
            return .vectorConvert(
                kind,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
        }

        // Advanced SIMD two-register-misc pairwise long add/accumulate (`Vd.Ta, Vn.Tb`).
        if parts.count == 1,
           instruction.operands.count == 2,
           isVectorRegisterOperand(instruction.operands[0]),
           isVectorRegisterOperand(instruction.operands[1]),
           let kind = A64.VectorPairwiseLongAddKind(rawValue: mnemonic) {
            return .vectorPairwiseLongAdd(
                kind,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
        }

        // Advanced SIMD two-register-misc extract-narrow (`Vd.Tb, Vn.Ta`); the `2`
        // suffix selects the upper-half (128-bit destination) variant.
        if parts.count == 1,
           instruction.operands.count == 2,
           isVectorRegisterOperand(instruction.operands[0]) {
            let upper = mnemonic.hasSuffix("2")
            let base = upper ? String(mnemonic.dropLast()) : mnemonic
            if let kind = A64.VectorExtractNarrowKind(rawValue: base) {
                let destination = try A64Parser.vectorRegister(instruction.operands[0])
                // The `2` form requires a 128-bit destination; the plain form a 64-bit one.
                guard (destination.arrangement.q == 1) == upper else {
                    throw AssemblerError.invalidRegister(instruction.operands[0])
                }
                return .vectorExtractNarrow(
                    kind,
                    destination: destination,
                    source: try A64Parser.vectorRegister(instruction.operands[1])
                )
            }
        }

        // Advanced SIMD vector compare against zero (`Vd.T, Vn.T, #0` or `#0.0`).
        // Only the immediate forms route here; the three-register shapes fall through
        // to the three-same group below.
        if parts.count == 1,
           instruction.operands.count == 3,
           instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#"),
           isVectorRegisterOperand(instruction.operands[0]),
           let kind = A64.VectorCompareZeroKind(rawValue: mnemonic) {
            let imm = instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let expected = kind.isFloat ? "#0.0" : "#0"
            guard imm == expected else { throw AssemblerError.invalidImmediate(instruction.operands[2]) }
            return .vectorCompareZero(
                kind,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
        }

        // Advanced SIMD scalar shift by immediate, narrowing (`Vd, Vn, #shift`).
        if parts.count == 1,
           instruction.operands.count == 3,
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[0]),
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[1]),
           instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#"),
           let kind = A64.ScalarShiftNarrowKind(rawValue: mnemonic) {
            return .scalarShiftNarrow(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1]),
                shift: Int(try A64Parser.immediate(instruction.operands[2]))
            )
        }

        // Advanced SIMD scalar shift by immediate, fixed-point convert (`Vd, Vn, #fbits`).
        if parts.count == 1,
           instruction.operands.count == 3,
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[0]),
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[1]),
           instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#"),
           let kind = A64.ScalarShiftFixedPointKind(rawValue: mnemonic) {
            return .scalarShiftFixedPoint(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1]),
                fbits: Int(try A64Parser.immediate(instruction.operands[2]))
            )
        }

        // Advanced SIMD scalar shift by immediate (`Vd, Vn, #shift`).
        if parts.count == 1,
           instruction.operands.count == 3,
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[0]),
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[1]),
           instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#"),
           let kind = A64.ScalarShiftImmediateKind(rawValue: mnemonic) {
            return .scalarShiftImmediate(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1]),
                shift: Int(try A64Parser.immediate(instruction.operands[2]))
            )
        }

        // Advanced SIMD scalar copy: `dup`/`mov` with a scalar FP destination and a
        // single vector element source (`mov d0, v1.d[1]`).
        if parts.count == 1,
           (mnemonic == "dup" || mnemonic == "mov"),
           instruction.operands.count == 2,
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[0]),
           A64Parser.isVectorElementOperand(instruction.operands[1]) {
            return .scalarCopyDuplicate(
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                element: try A64Parser.vectorElement(instruction.operands[1])
            )
        }

        // Advanced SIMD two-register-misc FP precision converts (`Vd.Ta, Vn.Tb`); the
        // `2` suffix selects the upper-half (`Q=1`) variant. Vector operands distinguish
        // these from the scalar `fcvtxn` form handled below.
        if parts.count == 1,
           instruction.operands.count == 2,
           isVectorRegisterOperand(instruction.operands[0]),
           isVectorRegisterOperand(instruction.operands[1]) {
            let upper = mnemonic.hasSuffix("2")
            let base = upper ? String(mnemonic.dropLast()) : mnemonic
            if let kind = A64.VectorFPConvertPrecisionKind(rawValue: base) {
                return .vectorFPConvertPrecision(
                    kind,
                    upper: upper,
                    destination: try A64Parser.vectorRegister(instruction.operands[0]),
                    source: try A64Parser.vectorRegister(instruction.operands[1])
                )
            }
        }

        // Advanced SIMD two-register-misc FP rounding and reciprocal estimates (`Vd.T, Vn.T`).
        // The vector-register shape distinguishes it from the scalar estimate forms below.
        if parts.count == 1,
           instruction.operands.count == 2,
           isVectorRegisterOperand(instruction.operands[0]),
           isVectorRegisterOperand(instruction.operands[1]),
           let kind = A64.VectorRoundReciprocalKind(rawValue: mnemonic) {
            return .vectorRoundReciprocal(
                kind,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
        }

        // Scalar floating-point round-to-integral (`Sd, Sn` / `Dd, Dn` / `Hd, Hn`),
        // including the Armv8.5 frint32/frint64 forms (single/double only).
        if parts.count == 1,
           instruction.operands.count == 2,
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[0]),
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[1]),
           let kind = A64.FPDataProcessing1Kind(rawValue: mnemonic),
           kind.isRoundToIntegral {
            return .fpDataProcessing1(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1])
            )
        }

        // Advanced SIMD scalar FP two-register misc compare-against-zero (`Vd, Vn, #0.0`).
        if parts.count == 1,
           instruction.operands.count == 3,
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[0]),
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[1]),
           instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#"),
           let kind = A64.ScalarFPTwoRegisterMiscKind(rawValue: mnemonic),
           kind.spec.category == .compareZero,
           (try? A64Parser.floatImmediate(instruction.operands[2])) == 0 {
            return .scalarFPTwoRegisterMisc(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1])
            )
        }

        // Advanced SIMD scalar FP two-register misc (FP converts / estimates / fcvtxn):
        // two scalar FP register operands.
        if parts.count == 1,
           instruction.operands.count == 2,
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[0]),
           A64Parser.isScalarFloatRegisterOperand(instruction.operands[1]),
           let kind = A64.ScalarFPTwoRegisterMiscKind(rawValue: mnemonic),
           kind.spec.category != .compareZero {
            return .scalarFPTwoRegisterMisc(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.floatRegister(instruction.operands[1])
            )
        }

        // Advanced SIMD scalar three different (`Vd, Vn, Vm` — long saturating doubling).
        if parts.count == 1,
           instruction.operands.count == 3,
           instruction.operands.allSatisfy(A64Parser.isScalarFloatRegisterOperand),
           let kind = A64.ScalarThreeDifferentKind(rawValue: mnemonic) {
            return .scalarThreeDifferent(
                kind,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                first: try A64Parser.floatRegister(instruction.operands[1]),
                second: try A64Parser.floatRegister(instruction.operands[2])
            )
        }

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
        case "yield", "wfe", "wfi", "sev", "sevl", "esb", "csdb":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 0)
            return .hint(A64.HintKind(rawValue: mnemonic)!.immediate)
        case "hint":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 1)
            let immediate = try A64Parser.immediate(instruction.operands[0])
            guard immediate >= 0, immediate <= 0x7f else { throw AssemblerError.invalidImmediate("hint") }
            return .hint(UInt32(immediate))
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
            // Vector copy aliases: MOV maps onto INS / UMOV.
            let destIsElement = A64Parser.isVectorElementOperand(instruction.operands[0])
            let srcIsElement = A64Parser.isVectorElementOperand(instruction.operands[1])
            if destIsElement && srcIsElement {
                return .vectorInsertElement(
                    destination: try A64Parser.vectorElement(instruction.operands[0]),
                    source: try A64Parser.vectorElement(instruction.operands[1])
                )
            }
            if destIsElement {
                return .vectorInsertGeneral(
                    destination: try A64Parser.vectorElement(instruction.operands[0]),
                    source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
                )
            }
            if srcIsElement {
                return .vectorMoveToGeneral(
                    signed: false,
                    destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                    source: try A64Parser.vectorElement(instruction.operands[1])
                )
            }
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
            if (mnemonic == "add" || mnemonic == "sub"), allOperandsAreVectorRegisters(instruction) {
                return try vectorThreeSame(instruction, kind: A64.VectorThreeSameKind(rawValue: mnemonic)!)
            }
            try expectOperandCount(instruction, 3...4)
            let addSubRd = try A64Parser.integerRegister(instruction.operands[0], allowSP: mnemonic == "add" || mnemonic == "sub")
            let addSubRn = try A64Parser.integerRegister(instruction.operands[1], allowSP: true)
            let addSubOp = promoteToExtendedIfStackPointer(try addSubOperand(instruction, startIndex: 2), rd: addSubRd, rn: addSubRn)
            return .addSub(
                A64.AddSubKind(rawValue: mnemonic)!,
                destination: addSubRd,
                first: addSubRn,
                operand: addSubOp
            )
        case "cmp", "cmn":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 2...3)
            let cmpRn = try A64Parser.integerRegister(instruction.operands[0], allowSP: true)
            let cmpOp = promoteToExtendedIfStackPointer(try addSubOperand(instruction, startIndex: 1), rd: zeroRegister(width: cmpRn.width), rn: cmpRn)
            return .compareAlias(
                A64.CompareAliasKind(rawValue: mnemonic)!,
                first: cmpRn,
                operand: cmpOp
            )
        case "and", "ands", "orr", "eor", "bic", "bics", "orn", "eon":
            guard parts.count == 1 else { return nil }
            if ["and", "orr", "eor", "bic", "orn"].contains(mnemonic), allOperandsAreVectorRegisters(instruction) {
                return try vectorThreeSame(instruction, kind: A64.VectorThreeSameKind(rawValue: mnemonic)!)
            }
            // `orr`/`bic` also have a vector modified-immediate form (`Vd.T, #imm{, lsl #n}`).
            if (mnemonic == "orr" || mnemonic == "bic"), isVectorModifiedImmediate(instruction) {
                return try vectorModifiedImmediate(instruction, kind: mnemonic == "orr" ? .orr : .bic)
            }
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
        case "sbfm", "bfm", "ubfm":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            guard rd.width == rn.width else { throw AssemblerError.invalidRegister(mnemonic) }
            let registerSize = Int64(rd.width)
            let immr = try A64Parser.bitfieldField(instruction.operands[2], mnemonic: mnemonic, registerSize: registerSize)
            let imms = try A64Parser.bitfieldField(instruction.operands[3], mnemonic: mnemonic, registerSize: registerSize)
            return .bitfield(A64.BitfieldKind(rawValue: mnemonic)!, destination: rd, source: rn, immr: immr, imms: imms)
        case "sbfx", "ubfx", "bfxil":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            guard rd.width == rn.width else { throw AssemblerError.invalidRegister(mnemonic) }
            let (immr, imms) = try A64Parser.bitfieldExtract(instruction, mnemonic: mnemonic, registerSize: Int64(rd.width))
            let kind: A64.BitfieldKind = mnemonic == "sbfx" ? .sbfm : (mnemonic == "ubfx" ? .ubfm : .bfm)
            return .bitfield(kind, destination: rd, source: rn, immr: immr, imms: imms)
        case "sbfiz", "ubfiz", "bfi":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            guard rd.width == rn.width else { throw AssemblerError.invalidRegister(mnemonic) }
            let (immr, imms) = try A64Parser.bitfieldInsert(instruction, mnemonic: mnemonic, registerSize: Int64(rd.width))
            let kind: A64.BitfieldKind = mnemonic == "sbfiz" ? .sbfm : (mnemonic == "ubfiz" ? .ubfm : .bfm)
            return .bitfield(kind, destination: rd, source: rn, immr: immr, imms: imms)
        case "bfc":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let registerSize = Int64(rd.width)
            let lsb = try A64Parser.immediate(instruction.operands[1])
            let width = try A64Parser.immediate(instruction.operands[2])
            guard lsb >= 0, lsb < registerSize, width >= 1, lsb + width <= registerSize else {
                throw AssemblerError.invalidImmediate(mnemonic)
            }
            let immr = UInt32((registerSize - lsb) % registerSize)
            let imms = UInt32(width - 1)
            return .bitfield(.bfm, destination: rd, source: zeroRegister(width: rd.width), immr: immr, imms: imms)
        case "sxtb", "sxth", "sxtw", "uxtb", "uxth":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let rn = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            let kind: A64.BitfieldKind
            let imms: UInt32
            switch mnemonic {
            case "sxtb": kind = .sbfm; imms = 7
            case "sxth": kind = .sbfm; imms = 15
            case "sxtw": kind = .sbfm; imms = 31; guard rd.is64Bit else { throw AssemblerError.invalidRegister(mnemonic) }
            case "uxtb": kind = .ubfm; imms = 7; guard !rd.is64Bit else { throw AssemblerError.invalidRegister(mnemonic) }
            default:    kind = .ubfm; imms = 15; guard !rd.is64Bit else { throw AssemblerError.invalidRegister(mnemonic) }
            }
            return .bitfield(kind, destination: rd, source: rn, immr: 0, imms: imms)
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
            if mnemonic == "mul", allOperandsAreVectorRegisters(instruction) {
                return try vectorThreeSame(instruction, kind: .mul)
            }
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
        case "adc", "adcs", "sbc", "sbcs":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            return .addSubCarry(
                A64.AddSubCarryKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                first: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                second: try A64Parser.integerRegister(instruction.operands[2], allowSP: false)
            )
        case "ngc", "ngcs":
            // Alias: `ngc Rd, Rm` == `sbc Rd, ZR, Rm` (likewise ngcs/sbcs).
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let rd = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let rm = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            return .addSubCarry(
                mnemonic == "ngc" ? .sbc : .sbcs,
                destination: rd,
                first: zeroRegister(width: rd.width),
                second: rm
            )
        case "smull", "umull", "smaddl", "umaddl", "smsubl", "umsubl", "smnegl", "umnegl", "smulh", "umulh":
            guard parts.count == 1 else { return nil }
            // `smull`/`umull` are also SIMD widening multiplies
            // (`smull v0.8h, v1.8b, v2.8b`); route those by operand type.
            if (mnemonic == "smull" || mnemonic == "umull"), allOperandsAreVectorRegisters(instruction) {
                try expectOperandCount(instruction, exactly: 3)
                return .vectorThreeDifferent(
                    A64.VectorThreeDifferentKind(rawValue: mnemonic)!,
                    destination: try A64Parser.vectorRegister(instruction.operands[0]),
                    first: try A64Parser.vectorRegister(instruction.operands[1]),
                    second: try A64Parser.vectorRegister(instruction.operands[2])
                )
            }
            let kind = A64.MultiplyWideKind(rawValue: mnemonic)!
            try expectOperandCount(instruction, exactly: kind.hasAccumulator ? 4 : 3)
            let accumulator = kind.hasAccumulator
                ? try A64Parser.integerRegister(instruction.operands[3], allowSP: false)
                : nil
            return .multiplyWide(
                kind,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                first: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                second: try A64Parser.integerRegister(instruction.operands[2], allowSP: false),
                accumulator: accumulator
            )
        case "crc32b", "crc32h", "crc32w", "crc32x", "crc32cb", "crc32ch", "crc32cw", "crc32cx":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            return .crc32(
                A64.CRC32Kind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                first: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                data: try A64Parser.integerRegister(instruction.operands[2], allowSP: false)
            )
        case "rbit", "rev16", "rev32", "rev", "clz", "cls":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            // `rbit`/`rev16`/`rev32`/`clz`/`cls` also exist as SIMD
            // two-register-misc forms (`rbit v0.8b, v1.8b`); route those by
            // operand type. Plain `rev` has no vector form.
            if mnemonic != "rev", operandsAreVectorRegisters(instruction) {
                return .vectorTwoRegisterMisc(
                    A64.VectorTwoRegisterMiscKind(rawValue: mnemonic)!,
                    destination: try A64Parser.vectorRegister(instruction.operands[0]),
                    source: try A64Parser.vectorRegister(instruction.operands[1])
                )
            }
            return .dataProcessingOneSource(
                A64.DataProcessingOneSourceKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            )
        case "csel", "csinc", "csinv", "csneg":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            return .conditionalSelect(
                A64.ConditionalSelectKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                first: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                second: try A64Parser.integerRegister(instruction.operands[2], allowSP: false),
                condition: try A64Parser.condition(instruction.operands[3])
            )
        case "cset", "csetm":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .conditionalSet(
                A64.ConditionalSetKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                condition: try A64Parser.condition(instruction.operands[1])
            )
        case "cinc", "cinv", "cneg":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            return .conditionalSelectAlias(
                A64.ConditionalSelectAliasKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                condition: try A64Parser.condition(instruction.operands[2])
            )
        case "ccmp", "ccmn":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            let first = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let nzcvValue = try A64Parser.immediate(instruction.operands[2])
            guard nzcvValue >= 0, nzcvValue <= 15 else {
                throw AssemblerError.invalidImmediate(instruction.operands[2])
            }
            let second: A64.ConditionalCompareOperand
            if instruction.operands[1].hasPrefix("#") {
                let imm = try A64Parser.immediate(instruction.operands[1])
                guard imm >= 0, imm <= 31 else {
                    throw AssemblerError.invalidImmediate(instruction.operands[1])
                }
                second = .immediate(UInt32(imm))
            } else {
                second = .register(try A64Parser.integerRegister(instruction.operands[1], allowSP: false))
            }
            return .conditionalCompare(
                A64.ConditionalCompareKind(rawValue: mnemonic)!,
                first: first,
                second: second,
                nzcv: UInt32(nzcvValue),
                condition: try A64Parser.condition(instruction.operands[3])
            )
        case "ldr", "ldrb", "ldrh", "ldrsb", "ldrsh", "ldrsw", "str", "strb", "strh", "ldur", "ldurb", "ldurh", "ldursb", "ldursh", "ldursw", "stur", "sturb", "sturh":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 2...3)
            // SIMD&FP form (`ldr q0, [x1]`, `str s0, [x1, #4]`, …): the target is a
            // scalar floating-point / vector register (b/h/s/d/q).
            if (mnemonic == "ldr" || mnemonic == "str" || mnemonic == "ldur" || mnemonic == "stur"),
               let target = try? A64Parser.floatRegister(instruction.operands[0]) {
                return .loadStoreSingleFP(
                    A64.LoadStoreSingleKind(rawValue: mnemonic)!,
                    target: target,
                    memory: try A64MemoryOperandParser.parse(instruction.operands, startIndex: 1)
                )
            }
            return .loadStoreSingle(
                A64.LoadStoreSingleKind(rawValue: mnemonic)!,
                target: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                memory: try A64MemoryOperandParser.parse(instruction.operands, startIndex: 1)
            )
        case "ldxrb", "ldxrh", "ldxr", "stxrb", "stxrh", "stxr",
             "ldaxrb", "ldaxrh", "ldaxr", "stlxrb", "stlxrh", "stlxr",
             "ldarb", "ldarh", "ldar", "stlrb", "stlrh", "stlr",
             "ldxp", "ldaxp", "stxp", "stlxp":
            guard parts.count == 1 else { return nil }
            let kind = A64.LoadStoreExclusiveKind(rawValue: mnemonic)!
            let expected = (kind.hasStatusRegister ? 1 : 0) + (kind.isPair ? 2 : 1) + 1
            try expectOperandCount(instruction, exactly: expected)
            var index = 0
            var status: A64.Register?
            if kind.hasStatusRegister {
                status = try A64Parser.integerRegister(instruction.operands[index], allowSP: false)
                index += 1
            }
            let value = try A64Parser.integerRegister(instruction.operands[index], allowSP: false)
            index += 1
            var value2: A64.Register?
            if kind.isPair {
                value2 = try A64Parser.integerRegister(instruction.operands[index], allowSP: false)
                index += 1
            }
            let memory = try A64MemoryOperandParser.parse(instruction.operands, startIndex: index)
            guard case .unsignedOffset(let base, 0) = memory else {
                throw AssemblerError.invalidMemoryOperand(instruction.operands[index...].joined(separator: ", "))
            }
            return .loadStoreExclusive(kind, status: status, value: value, value2: value2, base: base)
        case "prfm", "prfum":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 2...3)
            let kind = A64.PrefetchKind(rawValue: mnemonic)!
            let operation = try prefetchOperation(instruction.operands[0])
            let memory = try A64MemoryOperandParser.parse(instruction.operands, startIndex: 1)
            return .prefetch(kind, operation: operation, memory: memory)
        case "stlurb", "stlurh", "stlur", "ldapurb", "ldapurh", "ldapur",
             "ldapursb", "ldapursh", "ldapursw":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let kind = A64.RCpcUnscaledKind(rawValue: mnemonic)!
            let target = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let memory = try A64MemoryOperandParser.parse(instruction.operands, startIndex: 1)
            let base: IntegerRegister
            let offset: Int64
            switch memory {
            case .unsignedOffset(let b, let o), .signedUnscaled(let b, let o):
                base = b
                offset = o
            default:
                throw AssemblerError.invalidMemoryOperand(instruction.operands[1...].joined(separator: ", "))
            }
            return .rcpcUnscaled(kind, target: target, base: base, offset: offset)
        case "ldaprb", "ldaprh", "ldapr":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let kind = A64.LoadAcquireRCpcKind(rawValue: mnemonic)!
            let value = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let memory = try A64MemoryOperandParser.parse(instruction.operands, startIndex: 1)
            guard case .unsignedOffset(let base, 0) = memory else {
                throw AssemblerError.invalidMemoryOperand(instruction.operands[1...].joined(separator: ", "))
            }
            return .loadAcquireRCpc(kind, value: value, base: base)
        case "clrex":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 0...1)
            let immediate: Int64 = instruction.operands.isEmpty ? 15 : try A64Parser.immediate(instruction.operands[0])
            try checkRange(immediate, 0...0xf, instruction: "clrex")
            return .clearExclusive(UInt32(immediate))
        case "mrs":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let value = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            guard let register = A64.SystemRegister.parse(instruction.operands[1]) else {
                throw AssemblerError.unsupportedOperand(instruction.operands[1])
            }
            return .systemRegisterMove(read: true, register: register, value: value)
        case "msr":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            if let field = A64.PStateField(rawValue: instruction.operands[0].lowercased()) {
                let immediate = try A64Parser.immediate(instruction.operands[1])
                try checkRange(immediate, 0...0xf, instruction: "msr")
                return .pstate(field, immediate: UInt32(immediate))
            }
            guard let register = A64.SystemRegister.parse(instruction.operands[0]) else {
                throw AssemblerError.unsupportedOperand(instruction.operands[0])
            }
            let value = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            return .systemRegisterMove(read: false, register: register, value: value)
        case "sys":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 4...5)
            let op1 = try systemFieldValue(instruction.operands[0], instruction: "sys")
            let crn = try cRegisterNumber(instruction.operands[1], instruction: "sys")
            let crm = try cRegisterNumber(instruction.operands[2], instruction: "sys")
            let op2 = try systemFieldValue(instruction.operands[3], instruction: "sys")
            let register = instruction.operands.count == 5
                ? try A64Parser.integerRegister(instruction.operands[4], allowSP: false) : nil
            return .systemInstruction(read: false, op1: op1, crn: crn, crm: crm, op2: op2, register: register)
        case "sysl":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 5)
            let register = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let op1 = try systemFieldValue(instruction.operands[1], instruction: "sysl")
            let crn = try cRegisterNumber(instruction.operands[2], instruction: "sysl")
            let crm = try cRegisterNumber(instruction.operands[3], instruction: "sysl")
            let op2 = try systemFieldValue(instruction.operands[4], instruction: "sysl")
            return .systemInstruction(read: true, op1: op1, crn: crn, crm: crm, op2: op2, register: register)
        case "dc", "ic", "at", "tlbi":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 1...2)
            guard let alias = A64.SystemInstructionAlias.find(
                family: mnemonic, name: instruction.operands[0].lowercased()) else {
                throw AssemblerError.unsupportedOperand(instruction.operands[0])
            }
            var register: IntegerRegister?
            if instruction.operands.count == 2 {
                register = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            } else if alias.needsRegister {
                throw AssemblerError.unsupportedOperand(mnemonic)
            }
            return .systemInstruction(read: false, op1: alias.op1, crn: alias.crn,
                                      crm: alias.crm, op2: alias.op2, register: register)
        case "cas", "casa", "casl", "casal", "casb", "casab", "caslb", "casalb",
             "cash", "casah", "caslh", "casalh":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let kind = A64.CompareAndSwapKind(rawValue: mnemonic)!
            let compare = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let value = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            let memory = try A64MemoryOperandParser.parse(instruction.operands, startIndex: 2)
            guard case .unsignedOffset(let base, 0) = memory else {
                throw AssemblerError.invalidMemoryOperand(instruction.operands[2...].joined(separator: ", "))
            }
            return .compareAndSwap(kind, compare: compare, value: value, base: base)
        case "casp", "caspa", "caspl", "caspal":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 5)
            let kind = A64.CompareAndSwapPairKind(rawValue: mnemonic)!
            let compare = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
            let compareHigh = try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            let value = try A64Parser.integerRegister(instruction.operands[2], allowSP: false)
            let valueHigh = try A64Parser.integerRegister(instruction.operands[3], allowSP: false)
            // The high registers of each pair are implied and must be consecutive.
            guard compareHigh.number == compare.number + 1, compareHigh.width == compare.width,
                  valueHigh.number == value.number + 1, valueHigh.width == value.width else {
                throw AssemblerError.invalidRegister(mnemonic)
            }
            let memory = try A64MemoryOperandParser.parse(instruction.operands, startIndex: 4)
            guard case .unsignedOffset(let base, 0) = memory else {
                throw AssemblerError.invalidMemoryOperand(instruction.operands[4...].joined(separator: ", "))
            }
            return .compareAndSwapPair(kind, compare: compare, value: value, base: base)
        case "ldp", "stp":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 3...4)
            // SIMD&FP form (`ldp q0, q1, [x2]`, …): paired floating-point registers.
            if let first = try? A64Parser.floatRegister(instruction.operands[0]),
               let second = try? A64Parser.floatRegister(instruction.operands[1]) {
                return .loadStorePairFP(
                    A64.LoadStorePairKind(rawValue: mnemonic)!,
                    first: first,
                    second: second,
                    memory: try A64MemoryOperandParser.parse(instruction.operands, startIndex: 2)
                )
            }
            return .loadStorePair(
                A64.LoadStorePairKind(rawValue: mnemonic)!,
                first: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                second: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                memory: try A64MemoryOperandParser.parse(instruction.operands, startIndex: 2)
            )
        case "ld1", "st1", "ld2", "st2", "ld3", "st3", "ld4", "st4":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 2...3)
            let kind = A64.LoadStoreMultipleKind(rawValue: mnemonic)!
            // A `}[` in the register list selects the single-lane form (e.g. `{v0.s}[1]`),
            // otherwise it is the multiple-structures form (e.g. `{v0.4s}`).
            if instruction.operands[0].contains("}[") || instruction.operands[0].contains("} [") {
                let list = try A64Parser.vectorLaneList(instruction.operands[0])
                let expected = Int64(list.count) << list.width.sizeShift
                return .loadStoreSingleLane(
                    kind,
                    registers: list,
                    address: try A64Parser.vectorMemoryOperand(instruction.operands, baseIndex: 1, expectedPostImmediate: expected)
                )
            }
            let list = try A64Parser.vectorRegisterList(instruction.operands[0])
            let bytesPerRegister: Int64 = list.arrangement.q == 1 ? 16 : 8
            let expected = Int64(list.count) * bytesPerRegister
            return .loadStoreMultiple(
                kind,
                registers: list,
                address: try A64Parser.vectorMemoryOperand(instruction.operands, baseIndex: 1, expectedPostImmediate: expected)
            )
        case "tbl", "tbx":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let kind = A64.VectorTableLookupKind(rawValue: mnemonic)!
            return .vectorTableLookup(
                kind,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                table: try A64Parser.vectorRegisterList(instruction.operands[1]),
                index: try A64Parser.vectorRegister(instruction.operands[2])
            )
        case "ld1r", "ld2r", "ld3r", "ld4r":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, 2...3)
            let kind = A64.LoadStoreReplicateKind(rawValue: mnemonic)!
            let list = try A64Parser.vectorRegisterList(instruction.operands[0])
            // Each register loads one element; the implicit post-index immediate is
            // selem * elementBytes.
            let elementBytes = Int64(list.arrangement.elementWidth / 8)
            let expected = Int64(list.count) * elementBytes
            return .loadStoreReplicate(
                kind,
                registers: list,
                address: try A64Parser.vectorMemoryOperand(instruction.operands, baseIndex: 1, expectedPostImmediate: expected)
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
            if mnemonic != "fnmul", allOperandsAreVectorRegisters(instruction) {
                return try vectorThreeSame(instruction, kind: A64.VectorThreeSameKind(rawValue: mnemonic)!)
            }
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
        case "frint32z", "frint32x", "frint64z", "frint64x":
            // The scalar forms are intercepted by the SIMD pre-pass above; this
            // case handles the vector `.2s`/`.4s`/`.2d` two-register-misc forms.
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .vectorTwoRegisterMisc(
                A64.VectorTwoRegisterMiscKind(rawValue: mnemonic)!,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
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
        case "fcsel":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            return .fpConditionalSelect(
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                first: try A64Parser.floatRegister(instruction.operands[1]),
                second: try A64Parser.floatRegister(instruction.operands[2]),
                condition: try A64Parser.condition(instruction.operands[3])
            )
        case "fccmp", "fccmpe":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            let nzcvValue = try A64Parser.immediate(instruction.operands[2])
            guard nzcvValue >= 0, nzcvValue <= 0xf else {
                throw AssemblerError.invalidImmediate(instruction.operands[2])
            }
            return .fpConditionalCompare(
                A64.FPConditionalCompareKind(rawValue: mnemonic)!,
                first: try A64Parser.floatRegister(instruction.operands[0]),
                second: try A64Parser.floatRegister(instruction.operands[1]),
                nzcv: UInt32(nzcvValue),
                condition: try A64Parser.condition(instruction.operands[3])
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
            // High-half move between a general register and a 128-bit vector element:
            // `fmov x<d>, v<n>.d[1]` and `fmov v<d>.d[1], x<n>`.
            if instruction.operands.count == 2,
               (A64Parser.isVectorElementOperand(instruction.operands[0]) || A64Parser.isVectorElementOperand(instruction.operands[1])) {
                if A64Parser.isVectorElementOperand(instruction.operands[1]) {
                    return .fpMoveVectorHighToGeneral(
                        destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                        source: try A64Parser.vectorElement(instruction.operands[1])
                    )
                }
                return .fpMoveGeneralToVectorHigh(
                    destination: try A64Parser.vectorElement(instruction.operands[0]),
                    source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
                )
            }
            // Vector modified-immediate form: `Vd.T, #fp`.
            if isVectorRegisterOperand(instruction.operands[0]) {
                return try vectorModifiedImmediate(instruction, kind: .fmov)
            }
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
            // Vector fixed-point form: `Vd.T, Vn.T, #fbits`.
            if isVectorShiftImmediate(instruction) {
                return try vectorShiftImmediate(instruction, kind: A64.VectorShiftImmediateKind(rawValue: mnemonic)!)
            }
            // Scalar fixed-point form: `<Wd|Xd>, <n>, #fbits`.
            if instruction.operands.count == 3 {
                let fbits = try A64Parser.immediate(instruction.operands[2])
                guard fbits >= 1, fbits <= 64 else { throw AssemblerError.invalidImmediate(instruction.operands[2]) }
                return .fpConvertToFixed(
                    A64.FPConvertToIntKind(rawValue: mnemonic)!,
                    destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                    source: try A64Parser.floatRegister(instruction.operands[1]),
                    fbits: UInt32(fbits)
                )
            }
            try expectOperandCount(instruction, exactly: 2)
            return .fpConvertToInt(
                A64.FPConvertToIntKind(rawValue: mnemonic)!,
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                source: try A64Parser.floatRegister(instruction.operands[1])
            )
        case "scvtf", "ucvtf":
            guard parts.count == 1 else { return nil }
            // Vector fixed-point form: `Vd.T, Vn.T, #fbits`.
            if isVectorShiftImmediate(instruction) {
                return try vectorShiftImmediate(instruction, kind: A64.VectorShiftImmediateKind(rawValue: mnemonic)!)
            }
            // Scalar fixed-point form: `<d>, <Wn|Xn>, #fbits`.
            if instruction.operands.count == 3 {
                let fbits = try A64Parser.immediate(instruction.operands[2])
                guard fbits >= 1, fbits <= 64 else { throw AssemblerError.invalidImmediate(instruction.operands[2]) }
                return .fpConvertFromFixed(
                    A64.FPConvertFromIntKind(rawValue: mnemonic)!,
                    destination: try A64Parser.floatRegister(instruction.operands[0]),
                    source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false),
                    fbits: UInt32(fbits)
                )
            }
            try expectOperandCount(instruction, exactly: 2)
            return .fpConvertFromInt(
                A64.FPConvertFromIntKind(rawValue: mnemonic)!,
                destination: try A64Parser.floatRegister(instruction.operands[0]),
                source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            )
        case "fjcvtzs":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .fjcvtzs(
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                source: try A64Parser.floatRegister(instruction.operands[1])
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
        case "sdot", "udot":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let kind = A64.VectorDotProductKind(rawValue: mnemonic)!
            let destination = try A64Parser.vectorRegister(instruction.operands[0])
            let first = try A64Parser.vectorRegister(instruction.operands[1])
            // The third operand is either a plain vector (`Vm.8b/16b`) or an
            // indexed 4-byte group element (`Vm.4b[index]`).
            if instruction.operands[2].contains("[") {
                let element = try A64Parser.dotProductElement(instruction.operands[2])
                return .vectorDotProductByElement(kind, destination: destination, first: first, elementRegister: element.number, index: element.index)
            }
            return .vectorDotProduct(kind, destination: destination, first: first, second: try A64Parser.vectorRegister(instruction.operands[2]))
        case "usdot", "sudot":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let destination = try A64Parser.vectorRegister(instruction.operands[0])
            let first = try A64Parser.vectorRegister(instruction.operands[1])
            // Indexed form (`Vm.4b[index]`) exists for both usdot and sudot;
            // the plain vector (three-register) form exists only for usdot.
            if instruction.operands[2].contains("[") {
                let element = try A64Parser.dotProductElement(instruction.operands[2])
                let kind = A64.VectorMixedDotProductKind(rawValue: mnemonic)!
                return .vectorMixedDotByElement(kind, destination: destination, first: first, elementRegister: element.number, index: element.index)
            }
            guard mnemonic == "usdot" else {
                throw AssemblerError.invalidRegister(instruction.operands[2])
            }
            return .vectorUSDotProduct(destination: destination, first: first, second: try A64Parser.vectorRegister(instruction.operands[2]))
        case "smmla", "ummla", "usmmla":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let kind = A64.VectorMatrixMultiplyKind(rawValue: mnemonic)!
            return .vectorMatrixMultiply(
                kind,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                first: try A64Parser.vectorRegister(instruction.operands[1]),
                second: try A64Parser.vectorRegister(instruction.operands[2])
            )
        case "fcadd":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            return .vectorComplexAdd(
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                first: try A64Parser.vectorRegister(instruction.operands[1]),
                second: try A64Parser.vectorRegister(instruction.operands[2]),
                rotation: Int(try A64Parser.immediate(instruction.operands[3]))
            )
        case "fcmla":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            let destination = try A64Parser.vectorRegister(instruction.operands[0])
            let first = try A64Parser.vectorRegister(instruction.operands[1])
            let rotation = Int(try A64Parser.immediate(instruction.operands[3]))
            if A64Parser.isVectorElementOperand(instruction.operands[2]) {
                let element = try A64Parser.vectorElement(instruction.operands[2])
                return .vectorComplexMultiplyAddByElement(
                    destination: destination, first: first,
                    elementRegister: element.number, index: UInt32(element.index), rotation: rotation
                )
            }
            return .vectorComplexMultiplyAdd(
                destination: destination, first: first,
                second: try A64Parser.vectorRegister(instruction.operands[2]), rotation: rotation
            )
        case "fmlal", "fmlal2", "fmlsl", "fmlsl2":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let kind = A64.VectorFPMultiplyLongKind(rawValue: mnemonic)!
            let destination = try A64Parser.vectorRegister(instruction.operands[0])
            let first = try A64Parser.vectorRegister(instruction.operands[1])
            // The third operand is either a plain vector (`Vm.2h/4h`) or an
            // indexed FP16 element (`Vm.h[index]`).
            if instruction.operands[2].contains("[") {
                let element = try A64Parser.vectorElement(instruction.operands[2])
                return .vectorFPMultiplyLongByElement(kind, destination: destination, first: first, elementRegister: element.number, index: UInt32(element.index))
            }
            return .vectorFPMultiplyLong(kind, destination: destination, first: first, second: try A64Parser.vectorRegister(instruction.operands[2]))
        case "bfdot":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let destination = try A64Parser.vectorRegister(instruction.operands[0])
            let first = try A64Parser.vectorRegister(instruction.operands[1])
            if instruction.operands[2].contains("[") {
                let element = try A64Parser.bfdotElement(instruction.operands[2])
                return .vectorBFDotByElement(destination: destination, first: first, elementRegister: element.number, index: element.index)
            }
            return .vectorBFDot(destination: destination, first: first, second: try A64Parser.vectorRegister(instruction.operands[2]))
        case "bfmlalb", "bfmlalt":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let top = mnemonic == "bfmlalt"
            let destination = try A64Parser.vectorRegister(instruction.operands[0])
            let first = try A64Parser.vectorRegister(instruction.operands[1])
            if instruction.operands[2].contains("[") {
                let element = try A64Parser.vectorElement(instruction.operands[2])
                return .vectorBFMLALByElement(top: top, destination: destination, first: first, elementRegister: element.number, index: UInt32(element.index))
            }
            return .vectorBFMLAL(top: top, destination: destination, first: first, second: try A64Parser.vectorRegister(instruction.operands[2]))
        case "bfcvtn", "bfcvtn2":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .vectorBFConvertNarrow(
                top: mnemonic == "bfcvtn2",
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
        case "bfmmla":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            return .vectorBFMatrixMultiply(
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                first: try A64Parser.vectorRegister(instruction.operands[1]),
                second: try A64Parser.vectorRegister(instruction.operands[2])
            )
        case "sqrdmlah", "sqrdmlsh":
            // The indexed forms (`..., Vm.Ts[i]`) are routed earlier via
            // VectorIndexedKind; here only the non-indexed three-same-extra
            // forms remain: scalar (`Hd, Hn, Hm`) or vector (`Vd.T, Vn.T, Vm.T`).
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let kind = A64.VectorThreeSameExtraKind(rawValue: mnemonic)!
            if instruction.operands.allSatisfy(A64Parser.isScalarFloatRegisterOperand) {
                return .scalarThreeSameExtra(
                    kind,
                    destination: try A64Parser.floatRegister(instruction.operands[0]),
                    first: try A64Parser.floatRegister(instruction.operands[1]),
                    second: try A64Parser.floatRegister(instruction.operands[2])
                )
            }
            return .vectorThreeSameExtra(
                kind,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                first: try A64Parser.vectorRegister(instruction.operands[1]),
                second: try A64Parser.vectorRegister(instruction.operands[2])
            )
        case "rev64", "abs", "neg", "not", "cnt", "sqabs", "sqneg", "suqadd", "usqadd":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let kind = mnemonic == "not" ? A64.VectorTwoRegisterMiscKind.mvn : A64.VectorTwoRegisterMiscKind(rawValue: mnemonic)!
            return .vectorTwoRegisterMisc(
                kind,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
        case "aese", "aesd", "aesmc", "aesimc":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .cryptoAES(
                A64.CryptoAESKind(rawValue: mnemonic)!,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1])
            )
        case "sha1c", "sha1p", "sha1m", "sha1su0", "sha256h", "sha256h2", "sha256su1":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let kind = A64.CryptoSHA3Kind(rawValue: mnemonic)!
            let shape = kind.shape
            return .cryptoSHA3(
                kind,
                d: try A64Parser.cryptoSHAOperandNumber(instruction.operands[0], shape: shape.d),
                n: try A64Parser.cryptoSHAOperandNumber(instruction.operands[1], shape: shape.n),
                m: try A64Parser.cryptoSHAOperandNumber(instruction.operands[2], shape: shape.m)
            )
        case "sha1h", "sha1su1", "sha256su0":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let kind = A64.CryptoSHA2Kind(rawValue: mnemonic)!
            let shape = kind.shape
            return .cryptoSHA2(
                kind,
                d: try A64Parser.cryptoSHAOperandNumber(instruction.operands[0], shape: shape.d),
                n: try A64Parser.cryptoSHAOperandNumber(instruction.operands[1], shape: shape.n)
            )
        case "sha512h", "sha512h2", "sha512su1":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let kind = A64.CryptoSHA512Kind(rawValue: mnemonic)!
            let shape = kind.shape
            return .cryptoSHA512(
                kind,
                d: try A64Parser.cryptoSHAOperandNumber(instruction.operands[0], shape: shape.d),
                n: try A64Parser.cryptoSHAOperandNumber(instruction.operands[1], shape: shape.n),
                m: try A64Parser.cryptoSHAOperandNumber(instruction.operands[2], shape: shape.m)
            )
        case "sha512su0", "sm4e":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let kind = A64.CryptoTwoRegKind(rawValue: mnemonic)!
            let shape = kind.shape
            return .cryptoTwoReg(
                kind,
                d: try A64Parser.cryptoSHAOperandNumber(instruction.operands[0], shape: shape.d),
                n: try A64Parser.cryptoSHAOperandNumber(instruction.operands[1], shape: shape.n)
            )
        case "sm3partw1", "sm3partw2", "sm4ekey":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let kind = A64.CryptoSM3Kind(rawValue: mnemonic)!
            return .cryptoSM3(
                kind,
                d: try A64Parser.cryptoSHAOperandNumber(instruction.operands[0], shape: .vector4s),
                n: try A64Parser.cryptoSHAOperandNumber(instruction.operands[1], shape: .vector4s),
                m: try A64Parser.cryptoSHAOperandNumber(instruction.operands[2], shape: .vector4s)
            )
        case "sm3tt1a", "sm3tt1b", "sm3tt2a", "sm3tt2b":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let kind = A64.CryptoSM3IndexedKind(rawValue: mnemonic)!
            let element = try A64Parser.vectorElement(instruction.operands[2])
            guard element.width == .s, element.index >= 0, element.index <= 3 else {
                throw AssemblerError.invalidRegister(instruction.operands[2])
            }
            return .cryptoSM3Indexed(
                kind,
                d: try A64Parser.cryptoSHAOperandNumber(instruction.operands[0], shape: .vector4s),
                n: try A64Parser.cryptoSHAOperandNumber(instruction.operands[1], shape: .vector4s),
                m: element.number,
                index: UInt32(element.index)
            )
        case "sm3ss1":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            return .cryptoSM3SS1(
                d: try A64Parser.cryptoSHAOperandNumber(instruction.operands[0], shape: .vector4s),
                n: try A64Parser.cryptoSHAOperandNumber(instruction.operands[1], shape: .vector4s),
                m: try A64Parser.cryptoSHAOperandNumber(instruction.operands[2], shape: .vector4s),
                a: try A64Parser.cryptoSHAOperandNumber(instruction.operands[3], shape: .vector4s)
            )
        case "eor3", "bcax":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            let kind = A64.CryptoSHA3FourKind(rawValue: mnemonic)!
            return .cryptoSHA3Four(
                kind,
                d: try A64Parser.cryptoSHAOperandNumber(instruction.operands[0], shape: .vector16b),
                n: try A64Parser.cryptoSHAOperandNumber(instruction.operands[1], shape: .vector16b),
                m: try A64Parser.cryptoSHAOperandNumber(instruction.operands[2], shape: .vector16b),
                a: try A64Parser.cryptoSHAOperandNumber(instruction.operands[3], shape: .vector16b)
            )
        case "rax1":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            return .cryptoRAX1(
                d: try A64Parser.cryptoSHAOperandNumber(instruction.operands[0], shape: .vector2d),
                n: try A64Parser.cryptoSHAOperandNumber(instruction.operands[1], shape: .vector2d),
                m: try A64Parser.cryptoSHAOperandNumber(instruction.operands[2], shape: .vector2d)
            )
        case "xar":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            let imm6 = try A64Parser.immediate(instruction.operands[3])
            guard imm6 >= 0, imm6 <= 63 else { throw AssemblerError.invalidImmediate(instruction.operands[3]) }
            return .cryptoXAR(
                d: try A64Parser.cryptoSHAOperandNumber(instruction.operands[0], shape: .vector2d),
                n: try A64Parser.cryptoSHAOperandNumber(instruction.operands[1], shape: .vector2d),
                m: try A64Parser.cryptoSHAOperandNumber(instruction.operands[2], shape: .vector2d),
                imm6: UInt32(imm6)
            )
        case "zip1", "zip2", "uzp1", "uzp2", "trn1", "trn2":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            return .vectorPermute(
                A64.VectorPermuteKind(rawValue: mnemonic)!,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                first: try A64Parser.vectorRegister(instruction.operands[1]),
                second: try A64Parser.vectorRegister(instruction.operands[2])
            )
        case "ext":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 4)
            return .vectorExtract(
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                first: try A64Parser.vectorRegister(instruction.operands[1]),
                second: try A64Parser.vectorRegister(instruction.operands[2]),
                index: Int(try A64Parser.immediate(instruction.operands[3]))
            )
        case "movi", "mvni":
            guard parts.count == 1 else { return nil }
            return try vectorModifiedImmediate(instruction, kind: A64.VectorModifiedImmediateKind(rawValue: mnemonic)!)
        case "dup":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let destination = try A64Parser.vectorRegister(instruction.operands[0])
            if A64Parser.isVectorElementOperand(instruction.operands[1]) {
                return .vectorDuplicateElement(
                    destination: destination,
                    source: try A64Parser.vectorElement(instruction.operands[1])
                )
            }
            return .vectorDuplicateGeneral(
                destination: destination,
                source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            )
        case "smov", "umov":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .vectorMoveToGeneral(
                signed: mnemonic == "smov",
                destination: try A64Parser.integerRegister(instruction.operands[0], allowSP: false),
                source: try A64Parser.vectorElement(instruction.operands[1])
            )
        case "ins":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            let destination = try A64Parser.vectorElement(instruction.operands[0])
            if A64Parser.isVectorElementOperand(instruction.operands[1]) {
                return .vectorInsertElement(
                    destination: destination,
                    source: try A64Parser.vectorElement(instruction.operands[1])
                )
            }
            return .vectorInsertGeneral(
                destination: destination,
                source: try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
            )
        case "sshr", "ushr", "ssra", "usra", "srshr", "urshr", "srsra", "ursra", "sri",
             "shl", "sli", "sqshlu",
             "shrn", "rshrn", "sqshrn", "sqrshrn", "sqshrun", "sqrshrun", "uqshrn", "uqrshrn",
             "shrn2", "rshrn2", "sqshrn2", "sqrshrn2", "sqshrun2", "sqrshrun2", "uqshrn2", "uqrshrn2",
             "sshll", "ushll", "sshll2", "ushll2":
            guard parts.count == 1 else { return nil }
            // The `2` suffix (upper-half form) is implied by the `Q=1` arrangement.
            let base = mnemonic.hasSuffix("2") ? String(mnemonic.dropLast()) : mnemonic
            return try vectorShiftImmediate(instruction, kind: A64.VectorShiftImmediateKind(rawValue: base)!)
        case "sxtl", "uxtl", "sxtl2", "uxtl2":
            // Aliases of `sshll`/`ushll` with a zero shift.
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 2)
            return .vectorShiftImmediate(
                mnemonic.hasPrefix("s") ? .sshll : .ushll,
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: try A64Parser.vectorRegister(instruction.operands[1]),
                shift: 0
            )
        case "shll", "shll2":
            guard parts.count == 1 else { return nil }
            try expectOperandCount(instruction, exactly: 3)
            let source = try A64Parser.vectorRegister(instruction.operands[1])
            // The `2` suffix selects the upper-half (`Q=1`) source arrangement.
            let expectedQ: UInt32 = mnemonic == "shll2" ? 1 : 0
            guard source.arrangement.q == expectedQ else {
                throw AssemblerError.invalidRegister(instruction.operands[1])
            }
            let shift = try A64Parser.immediate(instruction.operands[2])
            guard shift >= 0 else { throw AssemblerError.invalidImmediate(instruction.operands[2]) }
            return .vectorShiftLeftLong(
                destination: try A64Parser.vectorRegister(instruction.operands[0]),
                source: source,
                shift: UInt32(shift)
            )
        case "shadd", "uhadd", "sqadd", "uqadd", "srhadd", "urhadd",
             "shsub", "uhsub", "sqsub", "uqsub",
             "cmgt", "cmhi", "cmge", "cmhs",
             "sshl", "ushl", "sqshl", "uqshl", "srshl", "urshl", "sqrshl", "uqrshl",
             "smax", "umax", "smin", "umin",
             "sabd", "uabd", "saba", "uaba",
             "cmtst", "cmeq",
             "mla", "mls", "pmul",
             "smaxp", "umaxp", "sminp", "uminp",
             "sqdmulh", "sqrdmulh", "addp",
             "bsl", "bit", "bif",
             "fmla", "fmulx", "fcmeq", "frecps",
             "fmls", "frsqrts",
             "fmaxnmp", "faddp", "fcmge", "facge", "fmaxp",
             "fminnmp", "fabd", "fcmgt", "facgt", "fminp":
            guard parts.count == 1 else { return nil }
            // `sqshl`/`uqshl` also have a shift-by-immediate form (`Vd.T, Vn.T, #imm`).
            if (mnemonic == "sqshl" || mnemonic == "uqshl"), isVectorShiftImmediate(instruction) {
                return try vectorShiftImmediate(instruction, kind: A64.VectorShiftImmediateKind(rawValue: mnemonic)!)
            }
            return try vectorThreeSame(instruction, kind: A64.VectorThreeSameKind(rawValue: mnemonic)!)
        default:
            // Atomic memory operations (LSE): LD<op>, SWP, and the ST<op> aliases.
            if parts.count == 1, let kind = A64.AtomicMemoryKind.parse(mnemonic) {
                return try atomicMemory(instruction, kind: kind)
            }
            // Advanced SIMD three-different (long/wide/narrow); the `2` suffix is
            // the upper-half form (implied by the `Q=1` arrangement).
            if parts.count == 1 {
                let base = mnemonic.hasSuffix("2") ? String(mnemonic.dropLast()) : mnemonic
                if let kind = A64.VectorThreeDifferentKind(rawValue: base) {
                    try expectOperandCount(instruction, exactly: 3)
                    return .vectorThreeDifferent(
                        kind,
                        destination: try A64Parser.vectorRegister(instruction.operands[0]),
                        first: try A64Parser.vectorRegister(instruction.operands[1]),
                        second: try A64Parser.vectorRegister(instruction.operands[2])
                    )
                }
            }
            return nil
        }
    }

    /// Parses a prefetch operation operand: a `<type><target><policy>` name
    /// (e.g. `pldl1keep`, `pstl3strm`) or a 5-bit `#imm`.
    private static func prefetchOperation(_ text: String) throws -> UInt32 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            let value = try A64Parser.immediate(trimmed)
            try checkRange(value, 0...0x1f, instruction: "prfm")
            return UInt32(value)
        }
        let name = trimmed.lowercased()
        let types = ["pld": UInt32(0), "pli": 1, "pst": 2]
        let targets = ["l1": UInt32(0), "l2": 1, "l3": 2]
        for (typeName, type) in types where name.hasPrefix(typeName) {
            let rest = name.dropFirst(typeName.count)
            for (targetName, target) in targets where rest.hasPrefix(targetName) {
                let policyName = rest.dropFirst(targetName.count)
                let policy: UInt32
                switch policyName {
                case "keep": policy = 0
                case "strm": policy = 1
                default: continue
                }
                return (type << 3) | (target << 1) | policy
            }
        }
        throw AssemblerError.unsupportedOperand(text)
    }

    /// Parse a `#imm` operand for a `SYS`/`SYSL` `op1`/`op2` field (0–7).
    private static func systemFieldValue(_ text: String, instruction: String) throws -> UInt32 {
        let value = try A64Parser.immediate(text)
        try checkRange(value, 0...7, instruction: instruction)
        return UInt32(value)
    }

    /// Parse a `c<n>` operand for a `SYS`/`SYSL` `CRn`/`CRm` field (0–15).
    private static func cRegisterNumber(_ text: String, instruction: String) throws -> UInt32 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("c"), let value = UInt32(trimmed.dropFirst()), value <= 15 else {
            throw AssemblerError.unsupportedOperand(text)
        }
        return value
    }

    private static func atomicMemory(_ instruction: ParsedInstruction, kind: A64.AtomicMemoryKind) throws -> Instruction {
        // ST<op> aliases take `Rs, [Xn]`; LD<op> and SWP take `Rs, Rt, [Xn]`.
        let baseIndex = kind.isStore ? 1 : 2
        try expectOperandCount(instruction, exactly: baseIndex + 1)
        let source = try A64Parser.integerRegister(instruction.operands[0], allowSP: false)
        let value: A64.Register? = kind.isStore
            ? nil : try A64Parser.integerRegister(instruction.operands[1], allowSP: false)
        let memory = try A64MemoryOperandParser.parse(instruction.operands, startIndex: baseIndex)
        guard case .unsignedOffset(let base, 0) = memory else {
            throw AssemblerError.invalidMemoryOperand(instruction.operands[baseIndex...].joined(separator: ", "))
        }
        return .atomicMemory(kind, source: source, value: value, base: base)
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
        if instruction.operands.count > startIndex + 1 {
            let modifier = instruction.operands[startIndex + 1]
            if let extend = addSubExtend(modifier) {
                return .extendedRegister(register, extend: extend.0, amount: extend.1)
            }
            return .shiftedRegister(register, shift: try shift(modifier))
        }
        return .shiftedRegister(register, shift: nil)
    }

    /// Parses an add/sub extend modifier such as `uxtb` or `sxtw #3`.
    /// Returns `nil` when the text is not an extend keyword (e.g. a shift).
    private static func addSubExtend(_ text: String) -> (A64.ExtendKind, Int?)? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { String($0).lowercased() }
        guard let keyword = parts.first else { return nil }
        let kind: A64.ExtendKind
        switch keyword {
        case "uxtb": kind = .uxtb
        case "uxth": kind = .uxth
        case "uxtw": kind = .uxtw
        case "uxtx": kind = .uxtx
        case "sxtb": kind = .sxtb
        case "sxth": kind = .sxth
        case "sxtw": kind = .sxtw
        case "sxtx": kind = .sxtx
        default: return nil
        }
        var amount: Int? = nil
        if parts.count >= 2 {
            let raw = parts[1].hasPrefix("#") ? String(parts[1].dropFirst()) : parts[1]
            amount = Int(raw)
        }
        return (kind, amount)
    }

    /// `add`/`sub`/`cmp`/`cmn` with a stack-pointer operand and a plain register
    /// must use the extended-register form (the shifted form cannot encode SP).
    /// The implicit extend is `uxtx` for 64-bit operations and `uxtw` for 32-bit.
    private static func promoteToExtendedIfStackPointer(_ operand: A64.AddSubOperand, rd: IntegerRegister, rn: IntegerRegister) -> A64.AddSubOperand {
        guard case .shiftedRegister(let rm, let shift) = operand, shift == nil else { return operand }
        guard rd.kind == .stackPointer || rn.kind == .stackPointer else { return operand }
        return .extendedRegister(rm, extend: rn.is64Bit ? .uxtx : .uxtw, amount: nil)
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
        return instruction.operands.allSatisfy(isVectorRegisterOperand)
    }

    /// True when every operand looks like an arrangement-qualified vector register (`v0.4s`).
    private static func allOperandsAreVectorRegisters(_ instruction: ParsedInstruction) -> Bool {
        !instruction.operands.isEmpty && instruction.operands.allSatisfy(isVectorRegisterOperand)
    }

    private static func isVectorRegisterOperand(_ operand: String) -> Bool {
        let trimmed = operand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("v") && trimmed.contains(".")
    }

    static func vectorThreeSame(_ instruction: ParsedInstruction, kind: A64.VectorThreeSameKind) throws -> Instruction {
        try expectOperandCount(instruction, exactly: 3)
        return .vectorThreeSame(
            kind,
            destination: try A64Parser.vectorRegister(instruction.operands[0]),
            first: try A64Parser.vectorRegister(instruction.operands[1]),
            second: try A64Parser.vectorRegister(instruction.operands[2])
        )
    }

    /// True when the operands look like `Vd.T, Vn.T, #imm` (vector shift by immediate).
    private static func isVectorShiftImmediate(_ instruction: ParsedInstruction) -> Bool {
        guard instruction.operands.count == 3 else { return false }
        return isVectorRegisterOperand(instruction.operands[0])
            && isVectorRegisterOperand(instruction.operands[1])
            && instruction.operands[2].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#")
    }

    /// True when the operands look like `Vd.T, #imm{, shift}` (vector modified immediate).
    private static func isVectorModifiedImmediate(_ instruction: ParsedInstruction) -> Bool {
        guard instruction.operands.count >= 2, isVectorRegisterOperand(instruction.operands[0]) else { return false }
        return instruction.operands[1].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#")
    }

    private static func vectorImmediateShift(_ text: String) throws -> A64.VectorImmediateShift {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true).map { String($0).lowercased() }
        guard parts.count == 2 else { throw AssemblerError.unsupportedShift(text) }
        let amount = try A64Parser.immediate(parts[1])
        switch parts[0] {
        case "lsl": return amount == 0 ? .none : .lsl(Int(amount))
        case "msl": return .msl(Int(amount))
        default: throw AssemblerError.unsupportedShift(text)
        }
    }

    static func vectorModifiedImmediate(_ instruction: ParsedInstruction, kind: A64.VectorModifiedImmediateKind) throws -> Instruction {
        try expectOperandCount(instruction, 2...3)
        let destinationText = instruction.operands[0].trimmingCharacters(in: .whitespacesAndNewlines)

        let destination: VectorRegister
        if isVectorRegisterOperand(destinationText) {
            destination = try A64Parser.vectorRegister(destinationText)
        } else if kind == .movi {
            // Scalar `movi d0, #imm` form, modelled with the `1d` arrangement.
            let scalar = try A64Parser.floatRegister(destinationText)
            guard scalar.width == 64 else { throw AssemblerError.invalidRegister(destinationText) }
            destination = VectorRegister(number: scalar.number, arrangement: .d1)
        } else {
            throw AssemblerError.invalidRegister(destinationText)
        }

        var shift: A64.VectorImmediateShift = .none
        if instruction.operands.count == 3 {
            shift = try vectorImmediateShift(instruction.operands[2])
        }

        let immediateText = instruction.operands[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let imm8: UInt8
        if kind == .fmov {
            let value = try A64Parser.floatImmediate(immediateText)
            guard let encoded = A64FloatImmediate.encode(value) else { throw AssemblerError.invalidImmediate(immediateText) }
            imm8 = UInt8(encoded & 0xff)
        } else if destination.arrangement == .d1 || destination.arrangement == .d2 {
            // 64-bit `movi`: each source byte must be all-zero or all-one.
            let value = try A64Parser.unsignedImmediate64(immediateText)
            var encoded: UInt8 = 0
            for index in 0..<8 {
                let byte = (value >> (index * 8)) & 0xff
                if byte == 0xff { encoded |= UInt8(1 << index) }
                else if byte != 0 { throw AssemblerError.invalidImmediate(immediateText) }
            }
            imm8 = encoded
        } else {
            let value = try A64Parser.immediate(immediateText)
            try checkRange(value, 0...255, instruction: kind.rawValue)
            imm8 = UInt8(value)
        }

        return .vectorModifiedImmediate(kind, destination: destination, imm8: imm8, shift: shift)
    }

    static func vectorShiftImmediate(_ instruction: ParsedInstruction, kind: A64.VectorShiftImmediateKind) throws -> Instruction {
        try expectOperandCount(instruction, exactly: 3)
        return .vectorShiftImmediate(
            kind,
            destination: try A64Parser.vectorRegister(instruction.operands[0]),
            source: try A64Parser.vectorRegister(instruction.operands[1]),
            shift: Int(try A64Parser.immediate(instruction.operands[2]))
        )
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
