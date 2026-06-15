import Foundation

internal enum X86Support {
    /// Verify that `value` falls within `range`, throwing `immediateOutOfRange`
    /// with the supplied mnemonic otherwise. Mirrors `A64Support.checkRange`.
    static func checkRange(_ value: Int64, _ range: ClosedRange<Int64>, instruction: String) throws {
        guard range.contains(value) else {
            throw AssemblerError.immediateOutOfRange(instruction: instruction, value: value, range: range)
        }
    }
}
