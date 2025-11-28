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
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.31.0")
    ],
    targets: [
        .binaryTarget(
            name: "BioSDK",
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.20/BioSDK.xcframework.zip",
            checksum: "317ec0069839ef445108353fc90af5f1fb8d20dd5a8389b135b3e0219ddabd3e"
        ),
        .target(
            name: "BioUI",
            dependencies: [
                "BioSDK",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Sources/BioUI"
        )
    ]
)
