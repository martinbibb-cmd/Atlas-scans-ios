// MARK: - ScanBundleV1 — DEPRECATED local mirror
//
// The contract types previously defined here have been replaced by the
// shared AtlasContracts package (AtlasContracts/Sources/AtlasContracts/).
//
// Import the shared types instead:
//
//     import AtlasContracts
//
// Types now provided by AtlasContracts:
//   • ScanBundleV1       (was: ScanBundleV1)
//   • ScanRoom           (was: ContractRoom)
//   • ScanWall           (was: ContractWall)
//   • ScanOpening        (was: ContractOpening)
//   • ScanDetectedObject (was: ContractTaggedObject)
//   • ScanMeta           (was fields on ContractScanJob / root bundle)
//   • ScanAnchor         (new)
//   • ScanQAFlag         (new)
//   • ScanConfidenceBand (new)
//   • ScanImportManifest            (new — typed manifest.json contract)
//   • ScanImportManifest.ImportSummary (new — import summary nested type)
//   • decodeImportManifest(_:)      (new — manifest.json decoder helper)
//   • currentScanBundleVersion (was: BundleSchemaVersion.current)
//   • validateScanBundle(_:)   (new)
//
// This file is intentionally empty. Do not re-add local contract types here.
