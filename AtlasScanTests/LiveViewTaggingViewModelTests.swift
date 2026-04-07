import XCTest
@testable import AtlasScan

// MARK: - LiveViewTaggingViewModelTests
//
// Unit tests for LiveViewTaggingViewModel:
//   - Initial state
//   - Tap handling (empty area → pickingCategory; near pin → objectSelected)
//   - Object placement (worldAnchor stored, phase advances, session updated)
//   - Category pick cancellation
//   - Object selection / deselection
//   - Object mutation (updateObject propagates to session)
//   - Object deletion (removed from session, phase returns to idle)
//   - Proximity detection threshold
//   - refreshPlacedObjects mirrors session state
//
// No UIKit, ARKit, or AVFoundation types required; runs on any simulator or device.

@MainActor
final class LiveViewTaggingViewModelTests: XCTestCase {

    private var session: PropertyScanSession!
    private var store: ScanSessionStore!
    private var atlasSync: AtlasSync!
    private var sessionVM: SessionCaptureViewModel!
    private var viewModel: LiveViewTaggingViewModel!

    override func setUp() async throws {
        try await super.setUp()
        session   = PropertyScanSession(propertyAddress: "1 Live Test Street")
        store     = ScanSessionStore()
        atlasSync = AtlasSync()
        sessionVM = SessionCaptureViewModel(session: session, store: store, atlasSync: atlasSync)
        viewModel = LiveViewTaggingViewModel(sessionViewModel: sessionVM)
    }

    override func tearDown() async throws {
        store.delete(sessionVM.session)
        viewModel  = nil
        sessionVM  = nil
        atlasSync  = nil
        store      = nil
        session    = nil
        try await super.tearDown()
    }

    // MARK: - Initial state

