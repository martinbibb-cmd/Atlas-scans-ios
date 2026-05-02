# Atlas Scan — TestFlight Release Notes
## Version 1.0 (Build 1) — Internal Testing

> **Internal testers only.** This build is not a public release.
> Increment `CURRENT_PROJECT_VERSION` in Build Settings before the next TestFlight upload.

---

## What to Test

Focus your testing on the full evidence-capture-to-handoff journey:

1. **App launch and home screen** — confirm the app opens without crash and all home cards appear.
2. **Diagnostics screen** — tap **Diagnostics** at the bottom of the home screen.
   - Verify **Build & Device Info** shows correct app version (`1.0`), build number (`1`), bundle ID, device model, and iOS version.
   - Verify LiDAR and RoomPlan availability are reported correctly for your device.
   - Verify **Permissions** lists Camera, Microphone, Speech Recognition, Photo Library, and Motion / AR with accurate statuses.
3. **Permission grant flow** — start a visit, trigger each capture type, and confirm permission prompts appear.
4. **Start a capture visit** — create a new local visit and capture at least one room scan, one photo, and one voice note.
5. **Review evidence** — open **Review Evidence**, confirm / reject items, and verify badge counts update.
6. **Complete visit and handoff** — complete capture, check that Atlas Mind URL shows **Ready**, and tap **Continue in Atlas Mind** (or verify graceful handling if Mind is not installed).
7. **Saved visits** — exit a visit mid-capture, reopen it from **Saved Visits**, and confirm evidence is preserved.
8. **Report TestFlight Issue** — tap the new button in **Diagnostics** and verify a pre-filled feedback sheet appears with correct build and device details.

---

## What Is Expected to Work

| Feature | Expected behaviour |
|---|---|
| Home screen | Loads without crash; all four cards visible |
| Diagnostics → Build Info | Shows version 1.0 / build 1 / correct bundle ID |
| Diagnostics → Permissions | Reflects current permission grant state accurately |
| Report TestFlight Issue | Share sheet opens with pre-filled build + device text |
| Start visit | `StartVisitView` sheet appears; visit persisted after creation |
| Room scan (LiDAR device) | RoomPlan capture session starts; mesh renders |
| Room scan (non-LiDAR device) | "LiDAR Not Available" message shown — no crash or blank screen |
| Photo capture | Camera or photo library picker works; photo added to draft |
| Voice note | Recording starts; transcription appears after stop |
| Floor plan editor | Drawing canvas opens; snapshot can be saved |
| Review evidence | Confirm / reject controls update statuses and badges |
| Complete capture + handoff | Atlas Mind deep-link opens Mind (or graceful fallback) |
| Saved visits | Existing drafts visible; evidence preserved on reopen |
| Developer mode | 7 taps on "Atlas Scan" label toggles dev mode; orange banner shown |

---

## Known Limitations

- **LiDAR / RoomPlan requires physical device.** Room scanning is unavailable on Simulator. Test on iPhone 12 Pro or later for LiDAR features.
- **Atlas Mind handoff requires Atlas Mind installed.** The deep-link is a no-op when Atlas Mind is not on the same device.
- **No cloud sync.** All data is stored on-device in the app's Documents directory. There is no iCloud or remote backup in this build.
- **Single active visit.** Only one visit can be active at a time. Starting a new visit while one is in progress will require exiting the current one first.
- **Cloudflare "Scheduled Visits" list.** Remote visit loading may time out or return an empty list in environments without a configured API endpoint. This is expected; use local visits for testing.
- **Live tagging / AI object recognition** is visible in the capture hub but relies on on-device models. Results may be inconsistent across devices and iOS versions.

---

## What Not to Judge Yet

The following areas are intentionally incomplete or placeholder in this build. Do not file bugs for them unless they cause a crash:

- **UI polish / visual design.** Spacing, fonts, icon choices, and colour usage are functional but not final.
- **Error message copy.** Error strings are developer-facing placeholders.
- **Export file format.** The `.atlasvisit` workspace export is a development artifact; the schema may change.
- **Atlas Mind PWA.** Content and behaviour inside the Mind WebView is owned by the Atlas Mind product and is outside scope for this build.
- **Localisation.** The app is English-only at this stage.
- **Accessibility.** VoiceOver and Dynamic Type have not been audited.
- **Performance on older devices.** The app targets iOS 17+ but has not been optimised for memory or battery on A12 or earlier chips.

---

## Build Configuration

| Setting | Value |
|---|---|
| App version (`MARKETING_VERSION`) | `1.0` |
| Build number (`CURRENT_PROJECT_VERSION`) | `1` |
| Bundle ID | `uk.atlas-phm.scan` |
| Minimum iOS | `17.0` |
| Development team | `34Y4H49QMY` (Atlas PHM Ltd) |

> **Before the next TestFlight upload:** increment `CURRENT_PROJECT_VERSION` in Xcode → Project → Build Settings (e.g. `1` → `2`).

---

## Feedback Template

Copy the template below into your TestFlight feedback or email and fill in all fields.
Alternatively, tap **Diagnostics → Report TestFlight Issue** inside the app — the form will be pre-filled with your build and device details.

```
## Atlas Scan TestFlight Issue Report

**App Version**: <from Diagnostics → Build & Device Info>
**Build Number**: <from Diagnostics → Build & Device Info>
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
