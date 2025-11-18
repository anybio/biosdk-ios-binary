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
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.3/BioSDK.xcframework.zip",
            checksum: "f72efb35493c1cf970294777e689f12812dc2732afc80b4a34110c770e4fed79"
        )
    ]
)
