// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BioSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "BioSDK",
            targets: ["BioSDK"]
        ),
        .library(
            name: "BioUI",
            targets: ["BioUI"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "BioSDK",
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.45/BioSDK.xcframework.zip",
            checksum: "c423f6d33797e074a1a1f125e0d45356a90e69c139afda1c513eb8670d3fedd6"
        ),
        .target(
            name: "BioUI",
            dependencies: ["BioSDK"],
            path: "Sources/BioUI"
        )
    ]
)
