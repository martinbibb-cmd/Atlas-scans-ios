// swift-tools-version: 5.9
import PackageDescription

// AtlasContracts — Swift mirror of the shared @atlas/contracts TypeScript package.
//
// This package defines the external boundary for scan-bundle data exchanged
// between native scan clients (e.g. Atlas Scan iOS) and the Atlas web app.
// The type shapes here track the TypeScript contract in
//   martinbibb-cmd/Atlas-contracts / src/scan/
// so that both sides speak the same wire format.

let package = Package(
    name: "AtlasContracts",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AtlasContracts", targets: ["AtlasContracts"]),
    ],
    targets: [
        .target(name: "AtlasContracts"),
    ]
)
