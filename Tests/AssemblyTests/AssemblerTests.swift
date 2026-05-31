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
