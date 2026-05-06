// swift-tools-version: 5.9
// AtlasScanCore — Core business-logic library for the Atlas Scan iOS app.

import PackageDescription

let package = Package(
    name: "AtlasScanV2",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "AtlasScanCore",
            targets: ["AtlasScanCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AtlasScanCore",
            dependencies: [],
            path: "Sources/AtlasScanCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
