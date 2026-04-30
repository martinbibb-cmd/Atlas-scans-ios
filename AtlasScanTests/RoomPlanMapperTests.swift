import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - RoomPlanMapperTests
//
// Unit tests for RoomPlanMapper and RoomPlanScanResult.
//
// All tests run on any simulator — no LiDAR hardware required.
//
// Covers:
//   - Room label and dimensions are mapped correctly
//   - captureSource is set to .lidar
//   - confidence is set to .high
//   - Floor plan outline is populated when outlinePoints provided
//   - LiDAR-inferred object pins are created with .inferred confidence
//   - Object category → ObjectPinType mapping
//   - RoomPlanMapper.autoSnapshot() produces correct metadata
//   - Exported SessionCaptureV2 still validates after a LiDAR room scan
//   - Mixed LiDAR + manual + photo capture still validates

final class RoomPlanMapperTests: XCTestCase {

    // MARK: - Helpers

    private func makeResult(
        widthM: Double? = 4.0,
        depthM: Double? = 3.0,
        heightM: Double? = 2.4,
        outlinePoints: [NormalisedPoint] = [],
        detectedObjects: [RoomPlanDetectedObject] = []
    ) -> RoomPlanScanResult {
        RoomPlanScanResult(
            widthM: widthM,
            depthM: depthM,
            heightM: heightM,
            outlinePoints: outlinePoints,
            detectedObjects: detectedObjects
        )
    }

    private let defaultOutline: [NormalisedPoint] = [
        NormalisedPoint(x: 0.05, y: 0.05),
        NormalisedPoint(x: 0.95, y: 0.05),
        NormalisedPoint(x: 0.95, y: 0.95),
        NormalisedPoint(x: 0.05, y: 0.95),
    ]

    // MARK: - Room scan mapping: identity

    func test_map_usesRoomIndexInLabel() {
        let (scan, _) = RoomPlanMapper.map(makeResult(), roomIndex: 1)
        XCTAssertEqual(scan.roomLabel, "Room 1")
    }

    func test_map_largerRoomIndexInLabel() {
        let (scan, _) = RoomPlanMapper.map(makeResult(), roomIndex: 5)
        XCTAssertEqual(scan.roomLabel, "Room 5")
    }

    // MARK: - Room scan mapping: dimensions

    func test_map_widthIsPreserved() {
        let (scan, _) = RoomPlanMapper.map(makeResult(widthM: 5.5), roomIndex: 1)
        XCTAssertEqual(scan.rawWidthM, 5.5)
    }

    func test_map_depthIsPreserved() {
        let (scan, _) = RoomPlanMapper.map(makeResult(depthM: 3.2), roomIndex: 1)
        XCTAssertEqual(scan.rawDepthM, 3.2)
    }

    func test_map_heightIsPreserved() {
        let (scan, _) = RoomPlanMapper.map(makeResult(heightM: 2.6), roomIndex: 1)
        XCTAssertEqual(scan.rawHeightM, 2.6)
    }

    func test_map_nilDimensionsAreNil() {
        let result = RoomPlanScanResult()
        let (scan, _) = RoomPlanMapper.map(result, roomIndex: 1)
        XCTAssertNil(scan.rawWidthM)
        XCTAssertNil(scan.rawDepthM)
        XCTAssertNil(scan.rawHeightM)
    }

    // MARK: - Room scan mapping: capture metadata

    func test_map_captureSourceIsLidar() {
        let (scan, _) = RoomPlanMapper.map(makeResult(), roomIndex: 1)
        XCTAssertEqual(scan.captureSource, .lidar)
    }

    func test_map_confidenceIsHigh() {
        let (scan, _) = RoomPlanMapper.map(makeResult(), roomIndex: 1)
        XCTAssertEqual(scan.confidence, .high)
    }

