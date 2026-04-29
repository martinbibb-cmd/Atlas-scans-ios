# Atlas Scan — iOS

A native iPhone/iPad app for service-engineering room capture.

**Atlas Scan** is the specialist capture companion to [Atlas](https://github.com/martinbibb-cmd/Atlas-recommendation).  
It owns **capture only** — room geometry, service-object tagging, and export.  
It does not contain recommendation logic, heat-loss calculation, or survey truth.

---

## What It Does

1. **Scan rooms** — walk the room, see geometry captured live (RoomPlan; mock adapter available for simulator)
2. **Tag service objects** — tap-to-add boiler, radiator, cylinder, manifold, flue, controls, meters, and more
3. **Review each room** — mark reviewed, add notes, confirm object placements
4. **Send to Atlas Mind** — submit the completed session directly to the Atlas Mind database (invisible to the engineer)

The UX philosophy:  
> *automatic geometry, manual service tagging*

---

## Architecture

```
AtlasScan/
├── App/                          Entry point (AtlasScanApp.swift)
├── Features/
│   ├── ScanSession/              Job list, job detail, new-job sheet
│   ├── RoomCapture/              Scanner adapter protocol + mock adapter + capture UI
│   ├── RoomReview/               Room geometry review + tagging
│   ├── ObjectTagging/            Add/edit tagged service objects
│   └── Export/                   Export preview + bundle share
├── Models/
│   ├── PropertyScanSession       NEW canonical capture model (whole-property session)
│   ├── ScanJob                   Legacy export-compat model; not canonical capture state
│   ├── ScannedRoom               Room children of a PropertyScanSession
│   ├── TaggedObject              Service object with clearance-profile and cross-links
│   └── TaggedPhoto               Evidence photo with per-photo sync state
├── Services/
│   ├── ScanSessionStore          Offline-first persistence (Documents/ScanSessions/)
│   ├── AtlasSync                 Upload queue with exponential backoff (transport: stub)
│   ├── ClearanceEngine           Three-layer clearance geometry (footprint / install / service)
│   └── ExportPackageBuilder      Builds ScanBundleV1 export packages
├── Contracts/                    ScanBundleV1 — atlas-contracts export shape
└── DevFixtures/                  MockData for previews and simulator
```

### What is new canonical state

- **`PropertyScanSession`** — the capture-side top-level entity. One session = one property.
  Rooms, tagged objects, photos, and validation issues are all children of one shared session.
  `scanState`, `reviewState`, and `syncState` track capture progress, review/sign-off, and Atlas
  upload lifecycle independently.
- **`ScanSessionStore`** — offline-first persistence; saves each session as `<uuid>.session.json`
  in `Documents/ScanSessions/` immediately on every mutation.
- **`AtlasSync`** — upload queue with per-item retry and exponential backoff.
- **Three-layer clearance geometry** — `ClearanceResult` now returns `footprintRect`,
  `installMinimumRect`, and `serviceAccessRect` as separate overlays.

### What is compatibility glue

- **`ScanJob`** remains in use as the export-contract model. `PropertyScanSession.toScanJob()`
  maps the session to a `ScanJob` so the existing export pipeline does not need to change.
- **`clearanceRect`** on `ClearanceResult` is a backward-compatible computed alias for
  `serviceAccessRect`. Existing callers continue to work without modification.
- Backward-compatible `init(from:)` decoders on `TaggedObject`, `TaggedPhoto`, and
  `PropertyScanSession` ensure that records saved before new fields were introduced
  (`linkedPhotoIDs`, `syncState`, `cameraPose`, etc.) still decode cleanly.

### What is not yet wired

- **Atlas transport** — `AtlasSync` contains a real upload queue, retry logic, and delegate
  callbacks, but `performPhotoUpload` and `performSessionMetadataUpload` are stubs.
  They will be wired to the real Atlas API endpoint when it is available.
- **AtlasMindClient** — `submitHandoff(session:)` is wired to the real
  `https://next.atlas-phm.uk/api/property/import` endpoint. Requires a valid auth token
  stored in the Keychain via `AtlasKeychainStore`.
- **End-to-end UX polish** — the session model and persistence foundation are in place;
  the final engineer workflow (whole-house single-pass capture flow) is not yet fully complete.

### What does not change

- **`ScanJob` export pipeline** — `ExportPackageBuilder`, `ExportBuilder`, and the
  `ScanBundleV1` contract are all unchanged. The export path remains `PropertyScanSession
  → toScanJob() → ExportPackageBuilder`.
- **Scanner adapter protocol** — `ScannerAdapterProtocol`, `MockScannerAdapter`, and
  `RoomCaptureViewModel` are unchanged.

### Key design rules

- **No recommendation logic** in this app
- **No heat-loss logic** in this app
- **No Atlas floor-plan canonical ownership**
- Scanner adapter is **protocol-based** — swap `MockScannerAdapter` → `RoomPlanScannerAdapter`
- Export emits `ScanBundleV1` matching `atlas-contracts` shape

---

## Session / Room Relationship

This is the conceptual heart of the current change:

- **Rooms are subordinate capture units inside one property session.**
  A `PropertyScanSession` holds a list of `ScannedRoom` records, each of which holds its own
  tagged objects and photos.
- **Objects and photos can exist at room level or session level.**
  `session.taggedObjects` and `session.photos` hold items not yet assigned to a specific room.
  `session.allTaggedObjects` and `session.allPhotos` aggregate both.
- **All rooms in a session share one coordinate context.**
  `roomAdjacencies` and `roomPlacements` define how rooms relate to each other spatially
  within the same session.

Previously, each `ScanJob` was an isolated room-level job. The session model enables
whole-house, single-pass surveying as one unit of work.

---

## Domain Layers

| Layer | Contents |
|-------|----------|
| **1 — Geometry** | rooms, walls, openings, approximate dimensions |
| **2 — Service tags** | boiler, cylinder, radiator, UFH manifold, flue, controls, meter, plant space, emitters |
| **3 — Evidence** | photos, notes, confidence flags, confirmed placements |
| **4 — Handoff** | direct submission to Atlas Mind via `AtlasPropertyV1` |

---

## Service Object Categories

**Heat Source / Plant** — boiler, heat pump, cylinder, thermal store, buffer vessel, pump, low loss header, expansion vessel, manifold, zone valve

**Emitters** — radiator, radiator drop, towel rail, UFH zone, fan convector

**Services / Utilities** — gas meter, electric meter, consumer unit, stop tap, flue, drain point

**Controls** — room thermostat, programmer, smart controller, thermostat receiver

**Structural / Siting** — airing cupboard, loft hatch, external wall candidate, likely flue route, service void, plant space

---

## Requirements

- Xcode 15+
- iOS 17+ / iPadOS 17+
- Swift 5.9+

Camera permission is required for room scanning.

---

## Getting Started

1. Clone the repo
2. Open `AtlasScan.xcodeproj` in Xcode
3. Select the `AtlasScan` scheme
4. Build and run on a simulator or device (iOS 17+)

In the simulator, `MockScannerAdapter` simulates a 4-second room capture so the full flow can be exercised without a physical device.

---

## Atlas Mind Handoff

When the engineer taps **Send to Atlas Mind**, the app:

1. Maps the completed `PropertyScanSession` to a canonical `AtlasPropertyV1` payload via
   `VisitSessionMapper`.
2. POSTs the JSON payload directly to `https://next.atlas-phm.uk/api/property/import`
   using `AtlasMindClient`.
3. Shows a spinner while submitting, a confirmation tick on success, or a retryable
   error screen on failure.

The engineer never sees raw JSON. The handoff is invisible — data flows directly into
the Atlas Mind database.

`ScanBundleV1` is retained as a compatibility export but is no longer the primary
handoff path. `AtlasPropertyV1` supersedes it as the canonical contract between
Atlas Scan and Atlas Mind.

---

## Related Repositories

- [Atlas-recommendation](https://github.com/martinbibb-cmd/Atlas-recommendation) — recommendation engine
- [Atlas-contracts](https://github.com/martinbibb-cmd/Atlas-contracts) — shared contract types (ScanBundleV1)
