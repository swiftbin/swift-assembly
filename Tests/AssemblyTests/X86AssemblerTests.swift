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
}
