import SwiftUI
import AtlasContracts

// MARK: - SessionCaptureV2DebugView
//
// Developer-only inspection view for the active visit's SessionCaptureV2 payload.
//
// IMPORTANT: This view is guarded by DeveloperModeStore.isEnabled and must
// never appear in the normal user flow. It exists solely to help engineers
// verify that capture data is being shaped correctly before Mind handoff.
//
// Access: VisitHomeView developer toolbar → "View SessionCaptureV2".

struct SessionCaptureV2DebugView: View {

    let visit: AtlasScanVisit
    let draft: CaptureSessionDraft

    @Environment(\.dismiss) private var dismiss

    private var capture: SessionCaptureV2 {
        SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
    }

    private var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(capture),
              let str = String(data: data, encoding: .utf8) else {
            return "{ \"error\": \"Failed to encode SessionCaptureV2\" }"
        }
        return str
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(jsonString)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("SessionCaptureV2")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = jsonString
                        #endif
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Text("🛠 Developer-only view — not visible to customers")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var draft = CaptureSessionStore.newSession(visitReference: "PREVIEW-001")
    draft.objectPins.append(CapturedObjectPinDraft(type: .boiler))
    let visit = AtlasScanVisit(visitNumber: "PREVIEW-001", brandId: "ATLAS")
    return SessionCaptureV2DebugView(visit: visit, draft: draft)
}
#endif
