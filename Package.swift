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
        .binaryTarget(name: "BioSDKCore", path: "Artifacts/BioSDKCore.xcframework"),
        .binaryTarget(name: "BioBLE", path: "Artifacts/BioBLE.xcframework"),
        .binaryTarget(name: "BioIngest", path: "Artifacts/BioIngest.xcframework"),
        .binaryTarget(name: "BioSDK", path: "Artifacts/BioSDK.xcframework"),
        .binaryTarget(name: "BioUI", path: "Artifacts/BioUI.xcframework"),
        
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
