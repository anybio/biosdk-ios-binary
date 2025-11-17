// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BioSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "BioSDK",
            targets: ["BioSDK"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "BioSDK",
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.0/BioSDK.xcframework.zip",
            checksum: "ab7cc581e7fe6cc7f1f42a7920c65d812dda39564c9c569e7575777b70fd7f1e"
        )
    ]
)
