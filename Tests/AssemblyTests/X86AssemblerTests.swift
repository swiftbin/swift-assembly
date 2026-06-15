import XCTest
@testable import Assembly

final class X86AssemblerTests: XCTestCase {
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
}
