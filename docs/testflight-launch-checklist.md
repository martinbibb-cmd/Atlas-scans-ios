# Atlas Scan — Internal TestFlight Launch Checklist (Build 1)

Use this checklist end-to-end when uploading build 1 and inviting internal testers.
Tick every box before marking the build as ready for feedback.

---

## Prerequisites

- [ ] Xcode 15 or later installed on the build machine.
- [ ] Apple ID for team `34Y4H49QMY` (Atlas PHM Ltd) added in **Xcode → Settings → Accounts**.
- [ ] App record exists in App Store Connect with bundle ID `uk.atlas-phm.scan`.
- [ ] `CURRENT_PROJECT_VERSION` is set to `1` in **Project → Build Settings**.
- [ ] `MARKETING_VERSION` is set to `1.0`.
- [ ] Scheme is set to **AtlasScan** and destination to **Any iOS Device (arm64)**.

---

## 1 · Archive in Xcode

- [ ] Open `AtlasScan.xcodeproj`.
- [ ] Select **Product → Clean Build Folder** (`⇧⌘K`).
- [ ] Select **Product → Archive** (`⇧⌘B` unavailable — use menu or run script).
- [ ] Wait for the Organizer window to open automatically.
- [ ] Confirm the archive appears under **Archives** with today's date and version `1.0 (1)`.

---

## 2 · Validate Archive

- [ ] In Organizer, select the new archive.
- [ ] Click **Validate App**.
- [ ] Choose **App Store Connect** as the distribution method.
- [ ] Select **Automatically manage signing** and confirm team `34Y4H49QMY`.
- [ ] Click **Validate** and wait for the result.
- [ ] Confirm validation completes with **no errors** (warnings about non-public APIs or bitcode are informational only — review but do not block on warnings).

---

## 3 · Upload to App Store Connect

- [ ] Back in Organizer with the validated archive selected, click **Distribute App**.
- [ ] Choose **App Store Connect → Upload**.
- [ ] Leave **Include bitcode for iOS content** checked (or unchecked if Xcode 15+ has removed the option — follow the current default).
- [ ] Leave **Upload your app's symbols** checked so crash symbolication works in TestFlight.
- [ ] Confirm signing: **Automatically manage signing**, team `34Y4H49QMY`.
- [ ] Click **Upload** and wait for the success confirmation dialog.
- [ ] Note the upload timestamp for audit purposes.

---

## 4 · Answer Export Compliance

