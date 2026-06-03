# swift-assembly

Library for assembling and disassembling ARM64 (AArch64) machine code.

In addition to turning assembly text into raw bytes, the reverse direction — decoding machine words back into assembly — is also supported, so instructions round-trip between the two representations.

<!-- # Badges -->

[![Github issues](https://img.shields.io/github/issues/swiftbin/swift-assembly)](https://github.com/swiftbin/swift-assembly/issues)
[![Github forks](https://img.shields.io/github/forks/swiftbin/swift-assembly)](https://github.com/swiftbin/swift-assembly/network/members)
[![Github stars](https://img.shields.io/github/stars/swiftbin/swift-assembly)](https://github.com/swiftbin/swift-assembly/stargazers)
[![Github top language](https://img.shields.io/github/languages/top/swiftbin/swift-assembly)](https://github.com/swiftbin/swift-assembly/)

## Features

- assemble ARM64 assembly text into machine code
- disassemble machine code back into assembly text
- move (wide / immediate / register aliases)
- add / sub, compare (cmp / cmn)
- logical (and / orr / eor / bic / orn / ...) and mvn
- shifts (lsl / lsr / asr), extract and rotate (extr / ror)
- multiply / divide (mul / madd / msub / udiv / sdiv)
- load / store (single and pair, including pre/post-indexed)
- branches, labels, and address generation (adr / adrp)
- pointer authentication on arm64e (paciasp / xpaci / ...)
- scalar floating-point (fmov / fadd / fsub / fmul / fdiv / fabs / fneg / fsqrt / fcmp / fcvt / scvtf / fcvtzs / ...)
- Advanced SIMD across-lanes reductions (addv / saddlv / uaddlv / smaxv / umaxv / sminv / uminv / fmaxv / fminv / fmaxnmv / fminnmv)
- Advanced SIMD two-register misc (rev64 / rev32 / rev16 / abs / neg / mvn / rbit / cnt / cls / clz / sqabs / sqneg / fabs / fneg / fsqrt)
- Advanced SIMD three-same (add / sub / mul / and / orr / eor / bic / orn / bsl / cmeq / cmgt / smax / umin / sshl / sqadd / sqdmulh / fadd / fsub / fmul / fdiv / fmla / fcmeq / frecps / ...)
- Advanced SIMD shift by immediate (sshr / ushr / ssra / usra / srshr / sri / shl / sli / sqshl / sqshlu / shrn(2) / rshrn(2) / sqshrn(2) / sqshrun(2) / uqshrn(2) / sshll(2) / ushll(2) / sxtl(2) / uxtl(2) / scvtf / ucvtf / fcvtzs / fcvtzu)
- Advanced SIMD modified immediate (movi / mvni / orr / bic / fmov, with lsl / msl shifts and the 64-bit movi forms)
- Advanced SIMD copy (dup from element / general register, smov / umov, ins from element / general register, and the mov aliases)
- Advanced SIMD permute (zip1 / zip2 / uzp1 / uzp2 / trn1 / trn2) and extract (ext)
- Advanced SIMD three-different (saddl(2) / ssubl / saddw / addhn(2) / subhn / sabal / sabdl / smlal / smlsl / smull(2) / pmull(2) / sqdmull / sqdmlal / sqdmlsl and the unsigned / rounding variants)
- Advanced SIMD vector x indexed element (mul / mla / mls / sqdmulh / sqrdmulh / fmul / fmla / fmls / fmulx and the long smull(2) / umull / smlal / umlsl / sqdmull / sqdmlal(2) / sqdmlsl forms)
- ...

## Usage

The entry point is the `ARM64Assembler` enum. All operations are static, so there is no instance to create.

### Assemble

To assemble a single instruction into a 32-bit word, use `assembleWord`.

```swift
import Assembler

let word = try ARM64Assembler.assembleWord("movz x0, #1")
// 0xd2800020
```

A multi-line program, with labels and comments, can be assembled into raw bytes with `assemble`.

```swift
let source = """
loop:
    subs x0, x0, #1   // decrement
    b.ne loop
    ret
"""

let bytes = try ARM64Assembler.assemble(source)
```

When you only need the encoded words rather than a byte buffer, use `assembleWords`.

```swift
let words = try ARM64Assembler.assembleWords(source)
```

### Disassemble

To decode a single machine word into its assembly text, use `disassembleWord`.

```swift
let text = try ARM64Assembler.disassembleWord(0xd2800020)
// "movz x0, #1"
```

A byte buffer can be disassembled into a newline-separated listing with `disassemble`, or into an array of strings with `disassembleWords`.

```swift
let listing = try ARM64Assembler.disassemble(bytes)
let lines = try ARM64Assembler.disassembleWords(words)
```

### arm64e

Pointer authentication instructions are gated behind the `arm64e` architecture. Pass it explicitly when assembling them.

```swift
let word = try ARM64Assembler.assembleWord("paciasp", architecture: .arm64e)
```

### Endianness

Both `assemble` and `disassemble` default to little-endian byte order. Pass `.big` to override it.

```swift
let bytes = try ARM64Assembler.assemble(source, endianness: .big)
```

### Error handling

Every operation can throw `AssemblerError`. It conforms to `Error`, `Equatable`, and `CustomStringConvertible`, so failures can be matched against specific cases or surfaced as a human-readable message.

```swift
do {
    _ = try ARM64Assembler.assembleWord("movz x0, #1")
} catch let error as AssemblerError {
    print(error.description)
}
```

Because it is `Equatable`, a particular failure can also be matched directly.

```swift
catch AssemblerError.unknownInstruction(let mnemonic) {
    // an unsupported or misspelled mnemonic
}
```

## Installation

### SwiftPM

Add the following to the dependencies of your `Package.swift`.

```swift
.package(url: "https://github.com/swiftbin/swift-assembly.git", from: "0.0.1")
```

## License

swift-assembly is released under the MIT License. See [LICENSE](./LICENSE)
