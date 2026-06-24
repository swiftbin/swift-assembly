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
        // 0x60 (legacy PUSHA) is invalid in long mode and not yet implemented;
        // an unhandled primary opcode reports `unknownEncoding`.
        XCTAssertThrowsError(try X86Assembler.disassemble([0x60])) { error in
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

    // MARK: - Phase 3 MOV r, [mem] / MOV [mem], r

    private static let movMemoryCases: [(String, [UInt8])] = [
        // Plain [base]
        ("mov rax, [rbx]",  [0x48, 0x8B, 0x03]),
        ("mov rax, [rsp]",  [0x48, 0x8B, 0x04, 0x24]),
        ("mov rax, [rbp]",  [0x48, 0x8B, 0x45, 0x00]),
        ("mov rax, [r8]",   [0x49, 0x8B, 0x00]),
        ("mov rax, [r12]",  [0x49, 0x8B, 0x04, 0x24]),
        ("mov rax, [r13]",  [0x49, 0x8B, 0x45, 0x00]),
        ("mov rax, [r15]",  [0x49, 0x8B, 0x07]),

        // Plain [base + disp8]
        ("mov rax, [rbx + 1]",   [0x48, 0x8B, 0x43, 0x01]),
        ("mov rax, [rbx - 1]",   [0x48, 0x8B, 0x43, 0xFF]),
        ("mov rax, [rsp + 8]",   [0x48, 0x8B, 0x44, 0x24, 0x08]),
        ("mov rax, [rbp + 8]",   [0x48, 0x8B, 0x45, 0x08]),
        ("mov rax, [r13 + 16]",  [0x49, 0x8B, 0x45, 0x10]),

        // Plain [base + disp32]
        ("mov rax, [rbx + 256]",  [0x48, 0x8B, 0x83, 0x00, 0x01, 0x00, 0x00]),
        ("mov rax, [rbx - 256]",  [0x48, 0x8B, 0x83, 0x00, 0xFF, 0xFF, 0xFF]),

        // SIB: base + index*scale, no displacement
        ("mov rax, [rbx + rcx]",       [0x48, 0x8B, 0x04, 0x0B]),
        ("mov rax, [rbx + rcx*2]",     [0x48, 0x8B, 0x04, 0x4B]),
        ("mov rax, [rbx + rcx*4]",     [0x48, 0x8B, 0x04, 0x8B]),
        ("mov rax, [rbx + rcx*8]",     [0x48, 0x8B, 0x04, 0xCB]),
        ("mov rax, [rbx + rcx*8 + 16]", [0x48, 0x8B, 0x44, 0xCB, 0x10]),
        ("mov rax, [rbx + rcx*8 + 4096]",
            [0x48, 0x8B, 0x84, 0xCB, 0x00, 0x10, 0x00, 0x00]),

        // SIB with extended registers (R8..R15)
        ("mov rax, [r8 + r9]",          [0x4B, 0x8B, 0x04, 0x08]),
        ("mov rax, [r12 + r13*4]",      [0x4B, 0x8B, 0x04, 0xAC]),
        ("mov r10, [r11 + r12*8 + 16]", [0x4F, 0x8B, 0x54, 0xE3, 0x10]),

        // RIP-relative
        ("mov rax, [rip]",       [0x48, 0x8B, 0x05, 0x00, 0x00, 0x00, 0x00]),
        ("mov rax, [rip + 16]",  [0x48, 0x8B, 0x05, 0x10, 0x00, 0x00, 0x00]),
        ("mov rax, [rip - 8]",   [0x48, 0x8B, 0x05, 0xF8, 0xFF, 0xFF, 0xFF]),

        // Absolute [disp32] and index-only forms
        ("mov rax, [4096]",          [0x48, 0x8B, 0x04, 0x25, 0x00, 0x10, 0x00, 0x00]),
        ("mov rax, [rcx*4]",         [0x48, 0x8B, 0x04, 0x8D, 0x00, 0x00, 0x00, 0x00]),
        ("mov rax, [rcx*4 + 16]",    [0x48, 0x8B, 0x04, 0x8D, 0x10, 0x00, 0x00, 0x00]),

        // Different widths
        ("mov al, [rbx]",   [0x8A, 0x03]),
        ("mov ax, [rbx]",   [0x66, 0x8B, 0x03]),
        ("mov eax, [rbx]",  [0x8B, 0x03]),

        // MR direction (memory destination)
        ("mov [rbx], rax",         [0x48, 0x89, 0x03]),
        ("mov [rsp + 8], rax",     [0x48, 0x89, 0x44, 0x24, 0x08]),
        ("mov [rip + 16], rax",    [0x48, 0x89, 0x05, 0x10, 0x00, 0x00, 0x00]),
        ("mov [rsi], al",          [0x88, 0x06]),
        ("mov [rdi + 16], bl",     [0x88, 0x5F, 0x10]),
    ]

    func testMovMemoryAssembles() throws {
        for (source, expected) in Self.movMemoryCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testMovMemoryDisassembles() throws {
        for (source, bytes) in Self.movMemoryCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `[rax*1]` canonicalises to `[rax]` because the scale-1 index with no
    /// base is identical to a bare base — the parser preserves user intent
    /// but the encoder picks the shorter form.
    func testMovMemoryScaleOneIndexCanonicalisesToBase() throws {
        let bytes = try X86Assembler.assemble("mov rax, [rcx*1]")
        XCTAssertEqual(bytes, [0x48, 0x8B, 0x01]) // == mov rax, [rcx]
        XCTAssertEqual(try X86Assembler.disassemble(bytes), "mov rax, [rcx]")
    }

    func testMovMemoryRSPCannotBeIndex() {
        XCTAssertThrowsError(try X86Assembler.assemble("mov rax, [rbx + rsp*2]")) { error in
            guard case AssemblerError.invalidMemoryOperand = error else {
                return XCTFail("expected invalidMemoryOperand, got \(error)")
            }
        }
    }

    func testMovMemoryInvalidScaleRejected() {
        XCTAssertThrowsError(try X86Assembler.assemble("mov rax, [rbx + rcx*3]")) { error in
            guard case AssemblerError.invalidMemoryOperand = error else {
                return XCTFail("expected invalidMemoryOperand, got \(error)")
            }
        }
    }

    func testMovMemoryAddressSizeMustBe64Bit() {
        XCTAssertThrowsError(try X86Assembler.assemble("mov rax, [ebx]")) { error in
            guard case AssemblerError.invalidMemoryOperand = error else {
                return XCTFail("expected invalidMemoryOperand, got \(error)")
            }
        }
    }

    /// Pipeline-level round-trip across the full set, exercising the byte
    /// cursor across encodings of varying length.
    func testMovMemoryRoundTripStream() throws {
        let source = Self.movMemoryCases.map(\.0).joined(separator: "\n")
        let expected = Self.movMemoryCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 4a MOV mem, imm + size hint

    private static let movMemImmCases: [(String, [UInt8])] = [
        // byte: C6 /0 ib
        ("mov byte ptr [rbx], 5",        [0xC6, 0x03, 0x05]),
        ("mov byte ptr [rbx + 4], 255",  [0xC6, 0x43, 0x04, 0xFF]),
        // word: 66 C7 /0 iw
        ("mov word ptr [rbx], 4660",     [0x66, 0xC7, 0x03, 0x34, 0x12]),
        // dword: C7 /0 id
        ("mov dword ptr [rbx], 256",     [0xC7, 0x03, 0x00, 0x01, 0x00, 0x00]),
        // qword: REX.W C7 /0 id (sign-extended)
        ("mov qword ptr [rbx], 0",       [0x48, 0xC7, 0x03, 0x00, 0x00, 0x00, 0x00]),
        ("mov qword ptr [rbx], -1",      [0x48, 0xC7, 0x03, 0xFF, 0xFF, 0xFF, 0xFF]),
        // RIP-relative
        ("mov qword ptr [rip + 16], 1",
            [0x48, 0xC7, 0x05, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]),
    ]

    func testMovMemImmAssembles() throws {
        for (source, expected) in Self.movMemImmCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testMovMemImmDisassembles() throws {
        for (source, bytes) in Self.movMemImmCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `mov [mem], imm` without a size hint is ambiguous and must be rejected.
    func testMovMemImmRequiresSizeHint() {
        XCTAssertThrowsError(try X86Assembler.assemble("mov [rbx], 5")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    /// A size hint that disagrees with the paired register is an error.
    func testMovSizeHintMismatchRejected() {
        XCTAssertThrowsError(try X86Assembler.assemble("mov eax, qword ptr [rbx]")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("mov byte ptr [rbx], rax")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    /// `qword ptr` with imm32-range value is fine; with an out-of-range
    /// value it errors (C7 /0 id is sign-extended only).
    func testMovQwordMemImmRangeCheck() {
        XCTAssertNoThrow(try X86Assembler.assemble("mov qword ptr [rbx], 2147483647"))
        XCTAssertThrowsError(try X86Assembler.assemble("mov qword ptr [rbx], 4294967296")) { error in
            guard case AssemblerError.immediateOutOfRange = error else {
                return XCTFail("expected immediateOutOfRange, got \(error)")
            }
        }
    }

    /// A size hint paired with a register is harmless when widths agree.
    func testMovSizeHintAgreesWithRegister() throws {
        XCTAssertEqual(try X86Assembler.assemble("mov qword ptr [rbx], rax"), [0x48, 0x89, 0x03])
        XCTAssertEqual(try X86Assembler.assemble("mov rax, qword ptr [rbx]"), [0x48, 0x8B, 0x03])
    }

    // MARK: - Phase 4b binary ALU (ADD/OR/ADC/SBB/AND/SUB/XOR/CMP)

    private static let binaryAluCases: [(String, [UInt8])] = [
        // ADD reg, reg across widths
        ("add al, bl",    [0x00, 0xD8]),
        ("add ax, bx",    [0x66, 0x01, 0xD8]),
        ("add eax, ebx",  [0x01, 0xD8]),
        ("add rax, rbx",  [0x48, 0x01, 0xD8]),
        ("add r8, r9",    [0x4D, 0x01, 0xC8]),

        // reg, mem / mem, reg
        ("add rax, [rbx]",     [0x48, 0x03, 0x03]),
        ("add [rbx], rax",     [0x48, 0x01, 0x03]),
        ("add eax, [rbx + 8]", [0x03, 0x43, 0x08]),

        // 83 form (sign-extended imm8) — chosen whenever imm fits Int8 and dst is non-byte
        ("add eax, 1",   [0x83, 0xC0, 0x01]),
        ("add ecx, 1",   [0x83, 0xC1, 0x01]),
        ("add rax, 1",   [0x48, 0x83, 0xC0, 0x01]),
        ("add rcx, -1",  [0x48, 0x83, 0xC1, 0xFF]),
        ("add ax, 1",    [0x66, 0x83, 0xC0, 0x01]),

        // Accumulator short form — chosen when dst is rAX and imm doesn't fit Int8
        ("add al, 5",       [0x04, 0x05]),
        ("add ax, 4660",    [0x66, 0x05, 0x34, 0x12]),
        ("add eax, 4096",   [0x05, 0x00, 0x10, 0x00, 0x00]),
        ("add rax, 4096",   [0x48, 0x05, 0x00, 0x10, 0x00, 0x00]),

        // 80/81 MI form — non-accumulator, imm doesn't fit Int8
        ("add bl, 5",     [0x80, 0xC3, 0x05]),
        ("add bx, 4660",  [0x66, 0x81, 0xC3, 0x34, 0x12]),
        ("add ecx, 4096", [0x81, 0xC1, 0x00, 0x10, 0x00, 0x00]),
        ("add rcx, 4096", [0x48, 0x81, 0xC1, 0x00, 0x10, 0x00, 0x00]),

        // mem, imm
        ("add byte ptr [rbx], 5",         [0x80, 0x03, 0x05]),
        ("add qword ptr [rbx], 1",        [0x48, 0x83, 0x03, 0x01]),
        ("add dword ptr [rbx], 1024",     [0x81, 0x03, 0x00, 0x04, 0x00, 0x00]),

        // Each of the other 7 families on the canonical reg, reg form
        ("or rax, rbx",  [0x48, 0x09, 0xD8]),
        ("adc rax, rbx", [0x48, 0x11, 0xD8]),
        ("sbb rax, rbx", [0x48, 0x19, 0xD8]),
        ("and rax, rbx", [0x48, 0x21, 0xD8]),
        ("sub rax, rbx", [0x48, 0x29, 0xD8]),
        ("xor rax, rbx", [0x48, 0x31, 0xD8]),
        ("cmp rax, rbx", [0x48, 0x39, 0xD8]),

        // Family-specific accumulator-imm sanity check
        ("xor eax, eax",  [0x31, 0xC0]),
        ("sub rax, -1",   [0x48, 0x83, 0xE8, 0xFF]),
        ("cmp eax, 4096", [0x3D, 0x00, 0x10, 0x00, 0x00]),
    ]

    func testBinaryAluAssembles() throws {
        for (source, expected) in Self.binaryAluCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testBinaryAluDisassembles() throws {
        for (source, bytes) in Self.binaryAluCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// The RM and MR forms produce identical text for register-to-register
    /// ops; the disassembler accepts both, the assembler canonicalises to MR.
    func testBinaryAluRMFormDecodes() throws {
        XCTAssertEqual(try X86Assembler.disassemble([0x03, 0xD8]), "add ebx, eax")
        XCTAssertEqual(try X86Assembler.assemble("add ebx, eax"), [0x01, 0xC3])
    }

    func testBinaryAluRoundTripStream() throws {
        let source = Self.binaryAluCases.map(\.0).joined(separator: "\n")
        let expected = Self.binaryAluCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    func testBinaryAluRejectsQwordImmediateOutOfInt32() {
        XCTAssertThrowsError(try X86Assembler.assemble("add rax, 4294967296")) { error in
            guard case AssemblerError.immediateOutOfRange = error else {
                return XCTFail("expected immediateOutOfRange, got \(error)")
            }
        }
    }

    // MARK: - Phase 4c unary ALU (INC/DEC/NEG/NOT) + TEST

    private static let unaryAluAndTestCases: [(String, [UInt8])] = [
        // INC / DEC across widths (FE/FF /0 and /1)
        ("inc al",   [0xFE, 0xC0]),
        ("inc ax",   [0x66, 0xFF, 0xC0]),
        ("inc eax",  [0xFF, 0xC0]),
        ("inc rax",  [0x48, 0xFF, 0xC0]),
        ("inc r8",   [0x49, 0xFF, 0xC0]),
        ("dec rax",  [0x48, 0xFF, 0xC8]),
        ("dec rcx",  [0x48, 0xFF, 0xC9]),
        ("inc qword ptr [rbx]",     [0x48, 0xFF, 0x03]),
        ("dec dword ptr [rbx + 8]", [0xFF, 0x4B, 0x08]),

        // NOT / NEG (F6/F7 /2 and /3)
        ("not rax",  [0x48, 0xF7, 0xD0]),
        ("neg rax",  [0x48, 0xF7, 0xD8]),
        ("not al",   [0xF6, 0xD0]),
        ("neg eax",  [0xF7, 0xD8]),
        ("not qword ptr [rbx]", [0x48, 0xF7, 0x13]),

        // TEST reg, reg
        ("test al, bl",   [0x84, 0xD8]),
        ("test ax, bx",   [0x66, 0x85, 0xD8]),
        ("test eax, ebx", [0x85, 0xD8]),
        ("test rax, rbx", [0x48, 0x85, 0xD8]),

        // TEST mem, reg (canonical MR-form direction)
        ("test [rbx], rax",     [0x48, 0x85, 0x03]),
        ("test [rbx + 8], eax", [0x85, 0x43, 0x08]),

        // TEST accumulator imm (A8/A9 short form)
        ("test al, 5",       [0xA8, 0x05]),
        ("test ax, 4660",    [0x66, 0xA9, 0x34, 0x12]),
        ("test eax, 1024",   [0xA9, 0x00, 0x04, 0x00, 0x00]),
        ("test rax, 1024",   [0x48, 0xA9, 0x00, 0x04, 0x00, 0x00]),

        // TEST general MI (F6/F7 /0) when dst is not the accumulator
        ("test bl, 5",                 [0xF6, 0xC3, 0x05]),
        ("test ecx, 1024",             [0xF7, 0xC1, 0x00, 0x04, 0x00, 0x00]),
        ("test rcx, 1",                [0x48, 0xF7, 0xC1, 0x01, 0x00, 0x00, 0x00]),
        ("test qword ptr [rbx], 1",    [0x48, 0xF7, 0x03, 0x01, 0x00, 0x00, 0x00]),
        ("test dword ptr [rbx], 256",  [0xF7, 0x03, 0x00, 0x01, 0x00, 0x00]),
    ]

    func testUnaryAluAndTestAssembles() throws {
        for (source, expected) in Self.unaryAluAndTestCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testUnaryAluAndTestDisassembles() throws {
        for (source, bytes) in Self.unaryAluAndTestCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `test reg, mem` canonicalises to `test mem, reg` on disassembly
    /// because TEST has no RM form — the MR form is the only available
    /// encoding, and it puts r/m (the memory) first.
    func testTestRegMemCanonicalisesToMemReg() throws {
        let bytes = try X86Assembler.assemble("test rax, [rbx]")
        XCTAssertEqual(bytes, [0x48, 0x85, 0x03])
        XCTAssertEqual(try X86Assembler.disassemble(bytes), "test [rbx], rax")
    }

    func testUnaryAluMemRequiresSizeHint() {
        XCTAssertThrowsError(try X86Assembler.assemble("inc [rbx]")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testUnaryAluRejectsImmediate() {
        XCTAssertThrowsError(try X86Assembler.assemble("inc 5")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testUnaryAluAndTestStreamRoundTrip() throws {
        let source = Self.unaryAluAndTestCases.map(\.0).joined(separator: "\n")
        let expected = Self.unaryAluAndTestCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 5 shifts and rotates

    private static let shiftCases: [(String, [UInt8])] = [
        // SHL (= /4) by 1 across widths
        ("shl al, 1",   [0xD0, 0xE0]),
        ("shl ax, 1",   [0x66, 0xD1, 0xE0]),
        ("shl eax, 1",  [0xD1, 0xE0]),
        ("shl rax, 1",  [0x48, 0xD1, 0xE0]),
        ("shl r8, 1",   [0x49, 0xD1, 0xE0]),

        // by CL
        ("shl al, cl",  [0xD2, 0xE0]),
        ("shl rax, cl", [0x48, 0xD3, 0xE0]),

        // by imm8
        ("shl al, 5",   [0xC0, 0xE0, 0x05]),
        ("shl rax, 5",  [0x48, 0xC1, 0xE0, 0x05]),
        ("shl rcx, 63", [0x48, 0xC1, 0xE1, 0x3F]),

        // All 7 shift kinds at qword by 1
        ("rol rax, 1", [0x48, 0xD1, 0xC0]),
        ("ror rax, 1", [0x48, 0xD1, 0xC8]),
        ("rcl rax, 1", [0x48, 0xD1, 0xD0]),
        ("rcr rax, 1", [0x48, 0xD1, 0xD8]),
        ("shl rax, 1", [0x48, 0xD1, 0xE0]),
        ("shr rax, 1", [0x48, 0xD1, 0xE8]),
        ("sar rax, 1", [0x48, 0xD1, 0xF8]),

        // Memory target (size hint required)
        ("shl qword ptr [rbx], 1",  [0x48, 0xD1, 0x23]),
        ("shl qword ptr [rbx], cl", [0x48, 0xD3, 0x23]),
        ("shl qword ptr [rbx], 5",  [0x48, 0xC1, 0x23, 0x05]),
    ]

    private static let doubleShiftCases: [(String, [UInt8])] = [
        ("shld rax, rbx, 4",   [0x48, 0x0F, 0xA4, 0xD8, 0x04]),
        ("shld rax, rbx, cl",  [0x48, 0x0F, 0xA5, 0xD8]),
        ("shrd rax, rbx, 4",   [0x48, 0x0F, 0xAC, 0xD8, 0x04]),
        ("shrd rax, rbx, cl",  [0x48, 0x0F, 0xAD, 0xD8]),
        ("shld eax, ebx, 4",   [0x0F, 0xA4, 0xD8, 0x04]),
        ("shld ax, bx, 4",     [0x66, 0x0F, 0xA4, 0xD8, 0x04]),
        ("shld [rbx], rcx, 4",
            [0x48, 0x0F, 0xA4, 0x0B, 0x04]),
    ]

    func testShiftAssembles() throws {
        for (source, expected) in Self.shiftCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testShiftDisassembles() throws {
        for (source, bytes) in Self.shiftCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testDoubleShiftAssembles() throws {
        for (source, expected) in Self.doubleShiftCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testDoubleShiftDisassembles() throws {
        for (source, bytes) in Self.doubleShiftCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `sal` is a synonym for `shl`; on disassembly the canonical mnemonic
    /// wins, but assembling either yields the same bytes.
    func testSalIsShlAlias() throws {
        XCTAssertEqual(try X86Assembler.assemble("sal rax, 1"), [0x48, 0xD1, 0xE0])
        XCTAssertEqual(try X86Assembler.disassemble([0x48, 0xD1, 0xE0]), "shl rax, 1")
    }

    /// C1 /4 with imm=1 is a non-canonical alternative to D1 /4. Decoding
    /// canonicalises it to the implicit `,1` form.
    func testShiftImmediateOneCanonicalisesToImplicit() throws {
        XCTAssertEqual(try X86Assembler.disassemble([0x48, 0xC1, 0xE0, 0x01]), "shl rax, 1")
        // Re-assembling the canonical text reaches the shorter D1 form.
        XCTAssertEqual(try X86Assembler.assemble("shl rax, 1"), [0x48, 0xD1, 0xE0])
    }

    func testShiftMemoryRequiresSizeHint() {
        XCTAssertThrowsError(try X86Assembler.assemble("shl [rbx], 1")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testDoubleShiftRejectsByOne() {
        // `shld rax, rbx, 1` is technically a literal-1 immediate, but
        // SHLD has no implicit-1 form. The parser routes a numeric 1 to
        // `.one`, which is rejected for SHLD/SHRD.
        XCTAssertThrowsError(try X86Assembler.assemble("shld rax, rbx, 1")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testShiftStreamRoundTrip() throws {
        let combined = Self.shiftCases + Self.doubleShiftCases
        let source = combined.map(\.0).joined(separator: "\n")
        let expected = combined.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 6b relative branches

    private static let numericBranchCases: [(String, [UInt8])] = [
        // JMP: short and long
        ("jmp 0",     [0xEB, 0x00]),
        ("jmp 5",     [0xEB, 0x05]),
        ("jmp -2",    [0xEB, 0xFE]),
        ("jmp 127",   [0xEB, 0x7F]),
        ("jmp -128",  [0xEB, 0x80]),
        ("jmp 128",   [0xE9, 0x80, 0x00, 0x00, 0x00]),
        ("jmp -129",  [0xE9, 0x7F, 0xFF, 0xFF, 0xFF]),

        // Jcc: a sampling across condition codes; rel8 and rel32
        ("je 0",      [0x74, 0x00]),
        ("jne 5",     [0x75, 0x05]),
        ("jb -1",     [0x72, 0xFF]),
        ("jae 1",     [0x73, 0x01]),
        ("jbe 4",     [0x76, 0x04]),
        ("ja 4",      [0x77, 0x04]),
        ("jl 0",      [0x7C, 0x00]),
        ("jge 0",     [0x7D, 0x00]),
        ("jle 0",     [0x7E, 0x00]),
        ("jg 0",      [0x7F, 0x00]),
        ("jo 0",      [0x70, 0x00]),
        ("jno 0",     [0x71, 0x00]),
        ("js 0",      [0x78, 0x00]),
        ("jns 0",     [0x79, 0x00]),
        ("jp 0",      [0x7A, 0x00]),
        ("jnp 0",     [0x7B, 0x00]),
        ("je 128",    [0x0F, 0x84, 0x80, 0x00, 0x00, 0x00]),
        ("jne -129",  [0x0F, 0x85, 0x7F, 0xFF, 0xFF, 0xFF]),

        // CALL: rel32 only
        ("call 0",    [0xE8, 0x00, 0x00, 0x00, 0x00]),
        ("call 5",    [0xE8, 0x05, 0x00, 0x00, 0x00]),
        ("call -5",   [0xE8, 0xFB, 0xFF, 0xFF, 0xFF]),

        // LOOP family (rel8 only)
        ("loop 0",    [0xE2, 0x00]),
        ("loope -1",  [0xE1, 0xFF]),
        ("loopne 5",  [0xE0, 0x05]),
        ("jrcxz 0",   [0xE3, 0x00]),
        ("jecxz 0",   [0x67, 0xE3, 0x00]),
    ]

    func testNumericBranchAssembles() throws {
        for (source, expected) in Self.numericBranchCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testNumericBranchDisassembles() throws {
        for (source, bytes) in Self.numericBranchCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// Aliases fold onto the canonical condition (e.g. `jz` → `je`).
    func testConditionalAliasesFoldToCanonical() throws {
        XCTAssertEqual(try X86Assembler.assemble("jz 0"),   [0x74, 0x00])
        XCTAssertEqual(try X86Assembler.assemble("jnz 0"),  [0x75, 0x00])
        XCTAssertEqual(try X86Assembler.assemble("jc 0"),   [0x72, 0x00])
        XCTAssertEqual(try X86Assembler.assemble("jnae 0"), [0x72, 0x00])
        XCTAssertEqual(try X86Assembler.assemble("jng 0"),  [0x7E, 0x00])
    }

    /// `loopz` / `loopnz` fold onto `loope` / `loopne`.
    func testLoopAliasesFoldToCanonical() throws {
        XCTAssertEqual(try X86Assembler.assemble("loopz 0"),  [0xE1, 0x00])
        XCTAssertEqual(try X86Assembler.assemble("loopnz 0"), [0xE0, 0x00])
    }

    /// Backward labels resolve directly to the optimal rel form: when the
    /// delta fits int8, the encoder picks rel8.
    func testBackwardLabelBranchPicksShortForm() throws {
        let bytes = try X86Assembler.assemble("""
        target:
        jmp target
        """)
        // `jmp target` at pc=0, target=0 → delta=0-(0+2)=-2 → rel8.
        XCTAssertEqual(bytes, [0xEB, 0xFE])
    }

    /// A forward label reference goes to rel32 because the assembler can't
    /// yet know whether the eventual delta will fit rel8.
    func testForwardLabelBranchUsesLongForm() throws {
        let bytes = try X86Assembler.assemble("""
        jmp target
        target:
        """)
        // 5-byte rel32 form: target = 5, delta = 5 - (0 + 5) = 0.
        XCTAssertEqual(bytes, [0xE9, 0x00, 0x00, 0x00, 0x00])
    }

    /// A more realistic loop body. The conditional `jne` targets a
    /// backward label and picks rel8.
    func testLabelLoopBodyRoundTrip() throws {
        let bytes = try X86Assembler.assemble("""
        loop_head:
        dec rcx
        jne loop_head
        ret
        """)
        // dec rcx                = 48 FF C9 (3 bytes)
        // jne loop_head (back)   = 75 FB    (2 bytes, delta=-5)
        // ret                    = C3       (1 byte)
        XCTAssertEqual(bytes, [0x48, 0xFF, 0xC9, 0x75, 0xFB, 0xC3])
    }

    /// Forward label resolution: CALL to a function defined later.
    func testForwardCallLabel() throws {
        let bytes = try X86Assembler.assemble("""
        call greeter
        ret
        greeter:
        ret
        """)
        // call greeter      = E8 ?? ?? ?? ?? (5 bytes)
        // ret               = C3
        // greeter:    (pc=6)
        // ret
        // delta from end of call (pc=5) to greeter pc=6 is 1.
        XCTAssertEqual(bytes, [0xE8, 0x01, 0x00, 0x00, 0x00, 0xC3, 0xC3])
    }

    /// An undefined label is reported with `labelNotFound`.
    func testUndefinedLabelReported() {
        XCTAssertThrowsError(try X86Assembler.assemble("jmp nowhere")) { error in
            guard case AssemblerError.labelNotFound(let name) = error else {
                return XCTFail("expected labelNotFound, got \(error)")
            }
            XCTAssertEqual(name, "nowhere")
        }
    }

    /// LOOP has no rel32 form; a target too far away is rejected.
    func testLoopRel8OutOfRange() {
        XCTAssertThrowsError(try X86Assembler.assemble("loop 128")) { error in
            guard case AssemblerError.branchOutOfRange = error else {
                return XCTFail("expected branchOutOfRange, got \(error)")
            }
        }
    }

    func testNumericBranchStreamRoundTrip() throws {
        let source = Self.numericBranchCases.map(\.0).joined(separator: "\n")
        let expected = Self.numericBranchCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 6c indirect JMP/CALL and ENTER

    private static let indirectAndEnterCases: [(String, [UInt8])] = [
        // JMP register-indirect
        ("jmp rax",  [0xFF, 0xE0]),
        ("jmp rcx",  [0xFF, 0xE1]),
        ("jmp r8",   [0x41, 0xFF, 0xE0]),
        ("jmp r15",  [0x41, 0xFF, 0xE7]),

        // CALL register-indirect
        ("call rax", [0xFF, 0xD0]),
        ("call rcx", [0xFF, 0xD1]),
        ("call r8",  [0x41, 0xFF, 0xD0]),

        // JMP memory-indirect
        ("jmp [rbx]",            [0xFF, 0x23]),
        ("jmp [rbx + 8]",        [0xFF, 0x63, 0x08]),
        ("jmp [rip + 16]",       [0xFF, 0x25, 0x10, 0x00, 0x00, 0x00]),

        // CALL memory-indirect
        ("call [rbx]",           [0xFF, 0x13]),
        ("call [rbx + rcx*8]",   [0xFF, 0x14, 0xCB]),

        // ENTER
        ("enter 0, 0",      [0xC8, 0x00, 0x00, 0x00]),
        ("enter 16, 0",     [0xC8, 0x10, 0x00, 0x00]),
        ("enter 4660, 3",   [0xC8, 0x34, 0x12, 0x03]),
        ("enter 65535, 255",[0xC8, 0xFF, 0xFF, 0xFF]),
    ]

    func testIndirectAndEnterAssembles() throws {
        for (source, expected) in Self.indirectAndEnterCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testIndirectAndEnterDisassembles() throws {
        for (source, bytes) in Self.indirectAndEnterCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `qword ptr [mem]` on an indirect target is accepted (qword is the
    /// only legal width in long mode) and disassembles back without the
    /// hint since it would be redundant.
    func testIndirectAcceptsQwordPtrHint() throws {
        XCTAssertEqual(try X86Assembler.assemble("jmp qword ptr [rbx]"), [0xFF, 0x23])
        XCTAssertEqual(try X86Assembler.disassemble([0xFF, 0x23]), "jmp [rbx]")
    }

    func testIndirectRejectsNonQword() {
        XCTAssertThrowsError(try X86Assembler.assemble("jmp eax")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("jmp dword ptr [rbx]")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testEnterImmediateOutOfRange() {
        XCTAssertThrowsError(try X86Assembler.assemble("enter 65536, 0")) { error in
            guard case AssemblerError.immediateOutOfRange = error else {
                return XCTFail("expected immediateOutOfRange, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("enter 0, 256")) { error in
            guard case AssemblerError.immediateOutOfRange = error else {
                return XCTFail("expected immediateOutOfRange, got \(error)")
            }
        }
    }

    func testIndirectAndEnterStreamRoundTrip() throws {
        let source = Self.indirectAndEnterCases.map(\.0).joined(separator: "\n")
        let expected = Self.indirectAndEnterCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 7 mul/div and sign-extension

    private static let signExtendCases: [(String, [UInt8])] = [
        ("cbw",  [0x66, 0x98]),
        ("cwde", [0x98]),
        ("cdqe", [0x48, 0x98]),
        ("cwd",  [0x66, 0x99]),
        ("cdq",  [0x99]),
        ("cqo",  [0x48, 0x99]),
    ]

    func testSignExtendAssembles() throws {
        for (mnemonic, expected) in Self.signExtendCases {
            XCTAssertEqual(try X86Assembler.assemble(mnemonic), expected, "assemble \(mnemonic)")
        }
    }

    func testSignExtendDisassembles() throws {
        for (mnemonic, bytes) in Self.signExtendCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), mnemonic, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    private static let mulDivCases: [(String, [UInt8])] = [
        // MUL r/m
        ("mul al",   [0xF6, 0xE0]),
        ("mul bl",   [0xF6, 0xE3]),
        ("mul ax",   [0x66, 0xF7, 0xE0]),
        ("mul ebx",  [0xF7, 0xE3]),
        ("mul rax",  [0x48, 0xF7, 0xE0]),
        ("mul r8",   [0x49, 0xF7, 0xE0]),
        ("mul qword ptr [rbx]", [0x48, 0xF7, 0x23]),

        // IMUL (1-op)
        ("imul rax", [0x48, 0xF7, 0xE8]),
        ("imul rbx", [0x48, 0xF7, 0xEB]),

        // DIV / IDIV
        ("div rcx",  [0x48, 0xF7, 0xF1]),
        ("idiv rcx", [0x48, 0xF7, 0xF9]),
        ("div bl",   [0xF6, 0xF3]),
    ]

    func testMulDivAssembles() throws {
        for (source, expected) in Self.mulDivCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testMulDivDisassembles() throws {
        for (source, bytes) in Self.mulDivCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    private static let imulMultiOperandCases: [(String, [UInt8])] = [
        // 2-operand IMUL (0F AF /r)
        ("imul ax, bx",   [0x66, 0x0F, 0xAF, 0xC3]),
        ("imul eax, ebx", [0x0F, 0xAF, 0xC3]),
        ("imul rax, rbx", [0x48, 0x0F, 0xAF, 0xC3]),
        ("imul rax, [rbx]", [0x48, 0x0F, 0xAF, 0x03]),
        ("imul r8, r9",   [0x4D, 0x0F, 0xAF, 0xC1]),

        // 3-operand IMUL with imm8 (6B /r ib) — short form when imm fits Int8
        ("imul rax, rbx, 5",   [0x48, 0x6B, 0xC3, 0x05]),
        ("imul ecx, edx, -1",  [0x6B, 0xCA, 0xFF]),
        ("imul ax, bx, 4",     [0x66, 0x6B, 0xC3, 0x04]),

        // 3-operand IMUL with imm16/32 (69 /r iw/id) — when imm doesn't fit Int8
        ("imul rax, rbx, 1024", [0x48, 0x69, 0xC3, 0x00, 0x04, 0x00, 0x00]),
        ("imul eax, ebx, 4096", [0x69, 0xC3, 0x00, 0x10, 0x00, 0x00]),
        ("imul ax, bx, 4660",   [0x66, 0x69, 0xC3, 0x34, 0x12]),

        // Memory source on the 3-operand form
        ("imul rax, [rbx], 5",  [0x48, 0x6B, 0x03, 0x05]),
    ]

    func testImulMultiOperandAssembles() throws {
        for (source, expected) in Self.imulMultiOperandCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testImulMultiOperandDisassembles() throws {
        for (source, bytes) in Self.imulMultiOperandCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// IMUL has no byte form for the multi-operand variants.
    func testImulMultiOperandRejectsByteWidth() {
        XCTAssertThrowsError(try X86Assembler.assemble("imul al, bl")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("imul al, bl, 5")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    /// IMUL has no imm64 form. A qword immediate outside Int32 errors out.
    func testImulQwordImmediateOutOfRange() {
        XCTAssertThrowsError(try X86Assembler.assemble("imul rax, rbx, 4294967296")) { error in
            guard case AssemblerError.immediateOutOfRange = error else {
                return XCTFail("expected immediateOutOfRange, got \(error)")
            }
        }
    }

    func testMulDivMemoryRequiresSizeHint() {
        XCTAssertThrowsError(try X86Assembler.assemble("mul [rbx]")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testMulDivAndImulStreamRoundTrip() throws {
        let cases = Self.signExtendCases + Self.mulDivCases + Self.imulMultiOperandCases
        let source = cases.map(\.0).joined(separator: "\n")
        let expected = cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 8a PUSH / POP / PUSHFQ / POPFQ / LEA

    private static let pushPopFlagsCases: [(String, [UInt8])] = [
        ("pushfq", [0x9C]),
        ("popfq",  [0x9D]),
        ("pushfw", [0x66, 0x9C]),
        ("popfw",  [0x66, 0x9D]),
    ]

    private static let pushPopLeaCases: [(String, [UInt8])] = [
        // PUSH register short form
        ("push rax", [0x50]),
        ("push rcx", [0x51]),
        ("push rbp", [0x55]),
        ("push r8",  [0x41, 0x50]),
        ("push r15", [0x41, 0x57]),
        ("push ax",  [0x66, 0x50]),
        ("push r8w", [0x66, 0x41, 0x50]),

        // PUSH memory (FF /6) — qword by default in long mode
        ("push qword ptr [rbx]",       [0xFF, 0x33]),
        ("push qword ptr [rbx + 8]",   [0xFF, 0x73, 0x08]),
        ("push word ptr [rbx]",        [0x66, 0xFF, 0x33]),

        // PUSH immediate (6A ib / 68 id)
        ("push 5",       [0x6A, 0x05]),
        ("push -1",      [0x6A, 0xFF]),
        ("push 127",     [0x6A, 0x7F]),
        ("push 128",     [0x68, 0x80, 0x00, 0x00, 0x00]),
        ("push 1000",    [0x68, 0xE8, 0x03, 0x00, 0x00]),
        ("push -1000",   [0x68, 0x18, 0xFC, 0xFF, 0xFF]),

        // POP register short form
        ("pop rax", [0x58]),
        ("pop r15", [0x41, 0x5F]),
        ("pop ax",  [0x66, 0x58]),

        // POP memory (8F /0)
        ("pop qword ptr [rbx]",        [0x8F, 0x03]),
        ("pop qword ptr [rbx + 8]",    [0x8F, 0x43, 0x08]),
        ("pop word ptr [rbx]",         [0x66, 0x8F, 0x03]),

        // LEA
        ("lea rax, [rbx]",                  [0x48, 0x8D, 0x03]),
        ("lea rax, [rbx + 8]",              [0x48, 0x8D, 0x43, 0x08]),
        ("lea rax, [rbx + rcx*4 + 256]",    [0x48, 0x8D, 0x84, 0x8B, 0x00, 0x01, 0x00, 0x00]),
        ("lea rax, [rip + 16]",             [0x48, 0x8D, 0x05, 0x10, 0x00, 0x00, 0x00]),
        ("lea eax, [rbx]",                  [0x8D, 0x03]),
        ("lea ax, [rbx]",                   [0x66, 0x8D, 0x03]),
        ("lea r8, [rbx]",                   [0x4C, 0x8D, 0x03]),
    ]

    func testPushPopFlagsAssembles() throws {
        for (mnemonic, expected) in Self.pushPopFlagsCases {
            XCTAssertEqual(try X86Assembler.assemble(mnemonic), expected, "assemble \(mnemonic)")
        }
    }

    func testPushPopFlagsDisassembles() throws {
        for (mnemonic, bytes) in Self.pushPopFlagsCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), mnemonic, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testPushPopLeaAssembles() throws {
        for (source, expected) in Self.pushPopLeaCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testPushPopLeaDisassembles() throws {
        for (source, bytes) in Self.pushPopLeaCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `pushf` / `popf` are NASM aliases for the qword forms in long mode.
    func testPushPopFlagsAliases() throws {
        XCTAssertEqual(try X86Assembler.assemble("pushf"), [0x9C])
        XCTAssertEqual(try X86Assembler.assemble("popf"),  [0x9D])
    }

    /// `push [mem]` without a size hint defaults to qword in long mode.
    func testPushMemoryDefaultsToQword() throws {
        XCTAssertEqual(try X86Assembler.assemble("push [rbx]"), [0xFF, 0x33])
    }

    func testPushPopRejectsByteAndDwordWidth() {
        XCTAssertThrowsError(try X86Assembler.assemble("push al")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("push eax")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("pop edi")) { _ in }
    }

    /// PUSH has no imm64 form. A value outside Int32 errors out.
    func testPushImmediateOutOfInt32() {
        XCTAssertThrowsError(try X86Assembler.assemble("push 4294967296")) { error in
            guard case AssemblerError.immediateOutOfRange = error else {
                return XCTFail("expected immediateOutOfRange, got \(error)")
            }
        }
    }

    /// LEA accepts a size hint on the source but ignores it; the
    /// destination register's width determines the operation width.
    func testLeaIgnoresSourceSizeHint() throws {
        XCTAssertEqual(try X86Assembler.assemble("lea rax, qword ptr [rbx]"), [0x48, 0x8D, 0x03])
        XCTAssertEqual(try X86Assembler.assemble("lea rax, dword ptr [rbx]"), [0x48, 0x8D, 0x03])
    }

    func testLeaRejectsRegisterSource() {
        XCTAssertThrowsError(try X86Assembler.assemble("lea rax, rbx")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testPushPopLeaStreamRoundTrip() throws {
        let cases = Self.pushPopFlagsCases + Self.pushPopLeaCases
        let source = cases.map(\.0).joined(separator: "\n")
        let expected = cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 8b MOVSX / MOVSXD / MOVZX + BSWAP

    private static let extendingMoveCases: [(String, [UInt8])] = [
        // MOVSX byte → 16/32/64
        ("movsx ax, bl",   [0x66, 0x0F, 0xBE, 0xC3]),
        ("movsx eax, bl",  [0x0F, 0xBE, 0xC3]),
        ("movsx rax, bl",  [0x48, 0x0F, 0xBE, 0xC3]),
        ("movsx rax, byte ptr [rbx]", [0x48, 0x0F, 0xBE, 0x03]),

        // MOVSX word → 32/64
        ("movsx eax, bx",  [0x0F, 0xBF, 0xC3]),
        ("movsx rax, bx",  [0x48, 0x0F, 0xBF, 0xC3]),
        ("movsx rax, word ptr [rbx]", [0x48, 0x0F, 0xBF, 0x03]),

        // MOVSXD r64, r/m32 (REX.W + 0x63)
        ("movsxd rax, ebx",                  [0x48, 0x63, 0xC3]),
        ("movsxd rax, dword ptr [rbx]",      [0x48, 0x63, 0x03]),
        ("movsxd r8, eax",                   [0x4C, 0x63, 0xC0]),

        // MOVZX byte → 16/32/64
        ("movzx ax, bl",   [0x66, 0x0F, 0xB6, 0xC3]),
        ("movzx eax, bl",  [0x0F, 0xB6, 0xC3]),
        ("movzx rax, bl",  [0x48, 0x0F, 0xB6, 0xC3]),
        ("movzx rax, byte ptr [rbx]", [0x48, 0x0F, 0xB6, 0x03]),

        // MOVZX word → 32/64
        ("movzx eax, bx",  [0x0F, 0xB7, 0xC3]),
        ("movzx rax, bx",  [0x48, 0x0F, 0xB7, 0xC3]),
        ("movzx rax, word ptr [rbx]", [0x48, 0x0F, 0xB7, 0x03]),

        // Mixed extended-byte register sources with REX-forced regs
        ("movsx rax, dil", [0x48, 0x0F, 0xBE, 0xC7]),
        ("movzx eax, r8b", [0x41, 0x0F, 0xB6, 0xC0]),
    ]

    private static let bswapCases: [(String, [UInt8])] = [
        ("bswap eax",  [0x0F, 0xC8]),
        ("bswap ecx",  [0x0F, 0xC9]),
        ("bswap edi",  [0x0F, 0xCF]),
        ("bswap r8d",  [0x41, 0x0F, 0xC8]),
        ("bswap r15d", [0x41, 0x0F, 0xCF]),
        ("bswap rax",  [0x48, 0x0F, 0xC8]),
        ("bswap rcx",  [0x48, 0x0F, 0xC9]),
        ("bswap r8",   [0x49, 0x0F, 0xC8]),
        ("bswap r15",  [0x49, 0x0F, 0xCF]),
    ]

    func testExtendingMoveAssembles() throws {
        for (source, expected) in Self.extendingMoveCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testExtendingMoveDisassembles() throws {
        for (source, bytes) in Self.extendingMoveCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testBswapAssembles() throws {
        for (source, expected) in Self.bswapCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testBswapDisassembles() throws {
        for (source, bytes) in Self.bswapCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testExtendingMoveRejectsBadShapes() {
        // MOVSX with same widths makes no sense.
        XCTAssertThrowsError(try X86Assembler.assemble("movsx eax, ebx")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        // MOVSX byte-to-byte.
        XCTAssertThrowsError(try X86Assembler.assemble("movsx al, bl")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        // MOVSX word source requires non-word destination.
        XCTAssertThrowsError(try X86Assembler.assemble("movsx ax, bx")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        // MOVSXD only accepts r64, r/m32.
        XCTAssertThrowsError(try X86Assembler.assemble("movsxd eax, ebx")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        // BSWAP rejects 16-bit operand.
        XCTAssertThrowsError(try X86Assembler.assemble("bswap ax")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        // BSWAP rejects 8-bit operand.
        XCTAssertThrowsError(try X86Assembler.assemble("bswap al")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testExtendingMoveMemoryRequiresSizeHint() {
        XCTAssertThrowsError(try X86Assembler.assemble("movsx rax, [rbx]")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testExtendingMoveAndBswapStreamRoundTrip() throws {
        let cases = Self.extendingMoveCases + Self.bswapCases
        let source = cases.map(\.0).joined(separator: "\n")
        let expected = cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 8c XCHG / XADD / CMPXCHG / CMPXCHG8B / 16B

    private static let xchgCases: [(String, [UInt8])] = [
        // Short form with rAX
        ("xchg rax, rcx",  [0x48, 0x91]),
        ("xchg rax, r8",   [0x49, 0x90]),
        ("xchg eax, ecx",  [0x91]),
        ("xchg ax, cx",    [0x66, 0x91]),
        ("xchg rax, rdi",  [0x48, 0x97]),

        // MR form (both non-rAX, or byte width)
        ("xchg rcx, rdx",  [0x48, 0x87, 0xD1]),
        ("xchg al, bl",    [0x86, 0xD8]),
        ("xchg eax, eax",  [0x87, 0xC0]),  // both rAX → MR form
        ("xchg rax, rax",  [0x48, 0x87, 0xC0]),

        // Memory operand
        ("xchg [rbx], rax",       [0x48, 0x87, 0x03]),
        ("xchg [rbx + 8], rcx",   [0x48, 0x87, 0x4B, 0x08]),
        ("xchg [rsi], al",        [0x86, 0x06]),
    ]

    private static let xaddCmpxchgCases: [(String, [UInt8])] = [
        // XADD r/m, r
        ("xadd al, bl",          [0x0F, 0xC0, 0xD8]),
        ("xadd eax, ebx",        [0x0F, 0xC1, 0xD8]),
        ("xadd rax, rbx",        [0x48, 0x0F, 0xC1, 0xD8]),
        ("xadd [rbx], rax",      [0x48, 0x0F, 0xC1, 0x03]),

        // CMPXCHG r/m, r — implicit comparator is rAX
        ("cmpxchg al, bl",       [0x0F, 0xB0, 0xD8]),
        ("cmpxchg eax, ebx",     [0x0F, 0xB1, 0xD8]),
        ("cmpxchg rax, rbx",     [0x48, 0x0F, 0xB1, 0xD8]),
        ("cmpxchg [rbx], rcx",   [0x48, 0x0F, 0xB1, 0x0B]),

        // CMPXCHG8B / CMPXCHG16B
        ("cmpxchg8b [rbx]",      [0x0F, 0xC7, 0x0B]),
        ("cmpxchg8b [rbx + 16]", [0x0F, 0xC7, 0x4B, 0x10]),
        ("cmpxchg16b [rbx]",     [0x48, 0x0F, 0xC7, 0x0B]),
        ("cmpxchg16b [rbx + rcx*8]", [0x48, 0x0F, 0xC7, 0x0C, 0xCB]),
    ]

    func testXchgAssembles() throws {
        for (source, expected) in Self.xchgCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testXchgDisassembles() throws {
        for (source, bytes) in Self.xchgCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `xchg rcx, rax` encodes the same bytes as `xchg rax, rcx`; the
    /// canonical disassembly places the accumulator first.
    func testXchgShortFormSwapsOrderToCanonical() throws {
        XCTAssertEqual(try X86Assembler.assemble("xchg rcx, rax"), [0x48, 0x91])
        XCTAssertEqual(try X86Assembler.disassemble([0x48, 0x91]), "xchg rax, rcx")
    }

    /// `xchg r8, rax` and `xchg rax, r8` both reach 49 90; the
    /// disassembly canonicalises to rAX-first.
    func testXchgShortFormExtendedRegister() throws {
        XCTAssertEqual(try X86Assembler.assemble("xchg r8, rax"), [0x49, 0x90])
        XCTAssertEqual(try X86Assembler.disassemble([0x49, 0x90]), "xchg rax, r8")
    }

    func testXaddCmpxchgAssembles() throws {
        for (source, expected) in Self.xaddCmpxchgCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testXaddCmpxchgDisassembles() throws {
        for (source, bytes) in Self.xaddCmpxchgCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testXchgRejectsImmediate() {
        XCTAssertThrowsError(try X86Assembler.assemble("xchg rax, 5")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testXaddCmpxchgRequireRegisterSource() {
        XCTAssertThrowsError(try X86Assembler.assemble("xadd rax, 5")) { _ in }
        XCTAssertThrowsError(try X86Assembler.assemble("cmpxchg rax, 5")) { _ in }
    }

    func testExchangeFamilyStreamRoundTrip() throws {
        let cases = Self.xchgCases + Self.xaddCmpxchgCases
        let source = cases.map(\.0).joined(separator: "\n")
        let expected = cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 9a CMOVcc / SETcc

    private static let cmovccCases: [(String, [UInt8])] = [
        // A sampling across condition codes, widths, and operand shapes.
        ("cmove rax, rbx",       [0x48, 0x0F, 0x44, 0xC3]),
        ("cmovne rax, rbx",      [0x48, 0x0F, 0x45, 0xC3]),
        ("cmovb eax, ebx",       [0x0F, 0x42, 0xC3]),
        ("cmovae rax, [rbx]",    [0x48, 0x0F, 0x43, 0x03]),
        ("cmovbe ax, bx",        [0x66, 0x0F, 0x46, 0xC3]),
        ("cmova rax, [rbx + 8]", [0x48, 0x0F, 0x47, 0x43, 0x08]),
        ("cmovl rax, rbx",       [0x48, 0x0F, 0x4C, 0xC3]),
        ("cmovge eax, ebx",      [0x0F, 0x4D, 0xC3]),
        ("cmovle r8, r9",        [0x4D, 0x0F, 0x4E, 0xC1]),
        ("cmovg rax, rbx",       [0x48, 0x0F, 0x4F, 0xC3]),
        ("cmovo rax, rbx",       [0x48, 0x0F, 0x40, 0xC3]),
        ("cmovs rax, rbx",       [0x48, 0x0F, 0x48, 0xC3]),
        ("cmovp rax, rbx",       [0x48, 0x0F, 0x4A, 0xC3]),
    ]

    private static let setccCases: [(String, [UInt8])] = [
        ("sete al",                  [0x0F, 0x94, 0xC0]),
        ("setne bl",                 [0x0F, 0x95, 0xC3]),
        ("setb cl",                  [0x0F, 0x92, 0xC1]),
        ("setae dl",                 [0x0F, 0x93, 0xC2]),
        ("setbe ah",                 [0x0F, 0x96, 0xC4]),
        ("seta bh",                  [0x0F, 0x97, 0xC7]),
        ("setl r8b",                 [0x41, 0x0F, 0x9C, 0xC0]),
        ("setg r15b",                [0x41, 0x0F, 0x9F, 0xC7]),
        ("seto byte ptr [rbx]",      [0x0F, 0x90, 0x03]),
        ("setno byte ptr [rbx + 4]", [0x0F, 0x91, 0x43, 0x04]),
        // REX-required byte regs
        ("sete dil",                 [0x40, 0x0F, 0x94, 0xC7]),
    ]

    func testCmovccAssembles() throws {
        for (source, expected) in Self.cmovccCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testCmovccDisassembles() throws {
        for (source, bytes) in Self.cmovccCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSetccAssembles() throws {
        for (source, expected) in Self.setccCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSetccDisassembles() throws {
        for (source, bytes) in Self.setccCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// CMOVcc / SETcc aliases (jz/jc/jnae/jng/...) fold onto the
    /// canonical condition codes the same way Jcc does.
    func testConditionalMoveAliases() throws {
        XCTAssertEqual(try X86Assembler.assemble("cmovz rax, rbx"),  [0x48, 0x0F, 0x44, 0xC3])
        XCTAssertEqual(try X86Assembler.assemble("cmovnz rax, rbx"), [0x48, 0x0F, 0x45, 0xC3])
        XCTAssertEqual(try X86Assembler.assemble("cmovc rax, rbx"),  [0x48, 0x0F, 0x42, 0xC3])
        XCTAssertEqual(try X86Assembler.assemble("setz al"), [0x0F, 0x94, 0xC0])
        XCTAssertEqual(try X86Assembler.assemble("setnz al"), [0x0F, 0x95, 0xC0])
    }

    func testCmovccRejectsByteWidth() {
        XCTAssertThrowsError(try X86Assembler.assemble("cmove al, bl")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testSetccRequiresByteWidth() {
        XCTAssertThrowsError(try X86Assembler.assemble("sete ax")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testCmovccSetccStreamRoundTrip() throws {
        let cases = Self.cmovccCases + Self.setccCases
        let source = cases.map(\.0).joined(separator: "\n")
        let expected = cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 9b BT / BTS / BTR / BTC + BSF / BSR

    private static let bitTestCases: [(String, [UInt8])] = [
        // r/m, r form
        ("bt rax, rbx",   [0x48, 0x0F, 0xA3, 0xD8]),
        ("bts rax, rbx",  [0x48, 0x0F, 0xAB, 0xD8]),
        ("btr rax, rbx",  [0x48, 0x0F, 0xB3, 0xD8]),
        ("btc rax, rbx",  [0x48, 0x0F, 0xBB, 0xD8]),
        ("bt eax, ebx",   [0x0F, 0xA3, 0xD8]),
        ("bt ax, bx",     [0x66, 0x0F, 0xA3, 0xD8]),

        // r/m, imm8 form (0F BA /n ib)
        ("bt rax, 5",     [0x48, 0x0F, 0xBA, 0xE0, 0x05]),
        ("bts rcx, 3",    [0x48, 0x0F, 0xBA, 0xE9, 0x03]),
        ("btr rax, 7",    [0x48, 0x0F, 0xBA, 0xF0, 0x07]),
        ("btc rax, 1",    [0x48, 0x0F, 0xBA, 0xF8, 0x01]),
        ("bt eax, 0",     [0x0F, 0xBA, 0xE0, 0x00]),

        // Memory operand
        ("bt qword ptr [rbx], 5", [0x48, 0x0F, 0xBA, 0x23, 0x05]),
        ("bt [rbx], rax",         [0x48, 0x0F, 0xA3, 0x03]),
    ]

    private static let bitScanCases: [(String, [UInt8])] = [
        ("bsf rax, rbx",  [0x48, 0x0F, 0xBC, 0xC3]),
        ("bsr rax, rbx",  [0x48, 0x0F, 0xBD, 0xC3]),
        ("bsf eax, ebx",  [0x0F, 0xBC, 0xC3]),
        ("bsr ax, bx",    [0x66, 0x0F, 0xBD, 0xC3]),
        ("bsf rax, [rbx]", [0x48, 0x0F, 0xBC, 0x03]),
    ]

    func testBitTestAssembles() throws {
        for (source, expected) in Self.bitTestCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testBitTestDisassembles() throws {
        for (source, bytes) in Self.bitTestCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testBitScanAssembles() throws {
        for (source, expected) in Self.bitScanCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testBitScanDisassembles() throws {
        for (source, bytes) in Self.bitScanCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testBitTestRejectsByteWidth() {
        XCTAssertThrowsError(try X86Assembler.assemble("bt al, bl")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testBitScanRejectsByteWidth() {
        XCTAssertThrowsError(try X86Assembler.assemble("bsf al, bl")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testBitTestStreamRoundTrip() throws {
        let cases = Self.bitTestCases + Self.bitScanCases
        let source = cases.map(\.0).joined(separator: "\n")
        let expected = cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 9c POPCNT / LZCNT / TZCNT

    private static let bitCountCases: [(String, [UInt8])] = [
        // POPCNT
        ("popcnt eax, ebx",     [0xF3, 0x0F, 0xB8, 0xC3]),
        ("popcnt rax, rbx",     [0xF3, 0x48, 0x0F, 0xB8, 0xC3]),
        ("popcnt ax, bx",       [0x66, 0xF3, 0x0F, 0xB8, 0xC3]),
        ("popcnt rax, [rbx]",   [0xF3, 0x48, 0x0F, 0xB8, 0x03]),

        // TZCNT (same opcode as BSF, distinguished by F3)
        ("tzcnt eax, ebx",      [0xF3, 0x0F, 0xBC, 0xC3]),
        ("tzcnt rax, rbx",      [0xF3, 0x48, 0x0F, 0xBC, 0xC3]),
        ("tzcnt r8, r9",        [0xF3, 0x4D, 0x0F, 0xBC, 0xC1]),

        // LZCNT (same opcode as BSR, distinguished by F3)
        ("lzcnt eax, ebx",      [0xF3, 0x0F, 0xBD, 0xC3]),
        ("lzcnt rax, rbx",      [0xF3, 0x48, 0x0F, 0xBD, 0xC3]),
        ("lzcnt rax, [rbx + 8]", [0xF3, 0x48, 0x0F, 0xBD, 0x43, 0x08]),
    ]

    func testBitCountAssembles() throws {
        for (source, expected) in Self.bitCountCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testBitCountDisassembles() throws {
        for (source, bytes) in Self.bitCountCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// BSF/BSR vs TZCNT/LZCNT share opcodes 0F BC and 0F BD; the F3
    /// mandatory prefix selects the latter pair.
    func testBitCountVersusBitScanOpcodeSharing() throws {
        // BSF / TZCNT share 0F BC
        XCTAssertEqual(try X86Assembler.assemble("bsf rax, rbx"),    [0x48, 0x0F, 0xBC, 0xC3])
        XCTAssertEqual(try X86Assembler.assemble("tzcnt rax, rbx"),  [0xF3, 0x48, 0x0F, 0xBC, 0xC3])
        // BSR / LZCNT share 0F BD
        XCTAssertEqual(try X86Assembler.assemble("bsr rax, rbx"),    [0x48, 0x0F, 0xBD, 0xC3])
        XCTAssertEqual(try X86Assembler.assemble("lzcnt rax, rbx"),  [0xF3, 0x48, 0x0F, 0xBD, 0xC3])
        // Disassembly chooses based on the F3 prefix
        XCTAssertEqual(try X86Assembler.disassemble([0x48, 0x0F, 0xBC, 0xC3]),       "bsf rax, rbx")
        XCTAssertEqual(try X86Assembler.disassemble([0xF3, 0x48, 0x0F, 0xBC, 0xC3]), "tzcnt rax, rbx")
    }

    func testBitCountRejectsByteWidth() {
        XCTAssertThrowsError(try X86Assembler.assemble("popcnt al, bl")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testBitCountStreamRoundTrip() throws {
        let source = Self.bitCountCases.map(\.0).joined(separator: "\n")
        let expected = Self.bitCountCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 10a String operations + REP/REPE/REPNE

    private static let stringOpCases: [(String, [UInt8])] = [
        // MOVS family
        ("movsb", [0xA4]),
        ("movsw", [0x66, 0xA5]),
        ("movsd", [0xA5]),
        ("movsq", [0x48, 0xA5]),

        // CMPS family
        ("cmpsb", [0xA6]),
        ("cmpsw", [0x66, 0xA7]),
        ("cmpsd", [0xA7]),
        ("cmpsq", [0x48, 0xA7]),

        // SCAS family
        ("scasb", [0xAE]),
        ("scasw", [0x66, 0xAF]),
        ("scasd", [0xAF]),
        ("scasq", [0x48, 0xAF]),

        // LODS family
        ("lodsb", [0xAC]),
        ("lodsw", [0x66, 0xAD]),
        ("lodsd", [0xAD]),
        ("lodsq", [0x48, 0xAD]),

        // STOS family
        ("stosb", [0xAA]),
        ("stosw", [0x66, 0xAB]),
        ("stosd", [0xAB]),
        ("stosq", [0x48, 0xAB]),

        // INS / OUTS (no qword form for port I/O)
        ("insb",  [0x6C]),
        ("insw",  [0x66, 0x6D]),
        ("insd",  [0x6D]),
        ("outsb", [0x6E]),
        ("outsw", [0x66, 0x6F]),
        ("outsd", [0x6F]),

        // REP on a moving op
        ("rep movsb", [0xF3, 0xA4]),
        ("rep movsw", [0xF3, 0x66, 0xA5]),
        ("rep movsd", [0xF3, 0xA5]),
        ("rep movsq", [0xF3, 0x48, 0xA5]),
        ("rep stosb", [0xF3, 0xAA]),
        ("rep stosq", [0xF3, 0x48, 0xAB]),
        ("rep lodsd", [0xF3, 0xAD]),
        ("rep insb",  [0xF3, 0x6C]),

        // REPE on a comparing op (F3)
        ("repe cmpsb", [0xF3, 0xA6]),
        ("repe cmpsq", [0xF3, 0x48, 0xA7]),
        ("repe scasw", [0xF3, 0x66, 0xAF]),

        // REPNE on a comparing op (F2)
        ("repne cmpsb", [0xF2, 0xA6]),
        ("repne scasq", [0xF2, 0x48, 0xAF]),
    ]

    func testStringOpAssembles() throws {
        for (source, expected) in Self.stringOpCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testStringOpDisassembles() throws {
        for (source, bytes) in Self.stringOpCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `rep` on a comparing op is the same byte as `repe`; disassembly
    /// canonicalises to "repe cmpsb" / "repe scasq".
    func testRepOnComparingFoldsToRepe() throws {
        XCTAssertEqual(try X86Assembler.assemble("rep cmpsb"), [0xF3, 0xA6])
        XCTAssertEqual(try X86Assembler.disassemble([0xF3, 0xA6]), "repe cmpsb")
    }

    /// `repz` / `repnz` are NASM aliases for `repe` / `repne`.
    func testRepetitionAliases() throws {
        XCTAssertEqual(try X86Assembler.assemble("repz cmpsb"),  [0xF3, 0xA6])
        XCTAssertEqual(try X86Assembler.assemble("repnz cmpsb"), [0xF2, 0xA6])
    }

    /// REPNE is only valid on CMPS/SCAS; the parser rejects it on a
    /// moving op.
    func testRepneRejectedOnMovingOp() {
        XCTAssertThrowsError(try X86Assembler.assemble("repne movsb")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    /// `pause` (F3 90) is still picked up by the zero-operand matcher
    /// even though F3 is now a tracked prefix.
    func testPauseStillRecognisedAfterF3PrefixTracking() throws {
        XCTAssertEqual(try X86Assembler.assemble("pause"), [0xF3, 0x90])
        XCTAssertEqual(try X86Assembler.disassemble([0xF3, 0x90]), "pause")
    }

    func testStringOpStreamRoundTrip() throws {
        let source = Self.stringOpCases.map(\.0).joined(separator: "\n")
        let expected = Self.stringOpCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 10b/c IN/OUT + INT

    private static let portIOCases: [(String, [UInt8])] = [
        // IN reg, imm8
        ("in al, 128",   [0xE4, 0x80]),
        ("in ax, 0",     [0x66, 0xE5, 0x00]),
        ("in eax, 64",   [0xE5, 0x40]),

        // IN reg, dx
        ("in al, dx",    [0xEC]),
        ("in ax, dx",    [0x66, 0xED]),
        ("in eax, dx",   [0xED]),

        // OUT imm8, reg
        ("out 128, al",  [0xE6, 0x80]),
        ("out 0, ax",    [0x66, 0xE7, 0x00]),
        ("out 64, eax",  [0xE7, 0x40]),

        // OUT dx, reg
        ("out dx, al",   [0xEE]),
        ("out dx, ax",   [0x66, 0xEF]),
        ("out dx, eax",  [0xEF]),
    ]

    func testPortIOAssembles() throws {
        for (source, expected) in Self.portIOCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testPortIODisassembles() throws {
        for (source, bytes) in Self.portIOCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testPortIORejectsNonAccumulator() {
        XCTAssertThrowsError(try X86Assembler.assemble("in bl, 5")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("out 5, bl")) { _ in }
    }

    func testPortIORejectsQword() {
        XCTAssertThrowsError(try X86Assembler.assemble("in rax, dx")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    private static let interruptCases: [(String, [UInt8])] = [
        ("int 0",    [0xCD, 0x00]),
        ("int 128",  [0xCD, 0x80]),
        ("int 255",  [0xCD, 0xFF]),
        ("int1",     [0xF1]),
        ("int3",     [0xCC]),
    ]

    func testInterruptAssembles() throws {
        for (source, expected) in Self.interruptCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testInterruptDisassembles() throws {
        for (source, bytes) in Self.interruptCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `int 3` parses but the encoder picks the shorter single-byte
    /// INT3 form (0xCC); disassembly canonicalises to "int3".
    func testInt3CanonicalisesToZeroOperand() throws {
        XCTAssertEqual(try X86Assembler.assemble("int 3"), [0xCC])
        XCTAssertEqual(try X86Assembler.disassemble([0xCC]), "int3")
    }

    func testInterruptVectorRange() {
        XCTAssertThrowsError(try X86Assembler.assemble("int 256")) { error in
            guard case AssemblerError.immediateOutOfRange = error else {
                return XCTFail("expected immediateOutOfRange, got \(error)")
            }
        }
    }

    func testPortIOAndInterruptStreamRoundTrip() throws {
        let cases = Self.portIOCases + Self.interruptCases
        let source = cases.map(\.0).joined(separator: "\n")
        let expected = cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 11a fences and basic system ops

    private static let systemBaseCases: [(String, [UInt8])] = [
        // Memory fences (mod=11 forms of 0F AE)
        ("lfence",  [0x0F, 0xAE, 0xE8]),
        ("mfence",  [0x0F, 0xAE, 0xF0]),
        ("sfence",  [0x0F, 0xAE, 0xF8]),
        // Cache invalidation
        ("invd",    [0x0F, 0x08]),
        ("wbinvd",  [0x0F, 0x09]),
        // Clear task-switched flag
        ("clts",    [0x0F, 0x06]),
        // CLFLUSH — 0F AE /7 with mod != 11
        ("clflush [rbx]",         [0x0F, 0xAE, 0x3B]),
        ("clflush [rbx + 16]",    [0x0F, 0xAE, 0x7B, 0x10]),
        ("clflush [rdi + rsi*4]", [0x0F, 0xAE, 0x3C, 0xB7]),
        // INVLPG — 0F 01 /7 with mod != 11
        ("invlpg [rbx]",          [0x0F, 0x01, 0x3B]),
        ("invlpg [rbx + 8]",      [0x0F, 0x01, 0x7B, 0x08]),
    ]

    func testSystemBaseAssembles() throws {
        for (source, expected) in Self.systemBaseCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSystemBaseDisassembles() throws {
        for (source, bytes) in Self.systemBaseCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// SWAPGS / RDTSCP are 0F 01 mod=11 sub-encodings already in the
    /// zero-operand table — the matcher's longest-prefix win keeps the
    /// new 0F 01 dispatch from interfering with them.
    func testSwapgsAndRdtscpStillRecognised() throws {
        XCTAssertEqual(try X86Assembler.assemble("swapgs"), [0x0F, 0x01, 0xF8])
        XCTAssertEqual(try X86Assembler.disassemble([0x0F, 0x01, 0xF8]), "swapgs")
        XCTAssertEqual(try X86Assembler.assemble("rdtscp"), [0x0F, 0x01, 0xF9])
        XCTAssertEqual(try X86Assembler.disassemble([0x0F, 0x01, 0xF9]), "rdtscp")
    }

    func testSystemBaseStreamRoundTrip() throws {
        let source = Self.systemBaseCases.map(\.0).joined(separator: "\n")
        let expected = Self.systemBaseCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 11b GDT/IDT/LDT/TR/MSW family

    private static let descriptorTableCases: [(String, [UInt8])] = [
        ("sgdt [rbx]",       [0x0F, 0x01, 0x03]),
        ("sidt [rbx]",       [0x0F, 0x01, 0x0B]),
        ("lgdt [rbx]",       [0x0F, 0x01, 0x13]),
        ("lidt [rbx]",       [0x0F, 0x01, 0x1B]),
        ("sgdt [rbx + 8]",   [0x0F, 0x01, 0x43, 0x08]),
        ("lidt [rax + rcx]", [0x0F, 0x01, 0x1C, 0x08]),
    ]

    private static let systemRMCases: [(String, [UInt8])] = [
        // 0F 00 family (r/m16 — emitted with 0x66 for register operand)
        ("sldt ax",     [0x66, 0x0F, 0x00, 0xC0]),
        ("str ax",      [0x66, 0x0F, 0x00, 0xC8]),
        ("lldt ax",     [0x66, 0x0F, 0x00, 0xD0]),
        ("ltr ax",      [0x66, 0x0F, 0x00, 0xD8]),
        ("verr ax",     [0x66, 0x0F, 0x00, 0xE0]),
        ("verw ax",     [0x66, 0x0F, 0x00, 0xE8]),
        ("lldt [rbx]",  [0x66, 0x0F, 0x00, 0x13]),
        ("verr [rbx]",  [0x66, 0x0F, 0x00, 0x23]),

        // SLDT/STR allow wider destinations (zero-extending).
        ("sldt eax",    [0x0F, 0x00, 0xC0]),
        ("sldt rax",    [0x48, 0x0F, 0x00, 0xC0]),
        ("str ecx",     [0x0F, 0x00, 0xC9]),

        // 0F 01 /4 SMSW, /6 LMSW
        ("smsw ax",     [0x66, 0x0F, 0x01, 0xE0]),
        ("smsw eax",    [0x0F, 0x01, 0xE0]),
        ("smsw rax",    [0x48, 0x0F, 0x01, 0xE0]),
        ("lmsw ax",     [0x66, 0x0F, 0x01, 0xF0]),
        ("lmsw [rbx]",  [0x66, 0x0F, 0x01, 0x33]),
    ]

    func testDescriptorTableAssembles() throws {
        for (source, expected) in Self.descriptorTableCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testDescriptorTableDisassembles() throws {
        for (source, bytes) in Self.descriptorTableCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSystemRMAssembles() throws {
        for (source, expected) in Self.systemRMCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSystemRMDisassembles() throws {
        for (source, bytes) in Self.systemRMCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// LLDT / LTR / LMSW / VERR / VERW are r/m16-only; the parser rejects
    /// 32- or 64-bit registers.
    func testNarrowSystemOpsRejectWiderRegisters() {
        XCTAssertThrowsError(try X86Assembler.assemble("lldt eax")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("lmsw rax")) { _ in }
        XCTAssertThrowsError(try X86Assembler.assemble("ltr ebx")) { _ in }
        XCTAssertThrowsError(try X86Assembler.assemble("verr ebx")) { _ in }
    }

    /// SGDT/SIDT/LGDT/LIDT take a memory operand only.
    func testDescriptorTableRejectsRegister() {
        XCTAssertThrowsError(try X86Assembler.assemble("sgdt rax")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testDescriptorAndSystemRMStreamRoundTrip() throws {
        let cases = Self.descriptorTableCases + Self.systemRMCases
        let source = cases.map(\.0).joined(separator: "\n")
        let expected = cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 11c MOV CR/DR + LAR/LSL

    private static let controlDebugMovCases: [(String, [UInt8])] = [
        // MOV r64, CRn
        ("mov rax, cr0",  [0x0F, 0x20, 0xC0]),
        ("mov rax, cr3",  [0x0F, 0x20, 0xD8]),
        ("mov rax, cr8",  [0x44, 0x0F, 0x20, 0xC0]),
        ("mov r8, cr0",   [0x41, 0x0F, 0x20, 0xC0]),
        // MOV CRn, r64
        ("mov cr0, rax",  [0x0F, 0x22, 0xC0]),
        ("mov cr3, rax",  [0x0F, 0x22, 0xD8]),
        ("mov cr8, rax",  [0x44, 0x0F, 0x22, 0xC0]),
        ("mov cr0, r8",   [0x41, 0x0F, 0x22, 0xC0]),
        // MOV r64, DRn
        ("mov rax, dr0",  [0x0F, 0x21, 0xC0]),
        ("mov rax, dr7",  [0x0F, 0x21, 0xF8]),
        // MOV DRn, r64
        ("mov dr0, rax",  [0x0F, 0x23, 0xC0]),
        ("mov dr7, rcx",  [0x0F, 0x23, 0xF9]),
    ]

    private static let larLslCases: [(String, [UInt8])] = [
        ("lar ax, bx",      [0x66, 0x0F, 0x02, 0xC3]),
        ("lar eax, ebx",    [0x0F, 0x02, 0xC3]),
        ("lar rax, rbx",    [0x48, 0x0F, 0x02, 0xC3]),
        ("lar rax, [rbx]",  [0x48, 0x0F, 0x02, 0x03]),

        ("lsl ax, bx",      [0x66, 0x0F, 0x03, 0xC3]),
        ("lsl eax, ebx",    [0x0F, 0x03, 0xC3]),
        ("lsl rax, rbx",    [0x48, 0x0F, 0x03, 0xC3]),
        ("lsl rax, [rbx]",  [0x48, 0x0F, 0x03, 0x03]),
    ]

    func testControlDebugMovAssembles() throws {
        for (source, expected) in Self.controlDebugMovCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testControlDebugMovDisassembles() throws {
        for (source, bytes) in Self.controlDebugMovCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testControlDebugMovRequiresQword() {
        XCTAssertThrowsError(try X86Assembler.assemble("mov eax, cr0")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("mov cr0, eax")) { _ in }
    }

    func testLarLslAssembles() throws {
        for (source, expected) in Self.larLslCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testLarLslDisassembles() throws {
        for (source, bytes) in Self.larLslCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testControlDebugAndLarLslStreamRoundTrip() throws {
        let cases = Self.controlDebugMovCases + Self.larLslCases
        let source = cases.map(\.0).joined(separator: "\n")
        let expected = cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 12a x87 zero-operand instructions

    private static let x87ZeroOperandCases: [(String, [UInt8])] = [
        // Unary FP and rounding
        ("fchs",     [0xD9, 0xE0]),
        ("fabs",     [0xD9, 0xE1]),
        ("ftst",     [0xD9, 0xE4]),
        ("fxam",     [0xD9, 0xE5]),
        ("fsqrt",    [0xD9, 0xFA]),
        ("frndint",  [0xD9, 0xFC]),
        // Constants
        ("fld1",     [0xD9, 0xE8]),
        ("fldl2t",   [0xD9, 0xE9]),
        ("fldl2e",   [0xD9, 0xEA]),
        ("fldpi",    [0xD9, 0xEB]),
        ("fldlg2",   [0xD9, 0xEC]),
        ("fldln2",   [0xD9, 0xED]),
        ("fldz",     [0xD9, 0xEE]),
        // Transcendental / arithmetic
        ("f2xm1",    [0xD9, 0xF0]),
        ("fyl2x",    [0xD9, 0xF1]),
        ("fptan",    [0xD9, 0xF2]),
        ("fpatan",   [0xD9, 0xF3]),
        ("fxtract",  [0xD9, 0xF4]),
        ("fprem1",   [0xD9, 0xF5]),
        ("fprem",    [0xD9, 0xF8]),
        ("fyl2xp1",  [0xD9, 0xF9]),
        ("fsincos",  [0xD9, 0xFB]),
        ("fscale",   [0xD9, 0xFD]),
        ("fsin",     [0xD9, 0xFE]),
        ("fcos",     [0xD9, 0xFF]),
        // Stack pointer adjustments
        ("fdecstp",  [0xD9, 0xF6]),
        ("fincstp",  [0xD9, 0xF7]),
        ("fnop",     [0xD9, 0xD0]),
        // Compare-and-pop pairs
        ("fucompp",  [0xDA, 0xE9]),
        ("fcompp",   [0xDE, 0xD9]),
        // Control word (no-WAIT and WAIT pairs)
        ("fnclex",   [0xDB, 0xE2]),
        ("fninit",   [0xDB, 0xE3]),
        ("fclex",    [0x9B, 0xDB, 0xE2]),
        ("finit",    [0x9B, 0xDB, 0xE3]),
    ]

    func testX87ZeroOperandAssembles() throws {
        for (mnemonic, expected) in Self.x87ZeroOperandCases {
            XCTAssertEqual(try X86Assembler.assemble(mnemonic), expected, "assemble \(mnemonic)")
        }
    }

    func testX87ZeroOperandDisassembles() throws {
        for (mnemonic, bytes) in Self.x87ZeroOperandCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), mnemonic, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// FWAIT (0x9B) on its own is still recognised as the `wait`
    /// mnemonic — the longer 9B DB E2/E3 sequences only win when the
    /// next two bytes form FCLEX/FINIT, so a bare 0x9B falls through
    /// to the wait entry.
    func testFwaitStillRecognisedAfterFclexFinit() throws {
        XCTAssertEqual(try X86Assembler.assemble("wait"), [0x9B])
        XCTAssertEqual(try X86Assembler.disassemble([0x9B]), "wait")
        XCTAssertEqual(try X86Assembler.assemble("fwait"), [0x9B])
    }

    func testX87ZeroOperandStreamRoundTrip() throws {
        let source = Self.x87ZeroOperandCases.map(\.0).joined(separator: "\n")
        let expected = Self.x87ZeroOperandCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14a SSE MOV family

    private static let sseMovCases: [(String, [UInt8])] = [
        // MOVAPS / MOVUPS — no mandatory prefix
        ("movaps xmm0, xmm1",              [0x0F, 0x28, 0xC1]),
        ("movaps xmm0, xmmword ptr [rbx]", [0x0F, 0x28, 0x03]),
        ("movaps xmmword ptr [rbx], xmm0", [0x0F, 0x29, 0x03]),
        ("movups xmm0, xmm1",              [0x0F, 0x10, 0xC1]),
        ("movups xmmword ptr [rbx], xmm1", [0x0F, 0x11, 0x0B]),

        // MOVAPD / MOVUPD — 0x66 mandatory prefix
        ("movapd xmm0, xmm1",              [0x66, 0x0F, 0x28, 0xC1]),
        ("movupd xmm0, xmmword ptr [rbx]", [0x66, 0x0F, 0x10, 0x03]),

        // MOVDQA / MOVDQU
        ("movdqa xmm0, xmm1",              [0x66, 0x0F, 0x6F, 0xC1]),
        ("movdqa xmmword ptr [rbx], xmm0", [0x66, 0x0F, 0x7F, 0x03]),
        ("movdqu xmm0, xmm1",              [0xF3, 0x0F, 0x6F, 0xC1]),
        ("movdqu xmm0, xmmword ptr [rbx]", [0xF3, 0x0F, 0x6F, 0x03]),

        // MOVSS (m32 source/destination)
        ("movss xmm0, xmm1",            [0xF3, 0x0F, 0x10, 0xC1]),
        ("movss xmm0, dword ptr [rbx]", [0xF3, 0x0F, 0x10, 0x03]),
        ("movss dword ptr [rbx], xmm0", [0xF3, 0x0F, 0x11, 0x03]),

        // MOVSD (m64 source/destination)
        ("movsd xmm0, xmm1",            [0xF2, 0x0F, 0x10, 0xC1]),
        ("movsd xmm0, qword ptr [rbx]", [0xF2, 0x0F, 0x10, 0x03]),
        ("movsd qword ptr [rbx], xmm0", [0xF2, 0x0F, 0x11, 0x03]),

        // Extended XMM registers (XMM8..XMM15)
        ("movaps xmm8, xmm0",  [0x44, 0x0F, 0x28, 0xC0]),
        ("movaps xmm0, xmm8",  [0x41, 0x0F, 0x28, 0xC0]),
        ("movaps xmm8, xmm9",  [0x45, 0x0F, 0x28, 0xC1]),
        ("movaps xmm15, xmm0", [0x44, 0x0F, 0x28, 0xF8]),

        // XMM register + memory with extended SIB
        ("movaps xmm8, xmmword ptr [r9 + 16]",  [0x45, 0x0F, 0x28, 0x41, 0x10]),
    ]

    func testSSEMovAssembles() throws {
        for (source, expected) in Self.sseMovCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEMovDisassembles() throws {
        for (source, bytes) in Self.sseMovCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// `movsd` with no operands stays the string-op (MOVSD scalar
    /// double-word). With two operands it routes to the SSE2 scalar
    /// double-precision move.
    func testMovsdMnemonicDisambiguation() throws {
        XCTAssertEqual(try X86Assembler.assemble("movsd"), [0xA5])
        XCTAssertEqual(try X86Assembler.assemble("movsd xmm0, xmm1"), [0xF2, 0x0F, 0x10, 0xC1])
        XCTAssertEqual(try X86Assembler.disassemble([0xA5]), "movsd")
        XCTAssertEqual(try X86Assembler.disassemble([0xF2, 0x0F, 0x10, 0xC1]), "movsd xmm0, xmm1")
    }

    /// Memory operand width must match the mnemonic's intrinsic size.
    func testSSEMovMemoryWidthMismatch() {
        XCTAssertThrowsError(try X86Assembler.assemble("movaps xmm0, qword ptr [rbx]")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("movss xmm0, qword ptr [rbx]")) { _ in }
    }

    func testSSEMovRejectsTwoMemoryOperands() {
        XCTAssertThrowsError(try X86Assembler.assemble("movaps [rbx], [rcx]")) { _ in }
    }

    func testSSEMovStreamRoundTrip() throws {
        let source = Self.sseMovCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseMovCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14b SSE arithmetic

    private static let sseArithmeticCases: [(String, [UInt8])] = [
        // ADD across all four variants
        ("addps xmm0, xmm1",                [0x0F, 0x58, 0xC1]),
        ("addpd xmm0, xmm1",                [0x66, 0x0F, 0x58, 0xC1]),
        ("addss xmm0, xmm1",                [0xF3, 0x0F, 0x58, 0xC1]),
        ("addsd xmm0, xmm1",                [0xF2, 0x0F, 0x58, 0xC1]),
        ("addps xmm0, xmmword ptr [rbx]",   [0x0F, 0x58, 0x03]),
        ("addss xmm0, dword ptr [rbx]",     [0xF3, 0x0F, 0x58, 0x03]),
        ("addsd xmm0, qword ptr [rbx]",     [0xF2, 0x0F, 0x58, 0x03]),

        // SUB
        ("subps xmm0, xmm1",                [0x0F, 0x5C, 0xC1]),
        ("subpd xmm0, xmm1",                [0x66, 0x0F, 0x5C, 0xC1]),
        ("subss xmm2, xmm3",                [0xF3, 0x0F, 0x5C, 0xD3]),
        ("subsd xmm0, xmm1",                [0xF2, 0x0F, 0x5C, 0xC1]),

        // MUL
        ("mulps xmm0, xmm1",                [0x0F, 0x59, 0xC1]),
        ("mulpd xmm0, xmm1",                [0x66, 0x0F, 0x59, 0xC1]),
        ("mulss xmm0, xmm1",                [0xF3, 0x0F, 0x59, 0xC1]),
        ("mulsd xmm0, xmm1",                [0xF2, 0x0F, 0x59, 0xC1]),

        // DIV
        ("divps xmm0, xmm1",                [0x0F, 0x5E, 0xC1]),
        ("divpd xmm0, xmm1",                [0x66, 0x0F, 0x5E, 0xC1]),
        ("divss xmm0, xmm1",                [0xF3, 0x0F, 0x5E, 0xC1]),
        ("divsd xmm0, xmm1",                [0xF2, 0x0F, 0x5E, 0xC1]),

        // MIN / MAX
        ("minps xmm0, xmm1",                [0x0F, 0x5D, 0xC1]),
        ("maxps xmm0, xmm1",                [0x0F, 0x5F, 0xC1]),
        ("minsd xmm0, xmm1",                [0xF2, 0x0F, 0x5D, 0xC1]),
        ("maxss xmm0, xmm1",                [0xF3, 0x0F, 0x5F, 0xC1]),

        // SQRT (binary form: src is r/m even though the operation is
        // mathematically unary)
        ("sqrtps xmm0, xmm1",               [0x0F, 0x51, 0xC1]),
        ("sqrtpd xmm0, xmm1",               [0x66, 0x0F, 0x51, 0xC1]),
        ("sqrtss xmm0, xmm1",               [0xF3, 0x0F, 0x51, 0xC1]),
        ("sqrtsd xmm0, xmm1",               [0xF2, 0x0F, 0x51, 0xC1]),
        ("sqrtps xmm0, xmmword ptr [rbx]",  [0x0F, 0x51, 0x03]),

        // Extended XMM
        ("addps xmm8, xmm9",                [0x45, 0x0F, 0x58, 0xC1]),
        ("subsd xmm15, qword ptr [r8]",     [0xF2, 0x45, 0x0F, 0x5C, 0x38]),
    ]

    func testSSEArithmeticAssembles() throws {
        for (source, expected) in Self.sseArithmeticCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEArithmeticDisassembles() throws {
        for (source, bytes) in Self.sseArithmeticCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSEArithmeticMemoryWidthMismatch() {
        XCTAssertThrowsError(try X86Assembler.assemble("addps xmm0, dword ptr [rbx]")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("addss xmm0, qword ptr [rbx]")) { _ in }
    }

    func testSSEArithmeticRejectsNonXMMDestination() {
        XCTAssertThrowsError(try X86Assembler.assemble("addps rax, xmm1")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testSSEArithmeticStreamRoundTrip() throws {
        let source = Self.sseArithmeticCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseArithmeticCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14c SSE logic + RCP/RSQRT

    private static let sseLogicAndReciprocalCases: [(String, [UInt8])] = [
        // RCP / RSQRT — single-precision only
        ("rcpps xmm0, xmm1",                [0x0F, 0x53, 0xC1]),
        ("rcpss xmm0, xmm1",                [0xF3, 0x0F, 0x53, 0xC1]),
        ("rcpss xmm0, dword ptr [rbx]",     [0xF3, 0x0F, 0x53, 0x03]),
        ("rsqrtps xmm0, xmm1",              [0x0F, 0x52, 0xC1]),
        ("rsqrtss xmm0, xmm1",              [0xF3, 0x0F, 0x52, 0xC1]),

        // Bit-wise logic — PS / PD only
        ("andps xmm0, xmm1",                [0x0F, 0x54, 0xC1]),
        ("andpd xmm0, xmm1",                [0x66, 0x0F, 0x54, 0xC1]),
        ("andnps xmm0, xmm1",               [0x0F, 0x55, 0xC1]),
        ("andnpd xmm0, xmm1",               [0x66, 0x0F, 0x55, 0xC1]),
        ("orps xmm0, xmm1",                 [0x0F, 0x56, 0xC1]),
        ("orpd xmm0, xmm1",                 [0x66, 0x0F, 0x56, 0xC1]),
        ("xorps xmm0, xmm1",                [0x0F, 0x57, 0xC1]),
        ("xorpd xmm0, xmm1",                [0x66, 0x0F, 0x57, 0xC1]),

        // Common idiom: zero a register via XOR with itself
        ("xorps xmm0, xmm0",                [0x0F, 0x57, 0xC0]),
        ("xorpd xmm0, xmm0",                [0x66, 0x0F, 0x57, 0xC0]),

        // Memory operands and extended XMM registers
        ("andps xmm0, xmmword ptr [rbx]",   [0x0F, 0x54, 0x03]),
        ("xorpd xmm8, xmmword ptr [r9]",    [0x66, 0x45, 0x0F, 0x57, 0x01]),
        ("rsqrtps xmm15, xmm0",             [0x44, 0x0F, 0x52, 0xF8]),
    ]

    func testSSELogicAndReciprocalAssembles() throws {
        for (source, expected) in Self.sseLogicAndReciprocalCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSELogicAndReciprocalDisassembles() throws {
        for (source, bytes) in Self.sseLogicAndReciprocalCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSELogicAndReciprocalStreamRoundTrip() throws {
        let source = Self.sseLogicAndReciprocalCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseLogicAndReciprocalCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14d SSE COMI / UCOMI

    private static let sseCompareCases: [(String, [UInt8])] = [
        // UCOMI (quiet — doesn't signal on QNaN)
        ("ucomiss xmm0, xmm1",              [0x0F, 0x2E, 0xC1]),
        ("ucomisd xmm0, xmm1",              [0x66, 0x0F, 0x2E, 0xC1]),
        ("ucomiss xmm0, dword ptr [rbx]",   [0x0F, 0x2E, 0x03]),
        ("ucomisd xmm0, qword ptr [rbx]",   [0x66, 0x0F, 0x2E, 0x03]),

        // COMI (ordered — signals on QNaN)
        ("comiss xmm0, xmm1",               [0x0F, 0x2F, 0xC1]),
        ("comisd xmm0, xmm1",               [0x66, 0x0F, 0x2F, 0xC1]),
        ("comiss xmm0, dword ptr [rbx]",    [0x0F, 0x2F, 0x03]),
        ("comisd xmm0, qword ptr [rbx]",    [0x66, 0x0F, 0x2F, 0x03]),

        // Extended XMM register
        ("ucomiss xmm15, xmm0",             [0x44, 0x0F, 0x2E, 0xF8]),
        ("comisd xmm0, xmm8",               [0x66, 0x41, 0x0F, 0x2F, 0xC0]),
    ]

    func testSSECompareAssembles() throws {
        for (source, expected) in Self.sseCompareCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSECompareDisassembles() throws {
        for (source, bytes) in Self.sseCompareCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSECompareWidthMismatch() {
        // COMISS / UCOMISS expect m32; COMISD / UCOMISD expect m64.
        XCTAssertThrowsError(try X86Assembler.assemble("ucomiss xmm0, qword ptr [rbx]")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("comisd xmm0, dword ptr [rbx]")) { _ in }
    }

    func testSSECompareStreamRoundTrip() throws {
        let source = Self.sseCompareCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseCompareCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14e SSE float ↔ float / int conversions (0F 5A / 5B)

    private static let sseConvertXMMCases: [(String, [UInt8])] = [
        // Scalar precision change
        ("cvtss2sd xmm0, xmm1",              [0xF3, 0x0F, 0x5A, 0xC1]),
        ("cvtss2sd xmm0, dword ptr [rbx]",   [0xF3, 0x0F, 0x5A, 0x03]),
        ("cvtsd2ss xmm0, xmm1",              [0xF2, 0x0F, 0x5A, 0xC1]),
        ("cvtsd2ss xmm0, qword ptr [rbx]",   [0xF2, 0x0F, 0x5A, 0x03]),

        // Packed precision change (note source widths)
        ("cvtps2pd xmm0, xmm1",              [0x0F, 0x5A, 0xC1]),
        ("cvtps2pd xmm0, qword ptr [rbx]",   [0x0F, 0x5A, 0x03]),
        ("cvtpd2ps xmm0, xmm1",              [0x66, 0x0F, 0x5A, 0xC1]),
        ("cvtpd2ps xmm0, xmmword ptr [rbx]", [0x66, 0x0F, 0x5A, 0x03]),

        // Integer ↔ packed single (0F 5B family)
        ("cvtdq2ps xmm0, xmm1",              [0x0F, 0x5B, 0xC1]),
        ("cvtdq2ps xmm0, xmmword ptr [rbx]", [0x0F, 0x5B, 0x03]),
        ("cvtps2dq xmm0, xmm1",              [0x66, 0x0F, 0x5B, 0xC1]),
        ("cvttps2dq xmm0, xmm1",             [0xF3, 0x0F, 0x5B, 0xC1]),

        // Extended XMM
        ("cvtss2sd xmm8, xmm9",              [0xF3, 0x45, 0x0F, 0x5A, 0xC1]),
        ("cvtdq2ps xmm15, xmm0",             [0x44, 0x0F, 0x5B, 0xF8]),
    ]

    func testSSEConvertXMMAssembles() throws {
        for (source, expected) in Self.sseConvertXMMCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEConvertXMMDisassembles() throws {
        for (source, bytes) in Self.sseConvertXMMCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// Each kind has an intrinsic source width — a hint that disagrees
    /// is rejected.
    func testSSEConvertXMMRejectsWidthMismatch() {
        // CVTSS2SD source is m32; m64 hint is wrong.
        XCTAssertThrowsError(try X86Assembler.assemble("cvtss2sd xmm0, qword ptr [rbx]")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        // CVTPS2PD source is m64 (low half of an xmm).
        XCTAssertThrowsError(try X86Assembler.assemble("cvtps2pd xmm0, xmmword ptr [rbx]")) { _ in }
    }

    func testSSEConvertXMMStreamRoundTrip() throws {
        let source = Self.sseConvertXMMCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseConvertXMMCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14f SSE GPR ↔ XMM conversions

    private static let sseConvertGPRCases: [(String, [UInt8])] = [
        // CVTSI2SS xmm, r/m32-or-64
        ("cvtsi2ss xmm0, eax",                  [0xF3, 0x0F, 0x2A, 0xC0]),
        ("cvtsi2ss xmm0, rax",                  [0xF3, 0x48, 0x0F, 0x2A, 0xC0]),
        ("cvtsi2ss xmm0, dword ptr [rbx]",      [0xF3, 0x0F, 0x2A, 0x03]),
        ("cvtsi2ss xmm0, qword ptr [rbx]",      [0xF3, 0x48, 0x0F, 0x2A, 0x03]),

        // CVTSI2SD xmm, r/m32-or-64
        ("cvtsi2sd xmm0, eax",                  [0xF2, 0x0F, 0x2A, 0xC0]),
        ("cvtsi2sd xmm0, rax",                  [0xF2, 0x48, 0x0F, 0x2A, 0xC0]),

        // CVTSS2SI r/r64, xmm/m32 (rounded)
        ("cvtss2si eax, xmm0",                  [0xF3, 0x0F, 0x2D, 0xC0]),
        ("cvtss2si rax, xmm0",                  [0xF3, 0x48, 0x0F, 0x2D, 0xC0]),
        ("cvtss2si eax, dword ptr [rbx]",       [0xF3, 0x0F, 0x2D, 0x03]),

        // CVTSD2SI
        ("cvtsd2si rax, xmm0",                  [0xF2, 0x48, 0x0F, 0x2D, 0xC0]),
        ("cvtsd2si eax, qword ptr [rbx]",       [0xF2, 0x0F, 0x2D, 0x03]),

        // CVTTSS2SI / CVTTSD2SI (truncating)
        ("cvttss2si eax, xmm0",                 [0xF3, 0x0F, 0x2C, 0xC0]),
        ("cvttss2si rax, xmm0",                 [0xF3, 0x48, 0x0F, 0x2C, 0xC0]),
        ("cvttsd2si rax, xmm0",                 [0xF2, 0x48, 0x0F, 0x2C, 0xC0]),
        ("cvttsd2si eax, qword ptr [rbx]",      [0xF2, 0x0F, 0x2C, 0x03]),

        // Extended XMM / GPR
        ("cvtsi2ss xmm8, r9",                   [0xF3, 0x4D, 0x0F, 0x2A, 0xC1]),
        ("cvtss2si r8, xmm15",                  [0xF3, 0x4D, 0x0F, 0x2D, 0xC7]),
    ]

    func testSSEConvertGPRAssembles() throws {
        for (source, expected) in Self.sseConvertGPRCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEConvertGPRDisassembles() throws {
        for (source, bytes) in Self.sseConvertGPRCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSEConvertGPRRejectsByteOrWord() {
        XCTAssertThrowsError(try X86Assembler.assemble("cvtsi2ss xmm0, al")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("cvtss2si ax, xmm0")) { _ in }
    }

    func testSSEConvertGPRMemoryNeedsSizeHint() {
        XCTAssertThrowsError(try X86Assembler.assemble("cvtsi2ss xmm0, [rbx]")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testSSEConvertGPRStreamRoundTrip() throws {
        let source = Self.sseConvertGPRCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseConvertGPRCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14g MOVD / MOVQ (XMM ↔ GPR)

    private static let movDQCases: [(String, [UInt8])] = [
        // MOVD xmm, r32 — load 32-bit
        ("movd xmm0, eax",                  [0x66, 0x0F, 0x6E, 0xC0]),
        ("movd xmm0, ebx",                  [0x66, 0x0F, 0x6E, 0xC3]),
        ("movd xmm0, dword ptr [rbx]",      [0x66, 0x0F, 0x6E, 0x03]),

        // MOVD r32, xmm — store low 32 bits
        ("movd eax, xmm0",                  [0x66, 0x0F, 0x7E, 0xC0]),
        ("movd dword ptr [rbx], xmm0",      [0x66, 0x0F, 0x7E, 0x03]),

        // MOVQ xmm, r64 — load 64-bit
        ("movq xmm0, rax",                  [0x66, 0x48, 0x0F, 0x6E, 0xC0]),
        ("movq xmm0, qword ptr [rbx]",      [0x66, 0x48, 0x0F, 0x6E, 0x03]),

        // MOVQ r64, xmm — store low 64 bits
        ("movq rax, xmm0",                  [0x66, 0x48, 0x0F, 0x7E, 0xC0]),
        ("movq qword ptr [rbx], xmm0",      [0x66, 0x48, 0x0F, 0x7E, 0x03]),

        // Extended XMM and GPR
        ("movd xmm8, r9d",                  [0x66, 0x45, 0x0F, 0x6E, 0xC1]),
        ("movq r15, xmm15",                 [0x66, 0x4D, 0x0F, 0x7E, 0xFF]),
    ]

    func testMovDQAssembles() throws {
        for (source, expected) in Self.movDQCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testMovDQDisassembles() throws {
        for (source, bytes) in Self.movDQCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testMovDQRejectsWidthMismatch() {
        // MOVD expects r32; MOVQ expects r64.
        XCTAssertThrowsError(try X86Assembler.assemble("movd xmm0, rax")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
        XCTAssertThrowsError(try X86Assembler.assemble("movq xmm0, eax")) { _ in }
    }

    func testMovDQRequiresXMMOnOneSide() {
        // Without an XMM operand the parser routes to the GPR `mov`,
        // not movd / movq.
        XCTAssertThrowsError(try X86Assembler.assemble("movd eax, ebx")) { error in
            guard case AssemblerError.unsupportedOperand = error else {
                return XCTFail("expected unsupportedOperand, got \(error)")
            }
        }
    }

    func testMovDQStreamRoundTrip() throws {
        let source = Self.movDQCases.map(\.0).joined(separator: "\n")
        let expected = Self.movDQCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14h SSE2 packed integer ops

    private static let ssePackedIntegerCases: [(String, [UInt8])] = [
        // Unsaturated add (B/W/D/Q)
        ("paddb xmm0, xmm1",                [0x66, 0x0F, 0xFC, 0xC1]),
        ("paddw xmm0, xmm1",                [0x66, 0x0F, 0xFD, 0xC1]),
        ("paddd xmm0, xmm1",                [0x66, 0x0F, 0xFE, 0xC1]),
        ("paddq xmm0, xmm1",                [0x66, 0x0F, 0xD4, 0xC1]),
        ("paddb xmm0, xmmword ptr [rbx]",   [0x66, 0x0F, 0xFC, 0x03]),

        // Unsaturated sub
        ("psubb xmm0, xmm1",                [0x66, 0x0F, 0xF8, 0xC1]),
        ("psubw xmm0, xmm1",                [0x66, 0x0F, 0xF9, 0xC1]),
        ("psubd xmm0, xmm1",                [0x66, 0x0F, 0xFA, 0xC1]),
        ("psubq xmm0, xmm1",                [0x66, 0x0F, 0xFB, 0xC1]),

        // Saturating signed
        ("paddsb xmm0, xmm1",               [0x66, 0x0F, 0xEC, 0xC1]),
        ("paddsw xmm0, xmm1",               [0x66, 0x0F, 0xED, 0xC1]),
        ("psubsb xmm0, xmm1",               [0x66, 0x0F, 0xE8, 0xC1]),
        ("psubsw xmm0, xmm1",               [0x66, 0x0F, 0xE9, 0xC1]),

        // Saturating unsigned
        ("paddusb xmm0, xmm1",              [0x66, 0x0F, 0xDC, 0xC1]),
        ("paddusw xmm0, xmm1",              [0x66, 0x0F, 0xDD, 0xC1]),
        ("psubusb xmm0, xmm1",              [0x66, 0x0F, 0xD8, 0xC1]),
        ("psubusw xmm0, xmm1",              [0x66, 0x0F, 0xD9, 0xC1]),

        // Bit-wise logic
        ("pand xmm0, xmm1",                 [0x66, 0x0F, 0xDB, 0xC1]),
        ("pandn xmm0, xmm1",                [0x66, 0x0F, 0xDF, 0xC1]),
        ("por xmm0, xmm1",                  [0x66, 0x0F, 0xEB, 0xC1]),
        ("pxor xmm0, xmm1",                 [0x66, 0x0F, 0xEF, 0xC1]),

        // Common idiom + memory + extended XMM
        ("pxor xmm0, xmm0",                 [0x66, 0x0F, 0xEF, 0xC0]),
        ("paddd xmm8, xmmword ptr [r9]",    [0x66, 0x45, 0x0F, 0xFE, 0x01]),
        ("pand xmm15, xmm0",                [0x66, 0x44, 0x0F, 0xDB, 0xF8]),
    ]

    func testSSEPackedIntegerAssembles() throws {
        for (source, expected) in Self.ssePackedIntegerCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEPackedIntegerDisassembles() throws {
        for (source, bytes) in Self.ssePackedIntegerCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSEPackedIntegerStreamRoundTrip() throws {
        let source = Self.ssePackedIntegerCases.map(\.0).joined(separator: "\n")
        let expected = Self.ssePackedIntegerCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14i PCMP / PMUL / PMIN / PMAX / PAVG / PSADBW

    private static let ssePackedIntegerExtraCases: [(String, [UInt8])] = [
        // Compare for equal (sets all-ones on equal lanes)
        ("pcmpeqb xmm0, xmm1",              [0x66, 0x0F, 0x74, 0xC1]),
        ("pcmpeqw xmm0, xmm1",              [0x66, 0x0F, 0x75, 0xC1]),
        ("pcmpeqd xmm0, xmm1",              [0x66, 0x0F, 0x76, 0xC1]),
        // Compare for greater-than (signed)
        ("pcmpgtb xmm0, xmm1",              [0x66, 0x0F, 0x64, 0xC1]),
        ("pcmpgtw xmm0, xmm1",              [0x66, 0x0F, 0x65, 0xC1]),
        ("pcmpgtd xmm0, xmm1",              [0x66, 0x0F, 0x66, 0xC1]),

        // Multiplies
        ("pmullw xmm0, xmm1",               [0x66, 0x0F, 0xD5, 0xC1]),
        ("pmulhw xmm0, xmm1",               [0x66, 0x0F, 0xE5, 0xC1]),
        ("pmulhuw xmm0, xmm1",              [0x66, 0x0F, 0xE4, 0xC1]),
        ("pmuludq xmm0, xmm1",              [0x66, 0x0F, 0xF4, 0xC1]),
        ("pmaddwd xmm0, xmm1",              [0x66, 0x0F, 0xF5, 0xC1]),

        // Per-lane min / max
        ("pminub xmm0, xmm1",               [0x66, 0x0F, 0xDA, 0xC1]),
        ("pminsw xmm0, xmm1",               [0x66, 0x0F, 0xEA, 0xC1]),
        ("pmaxub xmm0, xmm1",               [0x66, 0x0F, 0xDE, 0xC1]),
        ("pmaxsw xmm0, xmm1",               [0x66, 0x0F, 0xEE, 0xC1]),

        // Rounded average and sum-of-absolute-differences
        ("pavgb xmm0, xmm1",                [0x66, 0x0F, 0xE0, 0xC1]),
        ("pavgw xmm0, xmm1",                [0x66, 0x0F, 0xE3, 0xC1]),
        ("psadbw xmm0, xmm1",               [0x66, 0x0F, 0xF6, 0xC1]),

        // Memory operand + extended XMM
        ("pcmpeqd xmm0, xmmword ptr [rbx]", [0x66, 0x0F, 0x76, 0x03]),
        ("pmullw xmm8, xmm9",               [0x66, 0x45, 0x0F, 0xD5, 0xC1]),
    ]

    func testSSEPackedIntegerExtraAssembles() throws {
        for (source, expected) in Self.ssePackedIntegerExtraCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEPackedIntegerExtraDisassembles() throws {
        for (source, bytes) in Self.ssePackedIntegerExtraCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSEPackedIntegerExtraStreamRoundTrip() throws {
        let source = Self.ssePackedIntegerExtraCases.map(\.0).joined(separator: "\n")
        let expected = Self.ssePackedIntegerExtraCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14j PUNPCK + PACK

    private static let ssePackUnpackCases: [(String, [UInt8])] = [
        // Interleave low halves
        ("punpcklbw xmm0, xmm1",            [0x66, 0x0F, 0x60, 0xC1]),
        ("punpcklwd xmm0, xmm1",            [0x66, 0x0F, 0x61, 0xC1]),
        ("punpckldq xmm0, xmm1",            [0x66, 0x0F, 0x62, 0xC1]),
        ("punpcklqdq xmm0, xmm1",           [0x66, 0x0F, 0x6C, 0xC1]),
        // Interleave high halves
        ("punpckhbw xmm0, xmm1",            [0x66, 0x0F, 0x68, 0xC1]),
        ("punpckhwd xmm0, xmm1",            [0x66, 0x0F, 0x69, 0xC1]),
        ("punpckhdq xmm0, xmm1",            [0x66, 0x0F, 0x6A, 0xC1]),
        ("punpckhqdq xmm0, xmm1",           [0x66, 0x0F, 0x6D, 0xC1]),
        // Pack with saturation
        ("packsswb xmm0, xmm1",             [0x66, 0x0F, 0x63, 0xC1]),
        ("packssdw xmm0, xmm1",             [0x66, 0x0F, 0x6B, 0xC1]),
        ("packuswb xmm0, xmm1",             [0x66, 0x0F, 0x67, 0xC1]),
        // Memory + extended XMM
        ("punpcklbw xmm0, xmmword ptr [rbx]", [0x66, 0x0F, 0x60, 0x03]),
        ("packsswb xmm8, xmm9",               [0x66, 0x45, 0x0F, 0x63, 0xC1]),
    ]

    func testSSEPackUnpackAssembles() throws {
        for (source, expected) in Self.ssePackUnpackCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEPackUnpackDisassembles() throws {
        for (source, bytes) in Self.ssePackUnpackCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSEPackUnpackStreamRoundTrip() throws {
        let source = Self.ssePackUnpackCases.map(\.0).joined(separator: "\n")
        let expected = Self.ssePackUnpackCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14k SIMD variable shifts (count taken from xmm/m128)

    private static let sseVariableShiftCases: [(String, [UInt8])] = [
        // Logical shift left
        ("psllw xmm0, xmm1",                [0x66, 0x0F, 0xF1, 0xC1]),
        ("pslld xmm0, xmm1",                [0x66, 0x0F, 0xF2, 0xC1]),
        ("psllq xmm0, xmm1",                [0x66, 0x0F, 0xF3, 0xC1]),
        // Logical shift right
        ("psrlw xmm0, xmm1",                [0x66, 0x0F, 0xD1, 0xC1]),
        ("psrld xmm0, xmm1",                [0x66, 0x0F, 0xD2, 0xC1]),
        ("psrlq xmm0, xmm1",                [0x66, 0x0F, 0xD3, 0xC1]),
        // Arithmetic (signed) shift right — byte and qword variants
        // don't exist, only word and dword.
        ("psraw xmm0, xmm1",                [0x66, 0x0F, 0xE1, 0xC1]),
        ("psrad xmm0, xmm1",                [0x66, 0x0F, 0xE2, 0xC1]),
        // Memory operand + extended XMM
        ("psllq xmm0, xmmword ptr [rbx]",   [0x66, 0x0F, 0xF3, 0x03]),
        ("psraw xmm8, xmm9",                [0x66, 0x45, 0x0F, 0xE1, 0xC1]),
    ]

    func testSSEVariableShiftAssembles() throws {
        for (source, expected) in Self.sseVariableShiftCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEVariableShiftDisassembles() throws {
        for (source, bytes) in Self.sseVariableShiftCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSEVariableShiftStreamRoundTrip() throws {
        let source = Self.sseVariableShiftCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseVariableShiftCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14l imm8 SIMD shifts

    private static let sseImmediateShiftCases: [(String, [UInt8])] = [
        // PSRL imm (word/dword/qword)
        ("psrlw xmm0, 1",                   [0x66, 0x0F, 0x71, 0xD0, 0x01]),
        ("psrld xmm0, 4",                   [0x66, 0x0F, 0x72, 0xD0, 0x04]),
        ("psrlq xmm0, 7",                   [0x66, 0x0F, 0x73, 0xD0, 0x07]),
        // PSLL imm
        ("psllw xmm0, 1",                   [0x66, 0x0F, 0x71, 0xF0, 0x01]),
        ("pslld xmm0, 4",                   [0x66, 0x0F, 0x72, 0xF0, 0x04]),
        ("psllq xmm0, 7",                   [0x66, 0x0F, 0x73, 0xF0, 0x07]),
        // Arithmetic right shift (no qword form exists)
        ("psraw xmm0, 1",                   [0x66, 0x0F, 0x71, 0xE0, 0x01]),
        ("psrad xmm0, 31",                  [0x66, 0x0F, 0x72, 0xE0, 0x1F]),
        // 128-bit byte shifts
        ("pslldq xmm0, 4",                  [0x66, 0x0F, 0x73, 0xF8, 0x04]),
        ("psrldq xmm0, 8",                  [0x66, 0x0F, 0x73, 0xD8, 0x08]),
        // Extended XMM
        ("psllq xmm15, 1",                  [0x66, 0x41, 0x0F, 0x73, 0xF7, 0x01]),
        ("pslldq xmm8, 12",                 [0x66, 0x41, 0x0F, 0x73, 0xF8, 0x0C]),
    ]

    func testSSEImmediateShiftAssembles() throws {
        for (source, expected) in Self.sseImmediateShiftCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEImmediateShiftDisassembles() throws {
        for (source, bytes) in Self.sseImmediateShiftCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// The shift mnemonics overlap variable and imm8 forms; the parser
    /// dispatches on the second operand's type.
    func testSSEShiftMnemonicDisambiguation() throws {
        // Variable form: xmm source
        XCTAssertEqual(try X86Assembler.assemble("psllw xmm0, xmm1"), [0x66, 0x0F, 0xF1, 0xC1])
        // imm8 form
        XCTAssertEqual(try X86Assembler.assemble("psllw xmm0, 4"),    [0x66, 0x0F, 0x71, 0xF0, 0x04])
    }

    func testSSEImmediateShiftStreamRoundTrip() throws {
        let source = Self.sseImmediateShiftCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseImmediateShiftCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14m imm8 shuffles

    private static let sseShuffleCases: [(String, [UInt8])] = [
        // PSHUFD — 66 0F 70 /r ib
        ("pshufd xmm0, xmm1, 0",            [0x66, 0x0F, 0x70, 0xC1, 0x00]),
        ("pshufd xmm0, xmm1, 27",           [0x66, 0x0F, 0x70, 0xC1, 0x1B]),
        // PSHUFLW — F2 0F 70 /r ib
        ("pshuflw xmm2, xmm3, 228",         [0xF2, 0x0F, 0x70, 0xD3, 0xE4]),
        // PSHUFHW — F3 0F 70 /r ib
        ("pshufhw xmm2, xmm3, 228",         [0xF3, 0x0F, 0x70, 0xD3, 0xE4]),
        // SHUFPS — 0F C6 /r ib (no prefix)
        ("shufps xmm4, xmm5, 1",            [0x0F, 0xC6, 0xE5, 0x01]),
        // SHUFPD — 66 0F C6 /r ib
        ("shufpd xmm4, xmm5, 2",            [0x66, 0x0F, 0xC6, 0xE5, 0x02]),
        // Extended XMM operands
        ("pshufd xmm15, xmm0, 0",           [0x66, 0x44, 0x0F, 0x70, 0xF8, 0x00]),
        ("shufps xmm0, xmm15, 3",           [0x41, 0x0F, 0xC6, 0xC7, 0x03]),
        // Memory source
        ("pshufd xmm0, xmmword ptr [rdi], 4",     [0x66, 0x0F, 0x70, 0x07, 0x04]),
        ("shufpd xmm1, xmmword ptr [rbx + 8], 1", [0x66, 0x0F, 0xC6, 0x4B, 0x08, 0x01]),
    ]

    func testSSEShuffleAssembles() throws {
        for (source, expected) in Self.sseShuffleCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEShuffleDisassembles() throws {
        for (source, bytes) in Self.sseShuffleCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSEShuffleStreamRoundTrip() throws {
        let source = Self.sseShuffleCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseShuffleCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14n SSE compares (imm8 predicate)

    private static let ssePredicateCompareCases: [(String, [UInt8])] = [
        // CMPPS — no prefix
        ("cmpps xmm0, xmm1, 0",                 [0x0F, 0xC2, 0xC1, 0x00]),
        ("cmpps xmm0, xmm1, 7",                 [0x0F, 0xC2, 0xC1, 0x07]),
        // CMPPD — 66
        ("cmppd xmm2, xmm3, 2",                 [0x66, 0x0F, 0xC2, 0xD3, 0x02]),
        // CMPSS — F3
        ("cmpss xmm4, xmm5, 1",                 [0xF3, 0x0F, 0xC2, 0xE5, 0x01]),
        // CMPSD — F2 (SSE form, not the string op)
        ("cmpsd xmm6, xmm7, 4",                 [0xF2, 0x0F, 0xC2, 0xF7, 0x04]),
        // Extended XMM
        ("cmpps xmm15, xmm0, 0",                [0x44, 0x0F, 0xC2, 0xF8, 0x00]),
        ("cmppd xmm0, xmm15, 1",                [0x66, 0x41, 0x0F, 0xC2, 0xC7, 0x01]),
        // Memory source
        ("cmpps xmm0, xmmword ptr [rdi], 3",    [0x0F, 0xC2, 0x07, 0x03]),
        ("cmpsd xmm1, xmmword ptr [rbx + 4], 5",[0xF2, 0x0F, 0xC2, 0x4B, 0x04, 0x05]),
    ]

    func testSSEPredicateCompareAssembles() throws {
        for (source, expected) in Self.ssePredicateCompareCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEPredicateCompareDisassembles() throws {
        for (source, bytes) in Self.ssePredicateCompareCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// CMPSD with no operands is the string instruction; with three it
    /// is the SSE scalar-double compare. Both forms must coexist.
    func testCMPSDMnemonicDisambiguation() throws {
        XCTAssertEqual(try X86Assembler.assemble("cmpsd"),                      [0xA7])
        XCTAssertEqual(try X86Assembler.assemble("cmpsd xmm0, xmm1, 0"),        [0xF2, 0x0F, 0xC2, 0xC1, 0x00])
    }

    func testSSEPredicateCompareStreamRoundTrip() throws {
        let source = Self.ssePredicateCompareCases.map(\.0).joined(separator: "\n")
        let expected = Self.ssePredicateCompareCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14o SSE half-vector moves

    private static let sseHalfMoveCases: [(String, [UInt8])] = [
        // MOVLPS — 0F 12/13
        ("movlps xmm0, qword ptr [rdi]",        [0x0F, 0x12, 0x07]),
        ("movlps qword ptr [rdi], xmm0",        [0x0F, 0x13, 0x07]),
        // MOVHPS — 0F 16/17
        ("movhps xmm1, qword ptr [rsi]",        [0x0F, 0x16, 0x0E]),
        ("movhps qword ptr [rsi], xmm1",        [0x0F, 0x17, 0x0E]),
        // MOVLPD — 66 0F 12/13
        ("movlpd xmm2, qword ptr [rbx]",        [0x66, 0x0F, 0x12, 0x13]),
        ("movlpd qword ptr [rbx], xmm2",        [0x66, 0x0F, 0x13, 0x13]),
        // MOVHPD — 66 0F 16/17
        ("movhpd xmm3, qword ptr [rcx]",        [0x66, 0x0F, 0x16, 0x19]),
        ("movhpd qword ptr [rcx], xmm3",        [0x66, 0x0F, 0x17, 0x19]),
        // MOVHLPS / MOVLHPS — register-only
        ("movhlps xmm0, xmm1",                  [0x0F, 0x12, 0xC1]),
        ("movlhps xmm0, xmm1",                  [0x0F, 0x16, 0xC1]),
        // Extended XMM
        ("movlps xmm15, qword ptr [rax]",       [0x44, 0x0F, 0x12, 0x38]),
        ("movhpd qword ptr [r9], xmm8",         [0x66, 0x45, 0x0F, 0x17, 0x01]),
        ("movhlps xmm8, xmm15",                 [0x45, 0x0F, 0x12, 0xC7]),
    ]

    func testSSEHalfMoveAssembles() throws {
        for (source, expected) in Self.sseHalfMoveCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEHalfMoveDisassembles() throws {
        for (source, bytes) in Self.sseHalfMoveCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// Reg-only mnemonics must reject memory; memory mnemonics must
    /// reject xmm-only forms.
    func testSSEHalfMoveOperandShapeRejections() {
        XCTAssertThrowsError(try X86Assembler.assemble("movhlps xmm0, qword ptr [rdi]")) { _ in }
        XCTAssertThrowsError(try X86Assembler.assemble("movlps xmm0, xmm1")) { _ in }
    }

    func testSSEHalfMoveStreamRoundTrip() throws {
        let source = Self.sseHalfMoveCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseHalfMoveCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14p mask extract / MASKMOVDQU

    private static let sseMaskExtractCases: [(String, [UInt8])] = [
        // MOVMSKPS — no prefix
        ("movmskps eax, xmm1",              [0x0F, 0x50, 0xC1]),
        ("movmskps rax, xmm1",              [0x48, 0x0F, 0x50, 0xC1]),
        // MOVMSKPD — 66
        ("movmskpd ecx, xmm2",              [0x66, 0x0F, 0x50, 0xCA]),
        // PMOVMSKB — 66 0F D7
        ("pmovmskb edx, xmm3",              [0x66, 0x0F, 0xD7, 0xD3]),
        ("pmovmskb r10, xmm15",             [0x66, 0x4D, 0x0F, 0xD7, 0xD7]),
        // MASKMOVDQU — 66 0F F7
        ("maskmovdqu xmm0, xmm1",           [0x66, 0x0F, 0xF7, 0xC1]),
        ("maskmovdqu xmm15, xmm8",          [0x66, 0x45, 0x0F, 0xF7, 0xF8]),
    ]

    func testSSEMaskExtractAssembles() throws {
        for (source, expected) in Self.sseMaskExtractCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEMaskExtractDisassembles() throws {
        for (source, bytes) in Self.sseMaskExtractCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testMaskExtractRejectsByteRegister() {
        XCTAssertThrowsError(try X86Assembler.assemble("movmskps al, xmm0")) { _ in }
    }

    func testSSEMaskExtractStreamRoundTrip() throws {
        let source = Self.sseMaskExtractCases.map(\.0).joined(separator: "\n")
        let expected = Self.sseMaskExtractCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14q MXCSR + non-temporal stores

    private static let mxcsrNontemporalCases: [(String, [UInt8])] = [
        // LDMXCSR / STMXCSR
        ("ldmxcsr dword ptr [rdi]",                 [0x0F, 0xAE, 0x17]),
        ("stmxcsr dword ptr [rsi]",                 [0x0F, 0xAE, 0x1E]),
        // MOVNTPS — no prefix
        ("movntps xmmword ptr [rdi], xmm0",         [0x0F, 0x2B, 0x07]),
        ("movntps xmmword ptr [r8], xmm15",         [0x45, 0x0F, 0x2B, 0x38]),
        // MOVNTPD — 66 prefix
        ("movntpd xmmword ptr [rsi], xmm1",         [0x66, 0x0F, 0x2B, 0x0E]),
        // MOVNTDQ — 66 0F E7
        ("movntdq xmmword ptr [rdx], xmm2",         [0x66, 0x0F, 0xE7, 0x12]),
        // MOVNTI — 32 / 64
        ("movnti dword ptr [rdi], eax",             [0x0F, 0xC3, 0x07]),
        ("movnti qword ptr [rdi], rax",             [0x48, 0x0F, 0xC3, 0x07]),
        ("movnti qword ptr [r9], r10",              [0x4D, 0x0F, 0xC3, 0x11]),
    ]

    func testMXCSRNontemporalAssembles() throws {
        for (source, expected) in Self.mxcsrNontemporalCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testMXCSRNontemporalDisassembles() throws {
        for (source, bytes) in Self.mxcsrNontemporalCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testMovntiWidthMismatchRejected() {
        XCTAssertThrowsError(try X86Assembler.assemble("movnti qword ptr [rdi], eax")) { _ in }
    }

    func testMXCSRNontemporalStreamRoundTrip() throws {
        let source = Self.mxcsrNontemporalCases.map(\.0).joined(separator: "\n")
        let expected = Self.mxcsrNontemporalCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14r PREFETCH family

    private static let prefetchCases: [(String, [UInt8])] = [
        ("prefetchnta byte ptr [rdi]",          [0x0F, 0x18, 0x07]),
        ("prefetcht0 byte ptr [rdi]",           [0x0F, 0x18, 0x0F]),
        ("prefetcht1 byte ptr [rdi]",           [0x0F, 0x18, 0x17]),
        ("prefetcht2 byte ptr [rdi]",           [0x0F, 0x18, 0x1F]),
        ("prefetchw byte ptr [rdi]",            [0x0F, 0x0D, 0x0F]),
        // Extended base register
        ("prefetcht0 byte ptr [r9]",            [0x41, 0x0F, 0x18, 0x09]),
        // RIP-relative
        ("prefetcht0 byte ptr [rip + 16]",      [0x0F, 0x18, 0x0D, 0x10, 0x00, 0x00, 0x00]),
    ]

    func testPrefetchAssembles() throws {
        for (source, expected) in Self.prefetchCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testPrefetchDisassembles() throws {
        for (source, bytes) in Self.prefetchCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testPrefetchStreamRoundTrip() throws {
        let source = Self.prefetchCases.map(\.0).joined(separator: "\n")
        let expected = Self.prefetchCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 14s SSE3

    private static let sse3Cases: [(String, [UInt8])] = [
        // ADDSUB
        ("addsubps xmm0, xmm1",                     [0xF2, 0x0F, 0xD0, 0xC1]),
        ("addsubpd xmm0, xmm1",                     [0x66, 0x0F, 0xD0, 0xC1]),
        // HADD / HSUB
        ("haddps xmm2, xmm3",                       [0xF2, 0x0F, 0x7C, 0xD3]),
        ("haddpd xmm2, xmm3",                       [0x66, 0x0F, 0x7C, 0xD3]),
        ("hsubps xmm4, xmm5",                       [0xF2, 0x0F, 0x7D, 0xE5]),
        ("hsubpd xmm4, xmm5",                       [0x66, 0x0F, 0x7D, 0xE5]),
        // MOV*DUP
        ("movshdup xmm0, xmm1",                     [0xF3, 0x0F, 0x16, 0xC1]),
        ("movsldup xmm0, xmm1",                     [0xF3, 0x0F, 0x12, 0xC1]),
        ("movddup xmm0, xmm1",                      [0xF2, 0x0F, 0x12, 0xC1]),
        ("movddup xmm0, qword ptr [rdi]",           [0xF2, 0x0F, 0x12, 0x07]),
        // LDDQU
        ("lddqu xmm6, xmmword ptr [rdi]",           [0xF2, 0x0F, 0xF0, 0x37]),
        // Extended XMM
        ("addsubps xmm15, xmm0",                    [0xF2, 0x44, 0x0F, 0xD0, 0xF8]),
        ("haddpd xmm0, xmm15",                      [0x66, 0x41, 0x0F, 0x7C, 0xC7]),
        // Memory source
        ("addsubps xmm0, xmmword ptr [rdi]",        [0xF2, 0x0F, 0xD0, 0x07]),
    ]

    func testSSE3Assembles() throws {
        for (source, expected) in Self.sse3Cases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSE3Disassembles() throws {
        for (source, bytes) in Self.sse3Cases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testLddquRejectsRegisterSource() {
        XCTAssertThrowsError(try X86Assembler.assemble("lddqu xmm0, xmm1")) { _ in }
    }

    func testSSE3StreamRoundTrip() throws {
        let source = Self.sse3Cases.map(\.0).joined(separator: "\n")
        let expected = Self.sse3Cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 15 SSSE3

    private static let ssse3Cases: [(String, [UInt8])] = [
        // Byte shuffle
        ("pshufb xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x00, 0xC1]),
        // Horizontal add / sub family
        ("phaddw xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x01, 0xC1]),
        ("phaddd xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x02, 0xC1]),
        ("phaddsw xmm0, xmm1",                      [0x66, 0x0F, 0x38, 0x03, 0xC1]),
        ("pmaddubsw xmm0, xmm1",                    [0x66, 0x0F, 0x38, 0x04, 0xC1]),
        ("phsubw xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x05, 0xC1]),
        ("phsubd xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x06, 0xC1]),
        ("phsubsw xmm0, xmm1",                      [0x66, 0x0F, 0x38, 0x07, 0xC1]),
        // Sign-controlled negate
        ("psignb xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x08, 0xC1]),
        ("psignw xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x09, 0xC1]),
        ("psignd xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x0A, 0xC1]),
        // Multiply high with rounding
        ("pmulhrsw xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x0B, 0xC1]),
        // Absolute value
        ("pabsb xmm0, xmm1",                        [0x66, 0x0F, 0x38, 0x1C, 0xC1]),
        ("pabsw xmm0, xmm1",                        [0x66, 0x0F, 0x38, 0x1D, 0xC1]),
        ("pabsd xmm0, xmm1",                        [0x66, 0x0F, 0x38, 0x1E, 0xC1]),
        // PALIGNR (0F 3A)
        ("palignr xmm0, xmm1, 3",                   [0x66, 0x0F, 0x3A, 0x0F, 0xC1, 0x03]),
        // Extended XMM
        ("pshufb xmm15, xmm0",                      [0x66, 0x44, 0x0F, 0x38, 0x00, 0xF8]),
        ("pabsd xmm0, xmm15",                       [0x66, 0x41, 0x0F, 0x38, 0x1E, 0xC7]),
        // Memory source
        ("pshufb xmm0, xmmword ptr [rdi]",          [0x66, 0x0F, 0x38, 0x00, 0x07]),
        ("palignr xmm0, xmmword ptr [rsi], 7",      [0x66, 0x0F, 0x3A, 0x0F, 0x06, 0x07]),
    ]

    func testSSSE3Assembles() throws {
        for (source, expected) in Self.ssse3Cases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSSE3Disassembles() throws {
        for (source, bytes) in Self.ssse3Cases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSSE3StreamRoundTrip() throws {
        let source = Self.ssse3Cases.map(\.0).joined(separator: "\n")
        let expected = Self.ssse3Cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 16a SSE4.1 PMOVSX*/PMOVZX*

    private static let ssePackExtendCases: [(String, [UInt8])] = [
        // Sign-extending forms
        ("pmovsxbw xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x20, 0xC1]),
        ("pmovsxbd xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x21, 0xC1]),
        ("pmovsxbq xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x22, 0xC1]),
        ("pmovsxwd xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x23, 0xC1]),
        ("pmovsxwq xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x24, 0xC1]),
        ("pmovsxdq xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x25, 0xC1]),
        // Zero-extending forms
        ("pmovzxbw xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x30, 0xC1]),
        ("pmovzxbd xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x31, 0xC1]),
        ("pmovzxbq xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x32, 0xC1]),
        ("pmovzxwd xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x33, 0xC1]),
        ("pmovzxwq xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x34, 0xC1]),
        ("pmovzxdq xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x35, 0xC1]),
        // Memory source — widths vary
        ("pmovsxbw xmm0, qword ptr [rdi]",          [0x66, 0x0F, 0x38, 0x20, 0x07]),
        ("pmovsxbd xmm0, dword ptr [rdi]",          [0x66, 0x0F, 0x38, 0x21, 0x07]),
        ("pmovsxbq xmm0, word ptr [rdi]",           [0x66, 0x0F, 0x38, 0x22, 0x07]),
        ("pmovzxwq xmm0, dword ptr [rdi]",          [0x66, 0x0F, 0x38, 0x34, 0x07]),
        // Extended XMM
        ("pmovzxbw xmm15, xmm0",                    [0x66, 0x44, 0x0F, 0x38, 0x30, 0xF8]),
    ]

    func testSSEPackExtendAssembles() throws {
        for (source, expected) in Self.ssePackExtendCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSEPackExtendDisassembles() throws {
        for (source, bytes) in Self.ssePackExtendCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testSSEPackExtendWidthMismatchRejected() {
        XCTAssertThrowsError(try X86Assembler.assemble("pmovsxbw xmm0, dword ptr [rdi]")) { _ in }
    }

    func testSSEPackExtendStreamRoundTrip() throws {
        let source = Self.ssePackExtendCases.map(\.0).joined(separator: "\n")
        let expected = Self.ssePackExtendCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 16b SSE4.1 PMUL/PMIN/PMAX/PACK + PTEST + MOVNTDQA

    private static let sse41PackedCases: [(String, [UInt8])] = [
        ("ptest xmm0, xmm1",                        [0x66, 0x0F, 0x38, 0x17, 0xC1]),
        ("pmuldq xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x28, 0xC1]),
        ("pcmpeqq xmm0, xmm1",                      [0x66, 0x0F, 0x38, 0x29, 0xC1]),
        ("packusdw xmm0, xmm1",                     [0x66, 0x0F, 0x38, 0x2B, 0xC1]),
        ("pminsb xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x38, 0xC1]),
        ("pminsd xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x39, 0xC1]),
        ("pminuw xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x3A, 0xC1]),
        ("pminud xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x3B, 0xC1]),
        ("pmaxsb xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x3C, 0xC1]),
        ("pmaxsd xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x3D, 0xC1]),
        ("pmaxuw xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x3E, 0xC1]),
        ("pmaxud xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x3F, 0xC1]),
        ("pmulld xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0x40, 0xC1]),
        ("phminposuw xmm0, xmm1",                   [0x66, 0x0F, 0x38, 0x41, 0xC1]),
        // MOVNTDQA — memory only
        ("movntdqa xmm0, xmmword ptr [rdi]",        [0x66, 0x0F, 0x38, 0x2A, 0x07]),
        // Extended XMM
        ("pmulld xmm15, xmm0",                      [0x66, 0x44, 0x0F, 0x38, 0x40, 0xF8]),
        // Memory source
        ("pminsd xmm0, xmmword ptr [rsi]",          [0x66, 0x0F, 0x38, 0x39, 0x06]),
    ]

    func testSSE41PackedAssembles() throws {
        for (source, expected) in Self.sse41PackedCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSE41PackedDisassembles() throws {
        for (source, bytes) in Self.sse41PackedCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testMovntdqaRejectsRegisterSource() {
        XCTAssertThrowsError(try X86Assembler.assemble("movntdqa xmm0, xmm1")) { _ in }
    }

    func testSSE41PackedStreamRoundTrip() throws {
        let source = Self.sse41PackedCases.map(\.0).joined(separator: "\n")
        let expected = Self.sse41PackedCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 16c SSE4.1 imm8 (ROUND/BLEND/DPP/MPSADBW)

    private static let sse41ImmediateCases: [(String, [UInt8])] = [
        ("roundps xmm0, xmm1, 0",                       [0x66, 0x0F, 0x3A, 0x08, 0xC1, 0x00]),
        ("roundpd xmm0, xmm1, 1",                       [0x66, 0x0F, 0x3A, 0x09, 0xC1, 0x01]),
        ("roundss xmm0, xmm1, 2",                       [0x66, 0x0F, 0x3A, 0x0A, 0xC1, 0x02]),
        ("roundsd xmm0, xmm1, 3",                       [0x66, 0x0F, 0x3A, 0x0B, 0xC1, 0x03]),
        ("blendps xmm0, xmm1, 4",                       [0x66, 0x0F, 0x3A, 0x0C, 0xC1, 0x04]),
        ("blendpd xmm0, xmm1, 5",                       [0x66, 0x0F, 0x3A, 0x0D, 0xC1, 0x05]),
        ("pblendw xmm0, xmm1, 6",                       [0x66, 0x0F, 0x3A, 0x0E, 0xC1, 0x06]),
        ("dpps xmm0, xmm1, 240",                        [0x66, 0x0F, 0x3A, 0x40, 0xC1, 0xF0]),
        ("dppd xmm0, xmm1, 51",                         [0x66, 0x0F, 0x3A, 0x41, 0xC1, 0x33]),
        ("mpsadbw xmm0, xmm1, 7",                       [0x66, 0x0F, 0x3A, 0x42, 0xC1, 0x07]),
        // Memory source — ROUNDSS narrows to m32, ROUNDSD to m64.
        ("roundss xmm0, dword ptr [rdi], 0",            [0x66, 0x0F, 0x3A, 0x0A, 0x07, 0x00]),
        ("roundsd xmm0, qword ptr [rdi], 1",            [0x66, 0x0F, 0x3A, 0x0B, 0x07, 0x01]),
        ("blendps xmm0, xmmword ptr [rdi], 8",          [0x66, 0x0F, 0x3A, 0x0C, 0x07, 0x08]),
        // Extended XMM
        ("dpps xmm15, xmm0, 1",                         [0x66, 0x44, 0x0F, 0x3A, 0x40, 0xF8, 0x01]),
    ]

    func testSSE41ImmediateAssembles() throws {
        for (source, expected) in Self.sse41ImmediateCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSE41ImmediateDisassembles() throws {
        for (source, bytes) in Self.sse41ImmediateCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testRoundssWidthMismatchRejected() {
        XCTAssertThrowsError(try X86Assembler.assemble("roundss xmm0, qword ptr [rdi], 0")) { _ in }
    }

    func testSSE41ImmediateStreamRoundTrip() throws {
        let source = Self.sse41ImmediateCases.map(\.0).joined(separator: "\n")
        let expected = Self.sse41ImmediateCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 16d SSE4.1 PINSR / PEXTR / INSERTPS / EXTRACTPS / BLENDV

    private static let sse41LaneCases: [(String, [UInt8])] = [
        // PINSRB / PINSRW / PINSRD / PINSRQ
        ("pinsrb xmm0, eax, 3",                         [0x66, 0x0F, 0x3A, 0x20, 0xC0, 0x03]),
        ("pinsrb xmm0, byte ptr [rdi], 4",              [0x66, 0x0F, 0x3A, 0x20, 0x07, 0x04]),
        ("pinsrw xmm0, eax, 2",                         [0x66, 0x0F, 0xC4, 0xC0, 0x02]),
        ("pinsrw xmm0, word ptr [rdi], 1",              [0x66, 0x0F, 0xC4, 0x07, 0x01]),
        ("pinsrd xmm0, eax, 1",                         [0x66, 0x0F, 0x3A, 0x22, 0xC0, 0x01]),
        ("pinsrq xmm0, rax, 0",                         [0x66, 0x48, 0x0F, 0x3A, 0x22, 0xC0, 0x00]),
        // PEXTRB / PEXTRW / PEXTRD / PEXTRQ — using the SSE4.1 form
        ("pextrb eax, xmm0, 7",                         [0x66, 0x0F, 0x3A, 0x14, 0xC0, 0x07]),
        ("pextrb byte ptr [rdi], xmm0, 5",              [0x66, 0x0F, 0x3A, 0x14, 0x07, 0x05]),
        ("pextrw eax, xmm0, 3",                         [0x66, 0x0F, 0x3A, 0x15, 0xC0, 0x03]),
        ("pextrw word ptr [rdi], xmm0, 2",              [0x66, 0x0F, 0x3A, 0x15, 0x07, 0x02]),
        ("pextrd eax, xmm0, 1",                         [0x66, 0x0F, 0x3A, 0x16, 0xC0, 0x01]),
        ("pextrq rax, xmm0, 0",                         [0x66, 0x48, 0x0F, 0x3A, 0x16, 0xC0, 0x00]),
        // INSERTPS / EXTRACTPS
        ("insertps xmm0, xmm1, 16",                     [0x66, 0x0F, 0x3A, 0x21, 0xC1, 0x10]),
        ("insertps xmm0, dword ptr [rdi], 0",           [0x66, 0x0F, 0x3A, 0x21, 0x07, 0x00]),
        ("extractps eax, xmm0, 2",                      [0x66, 0x0F, 0x3A, 0x17, 0xC0, 0x02]),
        ("extractps dword ptr [rdi], xmm0, 1",          [0x66, 0x0F, 0x3A, 0x17, 0x07, 0x01]),
        // BLENDV — implicit XMM0
        ("blendvps xmm0, xmm1, xmm0",                   [0x66, 0x0F, 0x38, 0x14, 0xC1]),
        ("blendvpd xmm0, xmm1, xmm0",                   [0x66, 0x0F, 0x38, 0x15, 0xC1]),
        ("pblendvb xmm0, xmm1, xmm0",                   [0x66, 0x0F, 0x38, 0x10, 0xC1]),
        ("pblendvb xmm0, xmmword ptr [rdi], xmm0",      [0x66, 0x0F, 0x38, 0x10, 0x07]),
    ]

    func testSSE41LaneAssembles() throws {
        for (source, expected) in Self.sse41LaneCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSE41LaneDisassembles() throws {
        for (source, bytes) in Self.sse41LaneCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    /// The SSE2 PEXTRW form (66 0F C5 /r ib) should decode equally to
    /// the canonical pextrw representation.
    func testPextrwSSE2FormDecodes() throws {
        XCTAssertEqual(try X86Assembler.disassemble([0x66, 0x0F, 0xC5, 0xC0, 0x03]),
                       "pextrw eax, xmm0, 3")
    }

    func testBlendvRejectsNonXmm0Mask() {
        XCTAssertThrowsError(try X86Assembler.assemble("blendvps xmm0, xmm1, xmm1")) { _ in }
    }

    func testSSE41LaneStreamRoundTrip() throws {
        let source = Self.sse41LaneCases.map(\.0).joined(separator: "\n")
        let expected = Self.sse41LaneCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 16e SSE4.2

    private static let sse42Cases: [(String, [UInt8])] = [
        // PCMPESTRI/M, PCMPISTRI/M
        ("pcmpestrm xmm0, xmm1, 12",                    [0x66, 0x0F, 0x3A, 0x60, 0xC1, 0x0C]),
        ("pcmpestri xmm0, xmm1, 13",                    [0x66, 0x0F, 0x3A, 0x61, 0xC1, 0x0D]),
        ("pcmpistrm xmm0, xmm1, 14",                    [0x66, 0x0F, 0x3A, 0x62, 0xC1, 0x0E]),
        ("pcmpistri xmm0, xmm1, 15",                    [0x66, 0x0F, 0x3A, 0x63, 0xC1, 0x0F]),
        // PCMPGTQ
        ("pcmpgtq xmm0, xmm1",                          [0x66, 0x0F, 0x38, 0x37, 0xC1]),
        // CRC32 widths
        ("crc32 eax, bl",                               [0xF2, 0x0F, 0x38, 0xF0, 0xC3]),
        ("crc32 eax, byte ptr [rdi]",                   [0xF2, 0x0F, 0x38, 0xF0, 0x07]),
        ("crc32 eax, cx",                               [0xF2, 0x66, 0x0F, 0x38, 0xF1, 0xC1]),
        ("crc32 eax, word ptr [rdi]",                   [0xF2, 0x66, 0x0F, 0x38, 0xF1, 0x07]),
        ("crc32 eax, ecx",                              [0xF2, 0x0F, 0x38, 0xF1, 0xC1]),
        ("crc32 rax, rcx",                              [0xF2, 0x48, 0x0F, 0x38, 0xF1, 0xC1]),
        ("crc32 rax, qword ptr [rdi]",                  [0xF2, 0x48, 0x0F, 0x38, 0xF1, 0x07]),
        // Extended GPR / XMM
        ("crc32 r15d, eax",                             [0xF2, 0x44, 0x0F, 0x38, 0xF1, 0xF8]),
    ]

    func testSSE42Assembles() throws {
        for (source, expected) in Self.sse42Cases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testSSE42Disassembles() throws {
        for (source, bytes) in Self.sse42Cases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testCrc32WidthMismatchRejected() {
        XCTAssertThrowsError(try X86Assembler.assemble("crc32 rax, eax")) { _ in }
    }

    func testSSE42StreamRoundTrip() throws {
        let source = Self.sse42Cases.map(\.0).joined(separator: "\n")
        let expected = Self.sse42Cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 17 AES-NI + PCLMULQDQ

    private static let aesPclmulCases: [(String, [UInt8])] = [
        // AES family (0F 38 DB..DF)
        ("aesimc xmm0, xmm1",                           [0x66, 0x0F, 0x38, 0xDB, 0xC1]),
        ("aesenc xmm0, xmm1",                           [0x66, 0x0F, 0x38, 0xDC, 0xC1]),
        ("aesenclast xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0xDD, 0xC1]),
        ("aesdec xmm0, xmm1",                           [0x66, 0x0F, 0x38, 0xDE, 0xC1]),
        ("aesdeclast xmm0, xmm1",                       [0x66, 0x0F, 0x38, 0xDF, 0xC1]),
        // AESKEYGENASSIST + PCLMULQDQ (0F 3A + imm8)
        ("aeskeygenassist xmm0, xmm1, 16",              [0x66, 0x0F, 0x3A, 0xDF, 0xC1, 0x10]),
        ("pclmulqdq xmm0, xmm1, 17",                    [0x66, 0x0F, 0x3A, 0x44, 0xC1, 0x11]),
        // Memory source
        ("aesenc xmm0, xmmword ptr [rdi]",              [0x66, 0x0F, 0x38, 0xDC, 0x07]),
        ("pclmulqdq xmm0, xmmword ptr [rdi], 0",        [0x66, 0x0F, 0x3A, 0x44, 0x07, 0x00]),
        // Extended XMM
        ("aesenc xmm15, xmm0",                          [0x66, 0x44, 0x0F, 0x38, 0xDC, 0xF8]),
    ]

    func testAESPclmulAssembles() throws {
        for (source, expected) in Self.aesPclmulCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testAESPclmulDisassembles() throws {
        for (source, bytes) in Self.aesPclmulCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testAESPclmulStreamRoundTrip() throws {
        let source = Self.aesPclmulCases.map(\.0).joined(separator: "\n")
        let expected = Self.aesPclmulCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18a AVX V-arithmetic (VEX foundation)

    private static let vexArithmeticCases: [(String, [UInt8])] = [
        // VADDPS / VADDPD — packed singles & doubles, XMM and YMM
        ("vaddps xmm0, xmm1, xmm2",                     [0xC5, 0xF0, 0x58, 0xC2]),
        ("vaddpd xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0x58, 0xC2]),
        ("vaddps ymm0, ymm1, ymm2",                     [0xC5, 0xF4, 0x58, 0xC2]),
        ("vaddpd ymm0, ymm1, ymm2",                     [0xC5, 0xF5, 0x58, 0xC2]),
        // VADDSS / VADDSD — scalar variants
        ("vaddss xmm0, xmm1, xmm2",                     [0xC5, 0xF2, 0x58, 0xC2]),
        ("vaddsd xmm0, xmm1, xmm2",                     [0xC5, 0xF3, 0x58, 0xC2]),
        // VSUB / VMUL / VDIV cover the rest of the matrix
        ("vsubps xmm0, xmm1, xmm2",                     [0xC5, 0xF0, 0x5C, 0xC2]),
        ("vmulps ymm0, ymm1, ymm2",                     [0xC5, 0xF4, 0x59, 0xC2]),
        ("vdivpd xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0x5E, 0xC2]),
        ("vdivsd xmm0, xmm1, xmm2",                     [0xC5, 0xF3, 0x5E, 0xC2]),
        // Extended XMM/YMM force the 3-byte VEX form
        // xmm15 dst — only R needs flipping; 2-byte VEX still fits.
        ("vaddps xmm15, xmm1, xmm2",                    [0xC5, 0x70, 0x58, 0xFA]),
        // xmm15 source forces 3-byte VEX (B must be set).
        ("vaddps xmm0, xmm1, xmm15",                    [0xC4, 0xC1, 0x70, 0x58, 0xC7]),
        ("vaddps ymm15, ymm1, ymm2",                    [0xC5, 0x74, 0x58, 0xFA]),
        // Memory source — packed (m128) and scalar (m32/m64)
        ("vaddps xmm0, xmm1, xmmword ptr [rdi]",        [0xC5, 0xF0, 0x58, 0x07]),
        ("vaddpd ymm0, ymm1, ymmword ptr [rdi]",        [0xC5, 0xF5, 0x58, 0x07]),
        ("vaddss xmm0, xmm1, dword ptr [rdi]",          [0xC5, 0xF2, 0x58, 0x07]),
        ("vaddsd xmm0, xmm1, qword ptr [rdi]",          [0xC5, 0xF3, 0x58, 0x07]),
    ]

    func testVexArithmeticAssembles() throws {
        for (source, expected) in Self.vexArithmeticCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexArithmeticDisassembles() throws {
        for (source, bytes) in Self.vexArithmeticCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexArithmeticRejectsMixedSizes() {
        XCTAssertThrowsError(try X86Assembler.assemble("vaddps ymm0, xmm1, ymm2")) { _ in }
    }

    func testVexArithmeticStreamRoundTrip() throws {
        let source = Self.vexArithmeticCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexArithmeticCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18b VEX MIN/MAX/AND/ANDN/OR/XOR

    private static let vexArithmeticExtraCases: [(String, [UInt8])] = [
        // MIN / MAX — packed
        ("vminps xmm0, xmm1, xmm2",                     [0xC5, 0xF0, 0x5D, 0xC2]),
        ("vminpd ymm0, ymm1, ymm2",                     [0xC5, 0xF5, 0x5D, 0xC2]),
        ("vmaxps xmm0, xmm1, xmm2",                     [0xC5, 0xF0, 0x5F, 0xC2]),
        ("vmaxpd ymm0, ymm1, ymm2",                     [0xC5, 0xF5, 0x5F, 0xC2]),
        // MIN / MAX — scalar
        ("vminss xmm0, xmm1, xmm2",                     [0xC5, 0xF2, 0x5D, 0xC2]),
        ("vminsd xmm0, xmm1, xmm2",                     [0xC5, 0xF3, 0x5D, 0xC2]),
        ("vmaxss xmm0, xmm1, dword ptr [rdi]",          [0xC5, 0xF2, 0x5F, 0x07]),
        ("vmaxsd xmm0, xmm1, qword ptr [rdi]",          [0xC5, 0xF3, 0x5F, 0x07]),
        // AND / ANDN / OR / XOR — packed only
        ("vandps xmm0, xmm1, xmm2",                     [0xC5, 0xF0, 0x54, 0xC2]),
        ("vandpd ymm0, ymm1, ymm2",                     [0xC5, 0xF5, 0x54, 0xC2]),
        ("vandnps xmm0, xmm1, xmm2",                    [0xC5, 0xF0, 0x55, 0xC2]),
        ("vandnpd ymm0, ymm1, ymm2",                    [0xC5, 0xF5, 0x55, 0xC2]),
        ("vorps xmm0, xmm1, xmm2",                      [0xC5, 0xF0, 0x56, 0xC2]),
        ("vorpd ymm0, ymm1, ymm2",                      [0xC5, 0xF5, 0x56, 0xC2]),
        ("vxorps xmm0, xmm1, xmm2",                     [0xC5, 0xF0, 0x57, 0xC2]),
        ("vxorpd ymm0, ymm1, ymm2",                     [0xC5, 0xF5, 0x57, 0xC2]),
        // Memory + extended register
        ("vxorps ymm15, ymm0, ymmword ptr [rdi]",       [0xC5, 0x7C, 0x57, 0x3F]),
        ("vmaxpd xmm0, xmm1, xmmword ptr [rsi]",        [0xC5, 0xF1, 0x5F, 0x06]),
    ]

    func testVexArithmeticExtraAssembles() throws {
        for (source, expected) in Self.vexArithmeticExtraCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexArithmeticExtraDisassembles() throws {
        for (source, bytes) in Self.vexArithmeticExtraCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexArithmeticExtraStreamRoundTrip() throws {
        let source = Self.vexArithmeticExtraCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexArithmeticExtraCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18c VEX packed integer basics

    private static let vexPackedIntegerCases: [(String, [UInt8])] = [
        // VPADD
        ("vpaddb xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xFC, 0xC2]),
        ("vpaddw xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xFD, 0xC2]),
        ("vpaddd xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xFE, 0xC2]),
        ("vpaddq xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xD4, 0xC2]),
        // VPSUB
        ("vpsubb xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xF8, 0xC2]),
        ("vpsubw xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xF9, 0xC2]),
        ("vpsubd xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xFA, 0xC2]),
        ("vpsubq xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xFB, 0xC2]),
        // Bit-wise
        ("vpand xmm0, xmm1, xmm2",                      [0xC5, 0xF1, 0xDB, 0xC2]),
        ("vpandn xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xDF, 0xC2]),
        ("vpor xmm0, xmm1, xmm2",                       [0xC5, 0xF1, 0xEB, 0xC2]),
        ("vpxor xmm0, xmm1, xmm2",                      [0xC5, 0xF1, 0xEF, 0xC2]),
        // 256-bit (AVX2)
        ("vpaddd ymm0, ymm1, ymm2",                     [0xC5, 0xF5, 0xFE, 0xC2]),
        ("vpxor ymm0, ymm1, ymm2",                      [0xC5, 0xF5, 0xEF, 0xC2]),
        // Memory source + extended regs
        ("vpaddb xmm0, xmm1, xmmword ptr [rdi]",        [0xC5, 0xF1, 0xFC, 0x07]),
        ("vpxor ymm15, ymm0, ymmword ptr [rsi]",        [0xC5, 0x7D, 0xEF, 0x3E]),
    ]

    func testVexPackedIntegerAssembles() throws {
        for (source, expected) in Self.vexPackedIntegerCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexPackedIntegerDisassembles() throws {
        for (source, bytes) in Self.vexPackedIntegerCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexPackedIntegerStreamRoundTrip() throws {
        let source = Self.vexPackedIntegerCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexPackedIntegerCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18d VEX packed integer extras

    private static let vexPackedIntegerExtraCases: [(String, [UInt8])] = [
        // Saturating add/sub
        ("vpaddsb xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xEC, 0xC2]),
        ("vpaddsw xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xED, 0xC2]),
        ("vpaddusb xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0xDC, 0xC2]),
        ("vpaddusw xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0xDD, 0xC2]),
        ("vpsubsb xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xE8, 0xC2]),
        ("vpsubsw xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xE9, 0xC2]),
        ("vpsubusb xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0xD8, 0xC2]),
        ("vpsubusw xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0xD9, 0xC2]),
        // Compare
        ("vpcmpeqb xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0x74, 0xC2]),
        ("vpcmpeqw xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0x75, 0xC2]),
        ("vpcmpeqd xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0x76, 0xC2]),
        ("vpcmpgtb xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0x64, 0xC2]),
        ("vpcmpgtw xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0x65, 0xC2]),
        ("vpcmpgtd xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0x66, 0xC2]),
        // Multiplies / multiply-add
        ("vpmullw xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xD5, 0xC2]),
        ("vpmulhw xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xE5, 0xC2]),
        ("vpmulhuw xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0xE4, 0xC2]),
        ("vpmuludq xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0xF4, 0xC2]),
        ("vpmaddwd xmm0, xmm1, xmm2",                   [0xC5, 0xF1, 0xF5, 0xC2]),
        // Min/max
        ("vpminub xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xDA, 0xC2]),
        ("vpminsw xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xEA, 0xC2]),
        ("vpmaxub xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xDE, 0xC2]),
        ("vpmaxsw xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xEE, 0xC2]),
        // Avg / SAD
        ("vpavgb xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xE0, 0xC2]),
        ("vpavgw xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xE3, 0xC2]),
        ("vpsadbw xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0xF6, 0xC2]),
        // AVX2 256-bit smoke check
        ("vpcmpeqd ymm0, ymm1, ymm2",                   [0xC5, 0xF5, 0x76, 0xC2]),
        ("vpmaddwd ymm0, ymm1, ymmword ptr [rdi]",      [0xC5, 0xF5, 0xF5, 0x07]),
    ]

    func testVexPackedIntegerExtraAssembles() throws {
        for (source, expected) in Self.vexPackedIntegerExtraCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexPackedIntegerExtraDisassembles() throws {
        for (source, bytes) in Self.vexPackedIntegerExtraCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexPackedIntegerExtraStreamRoundTrip() throws {
        let source = Self.vexPackedIntegerExtraCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexPackedIntegerExtraCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18e VEX PUNPCK / PACK / variable shifts

    private static let vexPackedIntegerPunpackCases: [(String, [UInt8])] = [
        // Interleave low
        ("vpunpcklbw xmm0, xmm1, xmm2",                 [0xC5, 0xF1, 0x60, 0xC2]),
        ("vpunpcklwd xmm0, xmm1, xmm2",                 [0xC5, 0xF1, 0x61, 0xC2]),
        ("vpunpckldq xmm0, xmm1, xmm2",                 [0xC5, 0xF1, 0x62, 0xC2]),
        ("vpunpcklqdq xmm0, xmm1, xmm2",                [0xC5, 0xF1, 0x6C, 0xC2]),
        // Interleave high
        ("vpunpckhbw xmm0, xmm1, xmm2",                 [0xC5, 0xF1, 0x68, 0xC2]),
        ("vpunpckhwd xmm0, xmm1, xmm2",                 [0xC5, 0xF1, 0x69, 0xC2]),
        ("vpunpckhdq xmm0, xmm1, xmm2",                 [0xC5, 0xF1, 0x6A, 0xC2]),
        ("vpunpckhqdq xmm0, xmm1, xmm2",                [0xC5, 0xF1, 0x6D, 0xC2]),
        // Pack
        ("vpacksswb xmm0, xmm1, xmm2",                  [0xC5, 0xF1, 0x63, 0xC2]),
        ("vpackssdw xmm0, xmm1, xmm2",                  [0xC5, 0xF1, 0x6B, 0xC2]),
        ("vpackuswb xmm0, xmm1, xmm2",                  [0xC5, 0xF1, 0x67, 0xC2]),
        // Variable shifts
        ("vpsrlw xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xD1, 0xC2]),
        ("vpsrld xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xD2, 0xC2]),
        ("vpsrlq xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xD3, 0xC2]),
        ("vpsllw xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xF1, 0xC2]),
        ("vpslld xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xF2, 0xC2]),
        ("vpsllq xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xF3, 0xC2]),
        ("vpsraw xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xE1, 0xC2]),
        ("vpsrad xmm0, xmm1, xmm2",                     [0xC5, 0xF1, 0xE2, 0xC2]),
        // 256-bit smoke
        ("vpunpcklbw ymm0, ymm1, ymm2",                 [0xC5, 0xF5, 0x60, 0xC2]),
    ]

    func testVexPunpackPackShiftAssembles() throws {
        for (source, expected) in Self.vexPackedIntegerPunpackCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexPunpackPackShiftDisassembles() throws {
        for (source, bytes) in Self.vexPackedIntegerPunpackCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexPunpackPackShiftStreamRoundTrip() throws {
        let source = Self.vexPackedIntegerPunpackCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexPackedIntegerPunpackCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18f VEX 2-op (VSQRT/VRSQRT/VRCP)

    private static let vexUnaryCases: [(String, [UInt8])] = [
        // Packed 2-op forms
        ("vsqrtps xmm0, xmm1",                          [0xC5, 0xF8, 0x51, 0xC1]),
        ("vsqrtpd xmm0, xmm1",                          [0xC5, 0xF9, 0x51, 0xC1]),
        ("vsqrtps ymm0, ymm1",                          [0xC5, 0xFC, 0x51, 0xC1]),
        ("vsqrtpd ymm0, ymm1",                          [0xC5, 0xFD, 0x51, 0xC1]),
        ("vrsqrtps xmm0, xmm1",                         [0xC5, 0xF8, 0x52, 0xC1]),
        ("vrcpps xmm0, xmm1",                           [0xC5, 0xF8, 0x53, 0xC1]),
        ("vsqrtps xmm0, xmmword ptr [rdi]",             [0xC5, 0xF8, 0x51, 0x07]),
        // Scalar three-operand forms via VexArithmeticKind
        ("vsqrtss xmm0, xmm1, xmm2",                    [0xC5, 0xF2, 0x51, 0xC2]),
        ("vsqrtsd xmm0, xmm1, xmm2",                    [0xC5, 0xF3, 0x51, 0xC2]),
        ("vrsqrtss xmm0, xmm1, xmm2",                   [0xC5, 0xF2, 0x52, 0xC2]),
        ("vrcpss xmm0, xmm1, dword ptr [rdi]",          [0xC5, 0xF2, 0x53, 0x07]),
    ]

    func testVexUnaryAssembles() throws {
        for (source, expected) in Self.vexUnaryCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexUnaryDisassembles() throws {
        for (source, bytes) in Self.vexUnaryCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexUnaryStreamRoundTrip() throws {
        let source = Self.vexUnaryCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexUnaryCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18g VEX MOV family

    private static let vexMovCases: [(String, [UInt8])] = [
        // Register-register
        ("vmovaps xmm0, xmm1",                          [0xC5, 0xF8, 0x28, 0xC1]),
        ("vmovapd xmm0, xmm1",                          [0xC5, 0xF9, 0x28, 0xC1]),
        ("vmovups ymm0, ymm1",                          [0xC5, 0xFC, 0x10, 0xC1]),
        ("vmovupd ymm0, ymm1",                          [0xC5, 0xFD, 0x10, 0xC1]),
        ("vmovdqa xmm0, xmm1",                          [0xC5, 0xF9, 0x6F, 0xC1]),
        ("vmovdqu ymm0, ymm1",                          [0xC5, 0xFE, 0x6F, 0xC1]),
        // Load (register dst, memory src)
        ("vmovaps xmm0, xmmword ptr [rdi]",             [0xC5, 0xF8, 0x28, 0x07]),
        ("vmovdqa ymm0, ymmword ptr [rdi]",             [0xC5, 0xFD, 0x6F, 0x07]),
        // Store (memory dst, register src)
        ("vmovaps xmmword ptr [rdi], xmm0",             [0xC5, 0xF8, 0x29, 0x07]),
        ("vmovdqu ymmword ptr [rdi], ymm0",             [0xC5, 0xFE, 0x7F, 0x07]),
        // Extended XMM/YMM
        ("vmovaps xmm15, xmm0",                         [0xC5, 0x78, 0x28, 0xF8]),
    ]

    func testVexMovAssembles() throws {
        for (source, expected) in Self.vexMovCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexMovDisassembles() throws {
        for (source, bytes) in Self.vexMovCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexMovStreamRoundTrip() throws {
        let source = Self.vexMovCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexMovCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18h VEX imm8 SIMD shifts

    private static let vexImmediateShiftCases: [(String, [UInt8])] = [
        // PSRL imm
        ("vpsrlw xmm0, xmm1, 1",                        [0xC5, 0xF9, 0x71, 0xD1, 0x01]),
        ("vpsrld xmm0, xmm1, 4",                        [0xC5, 0xF9, 0x72, 0xD1, 0x04]),
        ("vpsrlq xmm0, xmm1, 7",                        [0xC5, 0xF9, 0x73, 0xD1, 0x07]),
        // PSLL imm
        ("vpsllw xmm0, xmm1, 1",                        [0xC5, 0xF9, 0x71, 0xF1, 0x01]),
        ("vpslld xmm0, xmm1, 4",                        [0xC5, 0xF9, 0x72, 0xF1, 0x04]),
        ("vpsllq xmm0, xmm1, 7",                        [0xC5, 0xF9, 0x73, 0xF1, 0x07]),
        // PSRA imm
        ("vpsraw xmm0, xmm1, 1",                        [0xC5, 0xF9, 0x71, 0xE1, 0x01]),
        ("vpsrad xmm0, xmm1, 31",                       [0xC5, 0xF9, 0x72, 0xE1, 0x1F]),
        // 128-bit byte shifts
        ("vpslldq xmm0, xmm1, 4",                       [0xC5, 0xF9, 0x73, 0xF9, 0x04]),
        ("vpsrldq xmm0, xmm1, 8",                       [0xC5, 0xF9, 0x73, 0xD9, 0x08]),
        // 256-bit (AVX2)
        ("vpslld ymm0, ymm1, 4",                        [0xC5, 0xFD, 0x72, 0xF1, 0x04]),
        ("vpsrldq ymm0, ymm1, 8",                       [0xC5, 0xFD, 0x73, 0xD9, 0x08]),
    ]

    func testVexImmediateShiftAssembles() throws {
        for (source, expected) in Self.vexImmediateShiftCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexImmediateShiftDisassembles() throws {
        for (source, bytes) in Self.vexImmediateShiftCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexImmediateShiftStreamRoundTrip() throws {
        let source = Self.vexImmediateShiftCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexImmediateShiftCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18i VEX imm8 shuffles

    private static let vexShuffleImmCases: [(String, [UInt8])] = [
        // VPSHUF — 2-op imm8
        ("vpshufd xmm0, xmm1, 27",                      [0xC5, 0xF9, 0x70, 0xC1, 0x1B]),
        ("vpshuflw xmm0, xmm1, 228",                    [0xC5, 0xFB, 0x70, 0xC1, 0xE4]),
        ("vpshufhw xmm0, xmm1, 228",                    [0xC5, 0xFA, 0x70, 0xC1, 0xE4]),
        // VSHUFPS / VSHUFPD — 3-op imm8
        ("vshufps xmm0, xmm1, xmm2, 1",                 [0xC5, 0xF0, 0xC6, 0xC2, 0x01]),
        ("vshufpd xmm0, xmm1, xmm2, 2",                 [0xC5, 0xF1, 0xC6, 0xC2, 0x02]),
        // VPALIGNR — 0F 3A escape
        ("vpalignr xmm0, xmm1, xmm2, 3",                [0xC4, 0xE3, 0x71, 0x0F, 0xC2, 0x03]),
        // 256-bit (AVX2)
        ("vpshufd ymm0, ymm1, 0",                       [0xC5, 0xFD, 0x70, 0xC1, 0x00]),
        ("vshufps ymm0, ymm1, ymm2, 4",                 [0xC5, 0xF4, 0xC6, 0xC2, 0x04]),
        ("vpalignr ymm0, ymm1, ymm2, 5",                [0xC4, 0xE3, 0x75, 0x0F, 0xC2, 0x05]),
        // Memory source
        ("vpshufd xmm0, xmmword ptr [rdi], 1",          [0xC5, 0xF9, 0x70, 0x07, 0x01]),
    ]

    func testVexShuffleImmAssembles() throws {
        for (source, expected) in Self.vexShuffleImmCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexShuffleImmDisassembles() throws {
        for (source, bytes) in Self.vexShuffleImmCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexShuffleImmStreamRoundTrip() throws {
        let source = Self.vexShuffleImmCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexShuffleImmCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18j VEX CMP + SSE3 V-prefix

    private static let vexCmpAndSse3Cases: [(String, [UInt8])] = [
        // VCMPPS / VCMPPD / VCMPSS / VCMPSD
        ("vcmpps xmm0, xmm1, xmm2, 0",                  [0xC5, 0xF0, 0xC2, 0xC2, 0x00]),
        ("vcmppd xmm0, xmm1, xmm2, 1",                  [0xC5, 0xF1, 0xC2, 0xC2, 0x01]),
        ("vcmpss xmm0, xmm1, xmm2, 2",                  [0xC5, 0xF2, 0xC2, 0xC2, 0x02]),
        ("vcmpsd xmm0, xmm1, xmm2, 3",                  [0xC5, 0xF3, 0xC2, 0xC2, 0x03]),
        ("vcmpps ymm0, ymm1, ymm2, 4",                  [0xC5, 0xF4, 0xC2, 0xC2, 0x04]),
        ("vcmpss xmm0, xmm1, dword ptr [rdi], 5",       [0xC5, 0xF2, 0xC2, 0x07, 0x05]),
        ("vcmpsd xmm0, xmm1, qword ptr [rdi], 6",       [0xC5, 0xF3, 0xC2, 0x07, 0x06]),
        // SSE3 V-prefixed
        ("vaddsubps xmm0, xmm1, xmm2",                  [0xC5, 0xF3, 0xD0, 0xC2]),
        ("vaddsubpd ymm0, ymm1, ymm2",                  [0xC5, 0xF5, 0xD0, 0xC2]),
        ("vhaddps xmm0, xmm1, xmm2",                    [0xC5, 0xF3, 0x7C, 0xC2]),
        ("vhaddpd xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0x7C, 0xC2]),
        ("vhsubps xmm0, xmm1, xmm2",                    [0xC5, 0xF3, 0x7D, 0xC2]),
        ("vhsubpd xmm0, xmm1, xmm2",                    [0xC5, 0xF1, 0x7D, 0xC2]),
        // VLDDQU / VMOVDDUP / VMOVSHDUP / VMOVSLDUP
        ("vlddqu xmm0, xmmword ptr [rdi]",              [0xC5, 0xFB, 0xF0, 0x07]),
        ("vmovddup xmm0, qword ptr [rdi]",              [0xC5, 0xFB, 0x12, 0x07]),
        ("vmovddup xmm0, xmm1",                         [0xC5, 0xFB, 0x12, 0xC1]),
        ("vmovshdup xmm0, xmm1",                        [0xC5, 0xFA, 0x16, 0xC1]),
        ("vmovsldup xmm0, xmm1",                        [0xC5, 0xFA, 0x12, 0xC1]),
        ("vmovddup ymm0, ymmword ptr [rdi]",            [0xC5, 0xFF, 0x12, 0x07]),
    ]

    func testVexCmpAndSse3Assembles() throws {
        for (source, expected) in Self.vexCmpAndSse3Cases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexCmpAndSse3Disassembles() throws {
        for (source, bytes) in Self.vexCmpAndSse3Cases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexCmpAndSse3StreamRoundTrip() throws {
        let source = Self.vexCmpAndSse3Cases.map(\.0).joined(separator: "\n")
        let expected = Self.vexCmpAndSse3Cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18k VEX MOVMSK family

    private static let vexMaskExtractCases: [(String, [UInt8])] = [
        ("vmovmskps eax, xmm1",                         [0xC5, 0xF8, 0x50, 0xC1]),
        ("vmovmskpd eax, xmm1",                         [0xC5, 0xF9, 0x50, 0xC1]),
        ("vmovmskps eax, ymm1",                         [0xC5, 0xFC, 0x50, 0xC1]),
        ("vmovmskpd eax, ymm1",                         [0xC5, 0xFD, 0x50, 0xC1]),
        ("vpmovmskb eax, xmm1",                         [0xC5, 0xF9, 0xD7, 0xC1]),
        // AVX2 256-bit form
        ("vpmovmskb eax, ymm1",                         [0xC5, 0xFD, 0xD7, 0xC1]),
    ]

    func testVexMaskExtractAssembles() throws {
        for (source, expected) in Self.vexMaskExtractCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexMaskExtractDisassembles() throws {
        for (source, bytes) in Self.vexMaskExtractCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexMaskExtractStreamRoundTrip() throws {
        let source = Self.vexMaskExtractCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexMaskExtractCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18l BMI1

    private static let bmi1Cases: [(String, [UInt8])] = [
        // ANDN
        ("andn eax, ebx, ecx",                          [0xC4, 0xE2, 0x60, 0xF2, 0xC1]),
        ("andn rax, rbx, rcx",                          [0xC4, 0xE2, 0xE0, 0xF2, 0xC1]),
        ("andn eax, ebx, dword ptr [rdi]",              [0xC4, 0xE2, 0x60, 0xF2, 0x07]),
        // BLSR / BLSMSK / BLSI
        ("blsr eax, ebx",                               [0xC4, 0xE2, 0x78, 0xF3, 0xCB]),
        ("blsmsk eax, ebx",                             [0xC4, 0xE2, 0x78, 0xF3, 0xD3]),
        ("blsi eax, ebx",                               [0xC4, 0xE2, 0x78, 0xF3, 0xDB]),
        ("blsi rax, rbx",                               [0xC4, 0xE2, 0xF8, 0xF3, 0xDB]),
        ("blsr eax, dword ptr [rdi]",                   [0xC4, 0xE2, 0x78, 0xF3, 0x0F]),
    ]

    func testBmi1Assembles() throws {
        for (source, expected) in Self.bmi1Cases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testBmi1Disassembles() throws {
        for (source, bytes) in Self.bmi1Cases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testBmi1StreamRoundTrip() throws {
        let source = Self.bmi1Cases.map(\.0).joined(separator: "\n")
        let expected = Self.bmi1Cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18m BMI2 shift-like GPR ops

    private static let bmi2ShiftLikeCases: [(String, [UInt8])] = [
        // BEXTR — pp=0, opcode F7
        ("bextr eax, ebx, ecx",                         [0xC4, 0xE2, 0x70, 0xF7, 0xC3]),
        ("bextr rax, rbx, rcx",                         [0xC4, 0xE2, 0xF0, 0xF7, 0xC3]),
        // BZHI — pp=0, opcode F5
        ("bzhi eax, ebx, ecx",                          [0xC4, 0xE2, 0x70, 0xF5, 0xC3]),
        // SHLX — pp=66, opcode F7
        ("shlx eax, ebx, ecx",                          [0xC4, 0xE2, 0x71, 0xF7, 0xC3]),
        // SARX — pp=F3, opcode F7
        ("sarx eax, ebx, ecx",                          [0xC4, 0xE2, 0x72, 0xF7, 0xC3]),
        // SHRX — pp=F2, opcode F7
        ("shrx eax, ebx, ecx",                          [0xC4, 0xE2, 0x73, 0xF7, 0xC3]),
        // Memory source
        ("bextr eax, dword ptr [rdi], ecx",             [0xC4, 0xE2, 0x70, 0xF7, 0x07]),
    ]

    func testBmi2ShiftLikeAssembles() throws {
        for (source, expected) in Self.bmi2ShiftLikeCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testBmi2ShiftLikeDisassembles() throws {
        for (source, bytes) in Self.bmi2ShiftLikeCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testBmi2ShiftLikeStreamRoundTrip() throws {
        let source = Self.bmi2ShiftLikeCases.map(\.0).joined(separator: "\n")
        let expected = Self.bmi2ShiftLikeCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18n RORX

    private static let rorxCases: [(String, [UInt8])] = [
        ("rorx eax, ebx, 7",                            [0xC4, 0xE3, 0x7B, 0xF0, 0xC3, 0x07]),
        ("rorx rax, rbx, 4",                            [0xC4, 0xE3, 0xFB, 0xF0, 0xC3, 0x04]),
        ("rorx eax, dword ptr [rdi], 1",                [0xC4, 0xE3, 0x7B, 0xF0, 0x07, 0x01]),
    ]

    func testRorxAssembles() throws {
        for (source, expected) in Self.rorxCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testRorxDisassembles() throws {
        for (source, bytes) in Self.rorxCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testRorxStreamRoundTrip() throws {
        let source = Self.rorxCases.map(\.0).joined(separator: "\n")
        let expected = Self.rorxCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18o BMI2 PDEP/PEXT/MULX

    private static let bmi2PextDepMulxCases: [(String, [UInt8])] = [
        ("pdep eax, ebx, ecx",                          [0xC4, 0xE2, 0x63, 0xF5, 0xC1]),
        ("pext eax, ebx, ecx",                          [0xC4, 0xE2, 0x62, 0xF5, 0xC1]),
        ("pdep rax, rbx, rcx",                          [0xC4, 0xE2, 0xE3, 0xF5, 0xC1]),
        ("mulx eax, ebx, ecx",                          [0xC4, 0xE2, 0x63, 0xF6, 0xC1]),
        ("mulx rax, rbx, rcx",                          [0xC4, 0xE2, 0xE3, 0xF6, 0xC1]),
        // Memory source
        ("pdep eax, ebx, dword ptr [rdi]",              [0xC4, 0xE2, 0x63, 0xF5, 0x07]),
        ("mulx rax, rbx, qword ptr [rdi]",              [0xC4, 0xE2, 0xE3, 0xF6, 0x07]),
    ]

    func testBmi2PextDepMulxAssembles() throws {
        for (source, expected) in Self.bmi2PextDepMulxCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testBmi2PextDepMulxDisassembles() throws {
        for (source, bytes) in Self.bmi2PextDepMulxCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testBmi2PextDepMulxStreamRoundTrip() throws {
        let source = Self.bmi2PextDepMulxCases.map(\.0).joined(separator: "\n")
        let expected = Self.bmi2PextDepMulxCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18p ADX (ADCX/ADOX)

    private static let adxCases: [(String, [UInt8])] = [
        ("adcx eax, ebx",                               [0x66, 0x0F, 0x38, 0xF6, 0xC3]),
        ("adcx rax, rbx",                               [0x66, 0x48, 0x0F, 0x38, 0xF6, 0xC3]),
        ("adox eax, ebx",                               [0xF3, 0x0F, 0x38, 0xF6, 0xC3]),
        ("adox rax, rbx",                               [0xF3, 0x48, 0x0F, 0x38, 0xF6, 0xC3]),
        ("adcx eax, dword ptr [rdi]",                   [0x66, 0x0F, 0x38, 0xF6, 0x07]),
        ("adox rax, qword ptr [rdi]",                   [0xF3, 0x48, 0x0F, 0x38, 0xF6, 0x07]),
    ]

    func testAdxAssembles() throws {
        for (source, expected) in Self.adxCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testAdxDisassembles() throws {
        for (source, bytes) in Self.adxCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testAdxStreamRoundTrip() throws {
        let source = Self.adxCases.map(\.0).joined(separator: "\n")
        let expected = Self.adxCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18q VEX MOVD / MOVQ

    private static let vexMovDQCases: [(String, [UInt8])] = [
        // VMOVD load / store
        ("vmovd xmm0, eax",                             [0xC5, 0xF9, 0x6E, 0xC0]),
        ("vmovd eax, xmm0",                             [0xC5, 0xF9, 0x7E, 0xC0]),
        ("vmovd xmm0, dword ptr [rdi]",                 [0xC5, 0xF9, 0x6E, 0x07]),
        ("vmovd dword ptr [rdi], xmm0",                 [0xC5, 0xF9, 0x7E, 0x07]),
        // VMOVQ load / store
        ("vmovq xmm0, rax",                             [0xC4, 0xE1, 0xF9, 0x6E, 0xC0]),
        ("vmovq rax, xmm0",                             [0xC4, 0xE1, 0xF9, 0x7E, 0xC0]),
        ("vmovq xmm0, qword ptr [rdi]",                 [0xC4, 0xE1, 0xF9, 0x6E, 0x07]),
        ("vmovq qword ptr [rdi], xmm0",                 [0xC4, 0xE1, 0xF9, 0x7E, 0x07]),
    ]

    func testVexMovDQAssembles() throws {
        for (source, expected) in Self.vexMovDQCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexMovDQDisassembles() throws {
        for (source, bytes) in Self.vexMovDQCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexMovDQStreamRoundTrip() throws {
        let source = Self.vexMovDQCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexMovDQCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18r VEX half-vector register MOV

    private static let vexHalfMoveRegCases: [(String, [UInt8])] = [
        ("vmovhlps xmm0, xmm1, xmm2",                   [0xC5, 0xF0, 0x12, 0xC2]),
        ("vmovlhps xmm0, xmm1, xmm2",                   [0xC5, 0xF0, 0x16, 0xC2]),
        ("vmovhlps xmm15, xmm1, xmm2",                  [0xC5, 0x70, 0x12, 0xFA]),
    ]

    func testVexHalfMoveRegAssembles() throws {
        for (source, expected) in Self.vexHalfMoveRegCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexHalfMoveRegDisassembles() throws {
        for (source, bytes) in Self.vexHalfMoveRegCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexHalfMoveRegStreamRoundTrip() throws {
        let source = Self.vexHalfMoveRegCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexHalfMoveRegCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18s VEX SSSE3

    private static let vexSSSE3Cases: [(String, [UInt8])] = [
        ("vpshufb xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x00, 0xC2]),
        ("vphaddw xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x01, 0xC2]),
        ("vphaddd xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x02, 0xC2]),
        ("vphaddsw xmm0, xmm1, xmm2",                   [0xC4, 0xE2, 0x71, 0x03, 0xC2]),
        ("vpmaddubsw xmm0, xmm1, xmm2",                 [0xC4, 0xE2, 0x71, 0x04, 0xC2]),
        ("vphsubw xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x05, 0xC2]),
        ("vphsubd xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x06, 0xC2]),
        ("vphsubsw xmm0, xmm1, xmm2",                   [0xC4, 0xE2, 0x71, 0x07, 0xC2]),
        ("vpsignb xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x08, 0xC2]),
        ("vpsignw xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x09, 0xC2]),
        ("vpsignd xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x0A, 0xC2]),
        ("vpmulhrsw xmm0, xmm1, xmm2",                  [0xC4, 0xE2, 0x71, 0x0B, 0xC2]),
        ("vpabsb xmm0, xmm1, xmm2",                     [0xC4, 0xE2, 0x71, 0x1C, 0xC2]),
        ("vpabsw xmm0, xmm1, xmm2",                     [0xC4, 0xE2, 0x71, 0x1D, 0xC2]),
        ("vpabsd xmm0, xmm1, xmm2",                     [0xC4, 0xE2, 0x71, 0x1E, 0xC2]),
        ("vpshufb ymm0, ymm1, ymm2",                    [0xC4, 0xE2, 0x75, 0x00, 0xC2]),
        ("vpshufb xmm0, xmm1, xmmword ptr [rdi]",       [0xC4, 0xE2, 0x71, 0x00, 0x07]),
    ]

    func testVexSSSE3Assembles() throws {
        for (source, expected) in Self.vexSSSE3Cases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexSSSE3Disassembles() throws {
        for (source, bytes) in Self.vexSSSE3Cases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexSSSE3StreamRoundTrip() throws {
        let source = Self.vexSSSE3Cases.map(\.0).joined(separator: "\n")
        let expected = Self.vexSSSE3Cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18t FMA3

    private static let fma3Cases: [(String, [UInt8])] = [
        // VFMADD132PS / 213 / 231 — packed single, xmm
        ("vfmadd132ps xmm0, xmm1, xmm2",                [0xC4, 0xE2, 0x71, 0x98, 0xC2]),
        ("vfmadd213ps xmm0, xmm1, xmm2",                [0xC4, 0xE2, 0x71, 0xA8, 0xC2]),
        ("vfmadd231ps xmm0, xmm1, xmm2",                [0xC4, 0xE2, 0x71, 0xB8, 0xC2]),
        // VFMADD PD — same opcode with W=1
        ("vfmadd132pd xmm0, xmm1, xmm2",                [0xC4, 0xE2, 0xF1, 0x98, 0xC2]),
        ("vfmadd213pd ymm0, ymm1, ymm2",                [0xC4, 0xE2, 0xF5, 0xA8, 0xC2]),
        // Scalar forms (opcode LSB toggled)
        ("vfmadd132ss xmm0, xmm1, xmm2",                [0xC4, 0xE2, 0x71, 0x99, 0xC2]),
        ("vfmadd213sd xmm0, xmm1, xmm2",                [0xC4, 0xE2, 0xF1, 0xA9, 0xC2]),
        // VFMSUB family
        ("vfmsub132ps xmm0, xmm1, xmm2",                [0xC4, 0xE2, 0x71, 0x9A, 0xC2]),
        ("vfmsub213pd ymm0, ymm1, ymm2",                [0xC4, 0xE2, 0xF5, 0xAA, 0xC2]),
        ("vfmsub231ss xmm0, xmm1, xmm2",                [0xC4, 0xE2, 0x71, 0xBB, 0xC2]),
        // VFNMADD family
        ("vfnmadd132ps xmm0, xmm1, xmm2",               [0xC4, 0xE2, 0x71, 0x9C, 0xC2]),
        ("vfnmadd213sd xmm0, xmm1, xmm2",               [0xC4, 0xE2, 0xF1, 0xAD, 0xC2]),
        // VFNMSUB family
        ("vfnmsub231pd ymm0, ymm1, ymm2",               [0xC4, 0xE2, 0xF5, 0xBE, 0xC2]),
        // VFMADDSUB / VFMSUBADD (packed only)
        ("vfmaddsub132ps xmm0, xmm1, xmm2",             [0xC4, 0xE2, 0x71, 0x96, 0xC2]),
        ("vfmaddsub213pd ymm0, ymm1, ymm2",             [0xC4, 0xE2, 0xF5, 0xA6, 0xC2]),
        ("vfmsubadd231ps xmm0, xmm1, xmm2",             [0xC4, 0xE2, 0x71, 0xB7, 0xC2]),
        // Memory source
        ("vfmadd213ps ymm0, ymm1, ymmword ptr [rdi]",   [0xC4, 0xE2, 0x75, 0xA8, 0x07]),
        ("vfmadd132ss xmm0, xmm1, dword ptr [rdi]",     [0xC4, 0xE2, 0x71, 0x99, 0x07]),
    ]

    func testFma3Assembles() throws {
        for (source, expected) in Self.fma3Cases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testFma3Disassembles() throws {
        for (source, bytes) in Self.fma3Cases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testFma3StreamRoundTrip() throws {
        let source = Self.fma3Cases.map(\.0).joined(separator: "\n")
        let expected = Self.fma3Cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18u VEX SSE4.1 packed

    private static let vexSSE41PackedCases: [(String, [UInt8])] = [
        ("vpmuldq xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x28, 0xC2]),
        ("vpcmpeqq xmm0, xmm1, xmm2",                   [0xC4, 0xE2, 0x71, 0x29, 0xC2]),
        ("vpackusdw xmm0, xmm1, xmm2",                  [0xC4, 0xE2, 0x71, 0x2B, 0xC2]),
        ("vpcmpgtq xmm0, xmm1, xmm2",                   [0xC4, 0xE2, 0x71, 0x37, 0xC2]),
        ("vpminsb xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x38, 0xC2]),
        ("vpminsd xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x39, 0xC2]),
        ("vpmaxsb xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x3C, 0xC2]),
        ("vpmaxud xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x3F, 0xC2]),
        ("vpmulld xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0x40, 0xC2]),
        ("vpmulld ymm0, ymm1, ymm2",                    [0xC4, 0xE2, 0x75, 0x40, 0xC2]),
        // 2-op (VPTEST / VPHMINPOSUW)
        ("vptest xmm0, xmm1",                           [0xC4, 0xE2, 0x79, 0x17, 0xC1]),
        ("vptest ymm0, ymm1",                           [0xC4, 0xE2, 0x7D, 0x17, 0xC1]),
        ("vphminposuw xmm0, xmm1",                      [0xC4, 0xE2, 0x79, 0x41, 0xC1]),
    ]

    func testVexSSE41PackedAssembles() throws {
        for (source, expected) in Self.vexSSE41PackedCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexSSE41PackedDisassembles() throws {
        for (source, bytes) in Self.vexSSE41PackedCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexSSE41PackedStreamRoundTrip() throws {
        let source = Self.vexSSE41PackedCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexSSE41PackedCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18v VEX PMOVSX/PMOVZX

    private static let vexPackExtendCases: [(String, [UInt8])] = [
        ("vpmovsxbw xmm0, xmm1",                        [0xC4, 0xE2, 0x79, 0x20, 0xC1]),
        ("vpmovsxbd xmm0, xmm1",                        [0xC4, 0xE2, 0x79, 0x21, 0xC1]),
        ("vpmovsxbq xmm0, xmm1",                        [0xC4, 0xE2, 0x79, 0x22, 0xC1]),
        ("vpmovsxwd xmm0, xmm1",                        [0xC4, 0xE2, 0x79, 0x23, 0xC1]),
        ("vpmovsxwq xmm0, xmm1",                        [0xC4, 0xE2, 0x79, 0x24, 0xC1]),
        ("vpmovsxdq xmm0, xmm1",                        [0xC4, 0xE2, 0x79, 0x25, 0xC1]),
        ("vpmovzxbw xmm0, xmm1",                        [0xC4, 0xE2, 0x79, 0x30, 0xC1]),
        ("vpmovzxdq ymm0, ymm1",                        [0xC4, 0xE2, 0x7D, 0x35, 0xC1]),
        ("vpmovsxbw xmm0, qword ptr [rdi]",             [0xC4, 0xE2, 0x79, 0x20, 0x07]),
    ]

    func testVexPackExtendAssembles() throws {
        for (source, expected) in Self.vexPackExtendCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexPackExtendDisassembles() throws {
        for (source, bytes) in Self.vexPackExtendCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexPackExtendStreamRoundTrip() throws {
        let source = Self.vexPackExtendCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexPackExtendCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18w VEX AES + PCLMULQDQ

    private static let vexAesPclmulCases: [(String, [UInt8])] = [
        ("vaesimc xmm0, xmm1",                          [0xC4, 0xE2, 0x79, 0xDB, 0xC1]),
        ("vaesenc xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0xDC, 0xC2]),
        ("vaesenclast xmm0, xmm1, xmm2",                [0xC4, 0xE2, 0x71, 0xDD, 0xC2]),
        ("vaesdec xmm0, xmm1, xmm2",                    [0xC4, 0xE2, 0x71, 0xDE, 0xC2]),
        ("vaesdeclast xmm0, xmm1, xmm2",                [0xC4, 0xE2, 0x71, 0xDF, 0xC2]),
        ("vaeskeygenassist xmm0, xmm1, 16",             [0xC4, 0xE3, 0x79, 0xDF, 0xC1, 0x10]),
        ("vpclmulqdq xmm0, xmm1, xmm2, 17",             [0xC4, 0xE3, 0x71, 0x44, 0xC2, 0x11]),
    ]

    func testVexAesPclmulAssembles() throws {
        for (source, expected) in Self.vexAesPclmulCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexAesPclmulDisassembles() throws {
        for (source, bytes) in Self.vexAesPclmulCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexAesPclmulStreamRoundTrip() throws {
        let source = Self.vexAesPclmulCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexAesPclmulCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18x VEX string compares

    private static let vexCmpStrCases: [(String, [UInt8])] = [
        ("vpcmpestrm xmm0, xmm1, 12",                   [0xC4, 0xE3, 0x79, 0x60, 0xC1, 0x0C]),
        ("vpcmpestri xmm0, xmm1, 13",                   [0xC4, 0xE3, 0x79, 0x61, 0xC1, 0x0D]),
        ("vpcmpistrm xmm0, xmm1, 14",                   [0xC4, 0xE3, 0x79, 0x62, 0xC1, 0x0E]),
        ("vpcmpistri xmm0, xmm1, 15",                   [0xC4, 0xE3, 0x79, 0x63, 0xC1, 0x0F]),
    ]

    func testVexCmpStrAssembles() throws {
        for (source, expected) in Self.vexCmpStrCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexCmpStrDisassembles() throws {
        for (source, bytes) in Self.vexCmpStrCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexCmpStrStreamRoundTrip() throws {
        let source = Self.vexCmpStrCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexCmpStrCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18y VEX SSE4.1 imm8 3-op

    private static let vexSSE41ImmCases: [(String, [UInt8])] = [
        ("vblendps xmm0, xmm1, xmm2, 4",                [0xC4, 0xE3, 0x71, 0x0C, 0xC2, 0x04]),
        ("vblendpd ymm0, ymm1, ymm2, 5",                [0xC4, 0xE3, 0x75, 0x0D, 0xC2, 0x05]),
        ("vpblendw xmm0, xmm1, xmm2, 6",                [0xC4, 0xE3, 0x71, 0x0E, 0xC2, 0x06]),
        ("vdpps xmm0, xmm1, xmm2, 240",                 [0xC4, 0xE3, 0x71, 0x40, 0xC2, 0xF0]),
        ("vdppd xmm0, xmm1, xmm2, 51",                  [0xC4, 0xE3, 0x71, 0x41, 0xC2, 0x33]),
        ("vmpsadbw xmm0, xmm1, xmm2, 7",                [0xC4, 0xE3, 0x71, 0x42, 0xC2, 0x07]),
    ]

    func testVexSSE41ImmAssembles() throws {
        for (source, expected) in Self.vexSSE41ImmCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexSSE41ImmDisassembles() throws {
        for (source, bytes) in Self.vexSSE41ImmCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexSSE41ImmStreamRoundTrip() throws {
        let source = Self.vexSSE41ImmCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexSSE41ImmCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18z VROUND family

    private static let vroundCases: [(String, [UInt8])] = [
        // Packed (2-op + imm)
        ("vroundps xmm0, xmm1, 0",                      [0xC4, 0xE3, 0x79, 0x08, 0xC1, 0x00]),
        ("vroundpd ymm0, ymm1, 1",                      [0xC4, 0xE3, 0x7D, 0x09, 0xC1, 0x01]),
        // Scalar (3-op + imm)
        ("vroundss xmm0, xmm1, xmm2, 2",                [0xC4, 0xE3, 0x71, 0x0A, 0xC2, 0x02]),
        ("vroundsd xmm0, xmm1, xmm2, 3",                [0xC4, 0xE3, 0x71, 0x0B, 0xC2, 0x03]),
    ]

    func testVroundAssembles() throws {
        for (source, expected) in Self.vroundCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVroundDisassembles() throws {
        for (source, bytes) in Self.vroundCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVroundStreamRoundTrip() throws {
        let source = Self.vroundCases.map(\.0).joined(separator: "\n")
        let expected = Self.vroundCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18aa VEX non-temporal stores

    private static let vexNonTemporalCases: [(String, [UInt8])] = [
        ("vmovntps xmmword ptr [rdi], xmm0",            [0xC5, 0xF8, 0x2B, 0x07]),
        ("vmovntps ymmword ptr [rdi], ymm0",            [0xC5, 0xFC, 0x2B, 0x07]),
        ("vmovntpd xmmword ptr [rdi], xmm0",            [0xC5, 0xF9, 0x2B, 0x07]),
        ("vmovntdq ymmword ptr [rdi], ymm0",            [0xC5, 0xFD, 0xE7, 0x07]),
    ]

    func testVexNonTemporalAssembles() throws {
        for (source, expected) in Self.vexNonTemporalCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexNonTemporalDisassembles() throws {
        for (source, bytes) in Self.vexNonTemporalCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexNonTemporalStreamRoundTrip() throws {
        let source = Self.vexNonTemporalCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexNonTemporalCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18ab VEX LDMXCSR / STMXCSR

    private static let vexMxcsrCases: [(String, [UInt8])] = [
        ("vldmxcsr dword ptr [rdi]",                    [0xC5, 0xF8, 0xAE, 0x17]),
        ("vstmxcsr dword ptr [rdi]",                    [0xC5, 0xF8, 0xAE, 0x1F]),
    ]

    func testVexMxcsrAssembles() throws {
        for (source, expected) in Self.vexMxcsrCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexMxcsrDisassembles() throws {
        for (source, bytes) in Self.vexMxcsrCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexMxcsrStreamRoundTrip() throws {
        let source = Self.vexMxcsrCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexMxcsrCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18ac AVX2 VPBROADCAST

    private static let vexBroadcastCases: [(String, [UInt8])] = [
        ("vpbroadcastb xmm0, xmm1",                     [0xC4, 0xE2, 0x79, 0x78, 0xC1]),
        ("vpbroadcastw xmm0, xmm1",                     [0xC4, 0xE2, 0x79, 0x79, 0xC1]),
        ("vpbroadcastd xmm0, xmm1",                     [0xC4, 0xE2, 0x79, 0x58, 0xC1]),
        ("vpbroadcastq ymm0, xmm1",                     [0xC4, 0xE2, 0x7D, 0x59, 0xC1]),
        ("vpbroadcastb xmm0, byte ptr [rdi]",           [0xC4, 0xE2, 0x79, 0x78, 0x07]),
    ]

    func testVexBroadcastAssembles() throws {
        for (source, expected) in Self.vexBroadcastCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexBroadcastDisassembles() throws {
        for (source, bytes) in Self.vexBroadcastCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexBroadcastStreamRoundTrip() throws {
        let source = Self.vexBroadcastCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexBroadcastCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18ad VEX same-size conversions

    private static let vexConversion1Cases: [(String, [UInt8])] = [
        ("vcvtdq2ps xmm0, xmm1",                        [0xC5, 0xF8, 0x5B, 0xC1]),
        ("vcvtps2dq xmm0, xmm1",                        [0xC5, 0xF9, 0x5B, 0xC1]),
        ("vcvttps2dq xmm0, xmm1",                       [0xC5, 0xFA, 0x5B, 0xC1]),
        ("vcvtdq2ps ymm0, ymm1",                        [0xC5, 0xFC, 0x5B, 0xC1]),
        // Scalar (3-op)
        ("vcvtss2sd xmm0, xmm1, xmm2",                  [0xC5, 0xF2, 0x5A, 0xC2]),
        ("vcvtsd2ss xmm0, xmm1, xmm2",                  [0xC5, 0xF3, 0x5A, 0xC2]),
        ("vcvtss2sd xmm0, xmm1, dword ptr [rdi]",       [0xC5, 0xF2, 0x5A, 0x07]),
        ("vcvtsd2ss xmm0, xmm1, qword ptr [rdi]",       [0xC5, 0xF3, 0x5A, 0x07]),
    ]

    func testVexConversion1Assembles() throws {
        for (source, expected) in Self.vexConversion1Cases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexConversion1Disassembles() throws {
        for (source, bytes) in Self.vexConversion1Cases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexConversion1StreamRoundTrip() throws {
        let source = Self.vexConversion1Cases.map(\.0).joined(separator: "\n")
        let expected = Self.vexConversion1Cases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }

    // MARK: - Phase 18ae VEX COMI/UCOMI

    private static let vexComiCases: [(String, [UInt8])] = [
        ("vucomiss xmm0, xmm1",                         [0xC5, 0xF8, 0x2E, 0xC1]),
        ("vucomisd xmm0, xmm1",                         [0xC5, 0xF9, 0x2E, 0xC1]),
        ("vcomiss xmm0, xmm1",                          [0xC5, 0xF8, 0x2F, 0xC1]),
        ("vcomisd xmm0, xmm1",                          [0xC5, 0xF9, 0x2F, 0xC1]),
        ("vucomiss xmm0, dword ptr [rdi]",              [0xC5, 0xF8, 0x2E, 0x07]),
        ("vcomisd xmm0, qword ptr [rdi]",               [0xC5, 0xF9, 0x2F, 0x07]),
    ]

    func testVexComiAssembles() throws {
        for (source, expected) in Self.vexComiCases {
            XCTAssertEqual(try X86Assembler.assemble(source), expected, "assemble \(source)")
        }
    }

    func testVexComiDisassembles() throws {
        for (source, bytes) in Self.vexComiCases {
            XCTAssertEqual(try X86Assembler.disassemble(bytes), source, "disassemble \(bytes.map { String($0, radix: 16) })")
        }
    }

    func testVexComiStreamRoundTrip() throws {
        let source = Self.vexComiCases.map(\.0).joined(separator: "\n")
        let expected = Self.vexComiCases.flatMap(\.1)
        let bytes = try X86Assembler.assemble(source)
        XCTAssertEqual(bytes, expected)
        XCTAssertEqual(try X86Assembler.disassemble(bytes), source)
    }
}
