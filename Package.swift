// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BioSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "BioSDK",
            targets: ["BioSDK"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "BioSDK",
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.0/BioSDK.xcframework.zip",
            checksum: "1ec0096c90919c3f7df7d89ee924181e23a6017df1b814dbf14cfc6936c0279b"
        )
    ]
)
