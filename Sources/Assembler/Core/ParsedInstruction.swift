internal struct ParsedInstruction: Equatable {
    var mnemonic: String
    var operands: [String]
    var original: String
}

internal struct ParsedProgram: Equatable {
    var labels: [String: Int64]
    var instructions: [ParsedInstruction]
}