- [ ] Log in to [App Store Connect](https://appstoreconnect.apple.com).
- [ ] Navigate to **Apps → Atlas Scan → TestFlight**.
- [ ] Wait for the build to reach **Processing** → **Ready to Submit** (typically 5–15 min).
- [ ] If an **Export Compliance** prompt appears, select:
  - **"Does your app use encryption?" → No**
  - (Atlas Scan does not implement custom encryption; standard HTTPS is exempt.)
- [ ] Confirm the build status changes to **Ready to Test**.

---

## 5 · Add Beta App Description

In App Store Connect → **Apps → Atlas Scan → TestFlight → Test Information**:

- [ ] **Beta App Description** — paste the text below:

  > Atlas Scan is a field-capture iOS app for service-engineering site surveys.
  > Engineers use it to record room geometry (RoomPlan / LiDAR), photos, voice notes,
  > tagged objects, and floor plans during a site visit, then hand the structured data
  > off to Atlas Mind for analysis and reporting.
  >
  > This is **Build 1** — an early internal build for flow validation.
  > Expect rough edges in UI polish, error copy, and performance.
  > Focus feedback on core capture → review → handoff correctness.

- [ ] **What to Test** — paste the text below:

  > 1. Launch the app and open Diagnostics — confirm build info and permission statuses.
  > 2. Grant all permissions (Camera, Microphone, Speech Recognition, Photo Library, Motion).
  > 3. Start a visit and capture at least one room scan, one photo, and one voice note.
  > 4. Open Review Evidence, confirm all items.
  > 5. Tap Complete Capture and verify the Atlas Mind URL row shows "Ready".
  > 6. Tap Continue in Atlas Mind (or note graceful handling if Mind is not installed).
  > 7. Exit mid-visit, re-open from Saved Visits, and verify evidence is preserved.

- [ ] **Feedback Email** — set to the team feedback address (e.g. `dev@atlas-phm.com` or equivalent).

- [ ] Save test information.

---

## 6 · Add Tester Instructions

In **TestFlight → Internal Testing → (group) → Build**:

- [ ] Attach `docs/testflight-release-notes-build-1.md` content as the **Test Notes** for build 1.
  Key points to include (summarise if the field has a character limit):
  - LiDAR requires iPhone 12 Pro or later — no crash on non-LiDAR device, but room scan is unavailable.
  - Atlas Mind handoff requires Atlas Mind installed on the same device.
  - Use **Diagnostics → Report TestFlight Issue** to file a pre-filled bug report.
  - Refer to the Feedback Template section for the structured report format.

- [ ] Verify the **Test Notes** field is non-empty before enabling the group.

---

## 7 · State the Known Limitations Explicitly

Confirm the following limitations are visible to testers (either in Test Notes or the Beta App Description):

- [ ] **LiDAR / RoomPlan** — requires physical device with LiDAR (iPhone 12 Pro or later). Unavailable on Simulator.
- [ ] **Atlas Mind handoff** — deep-link is a no-op when Atlas Mind is not installed on the same device.
- [ ] **No cloud sync** — all data stored on-device in the app's Documents directory; no iCloud or remote backup.
- [ ] **Single active visit** — only one visit can be active at a time.
- [ ] **Scheduled Visits list** — may time out or return empty without a configured API endpoint; use local visits for testing.
- [ ] **UI polish / error copy / accessibility** — intentionally incomplete in build 1; do not file cosmetic bugs.

---

## 8 · Add Feedback Route

- [ ] Confirm **Diagnostics → Report TestFlight Issue** button is visible inside the app.
- [ ] Confirm tapping it opens a pre-filled share sheet containing build number, app version, device model, and iOS version.
- [ ] Document the feedback channel in Test Notes: testers should use **Diagnostics → Report TestFlight Issue** or the structured template in the release notes.
- [ ] Verify the feedback email set in step 5 matches the address the team monitors.

---

## 9 · Test Matrix

Before marking the build open for the full internal group, at least one tester must have verified each row:

| # | Scenario | Device requirement | Pass criteria | Verified by | Date |
|---|---|---|---|---|---|
| 1 | Full flow on iPhone **with LiDAR** | iPhone 12 Pro or later | Room scan mesh renders; all evidence confirmed; Atlas Mind URL shows Ready; handoff opens Mind (or graceful fallback) | | |
| 2 | Room scan on iPhone **without LiDAR** | iPhone without LiDAR | "LiDAR Not Available" message shown; no crash or blank screen; Dismiss returns to room list | | |
| 3 | **Permission denied** paths | Any device | Deny Camera → room scan / photo capture shows a permissions error, not a crash; Deny Microphone → voice note shows error; Deny Speech → voice note shows error; Diagnostics reflects denied status | | |
| 4 | **Scan → Review → Complete → Mind handoff** | iPhone with LiDAR + Atlas Mind installed | Full journey without crash: start visit → room scan → photo → voice note → review → confirm all → complete → Atlas Mind opens with payload | | |

- [ ] All four matrix rows have a tester name and date filled in.

---

## 10 · Enable Internal Testing

- [ ] In App Store Connect → **TestFlight → Internal Testing**, confirm the build is in the group.
- [ ] Click **Enable** (or confirm the toggle is on).
- [ ] Send invitations to all internal testers or share the TestFlight public link.
- [ ] Confirm testers receive their TestFlight email invite within 5 minutes.

---

## Done

- [ ] Build 1 is live in TestFlight for internal testers.
- [ ] All test matrix rows are assigned.
- [ ] Feedback channel is confirmed working.
- [ ] Known limitations are communicated.

> **Next upload:** increment `CURRENT_PROJECT_VERSION` (`1` → `2`) in **Project → Build Settings** before archiving again.
