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
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.31/BioSDK.xcframework.zip",
            checksum: "79741d0fbaa0c636a148a52a5062b31d411a550b4387a07022f043ccd1f155c4"
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
