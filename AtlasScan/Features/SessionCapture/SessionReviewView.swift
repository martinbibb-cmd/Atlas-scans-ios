// SessionReviewView.swift
// Minimal placeholder to satisfy navigation from SessionCaptureView

import SwiftUI

struct SessionReviewView: View {
    let session: PropertyScanSession
    let store: ScanSessionStore

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Reference", value: session.jobReference)
                if !session.engineerName.isEmpty {
                    LabeledContent("Engineer", value: session.engineerName)
                }
                LabeledContent("Address", value: session.propertyAddress)
                LabeledContent("Rooms", value: "\(session.rooms.count)")
                LabeledContent("Objects", value: "\(session.totalTaggedObjects)")
                LabeledContent("Photos", value: "\(session.totalPhotos)")
                if session.totalVoiceNotes > 0 {
                    LabeledContent("Voice Notes", value: "\(session.totalVoiceNotes)")
                }
            }

            Section("Review") {
                Text("This is a placeholder for the session review surface.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Review Session")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SessionReviewView(
            session: PropertyScanSession(
                jobReference: "JOB-DEMO",
                propertyAddress: "12 Survey Street",
                engineerName: "Jane Engineer"
            ),
            store: ScanSessionStore()
        )
    }
}
#endif
