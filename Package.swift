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
            url: "https://github.com/anybio/biosdk-ios-binary/releases/download/1.0.5/BioSDK.xcframework.zip",
            checksum: "a35dadf25fbe04569f8d42e92bd97035b5d8262d3b565c18d93606f8d2b722f5"
        ),
        .target(
            name: "BioUI",
            dependencies: ["BioSDK"],
            path: "Sources/BioUI"
        )
    ]
)
