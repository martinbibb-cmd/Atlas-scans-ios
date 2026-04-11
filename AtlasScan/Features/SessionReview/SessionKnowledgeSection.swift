import SwiftUI

// MARK: - SessionKnowledgeSection
//
// Reusable view section that shows the structured knowledge coverage
// for a session: what household/system/priority/constraint facts are
// confirmed, what needs review, and what is missing.
//
// Used in both SessionReviewView and SessionCompletionView.

struct SessionKnowledgeSection: View {

    let session: PropertyScanSession

    private var summary: SessionKnowledgeSummary { session.knowledgeSummary }
    private var facts: [ExtractedSessionFact] { session.extractedFacts }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if facts.isEmpty {
                emptyState
            } else {
                groupedFacts
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("No captured needs yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Add voice notes during the walkthrough to capture household, system and customer context.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Grouped facts

    private var groupedFacts: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(SessionFactGroup.allCases, id: \.self) { group in
                let groupFacts = facts.filter { $0.category.group == group }
                if !groupFacts.isEmpty {
                    KnowledgeGroupRow(group: group, facts: groupFacts)
                }
            }

            if !summary.missingEssentials.isEmpty || !summary.reviewWarnings.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                warningsBlock
            }
        }
    }

    // MARK: - Warnings / missing

    private var warningsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(summary.missingEssentials, id: \.self) { msg in
                Label(msg, systemImage: "circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(summary.reviewWarnings, id: \.self) { msg in
                Label(msg, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - KnowledgeGroupRow

private struct KnowledgeGroupRow: View {
    let group: SessionFactGroup
    let facts: [ExtractedSessionFact]

    private var highestConfidence: ConfidenceLevel {
        facts.map(\.confidence).max() ?? .low
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Group icon
            Image(systemName: group.symbolName)
                .font(.subheadline)
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.displayName)
                        .font(.subheadline.weight(.semibold))
                    confidenceBadge
                }

                ForEach(facts.prefix(3)) { fact in
                    Text(fact.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if facts.count > 3 {
                    Text("+\(facts.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        switch highestConfidence {
        case .high:   return .green
        case .medium: return .orange
        case .low:    return .secondary
        }
    }

    private var confidenceBadge: some View {
        Text(highestConfidence.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch highestConfidence {
        case .high:   return .green
        case .medium: return .orange
        case .low:    return .secondary
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("With facts") {
    var session = MockData.sampleSession
    session.extractedFacts = [
        ExtractedSessionFact(
            category: .householdComposition,
            value: "Family of five, two adults, three children.",
            confidence: .high,
            sourceNoteID: UUID()
        ),
        ExtractedSessionFact(
            category: .customerConstraint,
            value: "Customer wants to keep airing cupboard free.",
            confidence: .high,
            sourceNoteID: UUID()
        ),
        ExtractedSessionFact(
            category: .currentSystemIssue,
            value: "Current combi struggles when both showers run.",
            confidence: .medium,
            sourceNoteID: UUID()
        ),
        ExtractedSessionFact(
            category: .waterQuality,
            value: "Hard water area, scaling around taps.",
            confidence: .medium,
            sourceNoteID: UUID()
        ),
    ]
    return List {
        Section("Captured Needs") {
            SessionKnowledgeSection(session: session)
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Empty") {
    let session = PropertyScanSession(propertyAddress: "1 Empty Street")
    return List {
        Section("Captured Needs") {
            SessionKnowledgeSection(session: session)
        }
    }
    .listStyle(.insetGrouped)
}
#endif
