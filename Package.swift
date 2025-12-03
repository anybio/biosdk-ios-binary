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
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.39/BioSDK.xcframework.zip",
            checksum: "a53e94be9c2556101e42ed728fcac7c985147ba45afe39d63ed5f320d94288e1"
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
