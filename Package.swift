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
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.34/BioSDK.xcframework.zip",
            checksum: "63e935879d4c860e9a432b3ce05b23c6cb5881daa7c156b2b297856a3bf03f31"
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
