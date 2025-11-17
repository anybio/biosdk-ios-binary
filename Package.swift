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
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.1/BioSDK.xcframework.zip",
            checksum: "c874982a73eea0abdfb66a4d4113e694ffc0f46d5219ef026a0fc1de86cffe24"
        )
    ]
)
