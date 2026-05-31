import Foundation

internal func encodeInstruction(_ instruction: ParsedInstruction, pc: Int64, labels: [String: Int64], architecture: ARM64Assembler.Architecture) throws -> UInt32 {
    if let structuredInstruction = try A64InstructionParser.instruction(instruction, pc: pc, labels: labels, architecture: architecture) {
        return try A64InstructionEncoder.encode(structuredInstruction)
    }

    throw AssemblerError.unknownInstruction(instruction.mnemonic)
}

internal func encode(_ instruction: ParsedInstruction, pc: Int64, labels: [String: Int64], architecture: ARM64Assembler.Architecture) throws -> UInt32 {
    try A64InstructionEncoder.encode(instruction, pc: pc, labels: labels, architecture: architecture)
}

internal func requireARM64E(_ architecture: ARM64Assembler.Architecture, instruction: String) throws {
    guard architecture == .arm64e else { throw AssemblerError.unknownInstruction("\(instruction) requires arm64e") }
}

internal func expectOperandCount(_ instruction: ParsedInstruction, exactly count: Int) throws {
    guard instruction.operands.count == count else {
        throw AssemblerError.invalidOperandCount(instruction: instruction.mnemonic, expected: "\(count)", actual: instruction.operands.count)
    }
}

internal func expectOperandCount(_ instruction: ParsedInstruction, _ range: ClosedRange<Int>) throws {
    guard range.contains(instruction.operands.count) else {
        throw AssemblerError.invalidOperandCount(instruction: instruction.mnemonic, expected: "\(range.lowerBound)...\(range.upperBound)", actual: instruction.operands.count)
    }
}

internal func checkRange(_ value: Int64, _ range: ClosedRange<Int64>, instruction: String) throws {
    guard range.contains(value) else { throw AssemblerError.immediateOutOfRange(instruction: instruction, value: value, range: range) }
}

internal func zeroRegister(width: Int) -> IntegerRegister {
    IntegerRegister(number: 31, width: width, kind: .zero)
}

internal func labelOrImmediateByteOffset(_ text: String, pc: Int64, labels: [String: Int64]) throws -> Int64 {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let target = labels[trimmed] { return target - pc }
    return try A64Parser.immediate(trimmed)
}
