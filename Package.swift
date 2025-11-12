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
        .binaryTarget(name: "BioSDKBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.22/BioSDK.xcframework.zip", checksum: "938e7bc40c0f0f903ed7dff67f973b14b9b851385641687d7918f08734831587"),
        .binaryTarget(name: "BioSDKCoreBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.22/BioSDKCore.xcframework.zip", checksum: "dbeb422b6a9912de4d2ba5ceaf258b58e63bf8ce3ce593a9ff95bab0b235443d"),
        .binaryTarget(name: "BioBLEBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.22/BioBLE.xcframework.zip", checksum: "6d4acdeaf8fc8e12a2efa7c907d5a3205a3a6eb58397023200ee0495ce603ef4"),
        .binaryTarget(name: "BioIngestBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.22/BioIngest.xcframework.zip", checksum: "73be77bfcd656b4c484da55a31e29861c6f30c8b30f5367b98bb97709cf90795"),
        .binaryTarget(name: "BioUIBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.22/BioUI.xcframework.zip", checksum: "2ae015a1fde78f34dc0deca1585903989907dfdbe27c37105345ba728d70ba64"),

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
