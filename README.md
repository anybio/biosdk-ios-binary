# BioSDK Binary Distribution

Binary distribution of BioSDK for iOS via Swift Package Manager.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/anybio/biosdk-ios-binary.git", from: "1.0.0")
]
```

Or add via Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/anybio/biosdk-ios-binary.git`
3. Select version `1.0.0` or later

## Usage

```swift
import BioSDK

// Initialize SDK
let sdk = BioSDKClient(configuration: .auto(
    organizationKey: "your-org-key",
    projectKey: "your-project-key"
))

// Start scanning for devices
sdk.startScan()

// Connect to a device
sdk.connect(device)

// Start streaming
try await sdk.startBackendSession(for: xUserId) { result in
    switch result {
    case .success(let sessionId):
        print("Session started: \(sessionId)")
    case .failure(let disposition):
        print("Session conflict or error: \(disposition)")
    }
}
```

## What's Included

This package provides a single unified `BioSDK.xcframework` containing:

- **BioSDKCore** - Core models and protocols
- **BioBLECore** - Objective-C BLE layer (XCFramework-safe)
- **BioBLE** - Swift BLE management
- **BioIngest** - HTTP streaming clients
- **BioSDK** - Main SDK orchestration
- **BioUI** - Optional SwiftUI components

All modules are bundled together for maximum compatibility and ease of use.

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Architecture

This binary distribution uses an umbrella framework approach to avoid Swift ABI stability issues across XCFramework module boundaries. All BLE operations use Objective-C bridging for maximum compatibility.

## License

Proprietary - © AnyBio, Inc.
