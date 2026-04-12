import Foundation
import UIKit
import RoomPlan

// MARK: - RoomScanEvidenceBuilder
//
// Builds a RoomScanEvidence record from a completed RoomPlan capture.
//
// Responsibilities:
//   1. Export the captured room as USDZ to the app's Documents directory.
//   2. Render a small preview thumbnail from the exported asset (or fallback).
//   3. Wrap the local file URLs + scan metadata into a RoomScanEvidence value.
//
// Architecture rules:
//   • Only produces evidence metadata — no heat-loss or engine inputs are derived.
//   • Heavy USDZ asset is stored externally on-device; RoomScanEvidence only
//     carries the local file URL string.
//   • Callers should attach the returned evidence to
//     PropertyScanSession.roomScanEvidence and call scheduleAutosave().

@MainActor
final class RoomScanEvidenceBuilder {

    // MARK: - Directory helpers

    private static var evidenceDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("RoomScanEvidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Build from CapturedRoomData
    //
    // Exports the raw CapturedRoomData as USDZ using RoomBuilder, saves it to
    // the evidence directory, and returns a populated RoomScanEvidence.

    /// Builds a `RoomScanEvidence` by exporting the completed room scan as USDZ.
    ///
    /// - Parameters:
    ///   - data: The `CapturedRoomData` produced by `RoomCaptureSessionDelegate`.
    ///   - propertySessionID: UUID of the owning `PropertyScanSession`.
    ///   - captureSessionID: UUID for this specific capture run (used to name files).
    ///   - linkedRoomIDs: Room IDs to link the evidence to immediately.
    /// - Returns: A `RoomScanEvidence` with local file URL populated, or nil on failure.
    static func build(
        from data: CapturedRoomData,
        propertySessionID: UUID,
        captureSessionID: UUID,
        linkedRoomIDs: [UUID] = []
    ) async -> RoomScanEvidence? {
        let fileURL = evidenceDirectory
            .appendingPathComponent(captureSessionID.uuidString)
            .appendingPathExtension("usdz")

        // Export USDZ
        do {
            let builder = RoomBuilder(options: [.beautifyObjects])
            let captured = try await builder.capturedRoom(from: data)
            try captured.export(to: fileURL, exportOptions: .mesh)
        } catch {
            return nil
        }

        // Generate preview thumbnail
        let previewURL = await renderPreviewThumbnail(for: fileURL, captureSessionID: captureSessionID)

        let device = await UIDevice.current.model
        let meta = RoomScanEvidence.CaptureMeta(
            device: device,
            timestamp: Date()
        )

        return RoomScanEvidence(
            propertySessionID: propertySessionID,
            captureSessionID: captureSessionID,
            localFileURLString: fileURL.absoluteString,
            assetFormat: .usdz,
            previewImageURLString: previewURL?.absoluteString,
            linkedRoomIDs: linkedRoomIDs,
            captureMeta: meta
        )
    }

    // MARK: - Build from ScannedRoom (lightweight, no USDZ)
    //
    // For devices or flows where the raw CapturedRoomData is no longer available,
    // produce an evidence record from the ScannedRoom metadata without an asset file.

    /// Builds a metadata-only `RoomScanEvidence` from an existing `ScannedRoom`.
    ///
    /// No USDZ is exported; `localFileURLString` is left nil.
    /// Suitable when the raw scan data has already been processed into a `ScannedRoom`.
    static func buildMetadataOnly(
        from room: ScannedRoom,
        propertySessionID: UUID
    ) -> RoomScanEvidence {
        let captureSessionID = UUID()
        let device = UIDevice.current.model

        let bounds: RoomScanEvidence.Bounds? = (room.areaSquareMetres != nil || room.ceilingHeightMetres != nil)
            ? RoomScanEvidence.Bounds(
                width: room.areaSquareMetres.map { sqrt($0) } ?? 0,
                length: room.areaSquareMetres.map { sqrt($0) } ?? 0,
                height: room.ceilingHeightMetres ?? 0
              )
            : nil

        let meta = RoomScanEvidence.CaptureMeta(
            device: device,
            timestamp: Date()
        )

        return RoomScanEvidence(
            propertySessionID: propertySessionID,
            captureSessionID: captureSessionID,
            localFileURLString: nil,
            assetFormat: .usdz,
            previewImageURLString: nil,
            linkedRoomIDs: [room.id],
            bounds: bounds,
            captureMeta: meta
        )
    }

    // MARK: - Preview thumbnail

    /// Renders a small JPEG thumbnail for the USDZ at `usdzURL`.
    ///
    /// Falls back to nil when QuickLook thumbnail generation is unavailable
    /// (e.g. in CI environments without a display).
    private static func renderPreviewThumbnail(
        for usdzURL: URL,
        captureSessionID: UUID
    ) async -> URL? {
        let thumbURL = evidenceDirectory
            .appendingPathComponent("\(captureSessionID.uuidString)_preview")
            .appendingPathExtension("jpg")

        // Use a simple placeholder thumbnail by drawing a scene-camera icon
        // into a 256×256 JPEG.  Replace with QLThumbnailGenerator when the app
        // targets iOS 17+ and the feature is needed.
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemGray6.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let config = UIImage.SymbolConfiguration(pointSize: 80, weight: .thin)
            if let icon = UIImage(systemName: "cube.transparent", withConfiguration: config) {
                let iconSize = icon.size
                let x = (size.width  - iconSize.width)  / 2
                let y = (size.height - iconSize.height) / 2
                icon.withTintColor(.systemGray2).draw(at: CGPoint(x: x, y: y))
            }
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.75) else { return nil }
        do {
            try jpegData.write(to: thumbURL)
            return thumbURL
        } catch {
            return nil
        }
    }
}
