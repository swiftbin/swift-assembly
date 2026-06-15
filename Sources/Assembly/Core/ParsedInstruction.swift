internal struct ParsedInstruction: Equatable {
    var mnemonic: String
    var operands: [String]
    var original: String
}

internal struct ParsedProgram: Equatable {
    /// Maps each label name to the index of the instruction it precedes
    /// in `instructions`. A label sitting at end-of-file has the index
    /// `instructions.count`. Architecture-specific assemblers translate
    /// these indexes into byte offsets according to their own size
    /// model (A64: index * 4, X86: cumulative variable lengths).
    var labels: [String: Int]
    var instructions: [ParsedInstruction]
}
