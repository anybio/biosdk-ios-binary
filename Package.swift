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
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.53/BioSDK.xcframework.zip",
            checksum: "b0189ad763be3248e1abdbd5adce77f14fb74439e752a2ecc57c04eaa770764c"
        ),
        .target(
            name: "BioUI",
            dependencies: ["BioSDK"],
            path: "Sources/BioUI"
        )
    ]
)
