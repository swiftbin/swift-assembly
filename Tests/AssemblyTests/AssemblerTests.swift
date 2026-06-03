import XCTest
@testable import Assembly

final class AssemblerTests: XCTestCase {
    func testBasicSystemAndBranchRegisterInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("nop"), 0xd503201f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ret"), 0xd65f03c0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ret x0"), 0xd65f0000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("br x16"), 0xd61f0200)
        XCTAssertEqual(try ARM64Assembler.assembleWord("blr x16"), 0xd63f0200)
        XCTAssertEqual(try ARM64Assembler.assembleWord("svc #0"), 0xd4000001)
        XCTAssertEqual(try ARM64Assembler.assembleWord("svc #0x80"), 0xd4001001)
    }

    func testExceptionAndBarrierInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("brk #0"), 0xd4200000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("brk #1"), 0xd4200020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("hlt #0"), 0xd4400000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("eret"), 0xd69f03e0)

        XCTAssertEqual(try ARM64Assembler.assembleWord("isb"), 0xd5033fdf)
        XCTAssertEqual(try ARM64Assembler.assembleWord("isb sy"), 0xd5033fdf)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dsb sy"), 0xd5033f9f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dmb ish"), 0xd5033bbf)
    }

    func testAssembleBytesAreLittleEndianByDefault() throws {
        XCTAssertEqual(
            try ARM64Assembler.assemble("ret"),
            [0xc0, 0x03, 0x5f, 0xd6]
        )
    }

    func testAssembleBytesCanBeBigEndian() throws {
        XCTAssertEqual(
            try ARM64Assembler.assemble("ret", endianness: .big),
            [0xd6, 0x5f, 0x03, 0xc0]
        )
    }

    func testDisassembleSystemBranchExceptionAndBarrier() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd503201f), "nop")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd65f03c0), "ret")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd65f0000), "ret x0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd61f0200), "br x16")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd63f0200), "blr x16")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd4001001), "svc #128")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd4200020), "brk #1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd4400000), "hlt #0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd69f03e0), "eret")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5033fdf), "isb")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5033f9f), "dsb sy")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5033bbf), "dmb ish")
    }

    func testDisassembleBytesUseEndianness() throws {
        XCTAssertEqual(
            try ARM64Assembler.disassemble([0xc0, 0x03, 0x5f, 0xd6, 0x1f, 0x20, 0x03, 0xd5]),
            """
            ret
            nop
            """
        )
        XCTAssertEqual(
            try ARM64Assembler.disassemble([0xd6, 0x5f, 0x03, 0xc0], endianness: .big),
            "ret"
        )
    }

    func testMoveWideInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("movz x0, #1"), 0xd2800020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov x0, #1"), 0xd2800020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movz w0, #1"), 0x52800020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movz x0, #0x1234"), 0xd2824680)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movz x0, #0x1234, lsl #16"), 0xd2a24680)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movn x0, #0"), 0x92800000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movk x0, #0x1234"), 0xf2824680)
    }

    func testMoveImmediateAliasChoosesMovzMovnOrLogicalImmediate() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov x0, #0x12340000"), 0xd2a24680)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov w0, #0x12340000"), 0x52a24680)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov x0, #-1"), 0x92800000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov w0, #-1"), 0x12800000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov x0, #0xff"), 0xd2801fe0)
    }

    func testRegisterMoveAliases() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov x0, x1"), 0xaa0103e0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov w0, w1"), 0x2a0103e0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov sp, x0"), 0x9100001f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov x0, sp"), 0x910003e0)
    }

    func testAddSubImmediateInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("add x0, x0, #1"), 0x91000400)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add w0, w0, #1"), 0x11000400)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sub x0, x0, #1"), 0xd1000400)
        XCTAssertEqual(try ARM64Assembler.assembleWord("adds x0, x0, #1"), 0xb1000400)
        XCTAssertEqual(try ARM64Assembler.assembleWord("subs x0, x0, #1"), 0xf1000400)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add x0, x0, #1, lsl #12"), 0x91400400)
    }

    func testAddSubShiftedRegisterInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("add x0, x1, x2"), 0x8b020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add x0, x1, x2, lsl #3"), 0x8b020c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sub x0, x1, x2"), 0xcb020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("adds x0, x1, x2"), 0xab020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("subs x0, x1, x2"), 0xeb020020)
    }

    func testCompareAliases() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmp x0, #1"), 0xf100041f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmn x0, #1"), 0xb100041f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmp x0, x1"), 0xeb01001f)
    }

    func testLogicalShiftedRegisterInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("and x0, x1, x2"), 0x8a020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("orr x0, x1, x2"), 0xaa020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("eor x0, x1, x2"), 0xca020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ands x0, x1, x2"), 0xea020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bic x0, x1, x2"), 0x8a220020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("orn x0, x1, x2"), 0xaa220020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("eon x0, x1, x2"), 0xca220020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mvn x0, x1"), 0xaa2103e0)
    }

    func testLogicalImmediateInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("and x0, x1, #0xff"), 0x92401c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("orr x0, x1, #0xff"), 0xb2401c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("eor x0, x1, #0xff"), 0xd2401c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ands x0, x1, #0xff"), 0xf2401c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("and w0, w1, #0xff"), 0x12001c20)
    }

    func testShiftAliasesAndExtract() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("lsl x0, x1, #3"), 0xd37df020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("lsr x0, x1, #3"), 0xd343fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("asr x0, x1, #3"), 0x9343fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("extr x0, x1, x2, #8"), 0x93c22020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ror x0, x1, #8"), 0x93c12020)
    }

    func testMultiplyAndDivideInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("mul x0, x1, x2"), 0x9b027c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mneg x0, x1, x2"), 0x9b02fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("madd x0, x1, x2, x3"), 0x9b020c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msub x0, x1, x2, x3"), 0x9b028c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("udiv x0, x1, x2"), 0x9ac20820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sdiv x0, x1, x2"), 0x9ac20c20)
    }

    func testAdrAndAdrp() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("adr x0, #0"), 0x10000000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("adr x0, #4"), 0x10000020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("adrp x0, #0"), 0x90000000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("adrp x0, #4096"), 0xb0000000)
    }

    func testDisassembleAdrAndAdrp() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x10000000), "adr x0, #0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x10000020), "adr x0, #4")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x90000000), "adrp x0, #0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xb0000000), "adrp x0, #4096")
    }

    func testUnconditionalBranchesWithLabels() throws {
        XCTAssertEqual(
            try ARM64Assembler.assembleWords("""
            b target
            nop
            target:
            ret
            """),
            [0x14000002, 0xd503201f, 0xd65f03c0]
        )

        XCTAssertEqual(
            try ARM64Assembler.assembleWords("""
            target:
            nop
            b target
            """),
            [0xd503201f, 0x17ffffff]
        )
    }

    func testConditionalBranchesWithLabels() throws {
        XCTAssertEqual(
            try ARM64Assembler.assembleWords("""
            b.eq target
            nop
            target:
            ret
            """),
            [0x54000040, 0xd503201f, 0xd65f03c0]
        )

        XCTAssertEqual(
            try ARM64Assembler.assembleWords("""
            target:
            nop
            b.ne target
            """),
            [0xd503201f, 0x54ffffe1]
        )
    }

    func testCompareAndTestBranchesWithLabels() throws {
        XCTAssertEqual(
            try ARM64Assembler.assembleWords("""
            cbz x0, target
            cbnz w1, target
            tbz x2, #1, target
            tbnz w3, #2, target
            target:
            ret
            """),
            [
                0xb4000080,
                0x35000061,
                0x36080042,
                0x37100023,
                0xd65f03c0,
            ]
        )
    }

    func testDisassembleBranchInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x14000002), "b #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x94000002), "bl #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x17ffffff), "b #-4")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x54000040), "b.eq #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x54ffffe1), "b.ne #-4")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xb4000080), "cbz x0, #16")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x35000061), "cbnz w1, #12")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x36080042), "tbz w2, #1, #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x37100023), "tbnz w3, #2, #4")
    }

    func testLoadStoreUnsignedOffsetInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr x0, [x1]"), 0xf9400020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr x0, [x1, #8]"), 0xf9400420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr w0, [x1, #4]"), 0xb9400420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldrb w0, [x1, #1]"), 0x39400420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldrh w0, [x1, #2]"), 0x79400420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str x0, [x1, #8]"), 0xf9000420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str w0, [x1, #4]"), 0xb9000420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("strb w0, [x1, #1]"), 0x39000420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("strh w0, [x1, #2]"), 0x79000420)
    }

    func testLoadStoreUnscaledAndIndexedInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr x0, [x1, #-8]"), 0xf85f8020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr x0, [x1, #8]!"), 0xf8408c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr x0, [x1], #8"), 0xf8408420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str x0, [x1, #-8]"), 0xf81f8020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str x0, [x1, #8]!"), 0xf8008c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str x0, [x1], #8"), 0xf8008420)
    }

    func testLoadStoreUnscaledAliases() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldur x0, [x1]"), 0xf8400020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldur x0, [x1, #8]"), 0xf8408020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldur w0, [x1, #4]"), 0xb8404020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldurb w0, [x1, #1]"), 0x38401020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldurh w0, [x1, #2]"), 0x78402020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stur x0, [x1]"), 0xf8000020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stur x0, [x1, #-8]"), 0xf81f8020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sturb w0, [x1, #1]"), 0x38001020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sturh w0, [x1, #2]"), 0x78002020)
    }

    func testLoadStoreRegisterOffsetInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr x0, [x1, x2]"), 0xf8626820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr x0, [x1, x2, lsl #3]"), 0xf8627820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr w0, [x1, w2, uxtw #2]"), 0xb8625820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str x0, [x1, x2]"), 0xf8226820)
    }

    func testSignExtendingLoads() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldrsb x0, [x1]"), 0x39800020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldrsb w0, [x1]"), 0x39c00020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldrsh x0, [x1]"), 0x79800020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldrsh w0, [x1]"), 0x79c00020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldrsw x0, [x1]"), 0xb9800020)
    }

    func testLoadStorePairInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("stp x0, x1, [sp, #-16]!"), 0xa9bf07e0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldp x0, x1, [sp], #16"), 0xa8c107e0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stp x0, x1, [sp, #16]"), 0xa90107e0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldp x0, x1, [sp, #16]"), 0xa94107e0)
    }

    func testARM64EInstructionsRequireARM64EArchitecture() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("paciasp"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("autiasp"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("xpaci x0"))

        XCTAssertEqual(try ARM64Assembler.assembleWord("paciasp", architecture: .arm64e), 0xd503233f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("autiasp", architecture: .arm64e), 0xd50323bf)
        XCTAssertEqual(try ARM64Assembler.assembleWord("pacibsp", architecture: .arm64e), 0xd503237f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("autibsp", architecture: .arm64e), 0xd50323ff)
        XCTAssertEqual(try ARM64Assembler.assembleWord("xpaci x0", architecture: .arm64e), 0xdac143e0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("xpacd x0", architecture: .arm64e), 0xdac147e0)
    }

    func testDisassembleAllFamilies() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd2800020), "movz x0, #1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd2a24680), "movz x0, #4660, lsl #16")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x92800000), "movn x0, #0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf2824680), "movk x0, #4660")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xaa0103e0), "mov x0, x1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x91000400), "add x0, x0, #1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x91400400), "add x0, x0, #1, lsl #12")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x8b020c20), "add x0, x1, x2, lsl #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf100041f), "cmp x0, #1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xeb01001f), "cmp x0, x1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x92401c20), "and x0, x1, #255")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xaa020020), "orr x0, x1, x2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xaa2103e0), "mvn x0, x1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd37df020), "lsl x0, x1, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd343fc20), "lsr x0, x1, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9343fc20), "asr x0, x1, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x93c22020), "extr x0, x1, x2, #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x93c12020), "ror x0, x1, #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9b027c20), "mul x0, x1, x2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9b02fc20), "mneg x0, x1, x2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9b020c20), "madd x0, x1, x2, x3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9ac20820), "udiv x0, x1, x2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9ac20c20), "sdiv x0, x1, x2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf9400420), "ldr x0, [x1, #8]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf8408c20), "ldr x0, [x1, #8]!")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf8408420), "ldr x0, [x1], #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf85f8020), "ldur x0, [x1, #-8]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf8626820), "ldr x0, [x1, x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf8627820), "ldr x0, [x1, x2, lsl #3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x39800020), "ldrsb x0, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xa9bf07e0), "stp x0, x1, [sp, #-16]!")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xa8c107e0), "ldp x0, x1, [sp], #16")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xa90107e0), "stp x0, x1, [sp, #16]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd503233f), "paciasp")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xdac143e0), "xpaci x0")
    }

    func testMachineCodeRoundTrips() throws {
        let arm64Sources = [
            "movz x0, #1", "movz w0, #1", "movn x0, #0", "movk x0, #4660",
            "mov x0, x1", "mov w0, w1",
            "add x0, x0, #1", "add x0, x0, #1, lsl #12", "sub x0, x0, #1", "adds x0, x0, #1",
            "add x0, x1, x2", "add x0, x1, x2, lsl #3", "subs x0, x1, x2",
            "cmp x0, #1", "cmn x0, #1", "cmp x0, x1",
            "and x0, x1, #0xff", "orr x0, x1, #0xff", "and w0, w1, #0xff",
            "and x0, x1, x2", "orr x0, x1, x2", "bic x0, x1, x2", "eon x0, x1, x2", "mvn x0, x1",
            "lsl x0, x1, #3", "lsr x0, x1, #3", "asr x0, x1, #3",
            "extr x0, x1, x2, #8", "ror x0, x1, #8",
            "mul x0, x1, x2", "mneg x0, x1, x2", "madd x0, x1, x2, x3", "msub x0, x1, x2, x3",
            "udiv x0, x1, x2", "sdiv x0, x1, x2",
            "ldr x0, [x1, #8]", "ldr w0, [x1, #4]", "ldrb w0, [x1, #1]", "str x0, [x1, #8]",
            "ldr x0, [x1, #8]!", "ldr x0, [x1], #8", "str x0, [x1, #-8]",
            "ldur x0, [x1, #8]", "stur x0, [x1, #-8]",
            "ldr x0, [x1, x2]", "ldr x0, [x1, x2, lsl #3]", "ldr w0, [x1, w2, uxtw #2]",
            "ldrsb x0, [x1]", "ldrsh w0, [x1]", "ldrsw x0, [x1]",
            "stp x0, x1, [sp, #-16]!", "ldp x0, x1, [sp], #16", "stp x0, x1, [sp, #16]",
            "adr x0, #4", "adrp x0, #4096", "nop", "ret", "br x16",
        ]
        for source in arm64Sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }

        let arm64eSources = ["paciasp", "autiasp", "pacibsp", "autibsp", "xpaci x0", "xpacd x0"]
        for source in arm64eSources {
            let word = try ARM64Assembler.assembleWord(source, architecture: .arm64e)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text, architecture: .arm64e)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testFloatingPointDataProcessingInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fadd s0, s1, s2"), 0x1e222820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fadd d0, d1, d2"), 0x1e622820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fsub s3, s4, s5"), 0x1e253883)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmul d6, d7, d8"), 0x1e6808e6)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fdiv s9, s10, s11"), 0x1e2b1949)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fnmul s0, s1, s2"), 0x1e228820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmax s0, s1, s2"), 0x1e224820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminnm d0, d1, d2"), 0x1e627820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fabs s0, s1"), 0x1e20c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fneg d0, d1"), 0x1e614020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fsqrt s0, s1"), 0x1e21c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov s0, s1"), 0x1e204020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmadd s0, s1, s2, s3"), 0x1f020c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fnmsub d0, d1, d2, d3"), 0x1f628c20)
    }

    func testFloatingPointCompareConvertAndMove() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvt d0, s1"), 0x1e22c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvt s0, d1"), 0x1e624020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmp s0, s1"), 0x1e212000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmp s0, #0.0"), 0x1e202008)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmpe d0, d1"), 0x1e612010)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov s0, #1.0"), 0x1e2e1000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov d0, #2.0"), 0x1e601000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov s0, #-0.5"), 0x1e3c1000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf s0, w0"), 0x1e220000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf d0, x0"), 0x9e620000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ucvtf s0, w1"), 0x1e230020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs w0, s0"), 0x1e380000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzu x0, d0"), 0x9e790000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov w0, s0"), 0x1e260000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov x0, d0"), 0x9e660000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov s0, w0"), 0x1e270000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov d0, x0"), 0x9e670000)
    }

    func testDisassembleFloatingPointInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e222820), "fadd s0, s1, s2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e6808e6), "fmul d6, d7, d8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e614020), "fneg d0, d1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e22c020), "fcvt d0, s1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e212000), "fcmp s0, s1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e202008), "fcmp s0, #0.0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e2e1000), "fmov s0, #1.0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e3c1000), "fmov s0, #-0.5")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1f020c20), "fmadd s0, s1, s2, s3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9e620000), "scvtf d0, x0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e380000), "fcvtzs w0, s0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e270000), "fmov s0, w0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9e660000), "fmov x0, d0")
    }

    func testFloatingPointRoundTrip() throws {
        let sources = [
            "fadd s0, s1, s2", "fadd d0, d1, d2", "fsub s3, s4, s5", "fmul d6, d7, d8",
            "fdiv s9, s10, s11", "fnmul s0, s1, s2", "fmax s0, s1, s2", "fminnm d0, d1, d2",
            "fabs s0, s1", "fneg d0, d1", "fsqrt s0, s1", "fmov s0, s1", "fmov d0, d1",
            "fcvt d0, s1", "fcvt s0, d1", "fcmp s0, s1", "fcmp s0, #0.0", "fcmpe d0, d1",
            "fmov s0, #1.0", "fmov d0, #2.0", "fmov s0, #-0.5", "fmadd s0, s1, s2, s3",
            "fnmsub d0, d1, d2, d3", "scvtf s0, w0", "scvtf d0, x0", "ucvtf s0, w1",
            "fcvtzs w0, s0", "fcvtzu x0, d0", "fmov w0, s0", "fmov x0, d0", "fmov s0, w0", "fmov d0, x0",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testFloatingPointInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fadd s0, d1, s2"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fadd b0, b1, b2"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvt s0, s1"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmov s0, #1.3"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcmp s0, #1.0"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmov w0, x1"))
    }

    func testAcrossLanesIntegerInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("addv b0, v1.8b"), 0x0e31b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("addv h0, v1.4h"), 0x0e71b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("addv s0, v1.4s"), 0x4eb1b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("addv b2, v3.16b"), 0x4e31b862)
        XCTAssertEqual(try ARM64Assembler.assembleWord("addv h4, v5.8h"), 0x4e71b8a4)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddlv h0, v1.8b"), 0x0e303820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddlv s0, v1.4h"), 0x0e703820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddlv d0, v1.4s"), 0x4eb03820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uaddlv h0, v1.8b"), 0x2e303820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uaddlv d0, v1.4s"), 0x6eb03820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smaxv b0, v1.8b"), 0x0e30a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umaxv b0, v1.16b"), 0x6e30a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sminv h0, v1.8h"), 0x4e71a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uminv s0, v1.4s"), 0x6eb1a820)
    }

    func testAcrossLanesFPInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxv s0, v1.4s"), 0x6e30f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminv s0, v1.4s"), 0x6eb0f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxnmv s0, v1.4s"), 0x6e30c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminnmv s0, v1.4s"), 0x6eb0c820)
    }

    func testDisassembleAcrossLanes() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e31b820), "addv b0, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4eb1b820), "addv s0, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e303820), "saddlv h0, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4eb03820), "saddlv d0, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e303820), "uaddlv h0, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6eb1a820), "uminv s0, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e30f820), "fmaxv s0, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6eb0c820), "fminnmv s0, v1.4s")
    }

    func testAcrossLanesRoundTrip() throws {
        let sources = [
            "addv b0, v1.8b", "addv h0, v1.4h", "addv s0, v1.4s", "addv b2, v3.16b", "addv h4, v5.8h",
            "saddlv h0, v1.8b", "saddlv s0, v1.4h", "saddlv d0, v1.4s", "saddlv h2, v3.16b", "saddlv s4, v5.8h",
            "uaddlv h0, v1.8b", "uaddlv d0, v1.4s",
            "smaxv b0, v1.8b", "smaxv h0, v1.4h", "smaxv s0, v1.4s",
            "umaxv b0, v1.16b", "sminv h0, v1.8h", "uminv s0, v1.4s",
            "fmaxv s0, v1.4s", "fminv s0, v1.4s", "fmaxnmv s0, v1.4s", "fminnmv s0, v1.4s",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testAcrossLanesInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("addv s0, v1.2s"))   // 2s reserved
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("addv d0, v1.2d"))   // D forms invalid
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("addv h0, v1.8b"))   // dst width mismatch
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("saddlv b0, v1.8b")) // long dst must widen
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmaxv s0, v1.2s"))  // FP only .4s
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("addv b0, v1.foo"))  // bad arrangement
    }

    func testVectorTwoRegisterMiscInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("rev64 v0.8b, v1.8b"), 0x0e200820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rev32 v6.8b, v7.8b"), 0x2e2008e6)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rev16 v10.8b, v11.8b"), 0x0e20196a)
        XCTAssertEqual(try ARM64Assembler.assembleWord("abs v0.8b, v1.8b"), 0x0e20b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("neg v2.4h, v3.4h"), 0x2e60b862)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mvn v4.16b, v5.16b"), 0x6e2058a4)
        XCTAssertEqual(try ARM64Assembler.assembleWord("not v4.16b, v5.16b"), 0x6e2058a4)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rbit v0.8b, v1.8b"), 0x2e605820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cnt v6.8b, v7.8b"), 0x0e2058e6)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cls v8.4s, v9.4s"), 0x4ea04928)
        XCTAssertEqual(try ARM64Assembler.assembleWord("clz v10.2s, v11.2s"), 0x2ea0496a)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqabs v12.8b, v13.8b"), 0x0e2079ac)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqneg v14.4h, v15.4h"), 0x2e6079ee)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fabs v12.4s, v13.4s"), 0x4ea0f9ac)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fneg v14.2d, v15.2d"), 0x6ee0f9ee)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fsqrt v16.4s, v17.4s"), 0x6ea1fa30)
    }

    func testDisassembleVectorTwoRegisterMisc() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e200820), "rev64 v0.8b, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e2008e6), "rev32 v6.8b, v7.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e20196a), "rev16 v10.8b, v11.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e20b820), "abs v0.8b, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e60b862), "neg v2.4h, v3.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e2058a4), "mvn v4.16b, v5.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e605820), "rbit v0.8b, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e2058e6), "cnt v6.8b, v7.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ea04928), "cls v8.4s, v9.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2ea0496a), "clz v10.2s, v11.2s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e2079ac), "sqabs v12.8b, v13.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e6079ee), "sqneg v14.4h, v15.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ea0f9ac), "fabs v12.4s, v13.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ee0f9ee), "fneg v14.2d, v15.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ea1fa30), "fsqrt v16.4s, v17.4s")
    }

    func testVectorTwoRegisterMiscRoundTrip() throws {
        let sources = [
            "rev64 v0.8b, v1.8b", "rev64 v2.4h, v3.4h", "rev64 v4.2s, v5.2s",
            "rev32 v6.8b, v7.8b", "rev32 v8.4h, v9.4h", "rev16 v10.8b, v11.8b",
            "abs v0.2d, v1.2d", "neg v2.2d, v3.2d", "mvn v4.16b, v5.16b", "rbit v6.16b, v7.16b", "cnt v6.8b, v7.8b",
            "cls v8.4s, v9.4s", "clz v10.2s, v11.2s", "sqabs v12.2d, v13.2d", "sqneg v14.2d, v15.2d",
            "fabs v12.4s, v13.4s", "fneg v14.2d, v15.2d", "fsqrt v16.4s, v17.4s",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorTwoRegisterMiscInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cnt v0.4h, v1.4h"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("rev32 v0.2s, v1.2s"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("rev16 v0.4h, v1.4h"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("rbit v0.4h, v1.4h"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("clz v0.2d, v1.2d"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fabs v0.8b, v1.8b"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("abs v0.8b, v1.16b"))
    }

    func testVectorThreeSameIntegerInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("add v0.16b, v1.16b, v2.16b"), 0x4e228420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sub v0.2d, v1.2d, v2.2d"), 0x6ee28420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqadd v0.8b, v1.8b, v2.8b"), 0x0e220c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmgt v0.4s, v1.4s, v2.4s"), 0x4ea23420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sshl v0.2d, v1.2d, v2.2d"), 0x4ee24420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smax v0.4h, v1.4h, v2.4h"), 0x0e626420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mul v0.8b, v1.8b, v2.8b"), 0x0e229c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("pmul v0.16b, v1.16b, v2.16b"), 0x6e229c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmulh v0.4h, v1.4h, v2.4h"), 0x0e62b420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmulh v0.2s, v1.2s, v2.2s"), 0x2ea2b420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("addp v0.2d, v1.2d, v2.2d"), 0x4ee2bc20)
    }

    func testVectorThreeSameLogicalInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("and v0.8b, v1.8b, v2.8b"), 0x0e221c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("orr v0.16b, v1.16b, v2.16b"), 0x4ea21c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bsl v0.8b, v1.8b, v2.8b"), 0x2e621c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bit v0.16b, v1.16b, v2.16b"), 0x6ea21c20)
    }

    func testVectorThreeSameFPInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fadd v0.4s, v1.4s, v2.4s"), 0x4e22d420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fsub v0.4s, v1.4s, v2.4s"), 0x4ea2d420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmul v0.2d, v1.2d, v2.2d"), 0x6e62dc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fdiv v0.2d, v1.2d, v2.2d"), 0x6e62fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmla v0.2s, v1.2s, v2.2s"), 0x0e22cc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmeq v0.4s, v1.4s, v2.4s"), 0x4e22e420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecps v0.4s, v1.4s, v2.4s"), 0x4e22fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fabd v0.4s, v1.4s, v2.4s"), 0x6ea2d420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("faddp v0.2s, v1.2s, v2.2s"), 0x2e22d420)
    }

    func testDisassembleVectorThreeSame() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e228420), "add v0.16b, v1.16b, v2.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e62b420), "sqdmulh v0.4h, v1.4h, v2.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e621c20), "bsl v0.8b, v1.8b, v2.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e62dc20), "fmul v0.2d, v1.2d, v2.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e22e420), "fcmeq v0.4s, v1.4s, v2.4s")
    }

    func testVectorThreeSameRoundTrip() throws {
        let sources = [
            "add v0.16b, v1.16b, v2.16b", "sub v3.2d, v4.2d, v5.2d", "sqadd v6.8b, v7.8b, v8.8b",
            "cmgt v9.4s, v10.4s, v11.4s", "uminp v0.4h, v1.4h, v2.4h", "saba v3.2s, v4.2s, v5.2s",
            "sqdmulh v6.8h, v7.8h, v8.8h", "sqrdmulh v9.4s, v10.4s, v11.4s", "addp v12.2d, v13.2d, v14.2d",
            "and v0.8b, v1.8b, v2.8b", "orn v3.16b, v4.16b, v5.16b", "bif v6.8b, v7.8b, v8.8b",
            "fadd v0.4s, v1.4s, v2.4s", "fmls v3.2d, v4.2d, v5.2d", "fmulx v6.2s, v7.2s, v8.2s",
            "fcmge v9.4s, v10.4s, v11.4s", "facgt v12.2d, v13.2d, v14.2d", "frsqrts v15.4s, v16.4s, v17.4s",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorThreeSameInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("add v0.1d, v1.1d, v2.1d"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("pmul v0.4h, v1.4h, v2.4h"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fadd v0.4h, v1.4h, v2.4h"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("mul v0.2d, v1.2d, v2.2d"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqdmulh v0.8b, v1.8b, v2.8b"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("shadd v0.2d, v1.2d, v2.2d"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("add v0.8b, v1.8b, v2.4h"))
    }

    func testVectorShiftImmediateSameInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("sshr v0.8b, v1.8b, #3"), 0x0f0d0420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ushr v0.8b, v1.8b, #3"), 0x2f0d0420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ssra v0.8b, v1.8b, #3"), 0x0f0d1420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("usra v0.8b, v1.8b, #3"), 0x2f0d1420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("srshr v0.8b, v1.8b, #3"), 0x0f0d2420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("urshr v0.8b, v1.8b, #3"), 0x2f0d2420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("srsra v0.8b, v1.8b, #3"), 0x0f0d3420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ursra v0.8b, v1.8b, #3"), 0x2f0d3420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sri v0.8b, v1.8b, #3"), 0x2f0d4420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sshr v0.4s, v1.4s, #5"), 0x4f3b0420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sshr v0.2d, v1.2d, #10"), 0x4f760420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("shl v0.8b, v1.8b, #3"), 0x0f0b5420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sli v0.8b, v1.8b, #3"), 0x2f0b5420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshl v0.8b, v1.8b, #3"), 0x0f0b7420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqshl v0.8b, v1.8b, #3"), 0x2f0b7420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshlu v0.8b, v1.8b, #3"), 0x2f0b6420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("shl v0.2d, v1.2d, #10"), 0x4f4a5420)
    }

    func testVectorShiftImmediateNarrowWidenAndConvert() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("shrn v0.8b, v1.8h, #3"), 0x0f0d8420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("shrn2 v0.16b, v1.8h, #3"), 0x4f0d8420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rshrn v0.8b, v1.8h, #3"), 0x0f0d8c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshrn v0.8b, v1.8h, #3"), 0x0f0d9420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrshrn v0.8b, v1.8h, #3"), 0x0f0d9c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqshrn v0.8b, v1.8h, #3"), 0x2f0d9420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqrshrn v0.8b, v1.8h, #3"), 0x2f0d9c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshrun v0.8b, v1.8h, #3"), 0x2f0d8420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrshrun v0.8b, v1.8h, #3"), 0x2f0d8c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sshll v0.8h, v1.8b, #3"), 0x0f0ba420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sshll2 v0.8h, v1.16b, #3"), 0x4f0ba420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ushll v0.8h, v1.8b, #3"), 0x2f0ba420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ushll2 v0.8h, v1.16b, #3"), 0x6f0ba420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sxtl v0.8h, v1.8b"), 0x0f08a420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uxtl v0.8h, v1.8b"), 0x2f08a420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf v0.4s, v1.4s, #3"), 0x4f3de420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ucvtf v0.2s, v1.2s, #3"), 0x2f3de420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs v0.4s, v1.4s, #3"), 0x4f3dfc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzu v0.2d, v1.2d, #3"), 0x6f7dfc20)
    }

    func testDisassembleVectorShiftImmediate() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f0d0420), "sshr v0.8b, v1.8b, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4f760420), "sshr v0.2d, v1.2d, #10")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f0b5420), "shl v0.8b, v1.8b, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f0d8420), "shrn v0.8b, v1.8h, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4f0d8420), "shrn2 v0.16b, v1.8h, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f0ba420), "sshll v0.8h, v1.8b, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6f0ba420), "ushll2 v0.8h, v1.16b, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f08a420), "sxtl v0.8h, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2f08a420), "uxtl v0.8h, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4f3dfc20), "fcvtzs v0.4s, v1.4s, #3")
    }

    func testVectorShiftImmediateRoundTrip() throws {
        let sources = [
            "sshr v0.8b, v1.8b, #3", "ushr v2.16b, v3.16b, #7", "ssra v4.4h, v5.4h, #5",
            "usra v6.8h, v7.8h, #12", "srshr v8.2s, v9.2s, #1", "urshr v10.4s, v11.4s, #31",
            "srsra v12.2d, v13.2d, #40", "sri v14.2d, v15.2d, #64", "shl v0.8b, v1.8b, #0",
            "sli v2.4s, v3.4s, #20", "sqshl v4.2d, v5.2d, #33", "uqshl v6.8h, v7.8h, #9",
            "sqshlu v8.16b, v9.16b, #5", "shrn v0.4h, v1.4s, #10", "shrn2 v2.8h, v3.4s, #16",
            "rshrn v4.2s, v5.2d, #20", "sqshrn v6.8b, v7.8h, #8", "uqshrn2 v8.16b, v9.8h, #3",
            "sqshrun v10.4h, v11.4s, #15", "sqrshrun2 v12.4s, v13.2d, #32",
            "sshll v0.4s, v1.4h, #10", "ushll2 v2.2d, v3.4s, #25", "sxtl v4.8h, v5.8b",
            "uxtl2 v6.4s, v7.8h", "scvtf v0.4s, v1.4s, #3", "ucvtf v2.2d, v3.2d, #40",
            "fcvtzs v4.2s, v5.2s, #5", "fcvtzu v6.4s, v7.4s, #20",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorShiftImmediateInvalidInputsThrow() throws {
        // `1d` is the scalar form, not a vector arrangement.
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sshr v0.1d, v1.1d, #3"))
        // Right-shift amount must be in 1...esize.
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sshr v0.8b, v1.8b, #9"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sshr v0.8b, v1.8b, #0"))
        // Left-shift amount must be in 0...esize-1.
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("shl v0.8b, v1.8b, #8"))
        // Narrowing source must be one element-size up from the destination.
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("shrn v0.8b, v1.4s, #3"))
        // Widening destination must be one element-size up from the source.
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sshll v0.4s, v1.8b, #3"))
        // Fixed-point convert is only defined for `2s`/`4s`/`2d`.
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf v0.8b, v1.8b, #3"))
    }

    func testVectorModifiedImmediateInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.8b, #0xab"), 0x0f05e560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.16b, #0xab"), 0x4f05e560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.4h, #0xab"), 0x0f058560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.4h, #0xab, lsl #8"), 0x0f05a560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.8h, #0xab, lsl #8"), 0x4f05a560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.2s, #0xab"), 0x0f050560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.2s, #0xab, lsl #8"), 0x0f052560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.2s, #0xab, lsl #16"), 0x0f054560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.2s, #0xab, lsl #24"), 0x0f056560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.4s, #0xab, lsl #24"), 0x4f056560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.2s, #0xab, msl #8"), 0x0f05c560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.2s, #0xab, msl #16"), 0x0f05d560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.4s, #0xab, msl #16"), 0x4f05d560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi d0, #0xff00ff00ff00ff00"), 0x2f05e540)
        XCTAssertEqual(try ARM64Assembler.assembleWord("movi v0.2d, #0xff00ff00ff00ff00"), 0x6f05e540)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mvni v0.4h, #0xab"), 0x2f058560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mvni v0.4h, #0xab, lsl #8"), 0x2f05a560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mvni v0.2s, #0xab, lsl #16"), 0x2f054560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mvni v0.4s, #0xab, msl #8"), 0x6f05c560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("orr v0.4h, #0xab"), 0x0f059560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("orr v0.4h, #0xab, lsl #8"), 0x0f05b560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("orr v0.2s, #0xab, lsl #16"), 0x0f055560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("orr v0.4s, #0xab"), 0x4f051560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bic v0.4h, #0xab"), 0x2f059560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bic v0.2s, #0xab, lsl #24"), 0x2f057560)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov v0.2s, #1.0"), 0x0f03f600)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov v0.4s, #1.0"), 0x4f03f600)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov v0.2d, #1.0"), 0x6f03f600)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov v0.2s, #-1.5"), 0x0f07f700)
    }

    func testDisassembleVectorModifiedImmediate() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f05e560), "movi v0.8b, #0xab")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f05a560), "movi v0.4h, #0xab, lsl #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f05c560), "movi v0.2s, #0xab, msl #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2f05e540), "movi d0, #0xff00ff00ff00ff00")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6f05e540), "movi v0.2d, #0xff00ff00ff00ff00")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6f05c560), "mvni v0.4s, #0xab, msl #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4f051560), "orr v0.4s, #0xab")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2f057560), "bic v0.2s, #0xab, lsl #24")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6f03f600), "fmov v0.2d, #1.0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f07f700), "fmov v0.2s, #-1.5")
    }

    func testVectorModifiedImmediateRoundTrip() throws {
        let sources = [
            "movi v0.8b, #0", "movi v1.16b, #255", "movi v2.4h, #0x10, lsl #8",
            "movi v3.8h, #0x10", "movi v4.2s, #0x7f, lsl #16", "movi v5.4s, #0x7f, msl #16",
            "movi v6.2d, #0xffff0000ffff0000", "movi d7, #0x00ff00ff00ff00ff",
            "mvni v8.4h, #0x33, lsl #8", "mvni v9.4s, #0x44, msl #8",
            "orr v10.8h, #0x55", "orr v11.4s, #0x66, lsl #24",
            "bic v12.4h, #0x77, lsl #8", "bic v13.2s, #0x88",
            "fmov v14.2s, #1.0", "fmov v15.4s, #-3.5", "fmov v16.2d, #0.5",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorModifiedImmediateInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("movi v0.8b, #0x100"))     // byte out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("movi v0.8b, #0xab, lsl #8")) // 8-bit takes no shift
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("movi v0.4h, #0xab, lsl #16")) // 16-bit only lsl 0/8
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("movi v0.2s, #0xab, lsl #32")) // out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("orr v0.2s, #0xab, msl #8"))  // orr has no msl form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("movi v0.2d, #0x1234"))       // bytes not all 0x00/0xff
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmov v0.2s, #100.0"))        // not representable
    }

    func testVectorCopyInstructions() throws {
        // DUP (element)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup v0.8b, v1.b[3]"), 0x0e070420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup v0.16b, v1.b[3]"), 0x4e070420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup v0.4h, v1.h[2]"), 0x0e0a0420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup v0.2s, v1.s[1]"), 0x0e0c0420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup v0.2d, v1.d[1]"), 0x4e180420)
        // DUP (general)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup v0.8b, w1"), 0x0e010c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup v0.4h, w1"), 0x0e020c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup v0.2s, w1"), 0x0e040c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup v0.2d, x1"), 0x4e080c20)
        // SMOV
        XCTAssertEqual(try ARM64Assembler.assembleWord("smov w0, v1.b[3]"), 0x0e072c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smov w0, v1.h[2]"), 0x0e0a2c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smov x0, v1.b[3]"), 0x4e072c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smov x0, v1.s[1]"), 0x4e0c2c20)
        // UMOV
        XCTAssertEqual(try ARM64Assembler.assembleWord("umov w0, v1.b[3]"), 0x0e073c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umov w0, v1.h[2]"), 0x0e0a3c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umov w0, v1.s[1]"), 0x0e0c3c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umov x0, v1.d[1]"), 0x4e183c20)
        // INS (general)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ins v0.b[3], w1"), 0x4e071c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ins v0.h[2], w1"), 0x4e0a1c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ins v0.s[1], w1"), 0x4e0c1c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ins v0.d[1], x1"), 0x4e181c20)
        // INS (element)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ins v0.b[3], v1.b[5]"), 0x6e072c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ins v0.h[2], v1.h[1]"), 0x6e0a1420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ins v0.s[1], v1.s[0]"), 0x6e0c0420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ins v0.d[1], v1.d[0]"), 0x6e180420)
    }

    func testVectorCopyMovAliases() throws {
        // MOV is an alias of INS (element/general) and UMOV.
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov v0.b[3], v1.b[5]"), 0x6e072c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov v0.s[1], w1"), 0x4e0c1c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov v0.d[1], x1"), 0x4e181c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov w0, v1.s[1]"), 0x0e0c3c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov x0, v1.d[1]"), 0x4e183c20)
    }

    func testDisassembleVectorCopy() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e070420), "dup v0.8b, v1.b[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e180420), "dup v0.2d, v1.d[1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e080c20), "dup v0.2d, x1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e072c20), "smov x0, v1.b[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e183c20), "umov x0, v1.d[1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e181c20), "ins v0.d[1], x1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e072c20), "ins v0.b[3], v1.b[5]")
    }

    func testVectorCopyRoundTrip() throws {
        let sources = [
            "dup v0.8b, v1.b[3]", "dup v2.16b, v3.b[7]", "dup v4.4h, v5.h[2]",
            "dup v6.8h, v7.h[6]", "dup v8.2s, v9.s[1]", "dup v10.4s, v11.s[3]",
            "dup v12.2d, v13.d[1]",
            "dup v14.8b, w15", "dup v16.4h, w17", "dup v18.2s, w19", "dup v20.2d, x21",
            "smov w0, v1.b[15]", "smov w2, v3.h[7]", "smov x4, v5.b[3]", "smov x6, v7.s[1]",
            "umov w8, v9.b[3]", "umov w10, v11.h[2]", "umov w12, v13.s[3]", "umov x14, v15.d[1]",
            "ins v0.b[15], w1", "ins v2.h[7], w3", "ins v4.s[3], w5", "ins v6.d[1], x7",
            "ins v8.b[3], v9.b[5]", "ins v10.h[2], v11.h[1]", "ins v12.s[1], v13.s[0]",
            "ins v14.d[1], v15.d[0]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorCopyInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dup v0.1d, v1.d[0]"))   // 1d is the scalar form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dup v0.8b, v1.h[2]"))   // element width mismatch
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dup v0.8b, v1.b[16]"))  // index out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dup v0.8b, x1"))        // B element needs W register
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dup v0.2d, w1"))        // D element needs X register
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("smov x0, v1.d[0]"))     // SMOV cannot take D
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("smov w0, v1.s[0]"))     // SMOV Wd max is H
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("umov w0, v1.d[0]"))     // UMOV Wd cannot take D
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("umov x0, v1.b[0]"))     // UMOV Xd only takes D
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ins v0.s[1], x1"))      // S element needs W register
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ins v0.b[3], v1.h[1]")) // element width mismatch
    }

    func testOverlappingMnemonicsStillResolveToScalarForms() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("add x0, x1, x2"), 0x8b020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fadd s0, s1, s2"), 0x1e222820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mul w0, w1, w2"), 0x1b027c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("orr w0, w1, w2"), 0x2a020020)
        // `sqshl`/`uqshl` still resolve to the three-same (register) form.
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshl v0.8b, v1.8b, v2.8b"), 0x0e224c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqshl v0.8b, v1.8b, v2.8b"), 0x2e224c20)
    }

    func testCommentsBlankLinesAndInlineLabels() throws {
        XCTAssertEqual(
            try ARM64Assembler.assembleWords("""
            // leading comment
            
            entry: mov x0, #1 ; inline comment
                   b done
            ignored_label: // label-only line
            done: ret
            """),
            [0xd2800020, 0x14000001, 0xd65f03c0]
        )
    }

    func testInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWords(""))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("unknown x0"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ret w0"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("movz x0, #0x10000"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("add x0, x0, #1, lsl #1"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldr x0, [x1, #3]"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("orr x0, x1, #0"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("bic x0, x1, #0xff"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dsb invalid"))
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("b missing_label"))
    }
}
