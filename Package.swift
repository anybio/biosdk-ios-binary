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
        // Aggregated SDK product: import BioSDK to get everything.
        .library(name: "BioSDK", targets: ["BioKit"]),
        // Also expose individual module products for advanced users.
        .library(name: "BioSDKCore", targets: ["BioSDKCore"]),
        .library(name: "BioBLE", targets: ["BioBLE"]),
        .library(name: "BioIngest", targets: ["BioIngest"]),
        .library(name: "BioUI", targets: ["BioUI"])    
    ],
    dependencies: [
        // External dependencies must be provided by the consumer when linking
        // the binary frameworks, to satisfy transitive symbols. Pin versions to
        // those used to build the binaries.
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.31.0"),
        .package(url: "https://github.com/nicklockwood/Expression.git", from: "0.13.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
    ],
    targets: [
        // LOCAL DEV: path-based binary targets pointing at built artifacts.
        // RELEASE: replace with .binaryTarget(name:url:checksum:) using your
        // uploaded GitHub Release asset URLs and checksums printed by the build script.
        .binaryTarget(name: "BioSDKCore", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.0/BioSDKCore.xcframework.zip", checksum: "8d1ac64e0b5f35ceb53632b1c45728e67e4fe52dfdd62aa41a19395c1f3415e8"),
        .binaryTarget(name: "BioBLE", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.0/BioBLE.xcframework.zip", checksum: "a1cc081519bdef482e1c1abceffccc2dbb29c00c57112a54aba1f8ee025bdfa0"),
        .binaryTarget(name: "BioIngest", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.0/BioIngest.xcframework.zip", checksum: "b75b0ad78b915c7978865cf579e34d3592b725bc13ec5872f0e1cb8a22619dd1"),
        .binaryTarget(name: "BioSDK", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.0/BioSDK.xcframework.zip", checksum: "1973e6ddaa0aa2d5e17083469df211b4fbd2a4036c0b62b610b0fa73ee6f1173"),
        .binaryTarget(name: "BioUI", url: "https://github.com/anybio/biosdk-ios-binary/releases/download/v1.0.0/BioUI.xcframework.zip", checksum: "e6c96cc066c0e585375ce92513a21bdf685fa6891844858ac41de74187b35a31"),
        
	// Aggregator target that pulls in all modules and re-exports them.
        // This contains only a small Swift shim and no proprietary source.
        .target(
            name: "BioKit",
            dependencies: [
                // Binary frameworks
                "BioSDKCore", "BioBLE", "BioIngest", "BioSDK", "BioUI",
                // Third-party products to satisfy link-time dependencies
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Expression", package: "Expression"),
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Aggregators/BioKit"
        )
    ]
)
