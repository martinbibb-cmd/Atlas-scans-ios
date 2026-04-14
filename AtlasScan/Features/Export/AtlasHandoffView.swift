import SwiftUI

struct AtlasHandoffView: View {

    let session: PropertyScanSession
    var onHandoffComplete: (() -> Void)?
    @State private var job: ScanJob
    @State private var hasNotifiedCompletion = false

    init(
        session: PropertyScanSession,
        onHandoffComplete: (() -> Void)? = nil
    ) {
        self.session = session
        self.onHandoffComplete = onHandoffComplete
        _job = State(initialValue: session.toScanJob())
    }

    var body: some View {
        ExportPreviewView(job: $job)
            .onChange(of: job.status) { _, status in
                guard status == .exported, !hasNotifiedCompletion else { return }
                hasNotifiedCompletion = true
                onHandoffComplete?()
            }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    AtlasHandoffView(session: MockData.sampleSession)
        .environmentObject(ScanJobStore())
}
#endif
