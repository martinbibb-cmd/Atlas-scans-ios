import Foundation

// MARK: - MockData
//
// Provides pre-built ScanJob instances for SwiftUI previews and simulator testing.
// Not shipped in production builds — guarded by DEBUG flag.

#if DEBUG
enum MockData {

    // MARK: Single job

    static var sampleJob: ScanJob {
        var job = ScanJob(
            id: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!,
            jobReference: "ATL-2024-001",
            propertyAddress: "14 Maple Street, Anytown, AN1 2BT",
            engineerName: "Sam Taylor"
        )
        job.rooms = [livingRoom, kitchen, utilityRoom]
        job.status = .inProgress
        return job
    }

    // MARK: Multiple jobs for list view

    static var sampleJobs: [ScanJob] {
        [sampleJob, draftJob, exportedJob]
    }

    static var draftJob: ScanJob {
        ScanJob(
            id: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000002")!,
            jobReference: "ATL-2024-002",
            propertyAddress: "7 Elm Close, Othertown, OT3 4CD",
            engineerName: "Alex Hughes",
            status: .draft
        )
    }

    static var exportedJob: ScanJob {
        var job = ScanJob(
            id: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000003")!,
            jobReference: "ATL-2024-003",
            propertyAddress: "22 Oak Avenue, Somewhere, SO5 6EF",
            engineerName: "Sam Taylor"
        )
        job.status = .exported
        job.rooms = [boilerRoom]
        return job
    }

    // MARK: Sample rooms

    static var livingRoom: ScannedRoom {
        let jobID = UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!

        let walls = (0..<4).map { i in
            ScannedWall(
                index: i,
                lengthMetres: [4.5, 5.2, 4.5, 5.2][i],
                heightMetres: 2.5,
                isExternalWall: i == 0,
                hasWindow: i == 0,
                hasDoor: i == 2
            )
        }

        var room = ScannedRoom(
            id: UUID(uuidString: "B1B2B3B4-0000-0000-0000-000000000001")!,
            jobID: jobID,
            name: "Living Room",
            floor: 0,
            areaSquareMetres: 23.4,
            ceilingHeightMetres: 2.5,
            walls: walls,
            geometryCaptured: true,
            isReviewed: true
        )

        room.taggedObjects = [
            TaggedObject(
                id: UUID(uuidString: "C1B2B3B4-0000-0000-0000-000000000001")!,
                roomID: room.id,
                category: .radiator,
                label: "Radiator",
                normalizedPosition: NormalizedPoint2D(x: 0.2, y: 0.05),
                wallIndex: 0,
                placementMode: .wallMounted,
                rotation: 0.0,
                quickFieldValues: [
                    "type": "Panel",
                    "width_estimate": "1200mm",
                    "external_wall": "true",
                    "under_window": "true"
                ],
                isConfirmed: true,
                confidence: .high
            ),
            TaggedObject(
                id: UUID(uuidString: "C1B2B3B4-0000-0000-0000-000000000002")!,
                roomID: room.id,
                category: .thermostat,
                label: "Room Thermostat",
                normalizedPosition: NormalizedPoint2D(x: 0.8, y: 0.4),
                wallIndex: 1,
                placementMode: .wallMounted,
                rotation: 0.0,
                isConfirmed: true,
                confidence: .high
            ),
        ]

        return room
    }

    static var kitchen: ScannedRoom {
        let jobID = UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!

        var room = ScannedRoom(
            id: UUID(uuidString: "B1B2B3B4-0000-0000-0000-000000000002")!,
            jobID: jobID,
            name: "Kitchen",
            floor: 0,
            areaSquareMetres: 14.2,
            ceilingHeightMetres: 2.4,
            geometryCaptured: true,
            isReviewed: false
        )

        room.taggedObjects = [
            TaggedObject(
                id: UUID(uuidString: "C1B2B3B4-0000-0000-0000-000000000003")!,
                roomID: room.id,
                category: .radiator,
                label: "Radiator",
                normalizedPosition: NormalizedPoint2D(x: 0.5, y: 0.05),
                placementMode: .wallMounted,
                rotation: 0.0,
                isConfirmed: true,
                confidence: .medium
            ),
        ]

        return room
    }

    static var utilityRoom: ScannedRoom {
        let jobID = UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!

        var room = ScannedRoom(
            id: UUID(uuidString: "B1B2B3B4-0000-0000-0000-000000000003")!,
            jobID: jobID,
            name: "Utility Room",
            floor: 0,
            areaSquareMetres: 6.5,
            ceilingHeightMetres: 2.4,
            geometryCaptured: false,
            isReviewed: false
        )

        room.taggedObjects = [
            TaggedObject(
                id: UUID(uuidString: "C1B2B3B4-0000-0000-0000-000000000004")!,
                roomID: room.id,
                category: .boiler,
                label: "Boiler",
                normalizedPosition: NormalizedPoint2D(x: 0.3, y: 0.1),
                placementMode: .floorPlaced,
                rotation: 0.0,
                quickFieldValues: [
                    "type": "Combi",
                    "flue_direction": "Rear",
                    "enclosed": "false"
                ],
                isConfirmed: true,
                confidence: .high
            ),
            TaggedObject(
                id: UUID(uuidString: "C1B2B3B4-0000-0000-0000-000000000005")!,
                roomID: room.id,
                category: .programmer,
                label: "Programmer",
                normalizedPosition: NormalizedPoint2D(x: 0.6, y: 0.4),
                placementMode: .wallMounted,
                rotation: 0.0,
                isConfirmed: false,
                confidence: .medium
            ),
        ]

        return room
    }

    static var boilerRoom: ScannedRoom {
        let jobID = UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000003")!

        var room = ScannedRoom(
            id: UUID(uuidString: "B1B2B3B4-0000-0000-0000-000000000004")!,
            jobID: jobID,
            name: "Boiler Room",
            floor: 0,
            areaSquareMetres: 4.0,
            ceilingHeightMetres: 2.2,
            geometryCaptured: true,
            isReviewed: true
        )

        room.taggedObjects = [
            TaggedObject(
                id: UUID(uuidString: "C1B2B3B4-0000-0000-0000-000000000006")!,
                roomID: room.id,
                category: .boiler,
                label: "Boiler",
                normalizedPosition: NormalizedPoint2D(x: 0.5, y: 0.1),
                placementMode: .floorPlaced,
                rotation: 0.0,
                quickFieldValues: ["type": "Heat-only", "enclosed": "true"],
                isConfirmed: true,
                confidence: .high
            ),
            TaggedObject(
                id: UUID(uuidString: "C1B2B3B4-0000-0000-0000-000000000007")!,
                roomID: room.id,
                category: .cylinder,
                label: "Cylinder",
                normalizedPosition: NormalizedPoint2D(x: 0.75, y: 0.3),
                placementMode: .floorPlaced,
                rotation: 0.0,
                quickFieldValues: ["vented": "Unvented", "size": "210L"],
                isConfirmed: true,
                confidence: .high
            ),
            TaggedObject(
                id: UUID(uuidString: "C1B2B3B4-0000-0000-0000-000000000008")!,
                roomID: room.id,
                category: .flue,
                label: "Flue",
                normalizedPosition: NormalizedPoint2D(x: 0.5, y: 0.0),
                wallIndex: 0,
                placementMode: .wallMounted,
                rotation: 0.0,
                quickFieldValues: ["direction": "Rear"],
                isConfirmed: true,
                confidence: .high
            ),
        ]

        return room
    }
}
#endif
