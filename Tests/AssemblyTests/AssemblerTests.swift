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
        XCTAssertEqual(try ARM64Assembler.assembleWord("suqadd v0.8b, v1.8b"), 0x0e203820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("suqadd v0.2d, v1.2d"), 0x4ee03820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("usqadd v0.16b, v1.16b"), 0x6e203820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("usqadd v0.2d, v1.2d"), 0x6ee03820)
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
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e203820), "suqadd v0.8b, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ee03820), "usqadd v0.2d, v1.2d")
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
            "suqadd v16.8h, v17.8h", "suqadd v18.2d, v19.2d", "usqadd v20.4h, v21.4h", "usqadd v22.4s, v23.4s",
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

    func testVectorPermuteInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("zip1 v0.8b, v1.8b, v2.8b"), 0x0e023820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("zip2 v0.8b, v1.8b, v2.8b"), 0x0e027820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("zip1 v0.16b, v1.16b, v2.16b"), 0x4e023820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("zip2 v0.16b, v1.16b, v2.16b"), 0x4e027820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uzp1 v0.4h, v1.4h, v2.4h"), 0x0e421820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uzp2 v0.4h, v1.4h, v2.4h"), 0x0e425820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("trn1 v0.2s, v1.2s, v2.2s"), 0x0e822820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("trn2 v0.2s, v1.2s, v2.2s"), 0x0e826820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("zip1 v0.2d, v1.2d, v2.2d"), 0x4ec23820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("zip2 v0.4s, v1.4s, v2.4s"), 0x4e827820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uzp1 v0.8h, v1.8h, v2.8h"), 0x4e421820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("trn2 v0.16b, v1.16b, v2.16b"), 0x4e026820)
    }

    func testVectorExtractInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ext v0.8b, v1.8b, v2.8b, #3"), 0x2e021820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ext v0.16b, v1.16b, v2.16b, #7"), 0x6e023820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ext v0.16b, v1.16b, v2.16b, #0"), 0x6e020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ext v0.8b, v1.8b, v2.8b, #7"), 0x2e023820)
    }

    func testDisassembleVectorPermuteAndExtract() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e023820), "zip1 v0.8b, v1.8b, v2.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ec23820), "zip1 v0.2d, v1.2d, v2.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e421820), "uzp1 v0.4h, v1.4h, v2.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e826820), "trn2 v0.2s, v1.2s, v2.2s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e021820), "ext v0.8b, v1.8b, v2.8b, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e023820), "ext v0.16b, v1.16b, v2.16b, #7")
    }

    func testVectorPermuteAndExtractRoundTrip() throws {
        let sources = [
            "zip1 v0.8b, v1.8b, v2.8b", "zip2 v3.16b, v4.16b, v5.16b",
            "uzp1 v6.4h, v7.4h, v8.4h", "uzp2 v9.8h, v10.8h, v11.8h",
            "trn1 v12.2s, v13.2s, v14.2s", "trn2 v15.4s, v16.4s, v17.4s",
            "zip1 v18.2d, v19.2d, v20.2d",
            "ext v0.8b, v1.8b, v2.8b, #0", "ext v3.8b, v4.8b, v5.8b, #7",
            "ext v6.16b, v7.16b, v8.16b, #0", "ext v9.16b, v10.16b, v11.16b, #15",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorPermuteAndExtractInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("zip1 v0.1d, v1.1d, v2.1d"))    // 1d reserved
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("zip1 v0.8b, v1.8b, v2.16b"))   // arrangement mismatch
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ext v0.4h, v1.4h, v2.4h, #1")) // ext is byte-only
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ext v0.8b, v1.8b, v2.8b, #8")) // index out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ext v0.16b, v1.16b, v2.16b, #16")) // index out of range
    }

    func testVectorThreeDifferentInstructions() throws {
        // Long forms (Vd.Ta, Vn.Tb, Vm.Tb), including the `2` upper-half forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddl v0.8h, v1.8b, v2.8b"), 0x0e220020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddl2 v0.8h, v1.16b, v2.16b"), 0x4e220020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddl v0.4s, v1.4h, v2.4h"), 0x0e620020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddl v0.2d, v1.2s, v2.2s"), 0x0ea20020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uaddl v0.8h, v1.8b, v2.8b"), 0x2e220020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ssubl v0.4s, v1.4h, v2.4h"), 0x0e622020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("usubl v0.2d, v1.2s, v2.2s"), 0x2ea22020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sabal v0.8h, v1.8b, v2.8b"), 0x0e225020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uabal v0.4s, v1.4h, v2.4h"), 0x2e625020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sabdl v0.2d, v1.2s, v2.2s"), 0x0ea27020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uabdl v0.8h, v1.8b, v2.8b"), 0x2e227020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smlal v0.4s, v1.4h, v2.4h"), 0x0e628020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umlal v0.2d, v1.2s, v2.2s"), 0x2ea28020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smlsl v0.8h, v1.8b, v2.8b"), 0x0e22a020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umlsl v0.4s, v1.4h, v2.4h"), 0x2e62a020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smull v0.2d, v1.2s, v2.2s"), 0x0ea2c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umull v0.8h, v1.8b, v2.8b"), 0x2e22c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smull2 v0.4s, v1.8h, v2.8h"), 0x4e62c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("pmull v0.8h, v1.8b, v2.8b"), 0x0e22e020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("pmull2 v0.8h, v1.16b, v2.16b"), 0x4e22e020)
        // PMULL 64→128 polynomial form (Vd.1Q, Vn.1D/2D, Vm.1D/2D).
        XCTAssertEqual(try ARM64Assembler.assembleWord("pmull v0.1q, v1.1d, v2.1d"), 0x0ee2e020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("pmull2 v0.1q, v1.2d, v2.2d"), 0x4ee2e020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmull v0.4s, v1.4h, v2.4h"), 0x0e62d020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmlal v0.2d, v1.2s, v2.2s"), 0x0ea29020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmlsl v0.4s, v1.4h, v2.4h"), 0x0e62b020)
        // Wide forms (Vd.Ta, Vn.Ta, Vm.Tb).
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddw v0.8h, v1.8h, v2.8b"), 0x0e221020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddw2 v0.8h, v1.8h, v2.16b"), 0x4e221020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uaddw v0.4s, v1.4s, v2.4h"), 0x2e621020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ssubw v0.2d, v1.2d, v2.2s"), 0x0ea23020)
        // Narrow forms (Vd.Tb, Vn.Ta, Vm.Ta).
        XCTAssertEqual(try ARM64Assembler.assembleWord("addhn v0.8b, v1.8h, v2.8h"), 0x0e224020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("addhn2 v0.16b, v1.8h, v2.8h"), 0x4e224020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("subhn v0.4h, v1.4s, v2.4s"), 0x0e626020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("raddhn v0.2s, v1.2d, v2.2d"), 0x2ea24020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rsubhn v0.8b, v1.8h, v2.8h"), 0x2e226020)
    }

    func testDisassembleVectorThreeDifferent() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e220020), "saddl v0.8h, v1.8b, v2.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e220020), "saddl2 v0.8h, v1.16b, v2.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0ea2c020), "smull v0.2d, v1.2s, v2.2s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e22e020), "pmull v0.8h, v1.8b, v2.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e22e020), "pmull2 v0.8h, v1.16b, v2.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0ee2e020), "pmull v0.1q, v1.1d, v2.1d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ee2e020), "pmull2 v0.1q, v1.2d, v2.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e221020), "saddw v0.8h, v1.8h, v2.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e224020), "addhn2 v0.16b, v1.8h, v2.8h")
    }

    func testVectorThreeDifferentRoundTrip() throws {
        let sources = [
            "saddl v0.8h, v1.8b, v2.8b", "saddl2 v3.4s, v4.8h, v5.8h",
            "uaddl v6.2d, v7.2s, v8.2s", "ssubl2 v9.8h, v10.16b, v11.16b",
            "smull v12.4s, v13.4h, v14.4h", "umull2 v15.2d, v16.4s, v17.4s",
            "pmull v18.8h, v19.8b, v20.8b", "pmull2 v21.8h, v22.16b, v23.16b",
            "pmull v30.1q, v31.1d, v0.1d", "pmull2 v1.1q, v2.2d, v3.2d",
            "sqdmull v24.4s, v25.4h, v26.4h", "sqdmlal v27.2d, v28.2s, v29.2s",
            "saddw v0.8h, v1.8h, v2.8b", "uaddw2 v3.4s, v4.4s, v5.8h",
            "addhn v6.8b, v7.8h, v8.8h", "subhn2 v9.8h, v10.4s, v11.4s",
            "raddhn v12.2s, v13.2d, v14.2d", "rsubhn2 v15.16b, v16.8h, v17.8h",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorThreeDifferentInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("saddl v0.8h, v1.4h, v2.4h"))   // source must be half-width
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("saddl v0.8h, v1.8b, v2.16b"))  // sources must match
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("pmull v0.4s, v1.4h, v2.4h"))   // pmull only has byte / 1q forms
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("pmull v0.1q, v1.2s, v2.2s"))   // 1q form requires 1d/2d source
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqdmull v0.8h, v1.8b, v2.8b")) // sqdmull excludes byte
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("addhn v0.8h, v1.8h, v2.8h"))   // narrow dest must be half
    }

    func testVectorDotProductInstructions() throws {
        // Vector form (Vd.2s/4s, Vn.8b/16b, Vm.8b/16b).
        XCTAssertEqual(try ARM64Assembler.assembleWord("sdot v0.2s, v1.8b, v2.8b"), 0x0e829420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sdot v0.4s, v1.16b, v2.16b"), 0x4e829420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("udot v0.2s, v1.8b, v2.8b"), 0x2e829420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("udot v0.4s, v1.16b, v2.16b"), 0x6e829420)
        // By-element form (Vd.2s/4s, Vn.8b/16b, Vm.4b[index]).
        XCTAssertEqual(try ARM64Assembler.assembleWord("sdot v0.2s, v1.8b, v2.4b[0]"), 0x0f82e020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sdot v0.4s, v1.16b, v2.4b[3]"), 0x4fa2e820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("udot v0.2s, v1.8b, v2.4b[1]"), 0x2fa2e020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("udot v0.4s, v1.16b, v2.4b[2]"), 0x6f82e820)
    }

    func testDisassembleVectorDotProduct() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e829420), "sdot v0.2s, v1.8b, v2.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e829420), "udot v0.4s, v1.16b, v2.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4fa2e820), "sdot v0.4s, v1.16b, v2.4b[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2fa2e020), "udot v0.2s, v1.8b, v2.4b[1]")
    }

    func testVectorDotProductRoundTrip() throws {
        let sources = [
            "sdot v0.2s, v1.8b, v2.8b", "sdot v3.4s, v4.16b, v5.16b",
            "udot v6.2s, v7.8b, v8.8b", "udot v9.4s, v10.16b, v11.16b",
            "sdot v12.2s, v13.8b, v14.4b[0]", "sdot v15.4s, v16.16b, v17.4b[3]",
            "udot v18.2s, v19.8b, v20.4b[1]", "udot v21.4s, v22.16b, v23.4b[2]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testVectorDotProductInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sdot v0.4h, v1.8b, v2.8b"))    // dest must be 2s/4s
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sdot v0.2s, v1.16b, v2.16b"))  // 2s pairs with 8b
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sdot v0.2s, v1.8b, v2.16b"))   // sources must match
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sdot v0.2s, v1.8b, v2.4b[4]")) // index out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sdot v0.2s, v1.8b, v2.8b[0]")) // element must be 4b
    }

    func testVectorThreeSameExtraInstructions() throws {
        // Vector non-indexed forms (Vd.T, Vn.T, Vm.T) with T in {4h,8h,2s,4s}.
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlah v0.4h, v1.4h, v2.4h"), 0x2e428420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlah v0.8h, v1.8h, v2.8h"), 0x6e428420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlah v0.2s, v1.2s, v2.2s"), 0x2e828420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlah v0.4s, v1.4s, v2.4s"), 0x6e828420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlsh v0.4h, v1.4h, v2.4h"), 0x2e428c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlsh v0.4s, v1.4s, v2.4s"), 0x6e828c20)
        // Scalar non-indexed forms (Hd/Sd, ...).
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlah h0, h1, h2"), 0x7e428420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlah s0, s1, s2"), 0x7e828420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlsh h0, h1, h2"), 0x7e428c20)
        // Vector by-element forms (Vm.Ts[index]), reusing the indexed encoding.
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlah v0.4h, v1.4h, v2.h[3]"), 0x2f72d020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlah v0.4s, v1.4s, v2.s[1]"), 0x6fa2d020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlsh v0.8h, v1.8h, v2.h[7]"), 0x6f72f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlsh v0.4s, v1.4s, v2.s[3]"), 0x6fa2f820)
        // Scalar by-element forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlah h0, h1, v2.h[3]"), 0x7f72d020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmlah s0, s1, v2.s[2]"), 0x7f82d820)
    }

    func testDisassembleVectorThreeSameExtra() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e428420), "sqrdmlah v0.4h, v1.4h, v2.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e828c20), "sqrdmlsh v0.4s, v1.4s, v2.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7e428420), "sqrdmlah h0, h1, h2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2f72d020), "sqrdmlah v0.4h, v1.4h, v2.h[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7f82d820), "sqrdmlah s0, s1, v2.s[2]")
    }

    func testVectorThreeSameExtraRoundTrip() throws {
        let sources = [
            "sqrdmlah v0.4h, v1.4h, v2.4h", "sqrdmlah v3.8h, v4.8h, v5.8h",
            "sqrdmlah v6.2s, v7.2s, v8.2s", "sqrdmlah v9.4s, v10.4s, v11.4s",
            "sqrdmlsh v12.4h, v13.4h, v14.4h", "sqrdmlsh v15.4s, v16.4s, v17.4s",
            "sqrdmlah h0, h1, h2", "sqrdmlah s3, s4, s5",
            "sqrdmlsh h6, h7, h8", "sqrdmlsh s9, s10, s11",
            "sqrdmlah v18.4h, v19.4h, v15.h[5]", "sqrdmlah v21.4s, v22.4s, v23.s[3]",
            "sqrdmlsh v24.8h, v25.8h, v14.h[2]", "sqrdmlsh v27.4s, v28.4s, v29.s[0]",
            "sqrdmlah h12, h13, v14.h[7]", "sqrdmlah s15, s16, v17.s[1]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testVectorThreeSameExtraInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqrdmlah v0.8b, v1.8b, v2.8b"))   // byte not allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqrdmlah v0.2d, v1.2d, v2.2d"))   // double not allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqrdmlah v0.4h, v1.4h, v2.8h"))   // arrangements must match
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqrdmlah d0, d1, d2"))            // scalar double not allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqrdmlah b0, b1, b2"))            // scalar byte not allowed
    }

    func testVectorIndexedInstructions() throws {
        // Same forms (Vd.T, Vn.T, Vm.Ts[index]).
        XCTAssertEqual(try ARM64Assembler.assembleWord("mul v0.4h, v1.4h, v2.h[3]"), 0x0f728020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mul v0.8h, v1.8h, v2.h[7]"), 0x4f728820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mul v0.2s, v1.2s, v2.s[1]"), 0x0fa28020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mul v0.4s, v1.4s, v2.s[3]"), 0x4fa28820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mla v0.4s, v1.4s, v2.s[2]"), 0x6f820820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mls v0.8h, v1.8h, v2.h[5]"), 0x6f524820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmulh v0.4s, v1.4s, v2.s[1]"), 0x4fa2c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmulh v0.8h, v1.8h, v2.h[6]"), 0x4f62d820)
        // FP forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmul v0.4s, v1.4s, v2.s[3]"), 0x4fa29820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmul v0.2d, v1.2d, v2.d[1]"), 0x4fc29820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmla v0.4s, v1.4s, v2.s[0]"), 0x4f821020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmls v0.2d, v1.2d, v2.d[0]"), 0x4fc25020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmulx v0.4s, v1.4s, v2.s[2]"), 0x6f829820)
        // Long forms (Vd.Ta, Vn.Tb, Vm.Ts[index]), including the `2` upper-half forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("smull v0.4s, v1.4h, v2.h[3]"), 0x0f72a020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smull2 v0.4s, v1.8h, v2.h[7]"), 0x4f72a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umull v0.2d, v1.2s, v2.s[1]"), 0x2fa2a020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smlal v0.2d, v1.2s, v2.s[3]"), 0x0fa22820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umlsl v0.4s, v1.4h, v2.h[2]"), 0x2f626020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmull v0.4s, v1.4h, v2.h[1]"), 0x0f52b020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmlal2 v0.2d, v1.4s, v2.s[2]"), 0x4f823820)
        // Element register beyond 0-15 for the S/D forms uses the M bit.
        XCTAssertEqual(try ARM64Assembler.assembleWord("mul v0.4h, v1.4h, v15.h[3]"), 0x0f7f8020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mul v0.4s, v1.4s, v31.s[3]"), 0x4fbf8820)
    }

    func testDisassembleVectorIndexed() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f728020), "mul v0.4h, v1.4h, v2.h[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4fa29820), "fmul v0.4s, v1.4s, v2.s[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4fc29820), "fmul v0.2d, v1.2d, v2.d[1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4f72a820), "smull2 v0.4s, v1.8h, v2.h[7]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4f823820), "sqdmlal2 v0.2d, v1.4s, v2.s[2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4fbf8820), "mul v0.4s, v1.4s, v31.s[3]")
    }

    func testVectorIndexedRoundTrip() throws {
        let sources = [
            "mul v0.4h, v1.4h, v2.h[3]", "mul v0.4s, v1.4s, v31.s[3]",
            "mla v3.8h, v4.8h, v5.h[7]", "mls v6.2s, v7.2s, v8.s[1]",
            "sqdmulh v9.4s, v10.4s, v11.s[2]", "sqrdmulh v12.8h, v13.8h, v9.h[0]",
            "fmul v15.4s, v16.4s, v17.s[3]", "fmul v18.2d, v19.2d, v20.d[1]",
            "fmla v21.2s, v22.2s, v23.s[0]", "fmls v24.4s, v25.4s, v26.s[2]",
            "fmulx v27.2d, v28.2d, v29.d[0]",
            "smull v0.4s, v1.4h, v2.h[3]", "smull2 v3.2d, v4.4s, v5.s[1]",
            "umull v6.2d, v7.2s, v8.s[3]", "smlal v9.4s, v10.4h, v11.h[5]",
            "umlsl2 v12.4s, v13.8h, v10.h[2]", "sqdmull v15.4s, v16.4h, v7.h[1]",
            "sqdmlal2 v18.2d, v19.4s, v20.s[2]", "sqdmlsl v21.4s, v22.4h, v3.h[6]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorIndexedInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("mul v0.4h, v1.4h, v2.s[1]"))    // element width mismatch
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("mul v0.4s, v1.4s, v2.s[4]"))    // index out of range (S: 0-3)
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("mul v0.4h, v1.4h, v16.h[3]"))   // H form limits register to 0-15
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("mul v0.8b, v1.8b, v2.b[3]"))    // byte element unsupported
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("smull v0.2d, v1.4h, v2.h[3]"))  // long dest must be one size up
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmla v0.4h, v1.4h, v2.h[3]"))   // FP16 indexed form unsupported
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmul v0.2d, v1.4s, v2.s[1]"))   // fp dest/source mismatch
    }

    func testScalarThreeSameInstructions() throws {
        // Double-only forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("add d0, d1, d2"), 0x5ee28420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sub d0, d1, d2"), 0x7ee28420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmeq d0, d1, d2"), 0x7ee28c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmge d0, d1, d2"), 0x5ee23c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmgt d0, d1, d2"), 0x5ee23420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmhi d0, d1, d2"), 0x7ee23420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmhs d0, d1, d2"), 0x7ee23c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmtst d0, d1, d2"), 0x5ee28c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sshl d0, d1, d2"), 0x5ee24420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ushl d0, d1, d2"), 0x7ee24420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("srshl d0, d1, d2"), 0x5ee25420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("urshl d0, d1, d2"), 0x7ee25420)
        // Saturating forms accept all element widths.
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqadd b0, b1, b2"), 0x5e220c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqadd h0, h1, h2"), 0x5e620c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqadd s0, s1, s2"), 0x5ea20c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqadd d0, d1, d2"), 0x5ee20c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqadd d0, d1, d2"), 0x7ee20c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqsub d0, d1, d2"), 0x5ee22c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqsub d0, d1, d2"), 0x7ee22c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshl b0, b1, b2"), 0x5e224c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqshl h0, h1, h2"), 0x7e624c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrshl s0, s1, s2"), 0x5ea25c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqrshl d0, d1, d2"), 0x7ee25c20)
        // sqdmulh / sqrdmulh accept only half and single widths.
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmulh h0, h1, h2"), 0x5e62b420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmulh s0, s1, s2"), 0x5ea2b420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmulh h0, h1, h2"), 0x7e62b420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmulh s0, s1, s2"), 0x7ea2b420)
    }

    func testDisassembleScalarThreeSame() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ee28420), "add d0, d1, d2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7ee28420), "sub d0, d1, d2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e220c20), "sqadd b0, b1, b2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea2b420), "sqdmulh s0, s1, s2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7ee25c20), "uqrshl d0, d1, d2")
    }

    func testScalarThreeSameRoundTrip() throws {
        let sources = [
            "add d0, d1, d2", "sub d3, d4, d5", "cmeq d6, d7, d8",
            "cmge d9, d10, d11", "cmgt d12, d13, d14", "cmhi d15, d16, d17",
            "cmhs d18, d19, d20", "cmtst d21, d22, d23",
            "sshl d24, d25, d26", "ushl d27, d28, d29", "srshl d30, d31, d0", "urshl d1, d2, d3",
            "sqadd b4, b5, b6", "uqadd h7, h8, h9", "sqsub s10, s11, s12", "uqsub d13, d14, d15",
            "sqshl b16, b17, b18", "uqshl h19, h20, h21", "sqrshl s22, s23, s24", "uqrshl d25, d26, d27",
            "sqdmulh h28, h29, h30", "sqrdmulh s31, s0, s1",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarThreeSameInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("add s0, s1, s2"))      // add is double-only
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cmeq b0, b1, b2"))     // cmeq is double-only
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqdmulh d0, d1, d2"))  // sqdmulh excludes double
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqdmulh b0, b1, b2"))  // sqdmulh excludes byte
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("add d0, d1, s2"))      // widths must match
    }

    func testScalarPairwiseInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("addp d0, v1.2d"), 0x5ef1b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("faddp s0, v1.2s"), 0x7e30d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("faddp d0, v1.2d"), 0x7e70d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxp s0, v1.2s"), 0x7e30f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxp d0, v1.2d"), 0x7e70f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminp s0, v1.2s"), 0x7eb0f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminp d0, v1.2d"), 0x7ef0f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxnmp s0, v1.2s"), 0x7e30c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxnmp d0, v1.2d"), 0x7e70c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminnmp s0, v1.2s"), 0x7eb0c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminnmp d0, v1.2d"), 0x7ef0c820)
    }

    func testDisassembleScalarPairwise() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ef1b820), "addp d0, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7e30d820), "faddp s0, v1.2s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7ef0f820), "fminp d0, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7e70c820), "fmaxnmp d0, v1.2d")
    }

    func testScalarPairwiseRoundTrip() throws {
        let sources = [
            "addp d0, v1.2d",
            "faddp s2, v3.2s", "faddp d4, v5.2d",
            "fmaxp s6, v7.2s", "fmaxp d8, v9.2d",
            "fminp s10, v11.2s", "fminp d12, v13.2d",
            "fmaxnmp s14, v15.2s", "fmaxnmp d16, v17.2d",
            "fminnmp s18, v19.2s", "fminnmp d20, v21.2d",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarPairwiseInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("addp s0, v1.2s"))    // addp is double-only
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("addp d0, v1.4s"))    // source must be 2d
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("faddp d0, v1.2s"))   // dest width must match source
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("faddp s0, v1.4s"))   // unsupported source arrangement
    }

    func testScalarTwoRegisterMiscInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("abs d0, d1"), 0x5ee0b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("neg d0, d1"), 0x7ee0b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqabs b0, b1"), 0x5e207820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqabs h0, h1"), 0x5e607820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqabs s0, s1"), 0x5ea07820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqabs d0, d1"), 0x5ee07820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqneg d0, d1"), 0x7ee07820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("suqadd b0, b1"), 0x5e203820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("usqadd d0, d1"), 0x7ee03820)
        // Compare-against-zero forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmeq d0, d1, #0"), 0x5ee09820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmge d0, d1, #0"), 0x7ee08820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmgt d0, d1, #0"), 0x5ee08820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmle d0, d1, #0"), 0x7ee09820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmlt d0, d1, #0"), 0x5ee0a820)
    }

    func testDisassembleScalarTwoRegisterMisc() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ee0b820), "abs d0, d1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7ee0b820), "neg d0, d1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e207820), "sqabs b0, b1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ee09820), "cmeq d0, d1, #0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ee0a820), "cmlt d0, d1, #0")
    }

    func testScalarTwoRegisterMiscRoundTrip() throws {
        let sources = [
            "abs d0, d1", "neg d2, d3",
            "sqabs b4, b5", "sqabs h6, h7", "sqabs s8, s9", "sqabs d10, d11",
            "sqneg b12, b13", "sqneg d14, d15",
            "suqadd b16, b17", "suqadd s18, s19", "usqadd h20, h21", "usqadd d22, d23",
            "cmeq d24, d25, #0", "cmge d26, d27, #0", "cmgt d28, d29, #0",
            "cmle d30, d31, #0", "cmlt d0, d1, #0",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarTwoRegisterMiscInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("abs s0, s1"))         // abs is double-only
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("neg b0, b1"))         // neg is double-only
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cmlt s0, s1, #0"))    // compare-zero is double-only
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("abs d0, s1"))         // widths must match
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cmeq d0, d1, #1"))    // only #0 is allowed
    }

    func testScalarShiftImmediateInstructions() throws {
        // Right shifts (amount 1...64).
        XCTAssertEqual(try ARM64Assembler.assembleWord("sshr d0, d1, #1"), 0x5f7f0420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sshr d0, d1, #64"), 0x5f400420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ushr d0, d1, #32"), 0x7f600420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ssra d0, d1, #5"), 0x5f7b1420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("usra d0, d1, #5"), 0x7f7b1420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("srshr d0, d1, #5"), 0x5f7b2420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("urshr d0, d1, #5"), 0x7f7b2420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("srsra d0, d1, #5"), 0x5f7b3420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ursra d0, d1, #5"), 0x7f7b3420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sri d0, d1, #7"), 0x7f794420)
        // Left shifts (amount 0...63).
        XCTAssertEqual(try ARM64Assembler.assembleWord("shl d0, d1, #0"), 0x5f405420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("shl d0, d1, #63"), 0x5f7f5420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sli d0, d1, #7"), 0x7f475420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshl d0, d1, #5"), 0x5f457420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqshl d0, d1, #5"), 0x7f457420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshlu d0, d1, #5"), 0x7f456420)
    }

    func testDisassembleScalarShiftImmediate() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f7f0420), "sshr d0, d1, #1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f400420), "sshr d0, d1, #64")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f405420), "shl d0, d1, #0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7f475420), "sli d0, d1, #7")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7f456420), "sqshlu d0, d1, #5")
    }

    func testScalarShiftImmediateRoundTrip() throws {
        let sources = [
            "sshr d0, d1, #1", "sshr d2, d3, #64", "ushr d4, d5, #33",
            "ssra d6, d7, #16", "usra d8, d9, #48", "srshr d10, d11, #1",
            "urshr d12, d13, #64", "srsra d14, d15, #7", "ursra d16, d17, #23",
            "sri d18, d19, #40",
            "shl d20, d21, #0", "shl d22, d23, #63", "sli d24, d25, #31",
            "sqshl d26, d27, #12", "uqshl d28, d29, #50", "sqshlu d30, d31, #5",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarShiftImmediateInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sshr d0, d1, #0"))    // right shift min is 1
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sshr d0, d1, #65"))   // right shift max is 64
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("shl d0, d1, #64"))    // left shift max is 63
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sshr s0, s1, #1"))    // only double-width supported
    }

    func testScalarThreeDifferentInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmull s0, h1, h2"), 0x5e62d020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmull d0, s1, s2"), 0x5ea2d020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmlal s0, h1, h2"), 0x5e629020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmlal d0, s1, s2"), 0x5ea29020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmlsl s0, h1, h2"), 0x5e62b020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmlsl d0, s1, s2"), 0x5ea2b020)
    }

    func testDisassembleScalarThreeDifferent() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e62d020), "sqdmull s0, h1, h2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea2d020), "sqdmull d0, s1, s2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e629020), "sqdmlal s0, h1, h2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e62b020), "sqdmlsl s0, h1, h2")
    }

    func testScalarThreeDifferentRoundTrip() throws {
        let sources = [
            "sqdmull s0, h1, h2", "sqdmull d3, s4, s5",
            "sqdmlal s6, h7, h8", "sqdmlal d9, s10, s11",
            "sqdmlsl s12, h13, h14", "sqdmlsl d15, s16, s17",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarThreeDifferentInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqdmull d0, h1, h2"))   // h source must produce s
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqdmull b0, b1, b2"))   // byte not allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqdmull q0, d1, d2"))   // double source not allowed
    }

    func testScalarIndexedInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmull s0, h1, v2.h[3]"), 0x5f72b020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmull d0, s1, v2.s[3]"), 0x5fa2b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmlal s0, h1, v2.h[7]"), 0x5f723820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmlsl d0, s1, v2.s[1]"), 0x5fa27020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmulh h0, h1, v2.h[3]"), 0x5f72c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqdmulh s0, s1, v2.s[3]"), 0x5fa2c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmulh h0, h1, v2.h[3]"), 0x5f72d020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrdmulh s0, s1, v2.s[3]"), 0x5fa2d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmul s0, s1, v2.s[3]"), 0x5fa29820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmul d0, d1, v2.d[1]"), 0x5fc29820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmla s0, s1, v2.s[3]"), 0x5fa21820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmls s0, s1, v2.s[3]"), 0x5fa25820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmulx s0, s1, v2.s[3]"), 0x7fa29820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmulx d0, d1, v2.d[1]"), 0x7fc29820)
    }

    func testDisassembleScalarIndexed() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f72b020), "sqdmull s0, h1, v2.h[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5fa2b820), "sqdmull d0, s1, v2.s[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f72c020), "sqdmulh h0, h1, v2.h[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5fa29820), "fmul s0, s1, v2.s[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7fc29820), "fmulx d0, d1, v2.d[1]")
    }

    func testScalarIndexedRoundTrip() throws {
        let sources = [
            "sqdmull s0, h1, v2.h[3]", "sqdmull d3, s4, v5.s[3]",
            "sqdmlal s6, h7, v8.h[7]", "sqdmlsl d9, s10, v11.s[1]",
            "sqdmulh h12, h13, v14.h[3]", "sqdmulh s15, s16, v17.s[2]",
            "sqrdmulh h18, h19, v3.h[5]", "sqrdmulh s20, s21, v22.s[3]",
            "fmul s23, s24, v25.s[1]", "fmul d26, d27, v28.d[0]",
            "fmla s29, s30, v31.s[3]", "fmls s0, s1, v2.s[0]",
            "fmulx s3, s4, v5.s[2]", "fmulx d6, d7, v8.d[1]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarIndexedInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqdmull d0, h1, v2.h[3]"))    // h source must produce s
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqdmulh d0, d1, v2.d[1]"))    // sqdmulh has no d form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmul h0, h1, v2.h[3]"))       // FP16 scalar indexed unsupported
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqdmull s0, h1, v16.h[3]"))   // H element reg limited to 0-15
    }

    func testScalarCopyInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup b0, v1.b[15]"), 0x5e1f0420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup h0, v1.h[7]"), 0x5e1e0420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup s0, v1.s[3]"), 0x5e1c0420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup d0, v1.d[1]"), 0x5e180420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dup d0, v1.d[0]"), 0x5e080420)
        // `mov` is the preferred alias for the scalar element copy.
        XCTAssertEqual(try ARM64Assembler.assembleWord("mov d0, v1.d[1]"), 0x5e180420)
    }

    func testDisassembleScalarCopy() throws {
        // The scalar element copy disassembles to its preferred `mov` form.
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e1f0420), "mov b0, v1.b[15]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e1e0420), "mov h0, v1.h[7]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e1c0420), "mov s0, v1.s[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e180420), "mov d0, v1.d[1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e080420), "mov d0, v1.d[0]")
    }

    func testScalarCopyRoundTrip() throws {
        let sources = [
            "dup b3, v4.b[10]", "dup h5, v6.h[2]", "dup s7, v8.s[1]",
            "dup d9, v10.d[0]", "mov d11, v12.d[1]", "mov s13, v14.s[3]",
            "mov b15, v16.b[7]", "mov h17, v18.h[4]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarCopyInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dup s0, v1.d[1]"))   // dest width must match element
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dup b0, v1.b[16]"))  // index out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dup d0, v1.d[2]"))   // index out of range
    }

    func testScalarFPTwoRegisterMiscInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtns s0, s1"), 0x5e21a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtns d0, d1"), 0x5e61a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtnu s0, s1"), 0x7e21a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtms s0, s1"), 0x5e21b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtmu s0, s1"), 0x7e21b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtps s0, s1"), 0x5ea1a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtpu s0, s1"), 0x7ea1a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs s0, s1"), 0x5ea1b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzu s0, s1"), 0x7ea1b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtas s0, s1"), 0x5e21c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtau s0, s1"), 0x7e21c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf s0, s1"), 0x5e21d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ucvtf s0, s1"), 0x7e21d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf d0, d1"), 0x5e61d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecpe s0, s1"), 0x5ea1d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frsqrte s0, s1"), 0x7ea1d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecpx s0, s1"), 0x5ea1f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtxn s0, d1"), 0x7e616820)
        // Compare against #0.0.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmeq s0, s1, #0.0"), 0x5ea0d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmge s0, s1, #0.0"), 0x7ea0c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmgt s0, s1, #0.0"), 0x5ea0c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmle s0, s1, #0.0"), 0x7ea0d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmlt s0, s1, #0.0"), 0x5ea0e820)
    }

    func testDisassembleScalarFPTwoRegisterMisc() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e21a820), "fcvtns s0, s1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e61d820), "scvtf d0, d1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea1b820), "fcvtzs s0, s1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7e616820), "fcvtxn s0, d1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea0d820), "fcmeq s0, s1, #0.0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea0e820), "fcmlt s0, s1, #0.0")
    }

    func testScalarFPTwoRegisterMiscRoundTrip() throws {
        let sources = [
            "fcvtns s0, s1", "fcvtns d2, d3", "fcvtnu s4, s5", "fcvtms d6, d7",
            "fcvtmu s8, s9", "fcvtps d10, d11", "fcvtpu s12, s13", "fcvtzs d14, d15",
            "fcvtzu s16, s17", "fcvtas d18, d19", "fcvtau s20, s21", "scvtf d22, d23",
            "ucvtf s24, s25", "frecpe d26, d27", "frsqrte s28, s29", "frecpx d30, d31",
            "fcvtxn s0, d1",
            "fcmgt s2, s3, #0.0", "fcmge d4, d5, #0.0", "fcmeq s6, s7, #0.0",
            "fcmle d8, d9, #0.0", "fcmlt s10, s11, #0.0",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarFPTwoRegisterMiscInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvtns b0, b1"))    // byte width unsupported
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvtns s0, d1"))    // operand widths must match
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvtxn d0, d1"))    // fcvtxn dest is single
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcmeq s0, s1, #1.0")) // only #0.0 allowed
    }

    func testScalarFPConvertToGeneralStillResolves() throws {
        // The general-register convert forms must keep their existing meaning.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs w0, s1"),
                       try ARM64Assembler.assembleWord("fcvtzs w0, s1"))
        XCTAssertNoThrow(try ARM64Assembler.assembleWord("fcvtzs w0, s1"))
        XCTAssertNoThrow(try ARM64Assembler.assembleWord("scvtf s0, w1"))
    }

    func testScalarThreeSameFPInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmulx s0, s1, s2"), 0x5e22dc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmulx d0, d1, d2"), 0x5e62dc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmeq s0, s1, s2"), 0x5e22e420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmge s0, s1, s2"), 0x7e22e420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmgt s0, s1, s2"), 0x7ea2e420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("facge s0, s1, s2"), 0x7e22ec20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("facgt s0, s1, s2"), 0x7ea2ec20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecps s0, s1, s2"), 0x5e22fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecps d0, d1, d2"), 0x5e62fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frsqrts s0, s1, s2"), 0x5ea2fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fabd s0, s1, s2"), 0x7ea2d420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fabd d0, d1, d2"), 0x7ee2d420)
    }

    func testDisassembleScalarThreeSameFP() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e22dc20), "fmulx s0, s1, s2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7ea2e420), "fcmgt s0, s1, s2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea2fc20), "frsqrts s0, s1, s2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7ee2d420), "fabd d0, d1, d2")
    }

    func testScalarThreeSameFPRoundTrip() throws {
        let sources = [
            "fmulx s0, s1, s2", "fmulx d3, d4, d5", "fcmeq s6, s7, s8",
            "fcmge d9, d10, d11", "fcmgt s12, s13, s14", "facge d15, d16, d17",
            "facgt s18, s19, s20", "frecps d21, d22, d23", "frsqrts s24, s25, s26",
            "fabd d27, d28, d29", "fabd s30, s31, s0",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarThreeSameFPInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmulx b0, b1, b2"))   // byte width unsupported
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmulx s0, d1, d2"))   // widths must match
    }

    func testScalarShiftNarrowInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshrn b0, h1, #3"), 0x5f0d9420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshrn h0, s1, #5"), 0x5f1b9420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshrn s0, d1, #9"), 0x5f379420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrshrn b0, h1, #3"), 0x5f0d9c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqshrn b0, h1, #3"), 0x7f0d9420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqrshrn h0, s1, #5"), 0x7f1b9c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqshrun b0, h1, #3"), 0x7f0d8420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqrshrun s0, d1, #9"), 0x7f378c20)
    }

    func testDisassembleScalarShiftNarrow() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f0d9420), "sqshrn b0, h1, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f379420), "sqshrn s0, d1, #9")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7f0d8420), "sqshrun b0, h1, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7f1b9c20), "uqrshrn h0, s1, #5")
    }

    func testScalarShiftNarrowRoundTrip() throws {
        let sources = [
            "sqshrn b0, h1, #1", "sqshrn b2, h3, #8", "sqshrn h4, s5, #16",
            "sqshrn s6, d7, #32", "sqrshrn b8, h9, #4", "uqshrn h10, s11, #10",
            "uqrshrn s12, d13, #20", "sqshrun b14, h15, #2", "sqrshrun h16, s17, #7",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarShiftNarrowInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqshrn b0, h1, #0"))   // shift min is 1
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqshrn b0, h1, #9"))   // shift max is destEsize (8)
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqshrn b0, s1, #3"))   // dest must be one size below source
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqshrn d0, d1, #3"))   // no d destination
    }

    func testScalarTwoRegisterMiscNarrowInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtn b0, h1"), 0x5e214820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtn h0, s1"), 0x5e614820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtn s0, d1"), 0x5ea14820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqxtn b0, h1"), 0x7e214820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqxtn s0, d1"), 0x7ea14820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtun b0, h1"), 0x7e212820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtun s0, d1"), 0x7ea12820)
    }

    func testDisassembleScalarTwoRegisterMiscNarrow() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e214820), "sqxtn b0, h1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea14820), "sqxtn s0, d1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7e214820), "uqxtn b0, h1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7e212820), "sqxtun b0, h1")
    }

    func testScalarTwoRegisterMiscNarrowRoundTrip() throws {
        let sources = [
            "sqxtn b0, h1", "sqxtn h2, s3", "sqxtn s4, d5",
            "uqxtn b6, h7", "uqxtn h8, s9", "uqxtn s10, d11",
            "sqxtun b12, h13", "sqxtun h14, s15", "sqxtun s16, d17",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarTwoRegisterMiscNarrowInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqxtn b0, s1"))   // dest must be one size below source
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqxtn d0, d1"))   // no d destination
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sqxtn h0, h1"))   // source must be one size above dest
    }

    func testScalarShiftFixedPointInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf s0, s1, #1"), 0x5f3fe420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf d0, d1, #1"), 0x5f7fe420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf s0, s1, #32"), 0x5f20e420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ucvtf s0, s1, #2"), 0x7f3ee420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs s0, s1, #3"), 0x5f3dfc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs d0, d1, #64"), 0x5f40fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzu d0, d1, #4"), 0x7f7cfc20)
    }

    func testDisassembleScalarShiftFixedPoint() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f3fe420), "scvtf s0, s1, #1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f7fe420), "scvtf d0, d1, #1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f3dfc20), "fcvtzs s0, s1, #3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7f7cfc20), "fcvtzu d0, d1, #4")
    }

    func testScalarShiftFixedPointRoundTrip() throws {
        let sources = [
            "scvtf s0, s1, #1", "scvtf s2, s3, #32", "scvtf d4, d5, #1", "scvtf d6, d7, #64",
            "ucvtf s8, s9, #16", "ucvtf d10, d11, #40",
            "fcvtzs s12, s13, #8", "fcvtzs d14, d15, #50",
            "fcvtzu s16, s17, #31", "fcvtzu d18, d19, #63",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarShiftFixedPointInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf s0, s1, #0"))    // fbits min is 1
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf s0, s1, #33"))   // S max is 32
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf d0, d1, #65"))   // D max is 64
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf s0, d1, #4"))    // mismatched widths
    }

    func testScalarFixedPointConvertWithoutFbitsStillResolves() throws {
        // Two-operand forms must stay the FP<->GP integer converts, not the scalar fixed-point form.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs w0, s1"), 0x1e380020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf s0, w1"), 0x1e220020)
    }

    func testLoadStoreFPSingleInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("str b0, [x1]"), 0x3d000020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str h0, [x1]"), 0x7d000020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str s0, [x1]"), 0xbd000020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str d0, [x1]"), 0xfd000020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str q0, [x1]"), 0x3d800020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr b0, [x1]"), 0x3d400020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr s0, [x1]"), 0xbd400020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr d0, [x1]"), 0xfd400020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr q0, [x1]"), 0x3dc00020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str q0, [x1, #16]"), 0x3d800420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr q0, [x1, #32]"), 0x3dc00820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str s0, [x1, #4]"), 0xbd000420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr d0, [x1, #8]"), 0xfd400420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str q0, [x1, #16]!"), 0x3c810c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr q0, [x1], #16"), 0x3cc10420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stur q0, [x1, #-8]"), 0x3c9f8020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldur s0, [x1, #3]"), 0xbc403020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr q0, [x1, x2]"), 0x3ce26820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str d0, [x1, x2, lsl #3]"), 0xfc227820)
    }

    func testLoadStoreFPPairInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("stp s0, s1, [x2]"), 0x2d000440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldp s0, s1, [x2]"), 0x2d400440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stp d0, d1, [x2]"), 0x6d000440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldp d0, d1, [x2]"), 0x6d400440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stp q0, q1, [x2]"), 0xad000440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldp q0, q1, [x2]"), 0xad400440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stp q0, q1, [x2, #32]"), 0xad010440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldp d0, d1, [x2, #16]!"), 0x6dc10440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stp s0, s1, [x2], #8"), 0x2c810440)
    }

    func testDisassembleLoadStoreFP() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x3dc00020), "ldr q0, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xbd000420), "str s0, [x1, #4]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x3c810c20), "str q0, [x1, #16]!")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x3cc10420), "ldr q0, [x1], #16")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x3ce26820), "ldr q0, [x1, x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xad400440), "ldp q0, q1, [x2]")
    }

    func testLoadStoreFPRoundTrip() throws {
        let sources = [
            "str b0, [x1]", "ldr h2, [x3, #6]", "str s4, [x5, #12]", "ldr d6, [x7, #16]!",
            "str q8, [x9], #16", "ldur s10, [x11, #-4]", "stur q12, [x13, #5]",
            "ldr q14, [x15, x16]", "str d18, [x19, x20, lsl #3]",
            "stp s0, s1, [x2]", "ldp d2, d3, [x4, #16]", "stp q4, q5, [x6, #32]!",
            "ldp q6, q7, [x8], #32",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testLoadStoreFPInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("str s0, [x1, #3]"))    // misaligned offset
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("stp s0, d1, [x2]"))    // mismatched widths
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldp q0, q1, [x2, x3]")) // register offset not allowed for pair
    }

    func testIntegerLoadStoreStillResolves() throws {
        // The integer load/store forms must remain unaffected by the SIMD&FP routing.
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldr x0, [x1]"), 0xf9400020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("str w0, [x1, #4]"), 0xb9000420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldp x0, x1, [x2]"), 0xa9400440)
    }

    func testLoadStoreMultipleInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.16b}, [x1]"), 0x4c007020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.8b}, [x1]"), 0x0c007020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.16b, v1.16b}, [x1]"), 0x4c00a020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.4s, v1.4s, v2.4s}, [x1]"), 0x4c006820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.2d, v1.2d, v2.2d, v3.2d}, [x1]"), 0x4c002c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.16b}, [x1]"), 0x4c407020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.16b, v1.16b}, [x1]"), 0x4c40a020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.8h, v1.8h, v2.8h}, [x1]"), 0x4c406420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x1]"), 0x4c402820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st2 {v0.16b, v1.16b}, [x1]"), 0x4c008020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st3 {v0.4s, v1.4s, v2.4s}, [x1]"), 0x4c004820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st4 {v0.2d, v1.2d, v2.2d, v3.2d}, [x1]"), 0x4c000c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld2 {v0.8h, v1.8h}, [x1]"), 0x4c408420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld3 {v0.2s, v1.2s, v2.2s}, [x1]"), 0x0c404820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld4 {v0.16b, v1.16b, v2.16b, v3.16b}, [x1]"), 0x4c400020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v30.2d, v31.2d}, [x5]"), 0x4c40acbe)  // register wrap-around
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.1d}, [x1]"), 0x0c407c20)           // 1d arrangement
    }

    func testLoadStoreMultiplePostIndex() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.16b}, [x1], #16"), 0x4c9f7020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.16b, v1.16b}, [x1], #32"), 0x4c9fa020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.4s, v1.4s, v2.4s}, [x1], #48"), 0x4c9f6820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.2d, v1.2d, v2.2d, v3.2d}, [x1], #64"), 0x4c9f2c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.8b}, [x1], #8"), 0x0cdf7020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.16b}, [x1], x2"), 0x4c827020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld2 {v0.16b, v1.16b}, [x1], #32"), 0x4cdf8020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st3 {v0.4s, v1.4s, v2.4s}, [x1], x5"), 0x4c854820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld4 {v0.2d, v1.2d, v2.2d, v3.2d}, [x1], #64"), 0x4cdf0c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.16b}, [sp], #16"), 0x4c9f73e0)  // SP base register
    }

    func testDisassembleLoadStoreMultiple() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4c007020), "st1 {v0.16b}, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4c40a020), "ld1 {v0.16b, v1.16b}, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4c008020), "st2 {v0.16b, v1.16b}, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4c9f7020), "st1 {v0.16b}, [x1], #16")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4c827020), "st1 {v0.16b}, [x1], x2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4cdf0c20), "ld4 {v0.2d, v1.2d, v2.2d, v3.2d}, [x1], #64")
    }

    func testLoadStoreMultipleRoundTrip() throws {
        let sources = [
            "st1 {v0.8b}, [x1]", "ld1 {v2.16b, v3.16b}, [x4]",
            "st1 {v5.4h, v6.4h, v7.4h}, [x8]", "ld1 {v9.2s, v10.2s, v11.2s, v12.2s}, [x13]",
            "st2 {v0.8h, v1.8h}, [x2]", "ld3 {v0.4s, v1.4s, v2.4s}, [x3]",
            "st4 {v0.16b, v1.16b, v2.16b, v3.16b}, [x4]",
            "ld1 {v30.2d, v31.2d}, [x5]",
            "st1 {v0.16b}, [sp], #16", "ld2 {v0.4s, v1.4s}, [x1], x2",
            "ld1 {v0.1d}, [x1]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testLoadStoreMultipleInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld2 {v0.16b}, [x1]"))               // LD2 needs 2 registers
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld1 {v0.16b, v1.8b}, [x1]"))        // mixed arrangements
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld1 {v0.16b, v2.16b}, [x1]"))       // non-consecutive
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("st1 {v0.16b}, [x1], #8"))           // wrong post-index immediate
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld3 {v0.4s, v1.4s, v2.4s, v3.4s}, [x1]")) // LD3 needs exactly 3
    }

    func testLoadStoreReplicateInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1r {v0.16b}, [x1]"), 0x4d40c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1r {v0.8h}, [x1]"), 0x4d40c420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1r {v0.4s}, [x1]"), 0x4d40c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1r {v0.2d}, [x1]"), 0x4d40cc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld2r {v0.16b, v1.16b}, [x1]"), 0x4d60c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld3r {v0.4s, v1.4s, v2.4s}, [x1]"), 0x4d40e820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld4r {v0.2d, v1.2d, v2.2d, v3.2d}, [x1]"), 0x4d60ec20)
        // Post-index forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1r {v0.16b}, [x1], #1"), 0x4ddfc020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld2r {v0.8h, v1.8h}, [x1], #4"), 0x4dffc420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld4r {v0.2d, v1.2d, v2.2d, v3.2d}, [x1], #32"), 0x4dffec20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1r {v5.4s}, [x2], x3"), 0x4dc3c845)
    }

    func testLoadStoreSingleLaneInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.b}[3], [x1]"), 0x0d400c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.h}[5], [x1]"), 0x4d404820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.s}[1], [x1]"), 0x0d409020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.d}[1], [x1]"), 0x4d408420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.b}[15], [x1]"), 0x4d001c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st1 {v0.d}[0], [sp]"), 0x0d0087e0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld2 {v0.s, v1.s}[2], [x1]"), 0x4d608020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st3 {v0.h, v1.h, v2.h}[7], [x1]"), 0x4d007820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld4 {v0.d, v1.d, v2.d, v3.d}[1], [x1]"), 0x4d60a420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st4 {v0.b, v1.b, v2.b, v3.b}[3], [x1]"), 0x0d202c20)
        // Post-index forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.s}[1], [x1], #4"), 0x0ddf9020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld1 {v0.b}[3], [x1], x2"), 0x0dc20c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ld3 {v0.h, v1.h, v2.h}[7], [x1], #6"), 0x4ddf7820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("st2 {v0.d, v1.d}[1], [x1], x5"), 0x4da58420)
    }

    func testDisassembleLoadStoreSingleStructure() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4d40c020), "ld1r {v0.16b}, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4d60ec20), "ld4r {v0.2d, v1.2d, v2.2d, v3.2d}, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ddfc020), "ld1r {v0.16b}, [x1], #1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0d400c20), "ld1 {v0.b}[3], [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4d408420), "ld1 {v0.d}[1], [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4d007820), "st3 {v0.h, v1.h, v2.h}[7], [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0ddf9020), "ld1 {v0.s}[1], [x1], #4")
    }

    func testLoadStoreSingleStructureRoundTrip() throws {
        let sources = [
            "ld1r {v0.16b}, [x1]", "ld1r {v3.8h}, [x4]", "ld1r {v7.4s}, [x8]", "ld1r {v9.2d}, [x10]",
            "ld2r {v0.16b, v1.16b}, [x1]", "ld3r {v5.4s, v6.4s, v7.4s}, [x8]",
            "ld4r {v0.2d, v1.2d, v2.2d, v3.2d}, [x1]",
            "ld1r {v0.16b}, [x1], #1", "ld1r {v5.4s}, [x2], x3",
            "ld1 {v0.b}[3], [x1]", "ld1 {v2.h}[5], [x3]", "ld1 {v4.s}[1], [x5]", "ld1 {v6.d}[1], [x7]",
            "st1 {v0.b}[15], [x1]", "st4 {v0.b, v1.b, v2.b, v3.b}[3], [x1]",
            "ld2 {v0.s, v1.s}[2], [x1]", "st3 {v0.h, v1.h, v2.h}[7], [x1]",
            "ld4 {v0.d, v1.d, v2.d, v3.d}[1], [x1]",
            "ld1 {v0.s}[1], [x1], #4", "ld1 {v0.b}[3], [x1], x2", "st2 {v0.d, v1.d}[1], [x1], x5",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testLoadStoreSingleStructureInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld1 {v0.b}[16], [x1]"))         // index out of range (B: max 15)
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld1 {v0.s}[4], [x1]"))          // index out of range (S: max 3)
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld1 {v0.d}[2], [x1]"))          // index out of range (D: max 1)
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld2 {v0.s}[1], [x1]"))          // LD2 needs 2 registers
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld2 {v0.s, v2.s}[1], [x1]"))    // non-consecutive
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld1 {v0.s}[1], [x1], #8"))      // wrong post-index immediate
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ld2r {v0.16b}, [x1]"))          // LD2R needs 2 registers
    }

    func testVectorTableLookupInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("tbl v0.8b, {v1.16b}, v2.8b"), 0x0e020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("tbl v0.16b, {v1.16b}, v2.16b"), 0x4e020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("tbl v0.8b, {v1.16b, v2.16b}, v3.8b"), 0x0e032020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("tbl v0.16b, {v1.16b, v2.16b, v3.16b}, v4.16b"), 0x4e044020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("tbl v0.8b, {v1.16b, v2.16b, v3.16b, v4.16b}, v5.8b"), 0x0e056020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("tbx v0.8b, {v1.16b}, v2.8b"), 0x0e021020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("tbx v0.16b, {v1.16b, v2.16b}, v3.16b"), 0x4e033020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("tbx v0.8b, {v30.16b, v31.16b, v0.16b}, v5.8b"), 0x0e0553c0)  // register wrap-around
        XCTAssertEqual(try ARM64Assembler.assembleWord("tbl v7.16b, {v31.16b, v0.16b, v1.16b, v2.16b}, v8.16b"), 0x4e0863e7)
    }

    func testDisassembleVectorTableLookup() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e020020), "tbl v0.8b, {v1.16b}, v2.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e044020), "tbl v0.16b, {v1.16b, v2.16b, v3.16b}, v4.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e021020), "tbx v0.8b, {v1.16b}, v2.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e0863e7), "tbl v7.16b, {v31.16b, v0.16b, v1.16b, v2.16b}, v8.16b")
    }

    func testVectorTableLookupRoundTrip() throws {
        let sources = [
            "tbl v0.8b, {v1.16b}, v2.8b", "tbl v0.16b, {v1.16b}, v2.16b",
            "tbl v0.8b, {v1.16b, v2.16b}, v3.8b", "tbx v5.16b, {v10.16b, v11.16b, v12.16b}, v13.16b",
            "tbx v0.8b, {v30.16b, v31.16b, v0.16b}, v5.8b",
            "tbl v7.16b, {v31.16b, v0.16b, v1.16b, v2.16b}, v8.16b",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorTableLookupInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("tbl v0.8b, {v1.8b}, v2.8b"))         // table must be 16b
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("tbl v0.8b, {v1.16b}, v2.16b"))       // dst/index arrangement mismatch
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("tbl v0.4s, {v1.16b}, v2.4s"))        // dst must be 8b/16b
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("tbl v0.8b, {v1.16b, v3.16b}, v2.8b")) // non-consecutive table
    }

    func testVectorCompareZeroInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmgt v0.8b, v1.8b, #0"), 0x0e208820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmeq v0.8b, v1.8b, #0"), 0x0e209820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmlt v0.8b, v1.8b, #0"), 0x0e20a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmge v0.8b, v1.8b, #0"), 0x2e208820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmle v0.8b, v1.8b, #0"), 0x2e209820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmgt v0.4s, v1.4s, #0"), 0x4ea08820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmeq v0.2d, v1.2d, #0"), 0x4ee09820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmge v0.8h, v1.8h, #0"), 0x6e608820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmle v0.16b, v1.16b, #0"), 0x6e209820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmlt v0.2s, v1.2s, #0"), 0x0ea0a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmgt v0.4s, v1.4s, #0.0"), 0x4ea0c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmeq v0.4s, v1.4s, #0.0"), 0x4ea0d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmlt v0.4s, v1.4s, #0.0"), 0x4ea0e820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmge v0.4s, v1.4s, #0.0"), 0x6ea0c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmle v0.4s, v1.4s, #0.0"), 0x6ea0d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmgt v0.2d, v1.2d, #0.0"), 0x4ee0c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmeq v0.2s, v1.2s, #0.0"), 0x0ea0d820)
    }

    func testDisassembleVectorCompareZero() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e208820), "cmgt v0.8b, v1.8b, #0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e208820), "cmge v0.8b, v1.8b, #0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ee09820), "cmeq v0.2d, v1.2d, #0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ea0c820), "fcmgt v0.4s, v1.4s, #0.0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ea0d820), "fcmle v0.4s, v1.4s, #0.0")
    }

    func testVectorCompareZeroRoundTrip() throws {
        let sources = [
            "cmgt v0.8b, v1.8b, #0", "cmeq v2.16b, v3.16b, #0", "cmlt v4.4h, v5.4h, #0",
            "cmge v6.8h, v7.8h, #0", "cmle v8.2s, v9.2s, #0", "cmgt v10.4s, v11.4s, #0",
            "cmeq v12.2d, v13.2d, #0",
            "fcmgt v0.2s, v1.2s, #0.0", "fcmeq v2.4s, v3.4s, #0.0", "fcmlt v4.2d, v5.2d, #0.0",
            "fcmge v6.4s, v7.4s, #0.0", "fcmle v8.2d, v9.2d, #0.0",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorCompareZeroInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cmgt v0.8b, v1.16b, #0"))   // arrangement mismatch
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cmgt v0.1d, v1.1d, #0"))    // 1d is the scalar form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcmgt v0.8b, v1.8b, #0.0")) // FP needs 2s/4s/2d
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cmgt v0.8b, v1.8b, #1"))    // must compare against zero
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcmgt v0.4s, v1.4s, #0"))   // FP needs #0.0
    }

    func testVectorExtractNarrowInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("xtn v0.8b, v1.8h"), 0x0e212820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("xtn v0.4h, v1.4s"), 0x0e612820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("xtn v0.2s, v1.2d"), 0x0ea12820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("xtn2 v0.16b, v1.8h"), 0x4e212820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("xtn2 v0.8h, v1.4s"), 0x4e612820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("xtn2 v0.4s, v1.2d"), 0x4ea12820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtn v0.8b, v1.8h"), 0x0e214820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtn v0.4h, v1.4s"), 0x0e614820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtn v0.2s, v1.2d"), 0x0ea14820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtn2 v0.16b, v1.8h"), 0x4e214820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqxtn v0.8b, v1.8h"), 0x2e214820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqxtn v0.2s, v1.2d"), 0x2ea14820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uqxtn2 v0.8h, v1.4s"), 0x6e614820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtun v0.8b, v1.8h"), 0x2e212820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtun v0.4h, v1.4s"), 0x2e612820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sqxtun2 v0.4s, v1.2d"), 0x6ea12820)
    }

    func testDisassembleVectorExtractNarrow() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e212820), "xtn v0.8b, v1.8h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ea12820), "xtn2 v0.4s, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e214820), "sqxtn v0.8b, v1.8h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e214820), "uqxtn v0.8b, v1.8h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ea12820), "sqxtun2 v0.4s, v1.2d")
    }

    func testVectorExtractNarrowRoundTrip() throws {
        let sources = [
            "xtn v0.8b, v1.8h", "xtn v2.4h, v3.4s", "xtn v4.2s, v5.2d",
            "xtn2 v0.16b, v1.8h", "xtn2 v2.8h, v3.4s", "xtn2 v4.4s, v5.2d",
            "sqxtn v0.8b, v1.8h", "sqxtn2 v6.16b, v7.8h",
            "uqxtn v8.4h, v9.4s", "uqxtn2 v10.8h, v11.4s",
            "sqxtun v12.2s, v13.2d", "sqxtun2 v14.4s, v15.2d",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorExtractNarrowInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("xtn v0.8b, v1.4s"))    // source must be one size up (8h)
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("xtn v0.16b, v1.8h"))   // 16b dest needs the xtn2 mnemonic
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("xtn2 v0.8b, v1.8h"))   // xtn2 needs a 128-bit dest
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("xtn v0.1d, v1.2d"))    // no D destination
    }

    func testVectorConvertInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf v0.2s, v1.2s"), 0x0e21d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf v0.4s, v1.4s"), 0x4e21d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf v0.2d, v1.2d"), 0x4e61d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ucvtf v0.2s, v1.2s"), 0x2e21d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ucvtf v0.4s, v1.4s"), 0x6e21d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ucvtf v0.2d, v1.2d"), 0x6e61d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs v0.2s, v1.2s"), 0x0ea1b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs v0.4s, v1.4s"), 0x4ea1b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs v0.2d, v1.2d"), 0x4ee1b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzu v0.4s, v1.4s"), 0x6ea1b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtns v0.4s, v1.4s"), 0x4e21a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtnu v0.2d, v1.2d"), 0x6e61a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtms v0.4s, v1.4s"), 0x4e21b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtmu v0.2s, v1.2s"), 0x2e21b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtps v0.4s, v1.4s"), 0x4ea1a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtpu v0.2d, v1.2d"), 0x6ee1a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtas v0.4s, v1.4s"), 0x4e21c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtau v0.2s, v1.2s"), 0x2e21c820)
    }

    func testDisassembleVectorConvert() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e21d820), "scvtf v0.2s, v1.2s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e61d820), "scvtf v0.2d, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ee1b820), "fcvtzs v0.2d, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ea1a820), "fcvtps v0.4s, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e21c820), "fcvtau v0.2s, v1.2s")
    }

    func testVectorConvertRoundTrip() throws {
        let sources = [
            "scvtf v0.2s, v1.2s", "scvtf v2.4s, v3.4s", "scvtf v4.2d, v5.2d",
            "ucvtf v6.2s, v7.2s", "ucvtf v8.2d, v9.2d",
            "fcvtzs v10.4s, v11.4s", "fcvtzu v12.2d, v13.2d",
            "fcvtns v0.4s, v1.4s", "fcvtnu v2.2d, v3.2d", "fcvtms v4.2s, v5.2s",
            "fcvtmu v6.4s, v7.4s", "fcvtps v8.2d, v9.2d", "fcvtpu v10.4s, v11.4s",
            "fcvtas v12.2s, v13.2s", "fcvtau v14.2d, v15.2d",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorConvertInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf v0.8b, v1.8b"))   // integer arrangements not allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf v0.4h, v1.4h"))   // FP16 not supported here
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvtzs v0.2s, v1.4s"))  // arrangement mismatch
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf v0.1d, v1.1d"))   // 1d is the scalar form
    }

    func testVectorPairwiseLongAddInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddlp v0.4h, v1.8b"), 0x0e202820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddlp v0.8h, v1.16b"), 0x4e202820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddlp v0.2s, v1.4h"), 0x0e602820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddlp v0.4s, v1.8h"), 0x4e602820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddlp v0.1d, v1.2s"), 0x0ea02820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("saddlp v0.2d, v1.4s"), 0x4ea02820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uaddlp v0.4h, v1.8b"), 0x2e202820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uaddlp v0.8h, v1.16b"), 0x6e202820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uaddlp v0.2d, v1.4s"), 0x6ea02820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sadalp v0.4h, v1.8b"), 0x0e206820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sadalp v0.2d, v1.4s"), 0x4ea06820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uadalp v0.4h, v1.8b"), 0x2e206820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uadalp v0.8h, v1.16b"), 0x6e206820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uadalp v0.2d, v1.4s"), 0x6ea06820)
    }

    func testDisassembleVectorPairwiseLongAdd() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e202820), "saddlp v0.4h, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ea02820), "saddlp v0.2d, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e202820), "uaddlp v0.8h, v1.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e206820), "sadalp v0.4h, v1.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ea06820), "uadalp v0.2d, v1.4s")
    }

    func testVectorPairwiseLongAddRoundTrip() throws {
        let sources = [
            "saddlp v0.4h, v1.8b", "saddlp v2.8h, v3.16b", "saddlp v4.2s, v5.4h",
            "saddlp v6.4s, v7.8h", "saddlp v8.1d, v9.2s", "saddlp v10.2d, v11.4s",
            "uaddlp v12.4h, v13.8b", "uaddlp v14.8h, v15.16b", "uaddlp v16.2d, v17.4s",
            "sadalp v18.4h, v19.8b", "sadalp v20.2d, v21.4s",
            "uadalp v22.4h, v23.8b", "uadalp v24.8h, v25.16b", "uadalp v26.2d, v27.4s",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorPairwiseLongAddInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("saddlp v0.8b, v1.8b"))   // dest must be widened
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("saddlp v0.4h, v1.16b"))  // Q mismatch
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("saddlp v0.4h, v1.4s"))   // source element-size mismatch
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("saddlp v0.1d, v1.1d"))   // source cannot be a D arrangement
    }

    func testVectorRoundReciprocalInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintn v0.2s, v1.2s"), 0x0e218820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintn v0.4s, v1.4s"), 0x4e218820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintn v0.2d, v1.2d"), 0x4e618820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintm v0.4s, v1.4s"), 0x4e219820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintp v0.2s, v1.2s"), 0x0ea18820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintz v0.4s, v1.4s"), 0x4ea19820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frinta v0.2d, v1.2d"), 0x6e618820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintx v0.4s, v1.4s"), 0x6e219820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frinti v0.2d, v1.2d"), 0x6ee19820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecpe v0.2s, v1.2s"), 0x0ea1d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecpe v0.4s, v1.4s"), 0x4ea1d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecpe v0.2d, v1.2d"), 0x4ee1d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frsqrte v0.4s, v1.4s"), 0x6ea1d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frsqrte v0.2d, v1.2d"), 0x6ee1d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("urecpe v0.2s, v1.2s"), 0x0ea1c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("urecpe v0.4s, v1.4s"), 0x4ea1c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ursqrte v0.4s, v1.4s"), 0x6ea1c820)
    }

    func testDisassembleVectorRoundReciprocal() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e618820), "frintn v0.2d, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0ea18820), "frintp v0.2s, v1.2s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ee19820), "frinti v0.2d, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ee1d820), "frecpe v0.2d, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ea1d820), "frsqrte v0.4s, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0ea1c820), "urecpe v0.2s, v1.2s")
    }

    func testVectorRoundReciprocalRoundTrip() throws {
        let sources = [
            "frintn v0.2s, v1.2s", "frintn v2.2d, v3.2d", "frintm v4.4s, v5.4s",
            "frintp v6.2s, v7.2s", "frintz v8.4s, v9.4s", "frinta v10.2d, v11.2d",
            "frintx v12.4s, v13.4s", "frinti v14.2d, v15.2d",
            "frecpe v16.2s, v17.2s", "frecpe v18.2d, v19.2d", "frsqrte v20.4s, v21.4s",
            "frsqrte v22.2d, v23.2d", "urecpe v24.2s, v25.2s", "urecpe v26.4s, v27.4s",
            "ursqrte v28.2s, v29.2s", "ursqrte v30.4s, v31.4s",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorRoundReciprocalInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("frintn v0.8b, v1.8b"))   // integer arrangement
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("urecpe v0.2d, v1.2d"))   // urecpe has no double form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ursqrte v0.2d, v1.2d"))  // ursqrte has no double form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("frecpe v0.2s, v1.4s"))   // arrangement mismatch
    }

    func testVectorFPConvertPrecisionInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtn v0.4h, v1.4s"), 0x0e216820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtn2 v0.8h, v1.4s"), 0x4e216820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtn v0.2s, v1.2d"), 0x0e616820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtn2 v0.4s, v1.2d"), 0x4e616820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtl v0.4s, v1.4h"), 0x0e217820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtl2 v0.4s, v1.8h"), 0x4e217820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtl v0.2d, v1.2s"), 0x0e617820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtl2 v0.2d, v1.4s"), 0x4e617820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtxn v0.2s, v1.2d"), 0x2e616820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtxn2 v0.4s, v1.2d"), 0x6e616820)
    }

    func testDisassembleVectorFPConvertPrecision() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e216820), "fcvtn v0.4h, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e616820), "fcvtn2 v0.4s, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e217820), "fcvtl v0.4s, v1.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e617820), "fcvtl2 v0.2d, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e616820), "fcvtxn v0.2s, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e616820), "fcvtxn2 v0.4s, v1.2d")
    }

    func testVectorFPConvertPrecisionRoundTrip() throws {
        let sources = [
            "fcvtn v0.4h, v1.4s", "fcvtn2 v2.8h, v3.4s", "fcvtn v4.2s, v5.2d", "fcvtn2 v6.4s, v7.2d",
            "fcvtl v8.4s, v9.4h", "fcvtl2 v10.4s, v11.8h", "fcvtl v12.2d, v13.2s", "fcvtl2 v14.2d, v15.4s",
            "fcvtxn v16.2s, v17.2d", "fcvtxn2 v18.4s, v19.2d",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorFPConvertPrecisionInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvtn v0.8h, v1.4s"))    // plain form needs 64-bit dest
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvtn2 v0.4h, v1.4s"))   // 2 form needs 128-bit dest
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvtl v0.2d, v1.4s"))    // wrong source for sz=1 plain
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvtxn v0.2s, v1.4s"))   // fcvtxn source must be 2d
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvtn v0.4h, v1.8h"))    // source must be FP
    }

    func testCryptoAESInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("aese v0.16b, v1.16b"), 0x4e284820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("aesd v0.16b, v1.16b"), 0x4e285820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("aesmc v0.16b, v1.16b"), 0x4e286820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("aesimc v0.16b, v1.16b"), 0x4e287820)
    }

    func testDisassembleCryptoAES() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e284820), "aese v0.16b, v1.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e285820), "aesd v0.16b, v1.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e286820), "aesmc v0.16b, v1.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e287820), "aesimc v0.16b, v1.16b")
        // The neighbouring two-register-misc cls form must still decode correctly.
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e204820), "cls v0.16b, v1.16b")
    }

    func testCryptoAESRoundTrip() throws {
        let sources = [
            "aese v0.16b, v1.16b", "aesd v2.16b, v3.16b",
            "aesmc v4.16b, v5.16b", "aesimc v6.16b, v7.16b",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testCryptoAESInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("aese v0.8b, v1.8b"))    // must be 16b
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("aese v0.4s, v1.4s"))    // must be 16b
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("aese v0.16b, v1.8b"))   // both must be 16b
    }

    func testCryptoSHAInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha1c q0, s1, v2.4s"), 0x5e020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha1p q0, s1, v2.4s"), 0x5e021020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha1m q0, s1, v2.4s"), 0x5e022020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha1su0 v0.4s, v1.4s, v2.4s"), 0x5e023020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha256h q0, q1, v2.4s"), 0x5e024020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha256h2 q0, q1, v2.4s"), 0x5e025020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha256su1 v0.4s, v1.4s, v2.4s"), 0x5e026020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha1h s0, s1"), 0x5e280820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha1su1 v0.4s, v1.4s"), 0x5e281820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha256su0 v0.4s, v1.4s"), 0x5e282820)
    }

    func testDisassembleCryptoSHA() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e020020), "sha1c q0, s1, v2.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e023020), "sha1su0 v0.4s, v1.4s, v2.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e024020), "sha256h q0, q1, v2.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e026020), "sha256su1 v0.4s, v1.4s, v2.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e280820), "sha1h s0, s1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e282820), "sha256su0 v0.4s, v1.4s")
    }

    func testCryptoSHARoundTrip() throws {
        let sources = [
            "sha1c q0, s1, v2.4s", "sha1p q3, s4, v5.4s", "sha1m q6, s7, v8.4s",
            "sha1su0 v9.4s, v10.4s, v11.4s", "sha256h q12, q13, v14.4s",
            "sha256h2 q15, q16, v17.4s", "sha256su1 v18.4s, v19.4s, v20.4s",
            "sha1h s21, s22", "sha1su1 v23.4s, v24.4s", "sha256su0 v25.4s, v26.4s",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testCryptoSHAInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sha1c v0.4s, s1, v2.4s"))  // dest must be Q
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sha1c q0, q1, v2.4s"))     // first must be S
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sha256h q0, q1, v2.2d"))   // third must be .4s
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sha1h q0, s1"))            // sha1h dest must be S
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sha1su1 v0.2s, v1.2s"))    // must be .4s
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
