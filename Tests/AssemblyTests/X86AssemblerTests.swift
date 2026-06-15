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
            XCTAssertEqual(try X86Assembler.assemble(mnemonic), expected, "assemble \(mnemonic)")
        }
    }

    func testZeroOperandInstructionsDisassemble() throws {
        for (mnemonic, bytes) in Self.zeroOperandCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), mnemonic, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testZeroOperandStreamRoundTrip() throws {
        let mnemonics = Self.zeroOperandCases.map(\.0)
        let source = mnemonics.joined(separator: "\n")
        let expected = Self.zeroOperandCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    func testZeroOperandAliasesFoldToCanonical() throws {
        XCTAssertEqual(try X86Assembler.assemble("fwait"), [0x9B])
        XCTAssertEqual(try X86Assembler.disassemble([0x9B]), "wait")
        XCTAssertEqual(try X86Assembler.assemble("xlat"), [0xD7])
        XCTAssertEqual(try X86Assembler.disassemble([0xD7]), "xlatb")
    }

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

    // MARK: - Phase 2 MOV register/register

    private static let movRegisterCases: [(String, [UInt8])] = [
        // 8-bit, no REX
        ("mov al, bl",  [0x88, 0xD8]),
        ("mov ah, bh",  [0x88, 0xFC]),
        // 16-bit
        ("mov ax, bx",  [0x66, 0x89, 0xD8]),
        ("mov cx, dx",  [0x66, 0x89, 0xD1]),
        // 32-bit
        ("mov eax, ebx", [0x89, 0xD8]),
        ("mov ecx, edx", [0x89, 0xD1]),
        // 64-bit
        ("mov rax, rbx", [0x48, 0x89, 0xD8]),
        ("mov rcx, rdx", [0x48, 0x89, 0xD1]),
        // REX.B (destination extended)
        ("mov r8, rax",  [0x49, 0x89, 0xC0]),
        // REX.R (source extended)
        ("mov rax, r8",  [0x4C, 0x89, 0xC0]),
        // REX.R + REX.B
        ("mov r8, r9",   [0x4D, 0x89, 0xC8]),
        // REX-forced byte registers
        ("mov dil, sil", [0x40, 0x88, 0xF7]),
        // r8b/r15b
        ("mov r8b, r9b", [0x45, 0x88, 0xC8]),
    ]

    func testMovRegisterRegisterAssembles() throws {
        for (source, expected) in Self.movRegisterCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testMovRegisterRegisterDisassembles() throws {
        for (source, bytes) in Self.movRegisterCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// The RM form (8B /r) decodes to the same instruction as the canonical
    /// MR form (89 /r), but the encoder always chooses MR — so re-assembly
    /// produces the canonical bytes, not the original RM ones.
    func testMovRegisterRegisterRMFormDecodes() throws {
        // `8B C8` = MOV ECX, EAX (RM form: reg=ECX(1), rm=EAX(0))
        XCTAssertEqual(try X86Assembler.disassemble([0x8B, 0xC8]), "mov ecx, eax")
        XCTAssertEqual(try X86Assembler.assemble("mov ecx, eax"), [0x89, 0xC1])
    }

    func testMovRegisterRegisterWidthMismatch() {
        XCTAssertThrowsError(try X86Assembler.assemble("mov al, ebx")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    /// AH/BH/CH/DH cannot appear in the same instruction as a register that
    /// requires a REX prefix (R8..R15 or SPL/BPL/SIL/DIL).
    func testMovHighByteWithREXByteRejected() {
        XCTAssertThrowsError(try X86Assembler.assemble("mov ah, dil")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("mov ah, r8b")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    // MARK: - Phase 2 MOV register/immediate

    private static let movImmediateCases: [(String, [UInt8])] = [
        // 8-bit immediate (B0+r ib)
        ("mov al, 5",    [0xB0, 0x05]),
        ("mov bl, 255",  [0xB3, 0xFF]),
        ("mov dil, 1",   [0x40, 0xB7, 0x01]),
        ("mov r8b, 7",   [0x41, 0xB0, 0x07]),

        // 16-bit (66 + B8+r iw)
        ("mov ax, 4660",   [0x66, 0xB8, 0x34, 0x12]),
        ("mov r8w, 1",     [0x66, 0x41, 0xB8, 0x01, 0x00]),

        // 32-bit (B8+r id) — operand zero-extends to r64 in hardware
        ("mov eax, 5",          [0xB8, 0x05, 0x00, 0x00, 0x00]),
        ("mov ecx, 3735928559", [0xB9, 0xEF, 0xBE, 0xAD, 0xDE]), // 0xDEADBEEF
        ("mov r8d, 1",          [0x41, 0xB8, 0x01, 0x00, 0x00, 0x00]),

        // 64-bit short form (REX.W C7 /0 id) when imm fits Int32
        ("mov rax, 0",   [0x48, 0xC7, 0xC0, 0x00, 0x00, 0x00, 0x00]),
        ("mov rax, -1",  [0x48, 0xC7, 0xC0, 0xFF, 0xFF, 0xFF, 0xFF]),
        ("mov r8, 1",    [0x49, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00]),
        ("mov r15, -1",  [0x49, 0xC7, 0xC7, 0xFF, 0xFF, 0xFF, 0xFF]),

        // 64-bit long form (REX.W B8+rd io) when imm exceeds Int32 range
        ("mov rax, 4294967296",
            [0x48, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]),
        ("mov rcx, 2147483648",
            [0x48, 0xB9, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00]),
    ]

    func testMovImmediateAssembles() throws {
        for (source, expected) in Self.movImmediateCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testMovImmediateDisassembles() throws {
        for (source, bytes) in Self.movImmediateCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `C6 /0` and `C7 /0` are valid alternates to the `B0+/B8+` short forms
    /// for register destinations; the decoder accepts them, and the encoder
    /// canonicalises to the shorter B-prefixed form.
    func testMovImmediateMIFormDecodes() throws {
        // C6 C0 05 = MOV AL, 5 (alternate to B0 05)
        XCTAssertEqual(try X86Assembler.disassemble([0xC6, 0xC0, 0x05]), "mov al, 5")
        // C7 C0 05 00 00 00 = MOV EAX, 5 (alternate to B8 05 00 00 00)
        XCTAssertEqual(try X86Assembler.disassemble([0xC7, 0xC0, 0x05, 0x00, 0x00, 0x00]), "mov eax, 5")
    }

    /// Hex-typed unsigned 64-bit literals round-trip via the canonical signed
    /// form (`-1 == 0xFFFFFFFFFFFFFFFF`). The bytes are the C7 short form.
    func testMovImmediateUnsignedQwordCanonicalisesToShort() throws {
        let bytes = try X86Assembler.assemble("mov rax, 0xFFFFFFFFFFFFFFFF")
        XCTAssertEqual(bytes, [0x48, 0xC7, 0xC0, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(try X86Assembler.disassemble(bytes), "mov rax, -1")
    }

    /// `mov r32, imm` zero-extends to the 64-bit destination in hardware; the
    /// signed input `-1` and the unsigned input `0xFFFFFFFF` are byte-identical.
    func testMovImmediate32ZeroExtendsAcrossSign() throws {
        let signed = try X86Assembler.assemble("mov eax, -1")
        let unsigned = try X86Assembler.assemble("mov eax, 4294967295")
        XCTAssertEqual(signed, [0xB8, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(signed, unsigned)
        XCTAssertEqual(try X86Assembler.disassemble(signed), "mov eax, 4294967295")
    }

    func testMovImmediateOutOfRangeForByte() {
        XCTAssertThrowsError(try X86Assembler.assemble("mov al, 256")) { error in
            guard case AssemblerError.immediateOutOfRange = error else {
                return XCTFail("expected immediateOutOfRange, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("mov al, -129")) { error in
            guard case AssemblerError.immediateOutOfRange = error else {
                return XCTFail("expected immediateOutOfRange, got \(error)")
            }
        }
    }

    /// Pipeline-level round-trip: encode a multi-instruction MOV program,
    /// then disassemble and re-assemble it, expecting byte equality.
    func testMovRoundTripStream() throws {
        let source = """
        mov rax, 1
        mov rbx, rax
        mov ecx, 4660
        mov r8, -1
        mov dil, 7
        """
        let bytes = try X86Assembler.assemble(source)
        let text = try X86Assembler.disassemble(bytes)
        XCTAssertEqual(try X86Assembler.assemble(text), bytes)
    }
}
