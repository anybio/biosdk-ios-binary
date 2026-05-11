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
    targets: [
        .binaryTarget(
            name: "BioSDK",
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.49/BioSDK.xcframework.zip",
            checksum: "c765fe3a2062a7c69e64d9ca0a9afdebcd03e3059a086d9b2dad8a002cd330cf"
        ),
        .target(
            name: "BioUI",
            dependencies: ["BioSDK"],
            path: "Sources/BioUI"
        )
    ]
)
