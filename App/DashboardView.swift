import SwiftUI
import EnergyBankKit

/// Today's two banks. Empty until the HealthKit and Screen Time importers exist
/// (DESIGN.md, Build Order steps 2–5).
struct DashboardView: View {
    private let ledger = EnergyModel().ledger(day: Day(Date()), sleep: nil, withdrawals: [], workouts: [])

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    BankRow(title: "Mind", value: ledger.total.mentalBalance)
                    BankRow(title: "Body", value: ledger.total.physicalBalance)
                }
                Section {
                    Text("No sleep or screen time recorded yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Energy Bank")
        }
    }
}

private struct BankRow: View {
    let title: String
    let value: Double

    var body: some View {
        LabeledContent(title) {
            Text(value, format: .number.precision(.fractionLength(0)))
                .monospacedDigit()
        }
    }
}

#Preview {
    DashboardView()
}
