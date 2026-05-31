import Foundation

public enum AssemblerError: Error, Equatable, CustomStringConvertible {
    case emptyInput
    case unknownInstruction(String)
    case invalidOperandCount(instruction: String, expected: String, actual: Int)
    case invalidRegister(String)
    case invalidImmediate(String)
    case immediateOutOfRange(instruction: String, value: Int64, range: ClosedRange<Int64>)
    case immediateAlignment(instruction: String, value: Int64, alignment: Int64)
    case unsupportedOperand(String)
    case invalidMemoryOperand(String)
    case unsupportedShift(String)
    case unsupportedExtend(String)
    case unsupportedCondition(String)
    case labelNotFound(String)
    case branchOutOfRange(instruction: String, label: String, byteOffset: Int64)
    case invalidByteCount(Int)
    case unknownEncoding(UInt32)

    public var description: String {
        switch self {
        case .emptyInput: return "Input is empty."
        case .unknownInstruction(let name): return "Unknown instruction: \(name)"
        case .invalidOperandCount(let instruction, let expected, let actual):
            return "Invalid operand count for \(instruction): expected \(expected), actual \(actual)."
        case .invalidRegister(let text): return "Invalid register: \(text)"
        case .invalidImmediate(let text): return "Invalid immediate: \(text)"
        case .immediateOutOfRange(let instruction, let value, let range):
            return "Immediate out of range for \(instruction): \(value), allowed \(range.lowerBound)...\(range.upperBound)."
        case .immediateAlignment(let instruction, let value, let alignment):
            return "Immediate for \(instruction) must be aligned to \(alignment): \(value)."
        case .unsupportedOperand(let text): return "Unsupported operand: \(text)"
        case .invalidMemoryOperand(let text): return "Invalid memory operand: \(text)"
        case .unsupportedShift(let text): return "Unsupported shift: \(text)"
        case .unsupportedExtend(let text): return "Unsupported extend: \(text)"
        case .unsupportedCondition(let text): return "Unsupported condition: \(text)"
        case .labelNotFound(let label): return "Label not found: \(label)"
        case .branchOutOfRange(let instruction, let label, let byteOffset):
            return "Branch target out of range for \(instruction) to \(label): byte offset \(byteOffset)."
        case .invalidByteCount(let count):
            return "Byte input length must be a multiple of 4, got \(count)."
        case .unknownEncoding(let word):
            return "Unknown instruction encoding: 0x\(String(word, radix: 16))."
        }
    }
}

