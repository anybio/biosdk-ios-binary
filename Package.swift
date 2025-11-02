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
        .binaryTarget(name: "BioSDKBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.7/BioSDK.xcframework.zip", checksum: "d2702d17850f642178dcc90841744566dc0719778b892bb60e35107df82c9868"),
        .binaryTarget(name: "BioSDKCoreBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.7/BioSDKCore.xcframework.zip", checksum: "8b4763b79a7a24ea417bff78a1ad70d400dd395e02fed477e4f7eb9cf9f893b5"),
        .binaryTarget(name: "BioBLEBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.7/BioBLE.xcframework.zip", checksum: "af8ef9defd84ce1fae20655b5a98477bdf655365d1c1285086fcd11c9bb97f4a"),
        .binaryTarget(name: "BioIngestBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.7/BioIngest.xcframework.zip", checksum: "ca6891274ec8e5769ced0c7e93c661b99bc58c05105c44e949f24b43c5beb187"),
        .binaryTarget(name: "BioUIBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.7/BioUI.xcframework.zip", checksum: "0798962aa8f9260707b26f3f1ff4beaf3a9bf9c91dfc50212b6839c509db0f36"),

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
