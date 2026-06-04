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
- Advanced SIMD two-register misc (rev64 / rev32 / rev16 / abs / neg / mvn / rbit / cnt / cls / clz / sqabs / sqneg / suqadd / usqadd / fabs / fneg / fsqrt)
- Advanced SIMD three-same (add / sub / mul / and / orr / eor / bic / orn / bsl / cmeq / cmgt / smax / umin / sshl / sqadd / sqdmulh / fadd / fsub / fmul / fdiv / fmla / fcmeq / frecps / ...)
- Advanced SIMD shift by immediate (sshr / ushr / ssra / usra / srshr / sri / shl / sli / sqshl / sqshlu / shrn(2) / rshrn(2) / sqshrn(2) / sqshrun(2) / uqshrn(2) / sshll(2) / ushll(2) / sxtl(2) / uxtl(2) / scvtf / ucvtf / fcvtzs / fcvtzu)
- Advanced SIMD modified immediate (movi / mvni / orr / bic / fmov, with lsl / msl shifts and the 64-bit movi forms)
- Advanced SIMD copy (dup from element / general register, smov / umov, ins from element / general register, and the mov aliases)
- Advanced SIMD permute (zip1 / zip2 / uzp1 / uzp2 / trn1 / trn2) and extract (ext)
- Advanced SIMD three-different (saddl(2) / ssubl / saddw / addhn(2) / subhn / sabal / sabdl / smlal / smlsl / smull(2) / pmull(2) including the 64→128 polynomial `.1q` form / sqdmull / sqdmlal / sqdmlsl and the unsigned / rounding variants)
- Advanced SIMD dot product (sdot / udot) in both the vector (`.2s/.4s, .8b/.16b`) and by-element (`.4b[index]`) forms
- Advanced SIMD saturating rounding multiply-accumulate (sqrdmlah / sqrdmlsh) in the vector, scalar, and by-element forms
- Advanced SIMD complex number arithmetic (fcadd with #90/#270 rotation, fcmla with #0/#90/#180/#270 in both the vector and by-element forms)
- Advanced SIMD FP16→FP32 widening multiply-accumulate (fmlal / fmlal2 / fmlsl / fmlsl2) in both the vector (`.2s/.4s, .2h/.4h`) and by-element (`.h[index]`) forms
- BFloat16 (bfdot in vector and `.2h[index]` forms, bfmlalb / bfmlalt in vector and `.h[index]` forms, bfmmla)
- BFloat16 convert (bfcvtn / bfcvtn2, FP32 `.4s` → BF16 `.4h` / `.8h` narrowing)
- Advanced SIMD half-precision three-same (FP16) arithmetic and compares on `.4h`/`.8h` (fadd / fsub / fmul / fdiv / fmla / fmls / fmax / fmin / fmaxnm / fminnm / fmulx / fcmeq / fcmge / fcmgt / facge / facgt / frecps / frsqrts / fabd / faddp / fmaxp / fminp / fmaxnmp / fminnmp)
- Advanced SIMD half-precision (FP16) by-element fmla / fmls / fmul / fmulx in both the vector (`.4h`/`.8h`, `Vm.h[index]`) and scalar (`h0, h1, Vm.h[index]`) forms
- Advanced SIMD vector x indexed element (mul / mla / mls / sqdmulh / sqrdmulh / fmul / fmla / fmls / fmulx and the long smull(2) / umull / smlal / umlsl / sqdmull / sqdmlal(2) / sqdmlsl forms)
- Advanced SIMD scalar three-same (add / sub / cmeq / cmge / cmgt / cmhi / cmhs / cmtst / sqadd / uqadd / sqsub / uqsub / sshl / ushl / srshl / urshl / sqshl / uqshl / sqrshl / uqrshl / sqdmulh / sqrdmulh)
- Advanced SIMD scalar pairwise reductions (addp / faddp / fmaxp / fminp / fmaxnmp / fminnmp)
- Advanced SIMD scalar two-register misc (abs / neg / sqabs / sqneg / suqadd / usqadd and the compare-against-zero cmeq / cmge / cmgt / cmle / cmlt)
- Advanced SIMD scalar shift by immediate (sshr / ushr / ssra / usra / srshr / urshr / srsra / ursra / sri / shl / sli / sqshl / uqshl / sqshlu — double-width forms)
- Advanced SIMD scalar three different (sqdmlal / sqdmlsl / sqdmull — long saturating-doubling forms)
- Advanced SIMD scalar x indexed element (sqdmlal / sqdmlsl / sqdmull / sqdmulh / sqrdmulh / fmul / fmla / fmls / fmulx)
- Advanced SIMD scalar copy (dup / mov from a vector element to a scalar FP register)
- Advanced SIMD scalar FP two-register misc (fcvtns / fcvtnu / fcvtms / fcvtmu / fcvtas / fcvtau / fcvtps / fcvtpu / fcvtzs / fcvtzu / scvtf / ucvtf / frecpe / frsqrte / frecpx / fcvtxn and the compare-against-#0.0 fcmeq / fcmge / fcmgt / fcmle / fcmlt)
- Advanced SIMD scalar FP three-same (fmulx / fcmeq / fcmge / fcmgt / facge / facgt / frecps / frsqrts / fabd)
- Advanced SIMD scalar shift by immediate, narrowing (sqshrn / sqrshrn / uqshrn / uqrshrn / sqshrun / sqrshrun)
- Advanced SIMD scalar two-register misc, saturating extract-narrow (sqxtn / uqxtn / sqxtun)
- Advanced SIMD scalar shift by immediate, fixed-point convert (scvtf / ucvtf / fcvtzs / fcvtzu with #fbits)
- SIMD&FP load/store register (ldr / str / ldur / stur of b/h/s/d/q) and pair (ldp / stp of s/d/q), with all addressing modes
- Advanced SIMD load/store multiple structures (ld1–ld4 / st1–st4) with brace-delimited register lists and the `[Xn]`, `[Xn], #imm`, `[Xn], Xm` addressing forms
- Advanced SIMD load/store single structure and replicate (ld1r–ld4r, and the single-lane ld1–ld4 / st1–st4 `{v0.s}[1]` forms) with all addressing modes
- Advanced SIMD table lookup (tbl / tbx) with 1–4 register table lists
- Advanced SIMD two-register-misc compare against zero (cmgt / cmeq / cmlt / cmge / cmle vs #0, and fcmgt / fcmeq / fcmlt / fcmge / fcmle vs #0.0)
- Advanced SIMD two-register-misc extract-narrow (xtn(2) / sqxtn(2) / uqxtn(2) / sqxtun(2))
- Advanced SIMD two-register-misc floating-point ↔ integer convert (fcvtns / fcvtnu / fcvtps / fcvtpu / fcvtms / fcvtmu / fcvtzs / fcvtzu / fcvtas / fcvtau / scvtf / ucvtf)
- Advanced SIMD two-register-misc pairwise long add and accumulate (saddlp / uaddlp / sadalp / uadalp)
- Advanced SIMD two-register-misc floating-point rounding and reciprocal estimates (frintn / frintm / frintp / frintz / frinta / frintx / frinti / frecpe / frsqrte / urecpe / ursqrte)
- Advanced SIMD two-register-misc floating-point precision converts (fcvtn(2) / fcvtl(2) / fcvtxn(2))
- Cryptographic AES single-round instructions (aese / aesd / aesmc / aesimc)
- Cryptographic SHA1/SHA256 instructions (sha1c / sha1p / sha1m / sha1su0 / sha256h / sha256h2 / sha256su1 / sha1h / sha1su1 / sha256su0)
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