    func test_map_withRawJSON_storesMetadata() {
        var result = makeResult()
        result.rawJSON = #"{"version":"1.0"}"#
        let (scan, _) = RoomPlanMapper.map(result, roomIndex: 1)
        XCTAssertEqual(scan.lidarMetadata, #"{"version":"1.0"}"#)
    }

    func test_map_withoutRawJSON_metadataIsNil() {
        let (scan, _) = RoomPlanMapper.map(makeResult(), roomIndex: 1)
        XCTAssertNil(scan.lidarMetadata)
    }

    // MARK: - Floor plan outline

    func test_map_withOutlinePoints_floorPlanIsSet() {
        let result = makeResult(outlinePoints: defaultOutline)
        let (scan, _) = RoomPlanMapper.map(result, roomIndex: 1)
        XCTAssertNotNil(scan.floorPlan)
    }

    func test_map_withOutlinePoints_outlineCountIsCorrect() {
        let result = makeResult(outlinePoints: defaultOutline)
        let (scan, _) = RoomPlanMapper.map(result, roomIndex: 1)
        XCTAssertEqual(scan.floorPlan?.outlinePoints.count, 4)
    }

    func test_map_withNoOutlinePoints_floorPlanIsNil() {
        let result = makeResult(outlinePoints: [])
        let (scan, _) = RoomPlanMapper.map(result, roomIndex: 1)
        XCTAssertNil(scan.floorPlan)
    }

    // MARK: - Object pins: counts

    func test_map_noDetectedObjects_noPins() {
        let (_, pins) = RoomPlanMapper.map(makeResult(), roomIndex: 1)
        XCTAssertTrue(pins.isEmpty)
    }

    func test_map_oneDetectedObject_onePin() {
        let obj = RoomPlanDetectedObject(
            category: .stove, label: "Stove",
            normalisedPositionX: 0.5, normalisedPositionY: 0.5
        )
        let result = makeResult(detectedObjects: [obj])
        let (_, pins) = RoomPlanMapper.map(result, roomIndex: 1)
        XCTAssertEqual(pins.count, 1)
    }

    func test_map_multipleDetectedObjects_matchingPinCount() {
        let objects = [
            RoomPlanDetectedObject(category: .stove,  label: "Stove", normalisedPositionX: 0.3, normalisedPositionY: 0.3),
            RoomPlanDetectedObject(category: .sink,   label: "Sink",  normalisedPositionX: 0.7, normalisedPositionY: 0.7),
            RoomPlanDetectedObject(category: .toilet, label: "Toilet", normalisedPositionX: 0.5, normalisedPositionY: 0.5),
        ]
        let result = makeResult(detectedObjects: objects)
        let (_, pins) = RoomPlanMapper.map(result, roomIndex: 1)
        XCTAssertEqual(pins.count, 3)
    }

    // MARK: - Object pins: metadata

    func test_map_pinSourceIsLidar() {
        let obj = RoomPlanDetectedObject(category: .bed, label: "Bed", normalisedPositionX: 0.5, normalisedPositionY: 0.5)
        let (_, pins) = RoomPlanMapper.map(makeResult(detectedObjects: [obj]), roomIndex: 1)
        XCTAssertEqual(pins.first?.pinSource, .lidar)
    }

    func test_map_pinConfidenceIsInferred() {
        let obj = RoomPlanDetectedObject(category: .chair, label: "Chair", normalisedPositionX: 0.2, normalisedPositionY: 0.8)
        let (_, pins) = RoomPlanMapper.map(makeResult(detectedObjects: [obj]), roomIndex: 1)
        XCTAssertEqual(pins.first?.pinConfidence, .inferred)
    }

    func test_map_pinRoomIdMatchesScanId() {
        let obj = RoomPlanDetectedObject(category: .sofa, label: "Sofa", normalisedPositionX: 0.5, normalisedPositionY: 0.5)
        let result = makeResult(detectedObjects: [obj])
        let (scan, pins) = RoomPlanMapper.map(result, roomIndex: 1)
        XCTAssertEqual(pins.first?.roomId, scan.id)
    }

    func test_map_pinLabelMatchesObjectLabel() {
        let obj = RoomPlanDetectedObject(category: .stove, label: "Stove / Boiler", normalisedPositionX: 0.5, normalisedPositionY: 0.5)
        let (_, pins) = RoomPlanMapper.map(makeResult(detectedObjects: [obj]), roomIndex: 1)
        XCTAssertEqual(pins.first?.label, "Stove / Boiler")
    }

    // MARK: - Object category → ObjectPinType

    func test_stoveCategory_mapsToBoiler() {
        XCTAssertEqual(RoomPlanObjectCategory.stove.objectPinType, .boiler)
    }

    func test_ovenCategory_mapsToBoiler() {
        XCTAssertEqual(RoomPlanObjectCategory.oven.objectPinType, .boiler)
    }

    func test_sinkCategory_mapsToStopTap() {
        XCTAssertEqual(RoomPlanObjectCategory.sink.objectPinType, .stopTap)
    }

    func test_bedCategory_mapsToGenericNote() {
        XCTAssertEqual(RoomPlanObjectCategory.bed.objectPinType, .genericNote)
    }

    func test_sofaCategory_mapsToGenericNote() {
        XCTAssertEqual(RoomPlanObjectCategory.sofa.objectPinType, .genericNote)
    }

    func test_unknownCategory_mapsToGenericNote() {
        XCTAssertEqual(RoomPlanObjectCategory.unknown.objectPinType, .genericNote)
    }

    func test_allCategories_haveNonEmptyDisplayLabel() {
        for category in RoomPlanObjectCategory.allCases {
            XCTAssertFalse(category.displayLabel.isEmpty, "\(category.rawValue) has empty displayLabel")
        }
    }

    // MARK: - Auto snapshot

    func test_autoSnapshot_roomIdMatchesScan() {
        let (scan, _) = RoomPlanMapper.map(makeResult(), roomIndex: 1)
        let snapshot = RoomPlanMapper.autoSnapshot(for: scan)
        XCTAssertEqual(snapshot.roomId, scan.id)
    }

    func test_autoSnapshot_imageRefContainsScanId() {
        let (scan, _) = RoomPlanMapper.map(makeResult(), roomIndex: 1)
        let snapshot = RoomPlanMapper.autoSnapshot(for: scan)
        XCTAssertTrue(
            snapshot.imageRef.contains(scan.id.uuidString),
            "imageRef should contain the scan UUID"
        )
    }

    func test_autoSnapshot_imageRefHasPngExtension() {
        let (scan, _) = RoomPlanMapper.map(makeResult(), roomIndex: 1)
        let snapshot = RoomPlanMapper.autoSnapshot(for: scan)
        XCTAssertTrue(snapshot.imageRef.hasSuffix(".png"))
    }

    // MARK: - Export validation: LiDAR scan only

    func test_lidarScan_exportValidates() throws {
        let result = makeResult(outlinePoints: defaultOutline)
        let (scan, _) = RoomPlanMapper.map(result, roomIndex: 1)

        var draft = CaptureSessionStore.newSession(visitReference: "JOB-LIDAR-001")
        draft.roomScans.append(scan)

        let exportResult = try CaptureSessionExporter.export(draft)
        let validation = validateSessionCaptureV2(exportResult.jsonData)
        XCTAssertTrue(
            validation.isSuccess,
            "LiDAR room scan must produce a valid SessionCaptureV2. Errors: \(validation.errors)"
        )
    }

    func test_lidarScan_exportedConfidenceIsHigh() throws {
        let (scan, _) = RoomPlanMapper.map(makeResult(), roomIndex: 1)
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-LIDAR-CONF")
        draft.roomScans.append(scan)

        let exportResult = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(exportResult.payload.roomScans.first?.confidence, .high)
    }

    // MARK: - Export validation: mixed capture (LiDAR + manual + photos)

    func test_mixedCapture_lidarPlusManualPlusPhoto_exportValidates() throws {
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-MIXED-LIDAR")

        // LiDAR scan
        let lidarResult = makeResult(widthM: 5.0, depthM: 4.0, heightM: 2.4, outlinePoints: defaultOutline)
        let (lidarScan, lidarPins) = RoomPlanMapper.map(lidarResult, roomIndex: 1)
        draft.roomScans.append(lidarScan)
        draft.objectPins.append(contentsOf: lidarPins)
        draft.floorPlanSnapshots.append(RoomPlanMapper.autoSnapshot(for: lidarScan))

        // Manual scan
        var manualScan = CapturedRoomScanDraft()
        manualScan.roomLabel     = "Utility Room"
        manualScan.rawWidthM     = 2.5
        manualScan.rawDepthM     = 2.0
        manualScan.confidence    = .medium
        manualScan.captureSource = .manual
        draft.roomScans.append(manualScan)

        // Photo
        var photo = CapturedPhotoDraft(localFilename: "boiler_front.jpg")
        photo.roomId = manualScan.id
        photo.kind   = .plant
        draft.photos.append(photo)

        let exportResult = try CaptureSessionExporter.export(draft)
        let validation = validateSessionCaptureV2(exportResult.jsonData)
        XCTAssertTrue(
            validation.isSuccess,
            "Mixed LiDAR + manual + photo capture must validate. Errors: \(validation.errors)"
        )
    }

    func test_mixedCapture_lidarPinsNotOverwritingManualPins() throws {
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-PINS-TEST")

        // Manual pin added before LiDAR capture
        var manualPin = CapturedObjectPinDraft(type: .boiler)
        manualPin.label = "Worcester Bosch 30i"
        draft.objectPins.append(manualPin)

        // LiDAR scan with inferred pins
        let lidarObj = RoomPlanDetectedObject(
            category: .stove, label: "Stove / Boiler",
            normalisedPositionX: 0.5, normalisedPositionY: 0.5
        )
        let lidarResult = makeResult(detectedObjects: [lidarObj])
        let (lidarScan, lidarPins) = RoomPlanMapper.map(lidarResult, roomIndex: 1)
        draft.roomScans.append(lidarScan)
        draft.objectPins.append(contentsOf: lidarPins)

        // Both manual AND inferred pins should be present
        XCTAssertEqual(draft.objectPins.count, 2, "Manual pins must not be overwritten by LiDAR pins")
        XCTAssertEqual(draft.objectPins.first?.pinSource, nil,   "Manual pin has no pinSource")
        XCTAssertEqual(draft.objectPins.last?.pinSource,  .lidar, "LiDAR pin has .lidar source")

        let exportResult = try CaptureSessionExporter.export(draft)
        let validation = validateSessionCaptureV2(exportResult.jsonData)
        XCTAssertTrue(validation.isSuccess, "Mixed manual + LiDAR pins must validate")
    }

    // MARK: - Photo-only job still valid after LiDAR added to session model

    func test_photoOnlyJob_remainsValidAfterLidarModelChanges() throws {
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-PHOTO-ONLY")
        draft.photos.append(CapturedPhotoDraft(localFilename: "overview.jpg"))

        let errors = CaptureSessionExporter.validate(draft)
        XCTAssertTrue(errors.isEmpty, "Photo-only session must still pass validation after model changes")

        let exportResult = try CaptureSessionExporter.export(draft)
        let validation = validateSessionCaptureV2(exportResult.jsonData)
        XCTAssertTrue(validation.isSuccess, "Photo-only export must still validate")
    }
}
