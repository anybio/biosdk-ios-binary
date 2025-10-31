# BioSDK Binary Distribution (Dynamic)

This folder contains the Swift Package manifest for distributing the BioSDK as prebuilt dynamic XCFrameworks. It is set up for local testing with path-based binary targets, and for release via GitHub (or any HTTPS host) using URL + checksum.

What you get
- Dynamic XCFrameworks for: BioSDKCore, BioBLE, BioIngest, BioSDK, BioUI
- A convenience aggregator module: BioKit (add the product named "BioSDK" and import BioKit)
- No source code disclosed in the binary package

Prerequisites
- Xcode 14+
- iOS 16+ target (can be widened later)

Compatibility modes (library evolution)
- Default build disables Swift library evolution to avoid third‑party module interface verification issues during Release builds.
- To enable Swift library evolution (emits .swiftinterface for better cross‑toolchain compatibility), set an environment toggle:

```bash
# Default (safer with some dependencies): no library evolution
LIB_EVOLUTION=0 ./BioSDK/scripts/build_xcframeworks.sh

# Enable library evolution (recommended once all dependencies verify cleanly)
LIB_EVOLUTION=1 ./BioSDK/scripts/build_xcframeworks.sh
```

Build locally (device + simulator)
From the repo root or BioSDK/:

```bash
# Default build (no library evolution)
chmod +x BioSDK/scripts/build_xcframeworks.sh
./BioSDK/scripts/build_xcframeworks.sh
```

Artifacts produced
- BioSDK/BinaryDistribution/Artifacts/*.xcframework
- BioSDK/BinaryDistribution/Artifacts/*.xcframework.zip
- Checksums printed to the terminal

Local consumption (without publishing)
In your app, add a local package dependency pointing to this folder:
- Xcode → Project → Package Dependencies → + → Add Local… → select BioSDK/BinaryDistribution
- Add the product named "BioSDK" to your app target (this maps to module BioKit)
- In code:

```swift
import BioKit // re-exports BioSDKCore, BioBLE, BioIngest, BioSDK, BioUI
```

Publishing (recommended)
1) Create a public repo for the binary package, e.g. your-org/BioSDK-Binary.
2) Copy this entire BinaryDistribution/ folder to the root of that repo.
3) Create a GitHub Release (e.g. v1.0.0) and upload each Artifacts/*.xcframework.zip.
4) Edit Package.swift in that repo and replace each .binaryTarget path with url + checksum using the printed values from the build.
5) Commit, tag, and push.

Consumers can then add:
```swift
.package(url: "https://github.com/your-org/BioSDK-Binary.git", exact: "1.0.0")
```
And link the product named "BioSDK", then import BioKit.

Notes
- Dynamic frameworks: consumers don’t need to declare your third-party dependencies; they are linked into the frameworks.
- If you later add resources to any module, re-run the script; XCFrameworks will include them automatically.
- If you need macCatalyst or tvOS, the build script can be extended similarly.

Troubleshooting
- Expression.swiftinterface verification errors during Release builds can occur with some toolchain versions. The default build disables interface verification and library evolution to avoid this. To ship with library evolution, update to dependency versions that emit valid interfaces with your Xcode, then use `LIB_EVOLUTION=1`.
