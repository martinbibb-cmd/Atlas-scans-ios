import SwiftUI

// MARK: - StartJobView
//
// Entry point for creating a new visit session manually.
//
// The engineer enters a visit/job reference (required) and, optionally, the
// Atlas appointment ID.  When present, the appointment ID is carried through
// into the exported SessionCaptureV2 payload (as appointmentId) so Atlas
// Recommendations can match the capture to the appointment that triggered
// the visit.  It is optional here because engineers can also start ad-hoc
// visits that were not pre-booked in Atlas Recommendations.
//
// For pre-booked visits, the appointment ID is filled automatically by
// VisitPickerView when the engineer selects a scheduled appointment.
//
// "One visit, one session, one home screen."

struct StartJobView: View {

    let onStart: (CaptureSessionDraft) -> Void

    @State private var appointmentId = ""
    @State private var visitReference = ""
    @State private var propertyAddress = ""
    @State private var customerName = ""

    private var isValid: Bool {
        !visitReference.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            headerSection
            Spacer()
            inputSection
            Spacer()
            startButton
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.tint)

            Text("New Visit")
                .font(.largeTitle.bold())

            Text("Enter the visit details to begin capturing.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldGroup {
                fieldLabel("Visit Reference *")
                TextField("e.g. JOB-2025-0001", text: $visitReference)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.title3)
                    .onSubmit {
                        if isValid { startJob() }
                    }
            }

            fieldGroup {
                fieldLabel("Appointment ID (optional — links this visit to Atlas Recommendations)")
                TextField("Atlas appointment UUID", text: $appointmentId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline.monospaced())
            }

            fieldGroup {
                fieldLabel("Property Address (optional)")
                TextField("e.g. 12 Coronation Street, M1 1AA", text: $propertyAddress)
                    .textInputAutocapitalization(.words)
            }

            fieldGroup {
                fieldLabel("Customer Name (optional)")
                TextField("e.g. John Smith", text: $customerName)
                    .textInputAutocapitalization(.words)
            }
        }
        .padding(.horizontal, 24)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
    }

    private func fieldGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Start button

    private var startButton: some View {
        Button(action: startJob) {
            HStack {
                Image(systemName: "play.fill")
                Text("Start Capture")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isValid ? Color.accentColor : Color.secondary.opacity(0.3))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isValid)
    }

    // MARK: - Actions

    private func startJob() {
        guard isValid else { return }
        let apptId = appointmentId.trimmingCharacters(in: .whitespaces)
        var draft = CaptureSessionStore.newSession(
            visitReference: visitReference.trimmingCharacters(in: .whitespaces),
            appointmentId: apptId.isEmpty ? nil : apptId
        )
        let addr = propertyAddress.trimmingCharacters(in: .whitespaces)
        if !addr.isEmpty { draft.propertyAddress = addr }
        let cust = customerName.trimmingCharacters(in: .whitespaces)
        if !cust.isEmpty { draft.customerName = cust }
        onStart(draft)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    StartJobView { _ in }
}
#endif
