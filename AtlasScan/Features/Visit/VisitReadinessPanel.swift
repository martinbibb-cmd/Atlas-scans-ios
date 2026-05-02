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
#Preview {
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
#endif
