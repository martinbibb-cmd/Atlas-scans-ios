import SwiftUI

// MARK: - JSONInspectorView
//
// A read-only inspector for a JSON string.
// Used by AtlasHandoffView to let engineers inspect the raw AtlasPropertyV1 payload
// before sharing or saving.

struct JSONInspectorView: View {

    let json: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var displayText: String {
        guard !searchText.isEmpty else { return json }
        // Highlight is not practical in plain text; just confirm the term is present.
        return json
    }

    private var matchCount: Int {
        guard !searchText.isEmpty else { return 0 }
        return json.components(separatedBy: searchText).count - 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(displayText)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Payload Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = json
                        #endif
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search payload")
            .overlay(alignment: .bottom) {
                if !searchText.isEmpty {
                    Text("\(matchCount) match\(matchCount == 1 ? "" : "es")")
                        .font(.caption2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    JSONInspectorView(json: """
    {
      "schemaVersion" : "1.0",
      "propertyID" : "A1B2C3D4-0000-0000-0000-000000000001",
      "jobReference" : "ATL-2024-001",
      "propertyAddress" : "14 Maple Street, Anytown"
    }
    """)
}
#endif
