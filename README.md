# Atlas Scan — iOS

A native iPhone/iPad app for service-engineering room capture.

**Atlas Scan** is the specialist capture companion to [Atlas](https://github.com/martinbibb-cmd/Atlas-recommendation).  
It owns **capture only** — room geometry, service-object tagging, and export.  
It does not contain recommendation logic, heat-loss calculation, or survey truth.

---

## What It Does

1. **Scan rooms** — walk the room, see geometry captured live (RoomPlan in PR 2; mock adapter in this PR)
2. **Tag service objects** — tap-to-add boiler, radiator, cylinder, manifold, flue, controls, meters, and more
3. **Review each room** — mark reviewed, add notes, confirm object placements
4. **Export to Atlas** — produce a versioned `ScanBundleV1` JSON bundle ready for Atlas ingestion

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
├── Models/                       ScanJob, ScannedRoom, TaggedObject, etc.
├── Services/                     ScanJobStore (persistence), ExportBuilder
├── Contracts/                    ScanBundleV1 — atlas-contracts export shape
└── DevFixtures/                  MockData for previews and simulator
```

### Key design rules

- **No recommendation logic** in this app
- **No heat-loss logic** in this app
- **No Atlas floor-plan canonical ownership**
- Scanner adapter is **protocol-based** — swap `MockScannerAdapter` → `RoomPlanScannerAdapter` in PR 2
- Export emits `ScanBundleV1` matching `atlas-contracts` shape

---

## Domain Layers

| Layer | Contents |
|-------|----------|
| **1 — Geometry** | rooms, walls, openings, approximate dimensions |
| **2 — Service tags** | boiler, cylinder, radiator, UFH manifold, flue, controls, meter, plant space, emitters |
| **3 — Evidence** | photos, notes, confidence flags, confirmed placements |
| **4 — Export** | versioned `ScanBundleV1` bundle to Atlas |

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

## PR Roadmap

| PR | Focus |
|----|-------|
| **PR 1 (this)** | Bootstrap app shell, models, tagging UI, export scaffolding, mock scanner |
| **PR 2** | RoomPlan integration — real LiDAR/camera scan |
| **PR 3** | Service tagging UX polish — photo evidence, placement editing |
| **PR 4** | Atlas export — real `ScanBundleV1`, validate + share/upload |

---

## Export Bundle Shape

The export produces a `ScanBundleV1` JSON bundle:

```json
{
  "schemaVersion": "1.0.0",
  "bundleID": "...",
  "exportedAt": "2024-01-01T10:00:00.000Z",
  "job": { "id": "...", "propertyAddress": "...", ... },
  "rooms": [
    {
      "id": "...",
      "name": "Living Room",
      "taggedObjects": [
        { "category": "radiator", "label": "Radiator", ... }
      ],
      ...
    }
  ]
}
```

Atlas decides what the scan data means. This app exports draft spatial evidence only.

---

## Related Repositories

- [Atlas-recommendation](https://github.com/martinbibb-cmd/Atlas-recommendation) — recommendation engine
- [Atlas-contracts](https://github.com/martinbibb-cmd/Atlas-contracts) — shared contract types (ScanBundleV1)
