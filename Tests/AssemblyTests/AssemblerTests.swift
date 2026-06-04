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

    func testMultiplyWideInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("smulh x0, x1, x2"), 0x9b427c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umulh x3, x4, x5"), 0x9bc57c83)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smull x6, w7, w8"), 0x9b287ce6)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umull x9, w10, w11"), 0x9bab7d49)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smaddl x12, w13, w14, x15"), 0x9b2e3dac)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umaddl x16, w17, w18, x19"), 0x9bb24e30)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smsubl x20, w21, w22, x23"), 0x9b36deb4)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umsubl x24, w25, w26, x27"), 0x9bbaef38)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smnegl x0, w1, w2"), 0x9b22fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("umnegl x3, w4, w5"), 0x9ba5fc83)
    }

    func testDisassembleMultiplyWide() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9b427c20), "smulh x0, x1, x2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9bab7d49), "umull x9, w10, w11")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9b2e3dac), "smaddl x12, w13, w14, x15")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9b36deb4), "smsubl x20, w21, w22, x23")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9b22fc20), "smnegl x0, w1, w2")
    }

    func testMultiplyWideRoundTrip() throws {
        for source in [
            "smulh x0, x1, x2", "umulh x3, x4, x5", "smull x6, w7, w8",
            "umull x9, w10, w11", "smaddl x12, w13, w14, x15", "umaddl x16, w17, w18, x19",
            "smsubl x20, w21, w22, x23", "umsubl x24, w25, w26, x27",
            "smnegl x0, w1, w2", "umnegl x3, w4, w5",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testMultiplyWideInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("smull w0, w1, w2"))     // dest must be 64-bit
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("smull x0, x1, x2"))     // long form takes 32-bit sources
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("smulh x0, w1, w2"))     // high form takes 64-bit sources
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("smaddl x0, w1, w2"))    // missing accumulator
    }

    func testCRC32Instructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("crc32b w0, w1, w2"), 0x1ac24020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("crc32h w3, w4, w5"), 0x1ac54483)
        XCTAssertEqual(try ARM64Assembler.assembleWord("crc32w w6, w7, w8"), 0x1ac848e6)
        XCTAssertEqual(try ARM64Assembler.assembleWord("crc32x w9, w10, x11"), 0x9acb4d49)
        XCTAssertEqual(try ARM64Assembler.assembleWord("crc32cb w12, w13, w14"), 0x1ace51ac)
        XCTAssertEqual(try ARM64Assembler.assembleWord("crc32ch w15, w16, w17"), 0x1ad1560f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("crc32cw w18, w19, w20"), 0x1ad45a72)
        XCTAssertEqual(try ARM64Assembler.assembleWord("crc32cx w21, w22, x23"), 0x9ad75ed5)
    }

    func testDisassembleCRC32() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1ac24020), "crc32b w0, w1, w2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9acb4d49), "crc32x w9, w10, x11")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1ace51ac), "crc32cb w12, w13, w14")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9ad75ed5), "crc32cx w21, w22, x23")
    }

    func testCRC32RoundTrip() throws {
        for source in [
            "crc32b w0, w1, w2", "crc32h w3, w4, w5", "crc32w w6, w7, w8",
            "crc32x w9, w10, x11", "crc32cb w12, w13, w14", "crc32ch w15, w16, w17",
            "crc32cw w18, w19, w20", "crc32cx w21, w22, x23",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testCRC32InvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("crc32b x0, w1, w2"))   // dest must be 32-bit
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("crc32b w0, w1, x2"))   // b variant takes w source
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("crc32x w0, w1, w2"))   // x variant needs x source
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("crc32b w0, w1"))       // missing operand
    }

    func testDataProcessingOneSourceInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("rbit w0, w1"), 0x5ac00020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rbit x2, x3"), 0xdac00062)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rev16 w4, w5"), 0x5ac004a4)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rev16 x6, x7"), 0xdac004e6)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rev32 x8, x9"), 0xdac00928)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rev w10, w11"), 0x5ac0096a)
        XCTAssertEqual(try ARM64Assembler.assembleWord("rev x12, x13"), 0xdac00dac)
        XCTAssertEqual(try ARM64Assembler.assembleWord("clz w14, w15"), 0x5ac011ee)
        XCTAssertEqual(try ARM64Assembler.assembleWord("clz x16, x17"), 0xdac01230)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cls w18, w19"), 0x5ac01672)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cls x20, x21"), 0xdac016b4)
    }

    func testDisassembleDataProcessingOneSource() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ac00020), "rbit w0, w1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ac004a4), "rev16 w4, w5")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xdac00928), "rev32 x8, x9")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ac0096a), "rev w10, w11")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xdac00dac), "rev x12, x13")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ac011ee), "clz w14, w15")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xdac016b4), "cls x20, x21")
    }

    func testDataProcessingOneSourceRoundTrip() throws {
        for source in [
            "rbit w0, w1", "rbit x2, x3", "rev16 w4, w5", "rev16 x6, x7",
            "rev32 x8, x9", "rev w10, w11", "rev x12, x13", "clz w14, w15",
            "clz x16, x17", "cls w18, w19", "cls x20, x21",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testDataProcessingOneSourceInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("rev32 w0, w1"))   // rev32 is 64-bit only
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("rbit w0, x1"))    // mismatched widths
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("clz w0"))         // missing source
    }

    func testHintInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("yield"), 0xd503203f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("wfe"), 0xd503205f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("wfi"), 0xd503207f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sev"), 0xd503209f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sevl"), 0xd50320bf)
        XCTAssertEqual(try ARM64Assembler.assembleWord("esb"), 0xd503221f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csdb"), 0xd503229f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("hint #6"), 0xd50320df)
        XCTAssertEqual(try ARM64Assembler.assembleWord("hint #11"), 0xd503217f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("hint #127"), 0xd5032fff)
    }

    func testDisassembleHint() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd503203f), "yield")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd503221f), "esb")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd503229f), "csdb")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd50320df), "hint #6")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5032fff), "hint #127")
        // nop (#0) and the paciasp-family hints are not misdecoded as plain hints.
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd503201f), "nop")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd503233f), "paciasp")
    }

    func testHintRoundTrip() throws {
        for source in [
            "yield", "wfe", "wfi", "sev", "sevl", "esb", "csdb",
            "hint #6", "hint #7", "hint #11", "hint #127",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testHintInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("hint #128"))  // immediate out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("hint"))       // missing immediate
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("yield x0"))   // takes no operands
    }

    func testLoadStoreExclusiveInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldxr w0, [x1]"), 0x885f7c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldxr x0, [x1]"), 0xc85f7c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldxrb w0, [x1]"), 0x085f7c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldxrh w0, [x1]"), 0x485f7c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stxr w2, w0, [x1]"), 0x88027c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stxr w2, x0, [x1]"), 0xc8027c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stxrb w2, w0, [x1]"), 0x08027c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stxrh w2, w0, [x1]"), 0x48027c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaxr w0, [x1]"), 0x885ffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaxr x0, [x1]"), 0xc85ffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaxrb w0, [x1]"), 0x085ffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaxrh w0, [x1]"), 0x485ffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stlxr w2, w0, [x1]"), 0x8802fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stlxr w2, x0, [x1]"), 0xc802fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stlxrb w2, w0, [x1]"), 0x0802fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stlxrh w2, w0, [x1]"), 0x4802fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldar w0, [x1]"), 0x88dffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldar x0, [x1]"), 0xc8dffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldarb w0, [x1]"), 0x08dffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldarh w0, [x1]"), 0x48dffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stlr w0, [x1]"), 0x889ffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stlr x0, [x1]"), 0xc89ffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stlrb w0, [x1]"), 0x089ffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stlrh w0, [x1]"), 0x489ffc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldxp w0, w1, [x2]"), 0x887f0440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldxp x0, x1, [x2]"), 0xc87f0440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stxp w4, w0, w1, [x2]"), 0x88240440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stxp w4, x0, x1, [x2]"), 0xc8240440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaxp w0, w1, [x2]"), 0x887f8440)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stlxp w4, w0, w1, [x2]"), 0x88248440)
    }

    func testDisassembleLoadStoreExclusive() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x885f7c20), "ldxr w0, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xc85f7c20), "ldxr x0, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x08027c20), "stxrb w2, w0, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x88dffc20), "ldar w0, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x889ffc20), "stlr w0, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xc87f0440), "ldxp x0, x1, [x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x88248440), "stlxp w4, w0, w1, [x2]")
    }

    func testLoadStoreExclusiveRoundTrip() throws {
        for source in [
            "ldxr w0, [x1]", "ldxr x0, [x1]", "ldxrb w0, [x1]", "ldxrh w0, [x1]",
            "stxr w2, w0, [x1]", "stxr w2, x0, [x1]", "stxrb w2, w0, [x1]", "stxrh w2, w0, [x1]",
            "ldaxr w0, [x1]", "ldaxr x0, [x1]", "ldaxrb w0, [x1]", "ldaxrh w0, [x1]",
            "stlxr w2, w0, [x1]", "stlxr w2, x0, [x1]", "stlxrb w2, w0, [x1]", "stlxrh w2, w0, [x1]",
            "ldar w0, [x1]", "ldar x0, [x1]", "ldarb w0, [x1]", "ldarh w0, [x1]",
            "stlr w0, [x1]", "stlr x0, [x1]", "stlrb w0, [x1]", "stlrh w0, [x1]",
            "ldxp w0, w1, [x2]", "ldxp x0, x1, [x2]", "stxp w4, w0, w1, [x2]", "stxp w4, x0, x1, [x2]",
            "ldaxp w0, w1, [x2]", "stlxp w4, w0, w1, [x2]",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testLoadStoreExclusiveInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldxrb x0, [x1]"))      // byte form requires W
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("stxr x2, w0, [x1]"))   // status is always W
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldxr w0, [x1, #8]"))   // no offset allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldxr w0, w1"))         // base must be a memory operand
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldxp w0, x1, [x2]"))   // mismatched pair widths
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("stxr w2, w0, w1, [x1]")) // too many operands
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldxr w0, w1, [x1]"))   // single form takes one value
    }

    func testCompareAndSwapInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("cas w0, w1, [x2]"), 0x88a07c41)
        XCTAssertEqual(try ARM64Assembler.assembleWord("casa w0, w1, [x2]"), 0x88e07c41)
        XCTAssertEqual(try ARM64Assembler.assembleWord("casl w0, w1, [x2]"), 0x88a0fc41)
        XCTAssertEqual(try ARM64Assembler.assembleWord("casal w0, w1, [x2]"), 0x88e0fc41)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cas x0, x1, [x2]"), 0xc8a07c41)
        XCTAssertEqual(try ARM64Assembler.assembleWord("casal x0, x1, [x2]"), 0xc8e0fc41)
        XCTAssertEqual(try ARM64Assembler.assembleWord("casb w0, w1, [x2]"), 0x08a07c41)
        XCTAssertEqual(try ARM64Assembler.assembleWord("casalb w0, w1, [x2]"), 0x08e0fc41)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cash w0, w1, [x2]"), 0x48a07c41)
        XCTAssertEqual(try ARM64Assembler.assembleWord("casalh w0, w1, [x2]"), 0x48e0fc41)
        XCTAssertEqual(try ARM64Assembler.assembleWord("casp w0, w1, w2, w3, [x4]"), 0x08207c82)
        XCTAssertEqual(try ARM64Assembler.assembleWord("caspa w0, w1, w2, w3, [x4]"), 0x08607c82)
        XCTAssertEqual(try ARM64Assembler.assembleWord("caspl w0, w1, w2, w3, [x4]"), 0x0820fc82)
        XCTAssertEqual(try ARM64Assembler.assembleWord("caspal w0, w1, w2, w3, [x4]"), 0x0860fc82)
        XCTAssertEqual(try ARM64Assembler.assembleWord("casp x0, x1, x2, x3, [x4]"), 0x48207c82)
        XCTAssertEqual(try ARM64Assembler.assembleWord("caspal x0, x1, x2, x3, [x4]"), 0x4860fc82)
    }

    func testDisassembleCompareAndSwap() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x88a07c41), "cas w0, w1, [x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xc8e0fc41), "casal x0, x1, [x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x08a07c41), "casb w0, w1, [x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x48e0fc41), "casalh w0, w1, [x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x08207c82), "casp w0, w1, w2, w3, [x4]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4860fc82), "caspal x0, x1, x2, x3, [x4]")
        // The exclusive pair forms must still decode (no collision with CAS).
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x887f0440), "ldxp w0, w1, [x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xc87f0440), "ldxp x0, x1, [x2]")
    }

    func testCompareAndSwapRoundTrip() throws {
        for source in [
            "cas w0, w1, [x2]", "casa w0, w1, [x2]", "casl w0, w1, [x2]", "casal w0, w1, [x2]",
            "cas x0, x1, [x2]", "casa x0, x1, [x2]", "casl x0, x1, [x2]", "casal x0, x1, [x2]",
            "casb w0, w1, [x2]", "casab w0, w1, [x2]", "caslb w0, w1, [x2]", "casalb w0, w1, [x2]",
            "cash w0, w1, [x2]", "casah w0, w1, [x2]", "caslh w0, w1, [x2]", "casalh w0, w1, [x2]",
            "casp w0, w1, w2, w3, [x4]", "caspa w0, w1, w2, w3, [x4]",
            "caspl w0, w1, w2, w3, [x4]", "caspal w0, w1, w2, w3, [x4]",
            "casp x0, x1, x2, x3, [x4]", "caspal x0, x1, x2, x3, [x4]",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testCompareAndSwapInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("casb x0, x1, [x2]"))     // byte form requires W
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cas w0, x1, [x2]"))      // mismatched widths
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cas w0, w1, [x2, #8]"))  // no offset allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("casp w1, w2, w3, w4, [x5]"))  // pair must start even
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("casp w0, w2, w4, w5, [x6]"))  // pair must be consecutive
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("casp w0, w1, x2, x3, [x4]"))  // pair widths must match
    }

    func testPrefetchInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm pldl1keep, [x0]"), 0xf9800000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm pldl1keep, [x0, #8]"), 0xf9800400)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm pldl1strm, [x0, #16]"), 0xf9800801)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm pldl2keep, [x0]"), 0xf9800002)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm pldl3keep, [x0]"), 0xf9800004)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm plil1keep, [x0]"), 0xf9800008)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm pstl1keep, [x0]"), 0xf9800010)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm pstl3strm, [x0, #4088]"), 0xf987fc15)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm #5, [x0]"), 0xf9800005)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm pldl1keep, [x0, x1]"), 0xf8a16800)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm pldl1keep, [x0, x1, lsl #3]"), 0xf8a17800)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfm pldl1keep, [x0, w1, uxtw #3]"), 0xf8a15800)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfum pldl1keep, [x0]"), 0xf8800000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("prfum pldl1keep, [x0, #-4]"), 0xf89fc000)
    }

    func testDisassemblePrefetch() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf9800000), "prfm pldl1keep, [x0]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf987fc15), "prfm pstl3strm, [x0, #4088]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf8a17800), "prfm pldl1keep, [x0, x1, lsl #3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf89fc000), "prfum pldl1keep, [x0, #-4]")
        // A numeric prefetch operation decodes to its canonical name.
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf9800005), "prfm pldl3strm, [x0]")
    }

    func testPrefetchRoundTrip() throws {
        var sources: [String] = []
        for type in ["pld", "pli", "pst"] {
            for target in ["l1", "l2", "l3"] {
                for policy in ["keep", "strm"] {
                    sources.append("prfm \(type)\(target)\(policy), [x0, #16]")
                    sources.append("prfum \(type)\(target)\(policy), [x1, #-8]")
                }
            }
        }
        sources.append(contentsOf: [
            "prfm pldl1keep, [x0]", "prfm pldl1keep, [x0, x1]",
            "prfm pldl1keep, [x0, x1, lsl #3]", "prfm pldl1keep, [x0, w1, uxtw #3]",
        ])
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testPrefetchInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("prfm pldl1keep, [x0, #7]"))   // offset not a multiple of 8
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("prfm pldl1keep, [x0, #-8]"))  // scaled form is unsigned
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("prfm bogus, [x0]"))           // unknown prefetch op
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("prfm #32, [x0]"))             // op out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("prfum pldl1keep, [x0, x1]"))  // unscaled has no register form
    }

    func testSystemRegisterMoveInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("mrs x0, nzcv"), 0xd53b4200)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr nzcv, x0"), 0xd51b4200)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mrs x1, fpcr"), 0xd53b4401)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr fpcr, x1"), 0xd51b4401)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mrs x2, fpsr"), 0xd53b4422)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mrs x3, tpidr_el0"), 0xd53bd043)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mrs x4, midr_el1"), 0xd5380004)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mrs x0, daif"), 0xd53b4220)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mrs x0, sp_el0"), 0xd5384100)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mrs x0, cntvct_el0"), 0xd53be040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("mrs x0, pmccntr_el0"), 0xd53b9d00)
        // Generic S<op0>_<op1>_C<n>_C<m>_<op2> form.
        XCTAssertEqual(try ARM64Assembler.assembleWord("mrs x0, s3_3_c13_c2_1"), 0xd53bd220)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr s3_3_c13_c2_1, x5"), 0xd51bd225)
    }

    func testDisassembleSystemRegisterMove() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd53b4200), "mrs x0, nzcv")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd51b4200), "msr nzcv, x0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5380004), "mrs x4, midr_el1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd53bd220), "mrs x0, s3_3_c13_c2_1")
    }

    func testSystemRegisterMoveRoundTrip() throws {
        let names = [
            "nzcv", "daif", "fpcr", "fpsr", "tpidr_el0", "tpidrro_el0", "tpidr_el1",
            "midr_el1", "mpidr_el1", "ctr_el0", "dczid_el0", "sp_el0", "elr_el1",
            "spsr_el1", "vbar_el1", "ttbr0_el1", "ttbr1_el1", "sctlr_el1", "esr_el1",
            "far_el1", "cntvct_el0", "cntfrq_el0", "pmccntr_el0", "s3_3_c13_c2_1",
        ]
        var sources: [String] = []
        for name in names {
            sources.append("mrs x7, \(name)")
            sources.append("msr \(name), x9")
        }
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testSystemRegisterMoveInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("mrs w0, nzcv"))      // must be 64-bit
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("mrs x0, bogus"))     // unknown register name
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("mrs x0, s9_3_c4_c2_0")) // op0 out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("mrs x0"))            // missing operand
    }

    func testPStateImmediateInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr spsel, #1"), 0xd50041bf)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr daifset, #2"), 0xd50342df)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr daifclr, #15"), 0xd5034fff)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr uao, #1"), 0xd500417f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr pan, #1"), 0xd500419f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr dit, #1"), 0xd503415f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr ssbs, #1"), 0xd503413f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("msr daifset, #0"), 0xd50340df)
    }

    func testDisassemblePStateImmediate() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd50041bf), "msr spsel, #1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd50342df), "msr daifset, #2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5034fff), "msr daifclr, #15")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd503413f), "msr ssbs, #1")
    }

    func testPStateImmediateRoundTrip() throws {
        for field in ["spsel", "daifset", "daifclr", "uao", "pan", "dit", "ssbs"] {
            for imm in [0, 1, 2, 7, 15] {
                let source = "msr \(field), #\(imm)"
                let word = try ARM64Assembler.assembleWord(source)
                let text = try ARM64Assembler.disassembleWord(word)
                XCTAssertEqual(text, source, "round trip failed for \(source)")
                XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
            }
        }
    }

    func testPStateImmediateInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("msr daifset, #16"))  // immediate out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("msr spsel, x0"))     // requires an immediate
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("msr daifset"))       // missing operand
    }

    func testSystemInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("dc civac, x0"), 0xd50b7e20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dc cvac, x1"), 0xd50b7a21)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dc zva, x3"), 0xd50b7423)
        XCTAssertEqual(try ARM64Assembler.assembleWord("dc isw, x0"), 0xd5087640)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ic ialluis"), 0xd508711f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ic ivau, x4"), 0xd50b7524)
        XCTAssertEqual(try ARM64Assembler.assembleWord("at s1e1r, x5"), 0xd5087805)
        XCTAssertEqual(try ARM64Assembler.assembleWord("tlbi vmalle1"), 0xd508871f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("tlbi vae1, x6"), 0xd5088726)
        XCTAssertEqual(try ARM64Assembler.assembleWord("tlbi vale1is, x0"), 0xd50883a0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sys #0, c7, c5, #0, x0"), 0xd5087500)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sysl x7, #0, c7, c5, #0"), 0xd5287507)
    }

    func testDisassembleSystemInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd50b7e20), "dc civac, x0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd508711f), "ic ialluis")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5087805), "at s1e1r, x5")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5088726), "tlbi vae1, x6")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5287507), "sysl x7, #0, c7, c5, #0")
        // A SYS whose fields match a known alias canonicalizes to that alias.
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd508751f), "ic iallu")
        // A SYS without a matching alias keeps the generic form.
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5087500), "sys #0, c7, c5, #0, x0")
    }

    func testSystemInstructionRoundTrip() throws {
        var sources: [String] = []
        for alias in ["dc ivac", "dc isw", "dc csw", "dc cisw", "dc zva", "dc cvac",
                      "dc cvau", "dc cvap", "dc civac", "ic ivau", "at s1e1r", "at s1e1w",
                      "at s1e0r", "at s1e0w", "tlbi vae1", "tlbi aside1", "tlbi vaae1",
                      "tlbi vale1", "tlbi vaale1", "tlbi vae1is", "tlbi aside1is",
                      "tlbi vaae1is", "tlbi vale1is", "tlbi vaale1is"] {
            sources.append("\(alias), x2")
        }
        sources.append(contentsOf: ["ic ialluis", "ic iallu", "tlbi vmalle1", "tlbi vmalle1is"])
        sources.append(contentsOf: ["sys #1, c7, c5, #0, x4", "sysl x5, #0, c2, c0, #3"])
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testSystemInstructionInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dc bogus, x0"))     // unknown DC op
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("dc civac"))         // requires a register
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("at s1e1r, w0"))     // register must be 64-bit
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sys #8, c7, c5, #0")) // op1 out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sys #0, x7, c5, #0")) // CRn must be c<n>
    }

    func testLoadAcquireRCpcAndClearExclusiveInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaprb w0, [x1]"), 0x38bfc020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaprh w0, [x1]"), 0x78bfc020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldapr w0, [x1]"), 0xb8bfc020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldapr x0, [x1]"), 0xf8bfc020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("clrex"), 0xd5033f5f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("clrex #15"), 0xd5033f5f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("clrex #0"), 0xd503305f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("clrex #5"), 0xd503355f)
    }

    func testDisassembleLoadAcquireRCpcAndClearExclusive() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x38bfc020), "ldaprb w0, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf8bfc020), "ldapr x0, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd5033f5f), "clrex")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xd503305f), "clrex #0")
    }

    func testLoadAcquireRCpcAndClearExclusiveRoundTrip() throws {
        for source in [
            "ldaprb w0, [x1]", "ldaprh w0, [x1]", "ldapr w0, [x1]", "ldapr x0, [x1]",
            "clrex", "clrex #0", "clrex #5", "clrex #14",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testLoadAcquireRCpcAndClearExclusiveInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldaprb x0, [x1]"))     // byte form requires W
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldapr w0, [x1, #8]"))  // no offset allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldapr w0, w1"))        // base must be a memory operand
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("clrex #16"))           // immediate out of range
    }

    func testAtomicMemoryInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldadd w1, w0, [x2]"), 0xb8210040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldadda w1, w0, [x2]"), 0xb8a10040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaddl w1, w0, [x2]"), 0xb8610040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaddal w1, w0, [x2]"), 0xb8e10040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldadd x1, x0, [x2]"), 0xf8210040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaddb w1, w0, [x2]"), 0x38210040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaddh w1, w0, [x2]"), 0x78210040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldaddalb w1, w0, [x2]"), 0x38e10040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldclr w1, w0, [x2]"), 0xb8211040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldeor w1, w0, [x2]"), 0xb8212040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldset w1, w0, [x2]"), 0xb8213040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldsmax w1, w0, [x2]"), 0xb8214040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldsmin w1, w0, [x2]"), 0xb8215040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldumax w1, w0, [x2]"), 0xb8216040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldumin w1, w0, [x2]"), 0xb8217040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("swp w1, w0, [x2]"), 0xb8218040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("swpal w1, w0, [x2]"), 0xb8e18040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("swp x1, x0, [x2]"), 0xf8218040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("swpb w1, w0, [x2]"), 0x38218040)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stadd w1, [x2]"), 0xb821005f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("staddl w1, [x2]"), 0xb861005f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("staddlb w1, [x2]"), 0x3861005f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("stumin w1, [x2]"), 0xb821705f)
        // The ST<op> aliases share an encoding with the LD<op> form whose result is wzr.
        XCTAssertEqual(try ARM64Assembler.assembleWord("ldadd w1, wzr, [x2]"), 0xb821005f)
    }

    func testDisassembleAtomicMemory() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xb8210040), "ldadd w1, w0, [x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf8e10040), "ldaddal x1, x0, [x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xb8218040), "swp w1, w0, [x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x78218040), "swph w1, w0, [x2]")
        // Result-discarded non-acquire forms prefer the ST<op> alias.
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xb821005f), "stadd w1, [x2]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xb861005f), "staddl w1, [x2]")
        // Acquire forms have no store alias, so the wzr destination stays explicit.
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xb8a1005f), "ldadda w1, wzr, [x2]")
    }

    func testAtomicMemoryRoundTrip() throws {
        var sources: [String] = []
        for op in ["add", "clr", "eor", "set", "smax", "smin", "umax", "umin"] {
            for order in ["", "a", "l", "al"] {
                for size in ["", "b", "h"] {
                    sources.append("ld\(op)\(order)\(size) w1, w0, [x2]")
                }
            }
            for order in ["", "l"] {
                for size in ["", "b", "h"] {
                    sources.append("st\(op)\(order)\(size) w1, [x2]")
                }
            }
        }
        for order in ["", "a", "l", "al"] {
            for size in ["", "b", "h"] {
                sources.append("swp\(order)\(size) w1, w0, [x2]")
            }
        }
        sources.append(contentsOf: ["ldadd x1, x0, [x2]", "swpal x1, x0, [x2]", "stadd x1, [x2]"])
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testAtomicMemoryInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldaddb x1, x0, [x2]"))  // byte form requires W
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldadd w1, x0, [x2]"))   // mismatched widths
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldadd w1, w0, [x2, #8]"))  // no offset allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("stadd w1, w0, [x2]"))   // store alias takes no result
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ldadd w1, [x2]"))       // load form needs a result
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("swpa w1, [x2]"))        // swp has no store alias
    }

    func testLoadStoreRegisterStillDecodesAfterAtomics() throws {
        // The atomic group shares the 0x38 space with load/store register; ensure
        // the ordinary forms still round-trip.
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xb9400020), "ldr w0, [x1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xf8616820), "ldr x0, [x1, x1]")
    }

    func testAddSubExtendedRegisterInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("add w0, w1, w2, uxtb"), 0x0b220020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add w0, w1, w2, uxth"), 0x0b222020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add w0, w1, w2, uxtw"), 0x0b224020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add w0, w1, w2, sxtb"), 0x0b228020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add w0, w1, w2, sxth"), 0x0b22a020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add w0, w1, w2, sxtw"), 0x0b22c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add w0, w1, w2, uxtb #2"), 0x0b220820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add x0, x1, w2, uxtw"), 0x8b224020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add x0, x1, x2, uxtx"), 0x8b226020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add x0, x1, x2, sxtx"), 0x8b22e020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add x0, x1, w2, sxtw #3"), 0x8b22cc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("adds w5, w6, w7, uxtb"), 0x2b2700c5)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sub x8, x9, w10, uxth #1"), 0xcb2a2528)
        XCTAssertEqual(try ARM64Assembler.assembleWord("subs w11, w12, w13, sxtb"), 0x6b2d818b)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add sp, x1, x2, uxtx"), 0x8b22603f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("add x0, sp, x2"), 0x8b2263e0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmp x1, x2, sxtx"), 0xeb22e03f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cmn w3, w4, uxtb"), 0x2b24007f)
    }

    func testDisassembleAddSubExtendedRegister() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0b220020), "add w0, w1, w2, uxtb")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0b220820), "add w0, w1, w2, uxtb #2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x8b226020), "add x0, x1, x2, uxtx")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x8b2263e0), "add x0, sp, x2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xeb22e03f), "cmp x1, x2, sxtx")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2b24007f), "cmn w3, w4, uxtb")
    }

    func testAddSubExtendedRegisterRoundTrip() throws {
        for source in [
            "add w0, w1, w2, uxtb", "add w0, w1, w2, uxth", "add w0, w1, w2, uxtw",
            "add w0, w1, w2, sxtb", "add w0, w1, w2, sxth", "add w0, w1, w2, sxtw",
            "add w0, w1, w2, uxtb #2", "add x0, x1, w2, uxtw", "add x0, x1, x2, uxtx",
            "add x0, x1, x2, sxtx", "add x0, x1, w2, sxtw #3", "adds w5, w6, w7, uxtb",
            "sub x8, x9, w10, uxth #1", "subs w11, w12, w13, sxtb",
            "add x0, sp, x2", "cmp x1, x2, sxtx", "cmn w3, w4, uxtb",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testAddSubExtendedRegisterInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("add x0, x1, x2, uxtw"))   // uxtw needs a 32-bit source
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("add x0, x1, w2, uxtx"))   // uxtx needs a 64-bit source
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("add w0, w1, w2, uxtb #5")) // shift amount out of range
    }

    func testAddSubCarryInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("adc w0, w1, w2"), 0x1a020020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("adc x3, x4, x5"), 0x9a050083)
        XCTAssertEqual(try ARM64Assembler.assembleWord("adcs w6, w7, w8"), 0x3a0800e6)
        XCTAssertEqual(try ARM64Assembler.assembleWord("adcs x9, x10, x11"), 0xba0b0149)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sbc w12, w13, w14"), 0x5a0e01ac)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sbc x15, x16, x17"), 0xda11020f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sbcs w18, w19, w20"), 0x7a140272)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sbcs x21, x22, x23"), 0xfa1702d5)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ngc w0, w1"), 0x5a0103e0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ngc x2, x3"), 0xda0303e2)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ngcs w4, w5"), 0x7a0503e4)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ngcs x6, x7"), 0xfa0703e6)
    }

    func testDisassembleAddSubCarry() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1a020020), "adc w0, w1, w2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xba0b0149), "adcs x9, x10, x11")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5a0e01ac), "sbc w12, w13, w14")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xfa1702d5), "sbcs x21, x22, x23")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5a0103e0), "ngc w0, w1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xfa0703e6), "ngcs x6, x7")
    }

    func testAddSubCarryRoundTrip() throws {
        for source in [
            "adc w0, w1, w2", "adc x3, x4, x5", "adcs w6, w7, w8", "adcs x9, x10, x11",
            "sbc w12, w13, w14", "sbc x15, x16, x17", "sbcs w18, w19, w20", "sbcs x21, x22, x23",
            "ngc w0, w1", "ngc x2, x3", "ngcs w4, w5", "ngcs x6, x7",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testAddSubCarryInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("adc w0, x1, w2"))   // mismatched widths
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("adc w0, w1"))       // missing operand
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ngc w0"))           // missing source
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ngc w0, x1"))       // mismatched widths
    }

    func testBitfieldInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("sbfm w0, w1, #2, #3"), 0x13020c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sbfm x0, x1, #2, #3"), 0x93420c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ubfm w0, w1, #2, #3"), 0x53020c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfm w0, w1, #2, #3"), 0x33020c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sbfx w0, w1, #2, #4"), 0x13021420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sbfx x0, x1, #2, #4"), 0x93421420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ubfx w0, w1, #2, #4"), 0x53021420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sbfiz w0, w1, #2, #4"), 0x131e0c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ubfiz w0, w1, #2, #4"), 0x531e0c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfi w0, w1, #2, #4"), 0x331e0c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfxil w0, w1, #2, #4"), 0x33021420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfc w0, #2, #4"), 0x331e0fe0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sxtb w0, w1"), 0x13001c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sxtb x0, w1"), 0x93401c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sxth w0, w1"), 0x13003c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sxth x0, w1"), 0x93403c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sxtw x0, w1"), 0x93407c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uxtb w0, w1"), 0x53001c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("uxth w0, w1"), 0x53003c20)
    }

    func testDisassembleBitfield() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x13021420), "sbfx w0, w1, #2, #4")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x531e0c20), "ubfiz w0, w1, #2, #4")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x331e0c20), "bfi w0, w1, #2, #4")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x331e0fe0), "bfc w0, #2, #4")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x13001c20), "sxtb w0, w1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x93407c20), "sxtw x0, w1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x53003c20), "uxth w0, w1")
    }

    func testBitfieldRoundTrip() throws {
        for source in [
            "sbfx w0, w1, #2, #4", "sbfx x0, x1, #2, #4", "ubfx w0, w1, #2, #4",
            "sbfiz w0, w1, #2, #4", "ubfiz w0, w1, #2, #4", "bfi w0, w1, #2, #4",
            "bfxil w0, w1, #2, #4", "bfc w0, #2, #4",
            "sxtb w0, w1", "sxtb x0, w1", "sxth w0, w1", "sxth x0, w1",
            "sxtw x0, w1", "uxtb w0, w1", "uxth w0, w1",
            "asr w0, w1, #5", "asr x0, x1, #5", "lsr w0, w1, #5",
            "lsl w0, w1, #5", "lsl x0, x1, #5",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source, "round trip failed for \(source)")
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "re-assemble failed for \(source)")
        }
    }

    func testBitfieldInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sbfm w0, w1, #32, #3"))  // immr out of range for 32-bit
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sbfm w0, w1, #2, #32"))  // imms out of range for 32-bit
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sxtw w0, w1"))            // sxtw requires 64-bit dest
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("uxtb x0, w1"))            // uxtb requires 32-bit dest
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sbfx w0, w1, #2"))        // missing width operand
    }

    func testConditionalSelectInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("csel w0, w1, w2, eq"), 0x1a820020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csel x0, x1, x2, ne"), 0x9a821020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csinc w0, w1, w2, ge"), 0x1a82a420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csinc x0, x1, x2, lt"), 0x9a82b420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csinv w0, w1, w2, gt"), 0x5a82c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csinv x0, x1, x2, le"), 0xda82d020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csneg w0, w1, w2, mi"), 0x5a824420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csneg x0, x1, x2, pl"), 0xda825420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csel x5, x6, x7, al"), 0x9a87e0c5)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csneg x3, x4, x5, vs"), 0xda856483)
    }

    func testDisassembleConditionalSelect() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1a820020), "csel w0, w1, w2, eq")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9a821020), "csel x0, x1, x2, ne")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1a82a420), "csinc w0, w1, w2, ge")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5a82c020), "csinv w0, w1, w2, gt")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xda825420), "csneg x0, x1, x2, pl")
    }

    func testConditionalSelectRoundTrip() throws {
        let sources = [
            "csel w0, w1, w2, eq", "csel x3, x4, x5, ne",
            "csinc w6, w7, w8, ge", "csinc x9, x10, x11, lt",
            "csinv w12, w13, w14, gt", "csinv x15, x16, x17, le",
            "csneg w18, w19, w20, mi", "csneg x21, x22, x23, pl",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testConditionalSelectInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("csel w0, x1, w2, eq"))  // mismatched widths
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("csel w0, w1, w2, zz"))  // bad condition
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("csel w0, w1, w2"))      // missing condition
    }

    func testConditionalCompareInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("ccmp w0, w1, #0, eq"), 0x7a410000)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ccmp x0, x1, #15, ne"), 0xfa41100f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ccmn w0, w1, #5, ge"), 0x3a41a005)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ccmn x0, x1, #10, lt"), 0xba41b00a)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ccmp w2, #3, #6, gt"), 0x7a43c846)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ccmp x3, #31, #9, le"), 0xfa5fd869)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ccmn w4, #0, #12, mi"), 0x3a40488c)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ccmn x5, #15, #1, pl"), 0xba4f58a1)
    }

    func testDisassembleConditionalCompare() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7a410000), "ccmp w0, w1, #0, eq")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xfa41100f), "ccmp x0, x1, #15, ne")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x3a41a005), "ccmn w0, w1, #5, ge")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7a43c846), "ccmp w2, #3, #6, gt")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xba4f58a1), "ccmn x5, #15, #1, pl")
    }

    func testConditionalCompareRoundTrip() throws {
        let sources = [
            "ccmp w0, w1, #0, eq", "ccmp x2, x3, #15, ne",
            "ccmn w4, w5, #5, ge", "ccmn x6, x7, #10, lt",
            "ccmp w8, #3, #6, gt", "ccmp x9, #31, #9, le",
            "ccmn w10, #0, #12, mi", "ccmn x11, #15, #1, pl",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testConditionalCompareInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ccmp w0, w1, #16, eq"))  // nzcv out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ccmp w0, #32, #0, eq"))  // imm5 out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ccmp w0, x1, #0, eq"))   // mismatched widths
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("ccmp w0, w1, #0, zz"))   // bad condition
    }

    func testConditionalSetAndSelectAliasInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("cset w0, eq"), 0x1a9f17e0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cset x1, ne"), 0x9a9f07e1)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csetm w2, ge"), 0x5a9fb3e2)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csetm x3, lt"), 0xda9fa3e3)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cinc w4, w5, gt"), 0x1a85d4a4)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cinc x6, x7, le"), 0x9a87c4e6)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cinv w8, w9, mi"), 0x5a895128)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cinv x10, x11, pl"), 0xda8b416a)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cneg w12, w13, vs"), 0x5a8d75ac)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cneg x14, x15, hi"), 0xda8f95ee)
        XCTAssertEqual(try ARM64Assembler.assembleWord("cset w16, cc"), 0x1a9f27f0)
        XCTAssertEqual(try ARM64Assembler.assembleWord("csetm x17, cs"), 0xda9f33f1)
    }

    func testDisassembleConditionalSetAndSelectAlias() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1a9f17e0), "cset w0, eq")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5a9fb3e2), "csetm w2, ge")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1a85d4a4), "cinc w4, w5, gt")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5a895128), "cinv w8, w9, mi")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5a8d75ac), "cneg w12, w13, vs")
        // csinc/csinv/csneg with distinct source registers are NOT aliased.
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1a82a420), "csinc w0, w1, w2, ge")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5a82c020), "csinv w0, w1, w2, gt")
    }

    func testConditionalSetAndSelectAliasRoundTrip() throws {
        for source in [
            "cset w0, eq", "cset x1, ne", "csetm w2, ge", "csetm x3, lt",
            "cinc w4, w5, gt", "cinc x6, x7, le", "cinv w8, w9, mi",
            "cinv x10, x11, pl", "cneg w12, w13, vs", "cneg x14, x15, hi",
        ] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word, "round trip failed for \(source)")
        }
    }

    func testConditionalSetAndSelectAliasInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cset w0, al"))      // AL not invertible
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cset w0, nv"))      // NV not invertible
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cinc w0, x1, eq"))  // mismatched widths
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cneg w0, w1, nv"))  // NV not invertible
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("cset w0, zz"))      // bad condition
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

    func testHalfPrecisionThreeSourceInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmadd h0, h1, h2, h3"), 0x1fc20c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmsub h0, h1, h2, h3"), 0x1fc28c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fnmadd h0, h1, h2, h3"), 0x1fe20c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fnmsub h0, h1, h2, h3"), 0x1fe28c20)
    }

    func testDisassembleHalfPrecisionThreeSource() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1fc20c20), "fmadd h0, h1, h2, h3")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1fe28c20), "fnmsub h0, h1, h2, h3")
    }

    func testHalfPrecisionThreeSourceRoundTrip() throws {
        let sources = [
            "fmadd h0, h1, h2, h3", "fmsub h4, h5, h6, h7",
            "fnmadd h8, h9, h10, h11", "fnmsub h12, h13, h14, h15",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
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

    func testScalarFloatingPointRoundToIntegralInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintn s0, s1"), 0x1e244020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintp s0, s1"), 0x1e24c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintm s0, s1"), 0x1e254020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintz s0, s1"), 0x1e25c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frinta s0, s1"), 0x1e264020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintx s0, s1"), 0x1e274020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frinti s0, s1"), 0x1e27c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintn d0, d1"), 0x1e644020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frinta h0, h1"), 0x1ee64020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintx h0, h1"), 0x1ee74020)
        // Armv8.5 frint32/frint64 (single/double only).
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint32z s0, s1"), 0x1e284020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint32x s0, s1"), 0x1e28c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint64z s0, s1"), 0x1e294020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint64x s0, s1"), 0x1e29c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint32z d0, d1"), 0x1e684020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint32x d0, d1"), 0x1e68c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint64z d0, d1"), 0x1e694020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint64x d0, d1"), 0x1e69c020)
    }

    func testDisassembleScalarFloatingPointRoundToIntegral() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e244020), "frintn s0, s1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e27c020), "frinti s0, s1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1ee64020), "frinta h0, h1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e284020), "frint32z s0, s1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e69c020), "frint64x d0, d1")
    }

    func testScalarFloatingPointRoundToIntegralRoundTrip() throws {
        let sources = [
            "frintn s0, s1", "frintp d2, d3", "frintm s4, s5", "frintz d6, d7",
            "frinta s8, s9", "frintx d10, d11", "frinti s12, s13",
            "frinta h14, h15", "frintx h16, h17", "frinti h18, h19",
            "frint32z s20, s21", "frint32x d22, d23", "frint64z s24, s25", "frint64x d26, d27",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testScalarFloatingPointRoundToIntegralInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("frintn s0, d1"))     // widths must match
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("frint32z h0, h1"))   // frint32 has no half form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("frint64x h0, h1"))   // frint64 has no half form
    }

    func testVectorFRINTToIntegerInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint32z v0.2s, v1.2s"), 0x0e21e820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint32z v0.4s, v1.4s"), 0x4e21e820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint32z v0.2d, v1.2d"), 0x4e61e820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint32x v0.2s, v1.2s"), 0x2e21e820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint32x v0.4s, v1.4s"), 0x6e21e820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint32x v0.2d, v1.2d"), 0x6e61e820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint64z v0.2s, v1.2s"), 0x0e21f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint64z v0.4s, v1.4s"), 0x4e21f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint64z v0.2d, v1.2d"), 0x4e61f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint64x v0.2s, v1.2s"), 0x2e21f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint64x v0.4s, v1.4s"), 0x6e21f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frint64x v0.2d, v1.2d"), 0x6e61f820)
    }

    func testDisassembleVectorFRINTToInteger() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e21e820), "frint32z v0.2s, v1.2s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e61e820), "frint32x v0.2d, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e21f820), "frint64z v0.4s, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e61f820), "frint64x v0.2d, v1.2d")
    }

    func testVectorFRINTToIntegerRoundTrip() throws {
        let sources = [
            "frint32z v0.2s, v1.2s", "frint32z v2.4s, v3.4s", "frint32z v4.2d, v5.2d",
            "frint32x v6.2s, v7.2s", "frint32x v8.4s, v9.4s", "frint32x v10.2d, v11.2d",
            "frint64z v12.2s, v13.2s", "frint64z v14.4s, v15.4s", "frint64z v16.2d, v17.2d",
            "frint64x v18.2s, v19.2s", "frint64x v20.4s, v21.4s", "frint64x v22.2d, v23.2d",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorFRINTToIntegerInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("frint32z v0.8b, v1.8b"))  // no byte form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("frint32z v0.4h, v1.4h"))  // no halfword form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("frint64x v0.1d, v1.1d"))  // 1d not allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("frint32z v0.2s, v1.4s"))  // arrangements must match
    }

    func testVectorShiftLeftLongInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("shll v0.8h, v1.8b, #8"), 0x2e213820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("shll2 v0.8h, v1.16b, #8"), 0x6e213820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("shll v0.4s, v1.4h, #16"), 0x2e613820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("shll2 v0.4s, v1.8h, #16"), 0x6e613820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("shll v0.2d, v1.2s, #32"), 0x2ea13820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("shll2 v0.2d, v1.4s, #32"), 0x6ea13820)
    }

    func testDisassembleVectorShiftLeftLong() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e213820), "shll v0.8h, v1.8b, #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e213820), "shll2 v0.8h, v1.16b, #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e613820), "shll v0.4s, v1.4h, #16")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ea13820), "shll2 v0.2d, v1.4s, #32")
    }

    func testVectorShiftLeftLongRoundTrip() throws {
        let sources = [
            "shll v0.8h, v1.8b, #8", "shll2 v2.8h, v3.16b, #8",
            "shll v4.4s, v5.4h, #16", "shll2 v6.4s, v7.8h, #16",
            "shll v8.2d, v9.2s, #32", "shll2 v10.2d, v11.4s, #32",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testVectorShiftLeftLongInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("shll v0.8h, v1.16b, #8"))  // 16b needs shll2
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("shll2 v0.8h, v1.8b, #8"))  // 8b needs shll
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("shll v0.8h, v1.8b, #4"))  // shift must equal element width
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("shll v0.2d, v1.1d, #64"))  // 1d source not allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("shll v0.4s, v1.8b, #8"))  // mismatched dest
    }

    func testFJCVTZSInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fjcvtzs w0, d1"), 0x1e7e0020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fjcvtzs w5, d7"), 0x1e7e00e5)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fjcvtzs w20, d31"), 0x1e7e03f4)
    }

    func testDisassembleFJCVTZS() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e7e0020), "fjcvtzs w0, d1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e7e03f4), "fjcvtzs w20, d31")
    }

    func testFJCVTZSRoundTrip() throws {
        for source in ["fjcvtzs w0, d1", "fjcvtzs w5, d7", "fjcvtzs w20, d31"] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testFJCVTZSInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fjcvtzs x0, d1"))  // dest must be 32-bit
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fjcvtzs w0, s1"))  // source must be double
    }

    func testFPConditionalSelectInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcsel s0, s1, s2, eq"), 0x1e220c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcsel d0, d1, d2, ne"), 0x1e621c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcsel h0, h1, h2, gt"), 0x1ee2cc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcsel s5, s6, s7, al"), 0x1e27ecc5)
    }

    func testFPConditionalCompareInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fccmp s1, s2, #0, eq"), 0x1e220420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fccmp d1, d2, #15, ne"), 0x1e62142f)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fccmpe s1, s2, #0, eq"), 0x1e220430)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fccmpe d3, d4, #5, mi"), 0x1e644475)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fccmp h1, h2, #7, lt"), 0x1ee2b427)
    }

    func testDisassembleFPConditionalSelectAndCompare() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e220c20), "fcsel s0, s1, s2, eq")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1ee2cc20), "fcsel h0, h1, h2, gt")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e220420), "fccmp s1, s2, #0, eq")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e220430), "fccmpe s1, s2, #0, eq")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1ee2b427), "fccmp h1, h2, #7, lt")
    }

    func testFPConditionalRoundTrip() throws {
        let sources = [
            "fcsel s0, s1, s2, eq", "fcsel d3, d4, d5, ne", "fcsel h6, h7, h8, gt",
            "fcsel s9, s10, s11, al",
            "fccmp s1, s2, #0, eq", "fccmp d1, d2, #15, ne", "fccmpe s3, s4, #3, mi",
            "fccmpe d5, d6, #5, pl", "fccmp h7, h8, #7, lt",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testFPConditionalInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcsel s0, d1, s2, eq"))   // mixed widths
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcsel s0, s1, s2, xy"))   // bad condition
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fccmp s1, s2, #16, eq"))  // nzcv out of range
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fccmp s1, d2, #0, eq"))   // mixed widths
    }

    func testFPFixedPointConvertInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf s0, w1, #4"), 0x1e02f020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ucvtf d0, x1, #8"), 0x9e43e020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs w0, s1, #4"), 0x1e18f020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzu x0, d1, #8"), 0x9e59e020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf h0, w1, #2"), 0x1ec2f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs w0, h1, #3"), 0x1ed8f420)
    }

    func testDisassembleFPFixedPointConvert() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e02f020), "scvtf s0, w1, #4")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9e43e020), "ucvtf d0, x1, #8")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1e18f020), "fcvtzs w0, s1, #4")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x1ed8f420), "fcvtzs w0, h1, #3")
    }

    func testFPFixedPointConvertRoundTrip() throws {
        let sources = [
            "scvtf s0, w1, #4", "ucvtf d2, x3, #8", "scvtf d4, w5, #1", "ucvtf s6, x7, #31",
            "fcvtzs w0, s1, #4", "fcvtzu x2, d3, #8", "fcvtzs x4, s5, #32", "fcvtzu w6, d7, #16",
            "scvtf h8, w9, #2", "fcvtzs w10, h11, #3", "ucvtf h12, x13, #5", "fcvtzu x14, h15, #6",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testFPFixedPointConvertInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf s0, w1, #0"))   // fbits must be >= 1
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf s0, w1, #33"))  // W register: fbits <= 32
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcvtzs w0, s1, #65"))  // out of range
    }

    func testFMovVectorHighInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov x0, v1.d[1]"), 0x9eae0020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov v2.d[1], x3"), 0x9eaf0062)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmov x30, v31.d[1]"), 0x9eae03fe)
    }

    func testDisassembleFMovVectorHigh() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9eae0020), "fmov x0, v1.d[1]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x9eaf0062), "fmov v2.d[1], x3")
    }

    func testFMovVectorHighRoundTrip() throws {
        for source in ["fmov x0, v1.d[1]", "fmov v2.d[1], x3", "fmov x30, v31.d[1]", "fmov v4.d[1], x5"] {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            let reassembled = try ARM64Assembler.assembleWord(text)
            XCTAssertEqual(reassembled, word, "round-trip failed for \(source) -> \(text)")
        }
    }

    func testFMovVectorHighInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmov w0, v1.d[1]"))  // must be 64-bit
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmov x0, v1.s[1]"))  // only .d[1] form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmov x0, v1.d[0]"))  // index must be 1
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
        // Half-precision (FP16) forms (destination `h`).
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxv h0, v1.4h"), 0x0e30f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxv h0, v1.8h"), 0x4e30f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminv h0, v1.8h"), 0x4eb0f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxnmv h0, v1.4h"), 0x0e30c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminnmv h0, v1.8h"), 0x4eb0c820)
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
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e30f820), "fmaxv h0, v1.8h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e30c820), "fmaxnmv h0, v1.4h")
    }

    func testAcrossLanesRoundTrip() throws {
        let sources = [
            "addv b0, v1.8b", "addv h0, v1.4h", "addv s0, v1.4s", "addv b2, v3.16b", "addv h4, v5.8h",
            "saddlv h0, v1.8b", "saddlv s0, v1.4h", "saddlv d0, v1.4s", "saddlv h2, v3.16b", "saddlv s4, v5.8h",
            "uaddlv h0, v1.8b", "uaddlv d0, v1.4s",
            "smaxv b0, v1.8b", "smaxv h0, v1.4h", "smaxv s0, v1.4s",
            "umaxv b0, v1.16b", "sminv h0, v1.8h", "uminv s0, v1.4s",
            "fmaxv s0, v1.4s", "fminv s0, v1.4s", "fmaxnmv s0, v1.4s", "fminnmv s0, v1.4s",
            "fmaxv h6, v7.4h", "fmaxv h8, v9.8h", "fminv h10, v11.8h",
            "fmaxnmv h12, v13.4h", "fminnmv h14, v15.8h",
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
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmaxv s0, v1.2s"))  // FP single only .4s
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmaxv s0, v1.8h"))  // FP16 dst must be `h`
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmaxv h0, v1.4s"))  // `h` dst needs FP16 source
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

    func testVectorThreeSameFP16Instructions() throws {
        // Three-same (FP16): `.4h`/`.8h` element forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fadd v0.4h, v1.4h, v2.4h"), 0x0e421420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fadd v0.8h, v1.8h, v2.8h"), 0x4e421420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fsub v0.4h, v1.4h, v2.4h"), 0x0ec21420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmul v0.4h, v1.4h, v2.4h"), 0x2e421c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fdiv v0.4h, v1.4h, v2.4h"), 0x2e423c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmla v0.4h, v1.4h, v2.4h"), 0x0e420c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmls v0.4h, v1.4h, v2.4h"), 0x0ec20c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmax v0.4h, v1.4h, v2.4h"), 0x0e423420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmin v0.4h, v1.4h, v2.4h"), 0x0ec23420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxnm v0.4h, v1.4h, v2.4h"), 0x0e420420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminnm v0.4h, v1.4h, v2.4h"), 0x0ec20420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmulx v0.4h, v1.4h, v2.4h"), 0x0e421c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmeq v0.4h, v1.4h, v2.4h"), 0x0e422420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmge v0.4h, v1.4h, v2.4h"), 0x2e422420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmgt v0.4h, v1.4h, v2.4h"), 0x2ec22420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("facge v0.4h, v1.4h, v2.4h"), 0x2e422c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("facgt v0.4h, v1.4h, v2.4h"), 0x2ec22c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecps v0.4h, v1.4h, v2.4h"), 0x0e423c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frsqrts v0.4h, v1.4h, v2.4h"), 0x0ec23c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fabd v0.4h, v1.4h, v2.4h"), 0x2ec21420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("faddp v0.4h, v1.4h, v2.4h"), 0x2e421420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxp v0.4h, v1.4h, v2.4h"), 0x2e423420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminp v0.4h, v1.4h, v2.4h"), 0x2ec23420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxnmp v0.4h, v1.4h, v2.4h"), 0x2e420420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminnmp v0.4h, v1.4h, v2.4h"), 0x2ec20420)
    }

    func testDisassembleVectorThreeSameFP16() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e421420), "fadd v0.4h, v1.4h, v2.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e421420), "fadd v0.8h, v1.8h, v2.8h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e421c20), "fmul v0.4h, v1.4h, v2.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2ec22420), "fcmgt v0.4h, v1.4h, v2.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2ec23420), "fminp v0.4h, v1.4h, v2.4h")
    }

    func testVectorThreeSameFP16RoundTrip() throws {
        let sources = [
            "fadd v0.4h, v1.4h, v2.4h", "fadd v3.8h, v4.8h, v5.8h",
            "fsub v6.4h, v7.4h, v8.4h", "fmul v9.8h, v10.8h, v11.8h",
            "fdiv v12.4h, v13.4h, v14.4h", "fmla v15.8h, v16.8h, v17.8h",
            "fmls v18.4h, v19.4h, v20.4h", "fmax v21.8h, v22.8h, v23.8h",
            "fminnm v24.4h, v25.4h, v26.4h", "fmulx v27.8h, v28.8h, v29.8h",
            "fcmeq v30.4h, v31.4h, v0.4h", "facgt v1.8h, v2.8h, v3.8h",
            "fabd v4.4h, v5.4h, v6.4h", "fmaxnmp v7.8h, v8.8h, v9.8h",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
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

    func testVectorMixedDotProductInstructions() throws {
        // USDOT vector form (only usdot has a three-register form).
        XCTAssertEqual(try ARM64Assembler.assembleWord("usdot v0.2s, v1.8b, v2.8b"), 0x0e829c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("usdot v0.4s, v1.16b, v2.16b"), 0x4e829c20)
        // USDOT/SUDOT by-element form (Vd.2s/4s, Vn.8b/16b, Vm.4b[index]).
        XCTAssertEqual(try ARM64Assembler.assembleWord("usdot v0.2s, v1.8b, v2.4b[0]"), 0x0f82f020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("usdot v0.4s, v1.16b, v2.4b[3]"), 0x4fa2f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sudot v0.2s, v1.8b, v2.4b[0]"), 0x0f02f020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sudot v0.4s, v1.16b, v2.4b[2]"), 0x4f02f820)
    }

    func testDisassembleVectorMixedDotProduct() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e829c20), "usdot v0.2s, v1.8b, v2.8b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e829c20), "usdot v0.4s, v1.16b, v2.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4fa2f820), "usdot v0.4s, v1.16b, v2.4b[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f02f020), "sudot v0.2s, v1.8b, v2.4b[0]")
    }

    func testVectorMixedDotProductRoundTrip() throws {
        let sources = [
            "usdot v0.2s, v1.8b, v2.8b", "usdot v3.4s, v4.16b, v5.16b",
            "usdot v6.2s, v7.8b, v8.4b[0]", "usdot v9.4s, v10.16b, v11.4b[3]",
            "sudot v12.2s, v13.8b, v14.4b[1]", "sudot v15.4s, v16.16b, v17.4b[2]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testVectorMixedDotProductInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sudot v0.2s, v1.8b, v2.8b"))   // sudot has no vector form
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("usdot v0.2s, v1.16b, v2.16b")) // 2s pairs with 8b
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("usdot v0.4h, v1.8b, v2.8b"))   // dest must be 2s/4s
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("usdot v0.2s, v1.8b, v2.4b[4]")) // index out of range
    }

    func testVectorMatrixMultiplyInstructions() throws {
        XCTAssertEqual(try ARM64Assembler.assembleWord("smmla v0.4s, v1.16b, v2.16b"), 0x4e82a420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ummla v0.4s, v1.16b, v2.16b"), 0x6e82a420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("usmmla v0.4s, v1.16b, v2.16b"), 0x4e82ac20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("smmla v5.4s, v6.16b, v7.16b"), 0x4e87a4c5)
    }

    func testDisassembleVectorMatrixMultiply() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e82a420), "smmla v0.4s, v1.16b, v2.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e82a420), "ummla v0.4s, v1.16b, v2.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4e82ac20), "usmmla v0.4s, v1.16b, v2.16b")
    }

    func testVectorMatrixMultiplyRoundTrip() throws {
        let sources = [
            "smmla v0.4s, v1.16b, v2.16b", "ummla v3.4s, v4.16b, v5.16b",
            "usmmla v6.4s, v7.16b, v8.16b", "smmla v29.4s, v30.16b, v31.16b",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testVectorMatrixMultiplyInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("smmla v0.2s, v1.8b, v2.8b"))    // must be 4s/16b
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("smmla v0.4s, v1.8b, v2.16b"))   // sources must be 16b
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("smmla v0.4h, v1.16b, v2.16b"))  // dest must be 4s
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

    func testVectorComplexInstructions() throws {
        // FCADD (rotation #90 / #270).
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcadd v0.4h, v1.4h, v2.4h, #90"), 0x2e42e420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcadd v0.4h, v1.4h, v2.4h, #270"), 0x2e42f420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcadd v0.2s, v1.2s, v2.2s, #90"), 0x2e82e420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcadd v0.4s, v1.4s, v2.4s, #270"), 0x6e82f420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcadd v0.2d, v1.2d, v2.2d, #90"), 0x6ec2e420)
        // FCMLA vector (rotation #0 / #90 / #180 / #270).
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.4h, v1.4h, v2.4h, #0"), 0x2e42c420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.4h, v1.4h, v2.4h, #90"), 0x2e42cc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.4h, v1.4h, v2.4h, #180"), 0x2e42d420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.4h, v1.4h, v2.4h, #270"), 0x2e42dc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.4s, v1.4s, v2.4s, #90"), 0x6e82cc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.2d, v1.2d, v2.2d, #180"), 0x6ec2d420)
        // FCMLA by element.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.4h, v1.4h, v2.h[0], #0"), 0x2f421020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.4h, v1.4h, v2.h[1], #90"), 0x2f623020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.8h, v1.8h, v2.h[3], #0"), 0x6f621820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.4s, v1.4s, v2.s[0], #180"), 0x6f825020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.4s, v1.4s, v2.s[1], #270"), 0x6f827820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmla v0.4s, v1.4s, v31.s[1], #0"), 0x6f9f1820)
    }

    func testDisassembleVectorComplex() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e42e420), "fcadd v0.4h, v1.4h, v2.4h, #90")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e82f420), "fcadd v0.4s, v1.4s, v2.4s, #270")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e42dc20), "fcmla v0.4h, v1.4h, v2.4h, #270")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ec2d420), "fcmla v0.2d, v1.2d, v2.2d, #180")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2f623020), "fcmla v0.4h, v1.4h, v2.h[1], #90")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6f827820), "fcmla v0.4s, v1.4s, v2.s[1], #270")
    }

    func testVectorComplexRoundTrip() throws {
        let sources = [
            "fcadd v0.4h, v1.4h, v2.4h, #90", "fcadd v3.8h, v4.8h, v5.8h, #270",
            "fcadd v6.2s, v7.2s, v8.2s, #90", "fcadd v9.4s, v10.4s, v11.4s, #270",
            "fcadd v12.2d, v13.2d, v14.2d, #90",
            "fcmla v0.4h, v1.4h, v2.4h, #0", "fcmla v3.8h, v4.8h, v5.8h, #90",
            "fcmla v6.2s, v7.2s, v8.2s, #180", "fcmla v9.4s, v10.4s, v11.4s, #270",
            "fcmla v12.2d, v13.2d, v14.2d, #90",
            "fcmla v0.4h, v1.4h, v15.h[3], #0", "fcmla v3.8h, v4.8h, v2.h[1], #90",
            "fcmla v6.4s, v7.4s, v31.s[0], #180", "fcmla v9.4s, v10.4s, v17.s[1], #270",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testVectorComplexInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcadd v0.4h, v1.4h, v2.4h, #0"))   // fcadd allows only 90/270
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcadd v0.8b, v1.8b, v2.8b, #90"))  // byte not allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcadd v0.1d, v1.1d, v2.1d, #90"))  // 1d not allowed
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcmla v0.4h, v1.4h, v2.4h, #45"))  // rotation must be multiple of 90
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcmla v0.4h, v1.4h, v16.h[0], #0")) // half element Vm <= 15
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fcmla v0.4s, v1.4s, v2.s[2], #0"))  // single index <= 1
    }

    func testVectorFPMultiplyLongInstructions() throws {
        // Vector forms (Vd.2s/4s, Vn.2h/4h, Vm.2h/4h).
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlal v0.2s, v1.2h, v2.2h"), 0x0e22ec20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlal2 v0.2s, v1.2h, v2.2h"), 0x2e22cc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlal v0.4s, v1.4h, v2.4h"), 0x4e22ec20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlal2 v0.4s, v1.4h, v2.4h"), 0x6e22cc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlsl v0.2s, v1.2h, v2.2h"), 0x0ea2ec20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlsl2 v0.2s, v1.2h, v2.2h"), 0x2ea2cc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlsl v0.4s, v1.4h, v2.4h"), 0x4ea2ec20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlsl2 v0.4s, v1.4h, v2.4h"), 0x6ea2cc20)
        // By-element forms (Vm.h[index], index 0–7, Vm <= 15).
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlal v0.2s, v1.2h, v2.h[0]"), 0x0f820020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlal2 v0.2s, v1.2h, v2.h[7]"), 0x2fb28820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlal v0.4s, v1.4h, v2.h[3]"), 0x4fb20020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlal2 v0.4s, v1.4h, v2.h[5]"), 0x6f928820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlsl v0.2s, v1.2h, v2.h[1]"), 0x0f924020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlsl2 v0.2s, v1.2h, v2.h[2]"), 0x2fa2c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlsl v0.4s, v1.4h, v2.h[3]"), 0x4fb24020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmlsl2 v0.4s, v1.4h, v2.h[5]"), 0x6f92c820)
    }

    func testDisassembleVectorFPMultiplyLong() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e22ec20), "fmlal v0.2s, v1.2h, v2.2h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e22cc20), "fmlal2 v0.4s, v1.4h, v2.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ea2ec20), "fmlsl v0.4s, v1.4h, v2.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f820020), "fmlal v0.2s, v1.2h, v2.h[0]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2fb28820), "fmlal2 v0.2s, v1.2h, v2.h[7]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6f92c820), "fmlsl2 v0.4s, v1.4h, v2.h[5]")
    }

    func testVectorFPMultiplyLongRoundTrip() throws {
        let sources = [
            "fmlal v0.2s, v1.2h, v2.2h", "fmlal2 v3.4s, v4.4h, v5.4h",
            "fmlsl v6.2s, v7.2h, v8.2h", "fmlsl2 v9.4s, v10.4h, v11.4h",
            "fmlal v0.4s, v1.4h, v15.h[3]", "fmlal2 v3.2s, v4.2h, v14.h[7]",
            "fmlsl v6.4s, v7.4h, v2.h[0]", "fmlsl2 v9.2s, v10.2h, v13.h[6]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testVectorFPMultiplyLongInvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmlal v0.4s, v1.2h, v2.2h"))   // dest .4s needs .4h sources
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmlal v0.2d, v1.2s, v2.2s"))   // only .2s/.4s dest
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmlal v0.2s, v1.2h, v16.h[0]")) // element Vm <= 15
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmlal v0.2s, v1.2h, v2.h[8]"))  // index <= 7
    }

    func testVectorBFloat16Instructions() throws {
        // BFDOT (vector and by-element).
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfdot v0.2s, v1.4h, v2.4h"), 0x2e42fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfdot v0.4s, v1.8h, v2.8h"), 0x6e42fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfdot v0.2s, v1.4h, v2.2h[0]"), 0x0f42f020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfdot v0.4s, v1.8h, v2.2h[3]"), 0x4f62f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfdot v0.2s, v1.4h, v18.2h[1]"), 0x0f72f020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfdot v0.2s, v1.4h, v31.2h[3]"), 0x0f7ff820)
        // BFMLALB / BFMLALT (vector and by-element).
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfmlalb v0.4s, v1.8h, v2.8h"), 0x2ec2fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfmlalt v0.4s, v1.8h, v2.8h"), 0x6ec2fc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfmlalb v0.4s, v1.8h, v2.h[0]"), 0x0fc2f020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfmlalt v0.4s, v1.8h, v2.h[7]"), 0x4ff2f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfmlalb v0.4s, v1.8h, v15.h[5]"), 0x0fdff820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfmlalt v0.4s, v1.8h, v14.h[3]"), 0x4ffef020)
        // BFMMLA.
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfmmla v0.4s, v1.8h, v2.8h"), 0x6e42ec20)
        // BFCVTN / BFCVTN2 (FP32→BF16 narrow).
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfcvtn v0.4h, v1.4s"), 0x0ea16820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bfcvtn2 v0.8h, v1.4s"), 0x4ea16820)
    }

    func testDisassembleVectorBFloat16() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2e42fc20), "bfdot v0.2s, v1.4h, v2.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4f62f820), "bfdot v0.4s, v1.8h, v2.2h[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2ec2fc20), "bfmlalb v0.4s, v1.8h, v2.8h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ec2fc20), "bfmlalt v0.4s, v1.8h, v2.8h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ff2f820), "bfmlalt v0.4s, v1.8h, v2.h[7]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6e42ec20), "bfmmla v0.4s, v1.8h, v2.8h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0ea16820), "bfcvtn v0.4h, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4ea16820), "bfcvtn2 v0.8h, v1.4s")
    }

    func testVectorBFloat16RoundTrip() throws {
        let sources = [
            "bfdot v0.2s, v1.4h, v2.4h", "bfdot v3.4s, v4.8h, v5.8h",
            "bfdot v6.2s, v7.4h, v18.2h[1]", "bfdot v9.4s, v10.8h, v31.2h[3]",
            "bfmlalb v0.4s, v1.8h, v2.8h", "bfmlalt v3.4s, v4.8h, v5.8h",
            "bfmlalb v6.4s, v7.8h, v15.h[5]", "bfmlalt v9.4s, v10.8h, v14.h[3]",
            "bfmmla v0.4s, v1.8h, v2.8h",
            "bfcvtn v0.4h, v1.4s", "bfcvtn2 v12.8h, v13.4s",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testVectorBFloat16InvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("bfdot v0.4s, v1.4h, v2.4h"))      // .4s dest needs .8h sources
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("bfmlalb v0.2s, v1.8h, v2.8h"))    // bfmlal dest is .4s
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("bfmlalb v0.4s, v1.8h, v16.h[0]")) // bfmlal element Vm <= 15
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("bfmmla v0.2s, v1.8h, v2.8h"))     // bfmmla dest is .4s
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("bfdot v0.2s, v1.4h, v2.2h[4]"))   // pair index <= 3
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("bfcvtn v0.8h, v1.4s"))            // bfcvtn dest is .4h
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("bfcvtn2 v0.4h, v1.4s"))           // bfcvtn2 dest is .8h
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("bfcvtn v0.4h, v1.2d"))            // source must be .4s
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
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmul v0.2d, v1.4s, v2.s[1]"))   // fp dest/source mismatch
    }

    func testVectorIndexedFP16Instructions() throws {
        // FP16 by-element fmla / fmls / fmul / fmulx on `.4h`/`.8h` (size=00).
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmla v0.4h, v1.4h, v2.h[0]"), 0x0f021020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmla v0.8h, v1.8h, v2.h[7]"), 0x4f321820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmls v0.4h, v1.4h, v2.h[1]"), 0x0f125020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmul v0.8h, v1.8h, v2.h[3]"), 0x4f329020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmulx v0.4h, v1.4h, v2.h[5]"), 0x2f129820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmla v0.4h, v1.4h, v15.h[2]"), 0x0f2f1020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmul v0.4h, v1.4h, v15.h[6]"), 0x0f2f9820)
        // Scalar FP16 by-element forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmla h0, h1, v2.h[0]"), 0x5f021020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmla h0, h1, v2.h[7]"), 0x5f321820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmls h0, h1, v2.h[1]"), 0x5f125020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmul h0, h1, v2.h[3]"), 0x5f329020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmulx h0, h1, v15.h[5]"), 0x7f1f9820)
    }

    func testDisassembleVectorIndexedFP16() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0f021020), "fmla v0.4h, v1.4h, v2.h[0]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x4f321820), "fmla v0.8h, v1.8h, v2.h[7]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x2f129820), "fmulx v0.4h, v1.4h, v2.h[5]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5f329020), "fmul h0, h1, v2.h[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7f1f9820), "fmulx h0, h1, v15.h[5]")
    }

    func testVectorIndexedFP16RoundTrip() throws {
        let sources = [
            "fmla v0.4h, v1.4h, v2.h[0]", "fmla v3.8h, v4.8h, v5.h[7]",
            "fmls v6.4h, v7.4h, v8.h[1]", "fmul v9.8h, v10.8h, v11.h[3]",
            "fmulx v12.4h, v13.4h, v14.h[5]", "fmul v15.4h, v16.4h, v15.h[6]",
            "fmla h0, h1, v2.h[0]", "fmls h3, h4, v5.h[2]",
            "fmul h6, h7, v8.h[4]", "fmulx h9, h10, v11.h[7]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testVectorIndexedFP16InvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmla v0.4h, v1.4h, v16.h[0]"))  // FP16 H form: Vm 0-15
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmla v0.4h, v1.4h, v2.h[8]"))   // index 0-7
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fmla v0.4h, v1.8h, v2.h[0]"))   // dest/source arrangement mismatch
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
        // Half-precision (`.2h` source reducing into a scalar `h`).
        XCTAssertEqual(try ARM64Assembler.assembleWord("faddp h0, v1.2h"), 0x5e30d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxp h0, v1.2h"), 0x5e30f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminp h0, v1.2h"), 0x5eb0f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmaxnmp h0, v1.2h"), 0x5e30c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fminnmp h0, v1.2h"), 0x5eb0c820)
    }

    func testDisassembleScalarPairwise() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ef1b820), "addp d0, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7e30d820), "faddp s0, v1.2s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7ef0f820), "fminp d0, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7e70c820), "fmaxnmp d0, v1.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e30d820), "faddp h0, v1.2h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5eb0f820), "fminp h0, v1.2h")
    }

    func testScalarPairwiseRoundTrip() throws {
        let sources = [
            "addp d0, v1.2d",
            "faddp s2, v3.2s", "faddp d4, v5.2d",
            "fmaxp s6, v7.2s", "fmaxp d8, v9.2d",
            "fminp s10, v11.2s", "fminp d12, v13.2d",
            "fmaxnmp s14, v15.2s", "fmaxnmp d16, v17.2d",
            "fminnmp s18, v19.2s", "fminnmp d20, v21.2d",
            "faddp h22, v23.2h", "fmaxp h24, v25.2h", "fminp h26, v27.2h",
            "fmaxnmp h28, v29.2h", "fminnmp h30, v31.2h",
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
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("faddp s0, v1.2h"))   // dest width must match source (h)
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("addp h0, v1.2h"))    // addp has no FP16 form
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
        // Half-precision (`h` register) forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtns h0, h1"), 0x5e79a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtnu h0, h1"), 0x7e79a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtms h0, h1"), 0x5e79b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtmu h0, h1"), 0x7e79b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtas h0, h1"), 0x5e79c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtau h0, h1"), 0x7e79c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf h0, h1"), 0x5e79d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ucvtf h0, h1"), 0x7e79d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtps h0, h1"), 0x5ef9a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtpu h0, h1"), 0x7ef9a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs h0, h1"), 0x5ef9b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzu h0, h1"), 0x7ef9b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecpe h0, h1"), 0x5ef9d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frsqrte h0, h1"), 0x7ef9d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecpx h0, h1"), 0x5ef9f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmgt h0, h1, #0.0"), 0x5ef8c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmge h0, h1, #0.0"), 0x7ef8c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmeq h0, h1, #0.0"), 0x5ef8d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmle h0, h1, #0.0"), 0x7ef8d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmlt h0, h1, #0.0"), 0x5ef8e820)
    }

    func testDisassembleScalarFPTwoRegisterMisc() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e21a820), "fcvtns s0, s1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e61d820), "scvtf d0, d1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea1b820), "fcvtzs s0, s1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7e616820), "fcvtxn s0, d1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea0d820), "fcmeq s0, s1, #0.0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea0e820), "fcmlt s0, s1, #0.0")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e79a820), "fcvtns h0, h1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ef9f820), "frecpx h0, h1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ef8d820), "fcmeq h0, h1, #0.0")
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
            "fcvtns h0, h1", "fcvtnu h2, h3", "fcvtms h4, h5", "fcvtmu h6, h7",
            "fcvtas h8, h9", "fcvtau h10, h11", "scvtf h12, h13", "ucvtf h14, h15",
            "fcvtps h16, h17", "fcvtpu h18, h19", "fcvtzs h20, h21", "fcvtzu h22, h23",
            "frecpe h24, h25", "frsqrte h26, h27", "frecpx h28, h29",
            "fcmgt h0, h1, #0.0", "fcmge h2, h3, #0.0", "fcmeq h4, h5, #0.0",
            "fcmle h6, h7, #0.0", "fcmlt h8, h9, #0.0",
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
        // Half-precision (`h` register) forms.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fmulx h0, h1, h2"), 0x5e421c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmeq h0, h1, h2"), 0x5e422420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmge h0, h1, h2"), 0x7e422420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmgt h0, h1, h2"), 0x7ec22420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("facge h0, h1, h2"), 0x7e422c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("facgt h0, h1, h2"), 0x7ec22c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecps h0, h1, h2"), 0x5e423c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frsqrts h0, h1, h2"), 0x5ec23c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fabd h0, h1, h2"), 0x7ec21420)
    }

    func testDisassembleScalarThreeSameFP() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e22dc20), "fmulx s0, s1, s2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7ea2e420), "fcmgt s0, s1, s2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ea2fc20), "frsqrts s0, s1, s2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7ee2d420), "fabd d0, d1, d2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5e421c20), "fmulx h0, h1, h2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x7ec21420), "fabd h0, h1, h2")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x5ec23c20), "frsqrts h0, h1, h2")
    }

    func testScalarThreeSameFPRoundTrip() throws {
        let sources = [
            "fmulx s0, s1, s2", "fmulx d3, d4, d5", "fcmeq s6, s7, s8",
            "fcmge d9, d10, d11", "fcmgt s12, s13, s14", "facge d15, d16, d17",
            "facgt s18, s19, s20", "frecps d21, d22, d23", "frsqrts s24, s25, s26",
            "fabd d27, d28, d29", "fabd s30, s31, s0",
            "fmulx h1, h2, h3", "fcmeq h4, h5, h6", "fcmge h7, h8, h9",
            "fcmgt h10, h11, h12", "facge h13, h14, h15", "facgt h16, h17, h18",
            "frecps h19, h20, h21", "frsqrts h22, h23, h24", "fabd h25, h26, h27",
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

    func testVectorTwoRegisterMiscFP16Instructions() throws {
        // fabs / fneg / fsqrt on .4h/.8h.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fabs v0.4h, v1.4h"), 0x0ef8f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fabs v0.8h, v1.8h"), 0x4ef8f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fneg v0.4h, v1.4h"), 0x2ef8f820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fsqrt v0.8h, v1.8h"), 0x6ef9f820)
        // FRINT* roundings.
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintn v0.4h, v1.4h"), 0x0e798820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintm v0.4h, v1.4h"), 0x0e799820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintp v0.4h, v1.4h"), 0x0ef98820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintz v0.4h, v1.4h"), 0x0ef99820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frinta v0.4h, v1.4h"), 0x2e798820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frintx v0.4h, v1.4h"), 0x2e799820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frinti v0.4h, v1.4h"), 0x2ef99820)
        // Reciprocal estimates.
        XCTAssertEqual(try ARM64Assembler.assembleWord("frecpe v0.4h, v1.4h"), 0x0ef9d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("frsqrte v0.4h, v1.4h"), 0x2ef9d820)
        // FP↔int converts.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtns v0.4h, v1.4h"), 0x0e79a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtnu v0.4h, v1.4h"), 0x2e79a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtms v0.4h, v1.4h"), 0x0e79b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtmu v0.4h, v1.4h"), 0x2e79b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtas v0.4h, v1.4h"), 0x0e79c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtau v0.4h, v1.4h"), 0x2e79c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtps v0.4h, v1.4h"), 0x0ef9a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtpu v0.4h, v1.4h"), 0x2ef9a820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzs v0.4h, v1.4h"), 0x0ef9b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcvtzu v0.4h, v1.4h"), 0x2ef9b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("scvtf v0.4h, v1.4h"), 0x0e79d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("ucvtf v0.8h, v1.8h"), 0x6e79d820)
        // Compare against #0.0.
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmeq v0.4h, v1.4h, #0.0"), 0x0ef8d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmge v0.4h, v1.4h, #0.0"), 0x2ef8c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmgt v0.4h, v1.4h, #0.0"), 0x0ef8c820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmle v0.4h, v1.4h, #0.0"), 0x2ef8d820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("fcmlt v0.4h, v1.4h, #0.0"), 0x0ef8e820)
    }

    func testDisassembleVectorTwoRegisterMiscFP16() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0ef8f820), "fabs v0.4h, v1.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x6ef9f820), "fsqrt v0.8h, v1.8h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e798820), "frintn v0.4h, v1.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0ef9d820), "frecpe v0.4h, v1.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0e79d820), "scvtf v0.4h, v1.4h")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0x0ef8c820), "fcmgt v0.4h, v1.4h, #0.0")
    }

    func testVectorTwoRegisterMiscFP16RoundTrip() throws {
        let sources = [
            "fabs v2.4h, v3.4h", "fneg v4.8h, v5.8h", "fsqrt v6.4h, v7.4h",
            "frintn v8.4h, v9.4h", "frintm v10.8h, v11.8h", "frintp v12.4h, v13.4h",
            "frintz v14.4h, v15.4h", "frinta v16.4h, v17.4h", "frintx v18.8h, v19.8h",
            "frinti v20.4h, v21.4h", "frecpe v22.4h, v23.4h", "frsqrte v24.8h, v25.8h",
            "fcvtns v26.4h, v27.4h", "fcvtnu v28.4h, v29.4h", "fcvtms v30.4h, v31.4h",
            "fcvtmu v0.8h, v1.8h", "fcvtas v2.4h, v3.4h", "fcvtau v4.4h, v5.4h",
            "fcvtps v6.4h, v7.4h", "fcvtpu v8.4h, v9.4h", "fcvtzs v10.4h, v11.4h",
            "fcvtzu v12.4h, v13.4h", "scvtf v14.8h, v15.8h", "ucvtf v16.4h, v17.4h",
            "fcmeq v18.4h, v19.4h, #0.0", "fcmge v20.4h, v21.4h, #0.0",
            "fcmgt v22.4h, v23.4h, #0.0", "fcmle v24.4h, v25.4h, #0.0",
            "fcmlt v26.8h, v27.8h, #0.0",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testVectorTwoRegisterMiscFP16InvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fabs v0.2h, v1.2h"))         // .2h not a valid arrangement
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("fsqrt v0.4h, v1.8h"))        // arrangement mismatch
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("scvtf v0.4h, v1.4s"))        // arrangement mismatch
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

    func testCryptoSHA512SM3SM4Instructions() throws {
        // SHA512 three-register and two-register.
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha512h q0, q1, v2.2d"), 0xce628020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha512h2 q0, q1, v2.2d"), 0xce628420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha512su1 v0.2d, v1.2d, v2.2d"), 0xce628820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sha512su0 v0.2d, v1.2d"), 0xcec08020)
        // SM4.
        XCTAssertEqual(try ARM64Assembler.assembleWord("sm4e v0.4s, v1.4s"), 0xcec08420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sm4ekey v0.4s, v1.4s, v2.4s"), 0xce62c820)
        // SM3 three-register and four-register.
        XCTAssertEqual(try ARM64Assembler.assembleWord("sm3partw1 v0.4s, v1.4s, v2.4s"), 0xce62c020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sm3partw2 v0.4s, v1.4s, v2.4s"), 0xce62c420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sm3ss1 v0.4s, v1.4s, v2.4s, v3.4s"), 0xce420c20)
        // SM3 imm2-indexed.
        XCTAssertEqual(try ARM64Assembler.assembleWord("sm3tt1a v0.4s, v1.4s, v2.s[3]"), 0xce42b020)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sm3tt1b v0.4s, v1.4s, v2.s[3]"), 0xce42b420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sm3tt2a v0.4s, v1.4s, v2.s[3]"), 0xce42b820)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sm3tt2b v0.4s, v1.4s, v2.s[3]"), 0xce42bc20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("sm3tt1a v0.4s, v1.4s, v2.s[0]"), 0xce428020)
    }

    func testDisassembleCryptoSHA512SM3SM4() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xce628020), "sha512h q0, q1, v2.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xce628820), "sha512su1 v0.2d, v1.2d, v2.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xcec08420), "sm4e v0.4s, v1.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xce420c20), "sm3ss1 v0.4s, v1.4s, v2.4s, v3.4s")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xce42bc20), "sm3tt2b v0.4s, v1.4s, v2.s[3]")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xce62c820), "sm4ekey v0.4s, v1.4s, v2.4s")
    }

    func testCryptoSHA512SM3SM4RoundTrip() throws {
        let sources = [
            "sha512h q5, q6, v7.2d", "sha512h2 q8, q9, v10.2d",
            "sha512su1 v11.2d, v12.2d, v13.2d", "sha512su0 v14.2d, v15.2d",
            "sm4e v16.4s, v17.4s", "sm4ekey v18.4s, v19.4s, v20.4s",
            "sm3partw1 v21.4s, v22.4s, v23.4s", "sm3partw2 v24.4s, v25.4s, v26.4s",
            "sm3ss1 v27.4s, v28.4s, v29.4s, v30.4s",
            "sm3tt1a v0.4s, v1.4s, v2.s[1]", "sm3tt1b v3.4s, v4.4s, v5.s[2]",
            "sm3tt2a v6.4s, v7.4s, v8.s[0]", "sm3tt2b v9.4s, v10.4s, v11.s[3]",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testCryptoSHA512SM3SM4InvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sha512h v0.2d, q1, v2.2d"))   // dest must be Q
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sha512su0 v0.4s, v1.4s"))     // must be .2d
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sm4e v0.2d, v1.2d"))          // must be .4s
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sm3tt1a v0.4s, v1.4s, v2.s[4]"))  // index 0-3
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("sm3tt1a v0.4s, v1.4s, v2.h[1]"))  // element must be .s
    }

    func testCryptoSHA3Instructions() throws {
        // Four-register SHA3.
        XCTAssertEqual(try ARM64Assembler.assembleWord("eor3 v0.16b, v1.16b, v2.16b, v3.16b"), 0xce020c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("bcax v0.16b, v1.16b, v2.16b, v3.16b"), 0xce220c20)
        XCTAssertEqual(try ARM64Assembler.assembleWord("eor3 v5.16b, v6.16b, v7.16b, v8.16b"), 0xce0720c5)
        // Three-register RAX1.
        XCTAssertEqual(try ARM64Assembler.assembleWord("rax1 v0.2d, v1.2d, v2.2d"), 0xce628c20)
        // XAR with imm6.
        XCTAssertEqual(try ARM64Assembler.assembleWord("xar v0.2d, v1.2d, v2.2d, #1"), 0xce820420)
        XCTAssertEqual(try ARM64Assembler.assembleWord("xar v0.2d, v1.2d, v2.2d, #63"), 0xce82fc20)
    }

    func testDisassembleCryptoSHA3() throws {
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xce020c20), "eor3 v0.16b, v1.16b, v2.16b, v3.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xce220c20), "bcax v0.16b, v1.16b, v2.16b, v3.16b")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xce628c20), "rax1 v0.2d, v1.2d, v2.2d")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xce820420), "xar v0.2d, v1.2d, v2.2d, #1")
        XCTAssertEqual(try ARM64Assembler.disassembleWord(0xce82fc20), "xar v0.2d, v1.2d, v2.2d, #63")
    }

    func testCryptoSHA3RoundTrip() throws {
        let sources = [
            "eor3 v10.16b, v11.16b, v12.16b, v13.16b",
            "bcax v14.16b, v15.16b, v16.16b, v17.16b",
            "rax1 v18.2d, v19.2d, v20.2d",
            "xar v21.2d, v22.2d, v23.2d, #0",
            "xar v24.2d, v25.2d, v26.2d, #31",
            "xar v27.2d, v28.2d, v29.2d, #63",
        ]
        for source in sources {
            let word = try ARM64Assembler.assembleWord(source)
            let text = try ARM64Assembler.disassembleWord(word)
            XCTAssertEqual(text, source)
            XCTAssertEqual(try ARM64Assembler.assembleWord(text), word)
        }
    }

    func testCryptoSHA3InvalidInputsThrow() throws {
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("eor3 v0.8b, v1.8b, v2.8b, v3.8b"))   // must be .16b
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("rax1 v0.4s, v1.4s, v2.4s"))          // must be .2d
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("xar v0.2d, v1.2d, v2.2d, #64"))      // imm6 0-63
        XCTAssertThrowsError(try ARM64Assembler.assembleWord("xar v0.16b, v1.16b, v2.16b, #1"))    // must be .2d
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
