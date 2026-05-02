# Atlas Scan — TestFlight Readiness Checklist

## App Purpose

Atlas Scan is a field-capture iOS app for service-engineering site surveys.
Engineers use it to record room geometry (RoomPlan), photos, voice notes, tagged objects, and floor plans during a visit, then hand the structured data off to Atlas Mind for analysis and reporting.

---

## Build Configuration

| Setting | Value |
|---|---|
| Bundle identifier | `uk.atlas-phm.scan` |
| App version (MARKETING_VERSION) | `1.0` |
| Build number (CURRENT_PROJECT_VERSION) | `1` |
| Minimum iOS version | `17.0` |
| Signing style | Automatic |
| Development team | `34Y4H49QMY` (Atlas PHM Ltd) |
| Xcode scheme | `AtlasScan` |

> **Before archiving for TestFlight:** increment `CURRENT_PROJECT_VERSION` in Xcode → Project → Build Settings for each new upload (e.g. 1 → 2 → 3).

---

## Test Account

No test account is required. The app operates entirely with locally stored data; there is no login or backend authentication step.

---

## Required Permissions

The app will request the following permissions at runtime. Each must be granted for full functionality.

| Permission | When requested | Purpose |
|---|---|---|
| Camera | On first room scan or photo capture | Room geometry scanning (RoomPlan / ARKit) and evidence photos |
| Microphone | On first voice note | Recording audio for on-device transcription |
| Speech Recognition | On first voice note | On-device transcription of voice notes |
| Photo Library (Read) | When importing from library | Importing evidence photos |
| Photo Library (Add) | If saving to library | Saving captured photos back to the camera roll |
| Local Network | If Multipeer Connectivity is enabled | Discovering nearby devices for collaborative capture (future) |
| Motion & Fitness | During ARKit scanning | Orientation and motion data for room-capture accuracy |

---

## Known Limitations (Build 1.0, build 1)

- **Simulator only:** RoomPlan / LiDAR capture requires a physical iPhone 12 Pro or later with LiDAR. The room-scan screen will be unavailable on simulators.
- **Atlas Mind handoff:** The "Continue in Atlas Mind" deep-link requires Atlas Mind to be installed on the same device. If not installed, the handoff step is a no-op.
- **No cloud sync:** All visit data is stored on-device in the app's Documents directory. No iCloud or remote backup is implemented in this build.
- **Single active visit:** Only one visit can be active at a time. Starting a new visit archives the previous one locally.

---

## Test Script

Walk through the following sequence to exercise the core capture → review → handoff journey.

### 1. Start a visit
1. Launch Atlas Scan.
2. Tap **Start New Visit**.
3. Enter a site/property name and confirm.

### 2. Capture a room
1. From the visit screen, tap **Add Room**.
2. Enter a room name and tap **Start Room Scan**.
3. Move the iPhone around the room for 15–30 seconds until RoomPlan shows a reasonable mesh.
4. Tap **Done** to accept the scan.

### 3. Capture a photo
1. In the room detail, tap **Add Photo**.
2. Take a photo of a service object or area of interest.
3. Confirm the capture.

### 4. Add a voice note
1. Tap **Add Note** (microphone icon).
2. Speak a short note (e.g. "Boiler is located in the utility cupboard under the stairs").
3. Tap stop — the note should appear as a transcript.

### 5. Tag an object
1. Tap **Tag Object** on the live camera view.
2. Point at a visible object and confirm the tag label.

### 6. Review captures
1. Tap **Review** from the visit screen.
2. Confirm each piece of evidence using the ✓ / ✗ controls.
3. All evidence should reach **Confirmed** status.

### 7. Complete visit and hand off
1. Tap **Complete Visit**.
2. Confirm readiness is **Ready**.
3. Tap **Continue in Atlas Mind**.
4. Verify Atlas Mind opens (or a "not installed" message is shown gracefully).

---

## Smoke-Test Checklist

Walk through the following sequence on a real device before submitting feedback. Tick each item as you verify it.

### Launch & Diagnostics

- [ ] App launches without crash.
- [ ] Tap **Diagnostics** (below the "Atlas Scan" label on the home screen).
  - [ ] **Build & Device Info** shows correct app version, build number, and bundle ID.
  - [ ] **Build & Device Info** shows correct device model and iOS version.
  - [ ] **Build & Device Info** reports LiDAR as **Available** (iPhone 12 Pro+) or **Unavailable** (older device).
  - [ ] **Permissions** shows the expected status for Camera, Microphone, Speech Recognition, Photo Library, and Motion / AR.
  - [ ] Tapping **Refresh Status** updates the permission rows without crashing.
  - [ ] Close the Diagnostics sheet.