    func test_init_phaseIsIdle() {
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func test_init_placedObjectsMirrorsSession() {
        XCTAssertEqual(viewModel.placedObjects.count,
                       sessionVM.session.allTaggedObjects.count)
    }

    func test_init_noPhotoSheet() {
        XCTAssertFalse(viewModel.showingPhotoSheet)
    }

    func test_init_noEditSheet() {
        XCTAssertFalse(viewModel.showingEditSheet)
    }

    // MARK: - Tap on empty area

    func test_handleTap_emptyArea_advancesToPickingCategory() {
        let pos = NormalizedPoint2D(x: 0.5, y: 0.5)
        viewModel.handleTap(at: pos)
        if case .pickingCategory(let p) = viewModel.phase {
            XCTAssertEqual(p, pos)
        } else {
            XCTFail("Expected .pickingCategory, got \(viewModel.phase)")
        }
    }

    // MARK: - Cancel category pick

    func test_cancelCategoryPick_returnsToIdle() {
        viewModel.handleTap(at: NormalizedPoint2D(x: 0.5, y: 0.5))
        viewModel.cancelCategoryPick()
        XCTAssertEqual(viewModel.phase, .idle)
    }

    // MARK: - Object placement

    func test_placeObject_addsToSession() {
        let pos = NormalizedPoint2D(x: 0.3, y: 0.4)
        viewModel.placeObject(category: .radiator, at: pos)
        XCTAssertEqual(sessionVM.session.allTaggedObjects.count, 1,
            "placeObject should add one TaggedObject to the session")
    }

    func test_placeObject_setsWorldAnchor() {
        let pos = NormalizedPoint2D(x: 0.3, y: 0.4)
        viewModel.placeObject(category: .radiator, at: pos)
        let obj = sessionVM.session.allTaggedObjects.first
        XCTAssertNotNil(obj?.worldAnchor, "Placed object should have a worldAnchor")
        XCTAssertEqual(obj?.worldAnchor?.screenX, 0.3, accuracy: 0.001)
        XCTAssertEqual(obj?.worldAnchor?.screenY, 0.4, accuracy: 0.001)
    }

    func test_placeObject_advancesToObjectSelected() {
        viewModel.placeObject(category: .boiler, at: NormalizedPoint2D(x: 0.5, y: 0.5))
        if case .objectSelected = viewModel.phase {
            // pass
        } else {
            XCTFail("Expected .objectSelected after placeObject, got \(viewModel.phase)")
        }
    }

    func test_placeObject_refreshesPlacedObjects() {
        viewModel.placeObject(category: .cylinder, at: NormalizedPoint2D(x: 0.6, y: 0.2))
        XCTAssertEqual(viewModel.placedObjects.count, 1)
    }

    func test_placeObject_setsCorrectCategory() {
        viewModel.placeObject(category: .flue, at: NormalizedPoint2D(x: 0.5, y: 0.5))
        XCTAssertEqual(viewModel.selectedObject?.category, .flue)
    }

    // MARK: - Tap near existing pin

    func test_handleTap_nearExistingAnchor_selectsObject() {
        let pos = NormalizedPoint2D(x: 0.5, y: 0.5)
        viewModel.placeObject(category: .radiator, at: pos)
        viewModel.deselectObject() // reset to idle

        // Tap very close to the placed anchor
        let nearPos = NormalizedPoint2D(x: 0.51, y: 0.51)
        viewModel.handleTap(at: nearPos)

        if case .objectSelected = viewModel.phase {
            // pass
        } else {
            XCTFail("Expected .objectSelected when tapping near existing pin, got \(viewModel.phase)")
        }
    }

    func test_handleTap_farFromAnyAnchor_startsPickingCategory() {
        let pos = NormalizedPoint2D(x: 0.1, y: 0.1)
        viewModel.placeObject(category: .radiator, at: pos)
        viewModel.deselectObject()

        // Tap far from the placed anchor
        let farPos = NormalizedPoint2D(x: 0.9, y: 0.9)
        viewModel.handleTap(at: farPos)

        if case .pickingCategory = viewModel.phase {
            // pass
        } else {
            XCTFail("Expected .pickingCategory when tapping far from existing pins, got \(viewModel.phase)")
        }
    }

    // MARK: - Object selection

    func test_selectObject_advancesToObjectSelected() {
        viewModel.placeObject(category: .boiler, at: NormalizedPoint2D(x: 0.5, y: 0.5))
        guard let id = sessionVM.session.allTaggedObjects.first?.id else {
            XCTFail("No objects in session")
            return
        }
        viewModel.deselectObject()
        viewModel.selectObject(id)
        XCTAssertEqual(viewModel.phase, .objectSelected(id))
    }

    func test_deselectObject_returnsToIdle() {
        viewModel.placeObject(category: .boiler, at: NormalizedPoint2D(x: 0.5, y: 0.5))
        viewModel.deselectObject()
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func test_selectedObject_returnsNilWhenIdle() {
        XCTAssertNil(viewModel.selectedObject)
    }

    func test_selectedObject_returnsObjectWhenSelected() {
        viewModel.placeObject(category: .cylinder, at: NormalizedPoint2D(x: 0.5, y: 0.5))
        XCTAssertNotNil(viewModel.selectedObject)
        XCTAssertEqual(viewModel.selectedObject?.category, .cylinder)
    }

    // MARK: - Object update

    func test_updateObject_propagatesToSession() {
        viewModel.placeObject(category: .boiler, at: NormalizedPoint2D(x: 0.5, y: 0.5))
        guard var obj = viewModel.selectedObject else {
            XCTFail("No selected object")
            return
        }
        obj.label = "Main Boiler"
        viewModel.updateObject(obj)

        let saved = sessionVM.session.allTaggedObjects.first { $0.id == obj.id }
        XCTAssertEqual(saved?.label, "Main Boiler",
            "updateObject should propagate label change to the session")
    }

    func test_updateObject_refreshesPlacedObjects() {
        viewModel.placeObject(category: .boiler, at: NormalizedPoint2D(x: 0.5, y: 0.5))
        guard var obj = viewModel.selectedObject else { return }
        obj.confidence = .high
        viewModel.updateObject(obj)
        let refreshed = viewModel.placedObjects.first { $0.id == obj.id }
        XCTAssertEqual(refreshed?.confidence, .high)
    }

    // MARK: - Object deletion

    func test_deleteSelectedObject_removesFromSession() {
        viewModel.placeObject(category: .radiator, at: NormalizedPoint2D(x: 0.5, y: 0.5))
        XCTAssertEqual(sessionVM.session.allTaggedObjects.count, 1)
        viewModel.deleteSelectedObject()
        XCTAssertEqual(sessionVM.session.allTaggedObjects.count, 0,
            "deleteSelectedObject should remove the object from the session")
    }

    func test_deleteSelectedObject_returnsToIdle() {
        viewModel.placeObject(category: .radiator, at: NormalizedPoint2D(x: 0.5, y: 0.5))
        viewModel.deleteSelectedObject()
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func test_deleteSelectedObject_refreshesPlacedObjects() {
        viewModel.placeObject(category: .cylinder, at: NormalizedPoint2D(x: 0.5, y: 0.5))
        viewModel.deleteSelectedObject()
        XCTAssertTrue(viewModel.placedObjects.isEmpty)
    }

    func test_deleteSelectedObject_noOpWhenIdle() {
        viewModel.deleteSelectedObject()  // phase is .idle — should not crash
        XCTAssertEqual(viewModel.phase, .idle)
    }

    // MARK: - Live tag count

    func test_liveTagCount_countsObjectsWithWorldAnchor() {
        viewModel.placeObject(category: .radiator, at: NormalizedPoint2D(x: 0.2, y: 0.3))
        viewModel.placeObject(category: .boiler,   at: NormalizedPoint2D(x: 0.7, y: 0.6))
        XCTAssertEqual(viewModel.liveTagCount, 2,
            "liveTagCount should count all objects that have a worldAnchor")
    }

    func test_liveTagCount_excludesObjectsWithoutAnchor() {
        // Add an object without a world anchor via sessionVM directly
        let obj = TaggedObject(roomID: sessionVM.session.id, category: .thermostat)
        sessionVM.addObject(obj)
        viewModel.refreshPlacedObjects()
        XCTAssertEqual(viewModel.liveTagCount, 0,
            "Objects without a worldAnchor should not count towards liveTagCount")
    }

    // MARK: - refreshPlacedObjects

    func test_refreshPlacedObjects_picksUpExternalChanges() {
        // Add object via sessionVM (bypassing the live view)
        let obj = TaggedObject(
            roomID: sessionVM.session.id,
            category: .boiler,
            worldAnchor: WorldAnchor3D(screenX: 0.5, screenY: 0.5)
        )
        sessionVM.addObject(obj)
        viewModel.refreshPlacedObjects()
        XCTAssertEqual(viewModel.placedObjects.count, 1,
            "refreshPlacedObjects should pick up objects added externally")
    }

    // MARK: - WorldAnchor3D model

    func test_worldAnchor_screenClamping() {
        let anchor = WorldAnchor3D(screenX: 1.5, screenY: -0.3)
        XCTAssertEqual(anchor.screenX, 1.0, accuracy: 0.001, "screenX should clamp to 1.0")
        XCTAssertEqual(anchor.screenY, 0.0, accuracy: 0.001, "screenY should clamp to 0.0")
    }

    func test_taggedObject_worldAnchorRoundtrip() throws {
        var obj = TaggedObject(roomID: UUID(), category: .radiator)
        obj.worldAnchor = WorldAnchor3D(x: 1.0, y: 0.0, z: 2.0, screenX: 0.3, screenY: 0.7)
        let data    = try JSONEncoder().encode(obj)
        let decoded = try JSONDecoder().decode(TaggedObject.self, from: data)
        XCTAssertEqual(decoded.worldAnchor?.screenX, 0.3, accuracy: 0.001)
        XCTAssertEqual(decoded.worldAnchor?.screenY, 0.7, accuracy: 0.001)
        XCTAssertEqual(decoded.worldAnchor?.z, 2.0, accuracy: 0.001)
    }

    func test_taggedObject_missingWorldAnchorDecodesAsNil() throws {
        // Encode an object without worldAnchor to simulate legacy data
        var obj = TaggedObject(roomID: UUID(), category: .boiler)
        obj.worldAnchor = nil
        let data    = try JSONEncoder().encode(obj)
        let decoded = try JSONDecoder().decode(TaggedObject.self, from: data)
        XCTAssertNil(decoded.worldAnchor, "Missing worldAnchor should decode as nil (backward compat)")
    }
}
