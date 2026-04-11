import SwiftUI

// MARK: - VoiceNoteCategoryPicker
//
// A compact picker that lets the engineer tag a voice note with an
// extraction category before or after recording.
//
// Shows a horizontally scrollable chip strip for quick selection.
// Used inside VoiceNoteRecorderSheet when the engineer wants to
// categorise a note explicitly (produces high-confidence extraction).

struct VoiceNoteCategoryPicker: View {

    @Binding var selection: SessionFactCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "None" chip to clear selection
                chip(
                    label: "General",
                    symbol: "mic",
                    isSelected: selection == nil
                ) {
                    selection = nil
                }

                ForEach(SessionFactCategory.allCases, id: \.self) { category in
                    chip(
                        label: category.displayName,
                        symbol: category.symbolName,
                        isSelected: selection == category
                    ) {
                        selection = selection == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func chip(
        label: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption2)
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.accentColor : Color(.separator),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    struct PreviewWrapper: View {
        @State private var selection: SessionFactCategory? = nil
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                VoiceNoteCategoryPicker(selection: $selection)
                Text(selection.map { "Selected: \($0.displayName)" } ?? "No category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            .padding(.vertical)
        }
    }
    return PreviewWrapper()
}
#endif
