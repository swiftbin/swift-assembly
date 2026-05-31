// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-assembly",
    products: [
        .library(
            name: "Assembly",
            targets: ["Assembly"]
        ),
    ],
    targets: [
        .target(
            name: "Assembly"
        ),
        .testTarget(
            name: "AssemblyTests",
            dependencies: ["Assembly"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
