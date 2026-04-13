import SwiftUI

// MARK: - SessionFactReviewView
//
// Full-screen review list of extracted session facts.
// Shows all facts grouped by category with confidence badges,
// source context (room / object / session-level), and provenance.
//
// Presented from the "Captured Needs" section of SessionReviewView.

struct SessionFactReviewView: View {

    let session: PropertyScanSession

    @Environment(\.dismiss) private var dismiss

    private var facts: [ExtractedSessionFact] { session.extractedFacts }

    var body: some View {
        NavigationStack {
            Group {
                if facts.isEmpty {
                    emptyState
                } else {
                    factList
                }
            }
            .navigationTitle("Captured Needs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - List

    private var factList: some View {
        List {
            ForEach(SessionFactGroup.allCases, id: \.self) { group in
                let groupFacts = facts.filter { $0.category.group == group }
                if !groupFacts.isEmpty {
                    Section(group.displayName) {
                        ForEach(groupFacts) { fact in
                            FactRow(fact: fact, session: session)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("No Captured Needs")
                    .font(.headline)
                Text("Add categorised voice notes during the walkthrough to build structured session knowledge.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - FactRow

private struct FactRow: View {
    let fact: ExtractedSessionFact
    let session: PropertyScanSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: fact.category.symbolName)
                    .font(.caption)
                    .foregroundStyle(categoryColor)

                Text(fact.category.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(categoryColor)

                Spacer()

                confidenceBadge
            }

            Text(fact.value)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let snippet = fact.verbatimSnippet {
                Label {
                    Text("You mentioned \"" + snippet + "\"")
                } icon: {
                    Image(systemName: "quote.opening")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
            }

            HStack(spacing: 8) {
                if let roomID = fact.roomID,
                   let room = session.rooms.first(where: { $0.id == roomID }) {
                    Label(room.name, systemImage: "square.split.2x1")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if fact.roomID == nil && fact.objectID == nil {
                    Label("Session level", systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Label(
                    fact.createdAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "clock"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var confidenceBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: fact.confidence.symbolName)
                .font(.caption2)
            Text(fact.confidence.displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.12))
        .foregroundStyle(badgeColor)
        .clipShape(Capsule())
    }

    private var categoryColor: Color {
        switch fact.category.group {
        case .household:   return .blue
        case .usage:       return .orange
        case .priorities:  return .purple
        case .constraints: return .red
        case .system:      return .teal
        }
    }

    private var badgeColor: Color {
        switch fact.confidence {
        case .high:   return .green
        case .medium: return .orange
        case .low:    return .secondary
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    SessionFactReviewView(session: MockData.sampleSession)
}
#endif

