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
        .binaryTarget(name: "BioSDKBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.4/BioSDK.xcframework.zip", checksum: "9068249213fb70a93cc3fcc67ccd659031755a6c2998040e8dd4cda4450bd7a0"),
        .binaryTarget(name: "BioSDKCoreBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.4/BioSDKCore.xcframework.zip", checksum: "0aaa4761bf4231a9d036c42f1d2f511881d2b1bbdf3786ee4789b44bb9c3e647"),
        .binaryTarget(name: "BioBLEBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.4/BioBLE.xcframework.zip", checksum: "e3e83b18fc4b82295f359a6fe81ddb70a0e0ab1c2c4ddcfd0bd0dbbbdfdfd721"),
        .binaryTarget(name: "BioIngestBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.4/BioIngest.xcframework.zip", checksum: "2db460a7d8ad95a3fe09b6ee46ce9d4b43a98d1692faf0ffab58ce3edecd1ede"),
        .binaryTarget(name: "BioUIBinary", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.4/BioUI.xcframework.zip", checksum: "ee05ae18bca6bb138a98e3acaed28132b4234ef1a0d6125603b81fe91802fbed"),

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
