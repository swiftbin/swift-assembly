import XCTest
@testable import Assembly

final class X86AssemblerTests: XCTestCase {
    // MARK: - Phase 0 pipeline

    func testNopAssemblesToSingleByte() throws {
        XCTAssertEqual(try X86Assembler.assemble("nop"), [0x90])
    }

    func testNopDisassemblesFromSingleByte() throws {
        XCTAssertEqual(try X86Assembler.disassemble([0x90]), "nop")
    }

    func testMultipleNopsRoundTrip() throws {
        let bytes = try X86Assembler.assemble("""
        nop
        nop
        nop
        """)
        XCTAssertEqual(bytes, [0x90, 0x90, 0x90])
        XCTAssertEqual(try X86Assembler.disassemble(bytes), "nop\nnop\nnop")
    }

    func testUnknownMnemonicThrows() {
        XCTAssertThrowsError(try X86Assembler.assemble("frobnicate")) { error in
            guard case AssemblerError.unknownInstruction(let name) = error else {
                return XCTFail("expected unknownInstruction, got \(error)")
            }
            XCTAssertEqual(name, "frobnicate")
        }
    }

    func testUnknownEncodingThrows() {
        XCTAssertThrowsError(try X86Assembler.disassemble([0xFF])) { error in
            guard case AssemblerError.unknownEncoding = error else {
                return XCTFail("expected unknownEncoding, got \(error)")
            }
        }
    }

    func testNopRejectsOperands() {
        XCTAssertThrowsError(try X86Assembler.assemble("nop rax")) { error in
            guard case AssemblerError.invalidOperandCount = error else {
                return XCTFail("expected invalidOperandCount, got \(error)")
            }
        }
    }

    // MARK: - Phase 1 zero-operand family

    /// Canonical mnemonic → encoding. Cross-checked against the Intel SDM
    /// volume 2 opcode tables for x86-64 long mode.
    private static let zeroOperandCases: [(String, [UInt8])] = [
        ("ret",     [0xC3]),
        ("retf",    [0xCB]),
        ("iret",    [0x66, 0xCF]),
        ("iretd",   [0xCF]),
        ("iretq",   [0x48, 0xCF]),
        ("leave",   [0xC9]),
        ("int3",    [0xCC]),
        ("ud2",     [0x0F, 0x0B]),
        ("clc",     [0xF8]),
        ("stc",     [0xF9]),
        ("cmc",     [0xF5]),
        ("cld",     [0xFC]),
        ("std",     [0xFD]),
        ("cli",     [0xFA]),
        ("sti",     [0xFB]),
        ("lahf",    [0x9F]),
        ("sahf",    [0x9E]),
        ("pause",   [0xF3, 0x90]),
        ("hlt",     [0xF4]),
        ("wait",    [0x9B]),
        ("xlatb",   [0xD7]),
        ("syscall", [0x0F, 0x05]),
        ("sysret",  [0x0F, 0x07]),
        ("sysretq", [0x48, 0x0F, 0x07]),
        ("swapgs",  [0x0F, 0x01, 0xF8]),
        ("cpuid",   [0x0F, 0xA2]),
        ("rdtsc",   [0x0F, 0x31]),
        ("rdtscp",  [0x0F, 0x01, 0xF9]),
        ("rdmsr",   [0x0F, 0x32]),
        ("wrmsr",   [0x0F, 0x30]),
        ("rdpmc",   [0x0F, 0x33]),
        ("monitor", [0x0F, 0x01, 0xC8]),
        ("mwait",   [0x0F, 0x01, 0xC9]),
    ]

    func testZeroOperandInstructionsAssemble() throws {
        for (mnemonic, expected) in Self.zeroOperandCases {
            XCTAssertEqual(
                try X86Assembler.assemble(mnemonic),
                expected,
                "assemble \(mnemonic)"
            )
        }
    }

    func testZeroOperandInstructionsDisassemble() throws {
        for (mnemonic, bytes) in Self.zeroOperandCases {
            XCTAssertEqual(
                try X86Assembler.disassemble(bytes),
                mnemonic,
                "disassemble \(bytes.map { String($0, radix: 16) })"
            )
        }
    }

    /// Round-trip the entire family glued together, exercising the byte
    /// cursor across boundaries (especially the prefix-sharing cases:
    /// `90 / F3 90`, `CF / 66 CF / 48 CF`, `0F 07 / 48 0F 07`).
    func testZeroOperandStreamRoundTrip() throws {
        let mnemonics = Self.zeroOperandCases.map(\.0)
        let source = mnemonics.joined(separator: "\n")
        let expected = Self.zeroOperandCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    /// Surface-level aliases fold onto their canonical mnemonic.
    func testZeroOperandAliasesFoldToCanonical() throws {
        XCTAssertEqual(try X86Assembler.assemble("fwait"), [0x9B])
        XCTAssertEqual(try X86Assembler.disassemble([0x9B]), "wait")
        XCTAssertEqual(try X86Assembler.assemble("xlat"), [0xD7])
        XCTAssertEqual(try X86Assembler.disassemble([0xD7]), "xlatb")
    }

    /// `48 CF` must decode as `iretq`, not as a REX-prefixed `iretd`.
    func testPrefixSharingDecodesToLongestMatch() throws {
        XCTAssertEqual(try X86Assembler.disassemble([0x48, 0xCF]), "iretq")
        XCTAssertEqual(try X86Assembler.disassemble([0xCF]), "iretd")
        XCTAssertEqual(try X86Assembler.disassemble([0x66, 0xCF]), "iret")

        XCTAssertEqual(try X86Assembler.disassemble([0x48, 0x0F, 0x07]), "sysretq")
        XCTAssertEqual(try X86Assembler.disassemble([0x0F, 0x07]), "sysret")

        XCTAssertEqual(try X86Assembler.disassemble([0xF3, 0x90]), "pause")
        XCTAssertEqual(try X86Assembler.disassemble([0x90]), "nop")
    }

    func testZeroOperandRejectsOperands() {
        XCTAssertThrowsError(try X86Assembler.assemble("ret rax")) { error in
            guard case AssemblerError.invalidOperandCount = error else {
                return XCTFail("expected invalidOperandCount, got \(error)")
            }
        }
    }
}
