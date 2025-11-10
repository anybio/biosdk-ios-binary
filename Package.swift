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
        .binaryTarget(name: "BioSDKBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.14/BioSDK.xcframework.zip", checksum: "ada7154809104b0b8a3a0275de6ae8b05a4fa1ddc3f2ee4fabdd4712e408375c"),
        .binaryTarget(name: "BioSDKCoreBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.14/BioSDKCore.xcframework.zip", checksum: "714f6f6a04fc3823ec11d1dd6fc7b5b961adcf2897d1690c699b87ef4a81cb3c"),
        .binaryTarget(name: "BioBLEBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.14/BioBLE.xcframework.zip", checksum: "164fcdab5e371f92bf8cccb22077d32f85bf3569def6d0697f386ff39cc26d1b"),
        .binaryTarget(name: "BioIngestBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.14/BioIngest.xcframework.zip", checksum: "ba6b73257568bf2681a22425c4f6454de35920d3896f6f6e2b884f298ad7d3cf"),
        .binaryTarget(name: "BioUIBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.14/BioUI.xcframework.zip", checksum: "256d32a2c6b285815ae332dc37c0c30df5c4c30a6e7391244e385434a0929a4a"),

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
