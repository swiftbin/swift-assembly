// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-assembler",
    products: [
        .library(
            name: "Assembler",
            targets: ["Assembler"]
        ),
    ],
    targets: [
        .target(
            name: "Assembler"
        ),
        .testTarget(
            name: "AssemblerTests",
            dependencies: ["Assembler"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
