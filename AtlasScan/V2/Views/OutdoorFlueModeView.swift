/// OutdoorFlueModeView — Captures outdoor flue terminal observations.

import SwiftUI
import AtlasScanCore

struct OutdoorFlueModeView: View {
    @ObservedObject var coordinator: ScanSessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var clearanceDistanceM: Double = 0
    @State private var selectedOpeningType: OpeningType = .window

    var body: some View {
        NavigationStack {
            Form {
                Section("Flue clearance") {
                    HStack {
                        Text("Distance to nearest opening (m)")
                        Spacer()
                        TextField("0.0", value: $clearanceDistanceM, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Picker("Opening type", selection: $selectedOpeningType) {
                        ForEach(OpeningType.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                }
            }
            .navigationTitle("Outdoor Flue Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let flag = QAFlagV1(
                            type: clearanceDistanceM >= 0.3 ? .clearancePass : .flueConflict,
                            detail: "Flue distance: \(String(format: "%.2f", clearanceDistanceM))m. Opening: \(selectedOpeningType.rawValue)"
                        )
                        coordinator.emitQAFlag(flag)
                        dismiss()
                    }
                }
            }
        }
    }
}