### Permission grant flow

- [ ] Start a new visit, begin a room scan → Camera permission prompt appears (if not yet granted).
- [ ] Add a voice note → Microphone and Speech Recognition prompts appear (if not yet granted).
- [ ] Add a photo via library → Photo Library prompt appears (if not yet granted).
- [ ] Return to **Diagnostics → Permissions** and confirm all granted permissions now show **Granted**.

### LiDAR / RoomPlan fallback

- [ ] On a device **without** LiDAR, tap **Scan Rooms → Add Room Scan**.
  - [ ] Screen shows "LiDAR Not Available" message — **no blank white screen**.
  - [ ] **Dismiss** button returns to the room list without crash.
- [ ] On a device **with** LiDAR, scanning flow starts normally.

### Core capture journey (unchanged)

- [ ] Start a visit, capture at least one room, photo, and voice note.
- [ ] Review and confirm all evidence.
- [ ] Tap **Complete Capture**.
- [ ] On the completion screen, verify the **Atlas Mind URL** row shows **Ready** (green).
  - [ ] If Developer Mode is active (7 taps on "Atlas Scan"), a payload length (chars) row is also shown.
- [ ] Tap **Continue in Atlas Mind** (or **Return to Home** if Mind is not installed).
- [ ] App does not crash at any point.

---

## Failure Report Template

Copy this template into your TestFlight feedback or bug report tool and fill in all fields.

```
## Atlas Scan TestFlight Failure Report

**Build**: <app version> (<build number>)
**Date**: <YYYY-MM-DD>
**Tester**: <name or email>

### Device

| Field        | Value |
|---|---|
| Device Model | <from Diagnostics → Build & Device Info> |
| iOS Version  | <from Diagnostics → Build & Device Info> |
| LiDAR        | Available / Unavailable |

### Permissions at time of failure

| Permission       | Status |
|---|---|
| Camera           | Granted / Denied / Not Asked |
| Microphone       | Granted / Denied / Not Asked |
| Speech           | Granted / Denied / Not Asked |
| Photo Library    | Granted / Denied / Not Asked |
| Motion / AR      | Granted / Unavailable |

### What happened

<Describe what you tapped / did, step by step.>

### Expected behaviour

<What should have happened.>

### Actual behaviour

<What actually happened — crash, blank screen, wrong data, etc.>

### Atlas Mind handoff status

<On the Visit Complete screen: "Atlas Mind URL: Ready" or "Atlas Mind URL: Not available">

### Screenshots / crash log

<Attach screenshots or Xcode crash log here.>
```


### Prerequisites
- Xcode 15 or later
- Apple Developer account with App Store Connect access for team `34Y4H49QMY`
- App record created in App Store Connect with bundle ID `uk.atlas-phm.scan`

### Steps

1. **Open the workspace**
   ```
   open AtlasScan.xcodeproj
   ```

2. **Set the scheme to AtlasScan and destination to "Any iOS Device (arm64)"**
   - Xcode toolbar → Scheme: `AtlasScan` | Device: `Any iOS Device (arm64)`

3. **Bump the build number**
   - Project navigator → AtlasScan target → Build Settings → `CURRENT_PROJECT_VERSION`
   - Increment by 1 for each new TestFlight upload.

4. **Archive**
   - Menu: **Product → Archive**
   - Wait for the Organizer window to open.

5. **Distribute to TestFlight**
   - In Organizer, select the archive → **Distribute App**
   - Choose **App Store Connect** → **Upload**
   - Confirm signing (Automatic should resolve the correct certificate/provisioning profile for team `34Y4H49QMY`).
   - Complete the upload wizard.

6. **Activate build in App Store Connect**
   - Log into [App Store Connect](https://appstoreconnect.apple.com)
   - Navigate to **Apps → Atlas Scan → TestFlight**
   - Wait for the build to finish processing (~5–15 min)
   - Add the build to an **Internal Testing** group
   - Invite testers by email or share the public TestFlight link

### Signing notes
- Team: `34Y4H49QMY` (Atlas PHM Ltd)
- Signing style: **Automatic** — Xcode will create or refresh the distribution certificate and provisioning profile automatically.
- If "No accounts" error appears: Xcode → Settings → Accounts → add the Apple ID associated with the developer subscription.
