import SwiftUI
import AtlasContracts

// MARK: - VisitReadinessPanel
//
// Shows all seven readiness flags as a checklist.
//
// Used in:
//   • VisitHomeView — always-visible readiness summary
//   • Complete capture gate sheet — blocking checklist

struct VisitReadinessPanel: View {

    let readiness: VisitReadinessV1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReadinessRow(label: "Rooms captured",          isReady: readiness.hasRooms)
            ReadinessRow(label: "Photos taken",            isReady: readiness.hasPhotos)
            ReadinessRow(label: "Heating system tagged",   isReady: readiness.hasHeatingSystem)
            ReadinessRow(label: "Hot water system tagged", isReady: readiness.hasHotWaterSystem)
            ReadinessRow(label: "Boiler tagged",           isReady: readiness.hasBoiler)
            ReadinessRow(label: "Flue tagged",             isReady: readiness.hasFlue)
            ReadinessRow(label: "Voice notes recorded",    isReady: readiness.hasNotes)
        }
    }
}

// MARK: - ExportReadinessGateView
//
// Compact export-gate panel shown in the spatial walkthrough and export flow.
//
// Displays the three critical capture flags — boiler pinned, flue pinned,
// and clearance verified — and exposes an Export button that is disabled
// until all three pass plus the full VisitReadinessV1.isReady check.
//
// Usage:
//   ExportReadinessGateView(visit: store.draft) { performExport() }

struct ExportReadinessGateView: View {

    let visit: CaptureSessionDraft
    let onExport: () -> Void

    private var readiness: VisitReadinessV1 {
        deriveVisitReadinessFromFieldSurvey(visit.toFieldSurvey())
    }

    private var clearanceOK: Bool {
        !visit.hasClearanceConflicts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Capture Readiness")
                .font(.headline)

            ReadinessRow(label: "Boiler Pinned",       isReady: readiness.hasBoiler)
            ReadinessRow(label: "Flue Pinned",         isReady: readiness.hasFlue)
            ReadinessRow(label: "Clearance Verified",  isReady: clearanceOK)

            Button(action: onExport) {
                Label("Export to Atlas Mind", systemImage: "arrow.up.forward.square.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!readiness.isReady || !clearanceOK)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - ReadinessRow

private struct ReadinessRow: View {

    let label: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReady ? .green : Color(.tertiaryLabel))
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(isReady ? .primary : .secondary)
            Spacer()
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Readiness Panel") {
    let readiness = VisitReadinessV1(
        hasRooms: true,
        hasPhotos: true,
        hasHeatingSystem: false,
        hasHotWaterSystem: false,
        hasBoiler: false,
        hasFlue: false,
        hasNotes: true
    )
    List {
        Section {
            VisitReadinessPanel(readiness: readiness)
        } header: {
            Text("Readiness")
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Export Gate — Not Ready") {
    ExportReadinessGateView(
        visit: CaptureSessionStore.newSession(visitReference: "JOB-2025-0001"),
        onExport: {}
    )
    .padding()
}

#Preview("Export Gate — Ready") {
    var draft = CaptureSessionStore.newSession(visitReference: "JOB-2025-0002")
    var r1 = CapturedRoomScanDraft()
    r1.roomLabel = "Kitchen"
    r1.rawWidthM = 4.5
    r1.rawDepthM = 3.8
    draft.roomScans = [r1]
    var boiler = CapturedObjectPinDraft(type: .boiler)
    boiler.roomId = r1.id
    var flue = CapturedObjectPinDraft(type: .flue)
    flue.roomId = r1.id
    draft.objectPins = [boiler, flue]
    draft.photos = [CapturedPhotoDraft(localFilename: "photo1.jpg")]
    return ExportReadinessGateView(visit: draft, onExport: {})
        .padding()
}
#endif
