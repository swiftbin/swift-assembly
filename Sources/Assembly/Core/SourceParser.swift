import Foundation

internal enum SourceParser {
    static func program(_ source: String) throws -> ParsedProgram {
        var labels: [String: Int64] = [:]
        var instructions: [ParsedInstruction] = []

        for rawLine in source.components(separatedBy: .newlines) {
            var line = stripComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            while let colonIndex = labelColonIndex(in: line) {
                let label = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty { labels[label] = Int64(instructions.count * 4) }
                line = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { break }
            }

            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard let first = parts.first else { continue }
            instructions.append(
                ParsedInstruction(
                    mnemonic: String(first).lowercased(),
                    operands: parts.count == 2 ? splitOperands(String(parts[1])) : [],
                    original: line
                )
            )
        }

        guard !instructions.isEmpty else { throw AssemblerError.emptyInput }
        return ParsedProgram(labels: labels, instructions: instructions)
    }

    static func stripComment(_ line: String) -> String {
        var depth = 0
        for index in line.indices {
            let ch = line[index]
            if ch == "[" { depth += 1 }
            if ch == "]" { depth = max(0, depth - 1) }
            if depth == 0 {
                if ch == ";" { return String(line[..<index]) }
                if ch == "/", line.index(after: index) < line.endIndex, line[line.index(after: index)] == "/" {
                    return String(line[..<index])
                }
            }
        }
        return line
    }

    static func labelColonIndex(in line: String) -> String.Index? {
        var depth = 0
        for index in line.indices {
            let ch = line[index]
            if ch == "[" { depth += 1 }
            if ch == "]" { depth = max(0, depth - 1) }
            if depth == 0, ch == ":" { return index }
            if depth == 0, ch.isWhitespace { return nil }
        }
        return nil
    }

    static func splitOperands(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0

        for ch in text {
            switch ch {
            case "[":
                depth += 1
                current.append(ch)
            case "]":
                depth = max(0, depth - 1)
                current.append(ch)
            case "," where depth == 0:
                let operand = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !operand.isEmpty { result.append(operand) }
                current.removeAll(keepingCapacity: true)
            default:
                current.append(ch)
            }
        }

        let operand = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !operand.isEmpty { result.append(operand) }
        return result
    }
}

