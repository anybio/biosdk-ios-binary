// swift-tools-version: 5.9
import PackageDescription

// Binary distribution of BioSDK. This manifest expects prebuilt .xcframeworks
// in the Artifacts/ directory for local testing. For release, replace the
// .binaryTarget path definitions with (url, checksum) pairs as noted below.

let package = Package(
    name: "BioSDK",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        // Primary product that includes all binary frameworks and dependencies
        .library(name: "BioSDK", targets: ["BioSDKWrapper"])
    ],
    dependencies: [
        // External dependencies must be provided by the consumer when linking
        // the binary frameworks, to satisfy transitive symbols. Pin versions to
        // those used to build the binaries.
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.31.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
    ],
    targets: [
        // Binary targets containing the prebuilt XCFrameworks
        .binaryTarget(name: "BioSDKBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.17/BioSDK.xcframework.zip", checksum: "8f384786a11e070c62761de68603038a606540c2218f5258273a3e0dfc70c7a8"),
        .binaryTarget(name: "BioSDKCoreBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.17/BioSDKCore.xcframework.zip", checksum: "092231c2def7b90f7c628be1dd6eb8138455b74ac7de49cfe3ecb8b2d31bf67d"),
        .binaryTarget(name: "BioBLEBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.17/BioBLE.xcframework.zip", checksum: "c0f9cc05ba64b2925715950e3a246a2d5fc06d303ed6f360303a7671befbf871"),
        .binaryTarget(name: "BioIngestBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.17/BioIngest.xcframework.zip", checksum: "34b62deb8351c53d6088e211b4706a4988ce9e893541fafee53142310e083034"),
        .binaryTarget(name: "BioUIBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.17/BioUI.xcframework.zip", checksum: "d285dc2803fb4fdbc27a1ba625e3ebe063ea4c098b986091b9e90eee6d5efa3b"),

        // Wrapper target that aggregates all binaries and dependencies without re-exporting
        .target(
            name: "BioSDKWrapper",
            dependencies: [
                "BioSDKCoreBinary",
                "BioBLEBinary",
                "BioIngestBinary",
                "BioSDKBinary",
                "BioUIBinary",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Aggregators/BioSDKWrapper"
        )
    ]
)
