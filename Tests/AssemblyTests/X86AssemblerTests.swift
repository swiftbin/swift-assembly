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
}
