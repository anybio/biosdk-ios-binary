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
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.43/BioSDK.xcframework.zip",
            checksum: "b5a423b52a3d31bca4c997b8d389b36099620cc4ac0c76d4bf3afed1b10fbf9b"
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
