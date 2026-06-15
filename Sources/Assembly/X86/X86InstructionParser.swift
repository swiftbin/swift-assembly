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
        throw AssemblerError.unknownInstruction(instruction.mnemonic)
    }

    // MARK: - MOV

    private static func parseMov(_ instruction: ParsedInstruction) throws -> X86.Instruction {
        guard instruction.operands.count == 2 else {
            throw AssemblerError.invalidOperandCount(
                instruction: "mov",
                expected: "2 operands",
                actual: instruction.operands.count
            )
        }
        let destination = try register(instruction.operands[0])
        if let source = try? register(instruction.operands[1]) {
            guard source.width == destination.width else {
                throw AssemblerError.unsupportedOperand(
                    "mov requires matching operand widths (\(destination.widthSuffix) vs \(source.widthSuffix))"
                )
            }
            return .mov(destination: destination, source: .register(source))
        }
        let immediate = try immediateAny(instruction.operands[1])
        try validateImmediateRange(immediate, width: destination.width, mnemonic: "mov")
        return .mov(destination: destination, source: .immediate(immediate))
    }

    // MARK: - Operand parsing

    static func register(_ text: String) throws -> X86.Register {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let register = X86.RegisterTable.lookup[key] {
            return register
        }
        throw AssemblerError.invalidRegister(text)
    }

    /// Parse an immediate that may be written as either a signed or unsigned
    /// integer literal up to 64 bits wide. Returns the bit pattern as `Int64`.
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

    /// Verify that `value` (taken as a bit pattern) fits the destination width
    /// when interpreted as either signed or unsigned.
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
            break // any Int64 bit pattern is valid
        }
    }
}
