import Charts
import SwiftUI

struct HistoryView: View {
    @AppStorage(PrefKey.historyEnabled) private var historyEnabled = true
    @State private var history = HistoryStore.shared
    @State private var store = ProStore.shared
    @State private var confirmingClear = false

    var body: some View {
        let days = history.dailyTotals(days: 7)
        Form {
            if !store.isPro { UnlockBanner() }

            Group {
                Section {
                    HStack(spacing: 24) {
                        stat("Today", days.last?.seconds ?? 0)
                        stat("Last 7 days", days.reduce(0) { $0 + $1.seconds })
                        stat("Sessions", count: history.entries.count)
                    }
                    Chart(days, id: \.day) { day in
                        BarMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Hours", day.seconds / 3600)
                        )
                        .foregroundStyle(.tint)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                    .chartYAxisLabel("Hours")
                    .frame(height: 140)
                    .accessibilityLabel("Awake time per day for the last 7 days")
                }

                Section("Recent Sessions") {
                    if history.entries.isEmpty {
                        Text("No sessions recorded yet.").foregroundStyle(.secondary)
                    }
                    ForEach(history.entries.prefix(50)) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.label).lineLimit(1)
                                Text(entry.start.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(DurationText.seconds(max(60, entry.duration)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Record history on this Mac", isOn: $historyEnabled)
                    Button("Clear History…", role: .destructive) { confirmingClear = true }
                        .disabled(history.entries.isEmpty)
                } footer: {
                    Text("History is stored only on this Mac and is never sent anywhere.")
                }
            }
            .disabled(!store.isPro)
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear all history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        }
    }

    private func stat(_ title: LocalizedStringKey, _ seconds: TimeInterval) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(DurationText.seconds(seconds)).font(.title2.weight(.semibold)).monospacedDigit()
        }
    }

    private func stat(_ title: LocalizedStringKey, count: Int) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(count, format: .number).font(.title2.weight(.semibold)).monospacedDigit()
        }
    }
}
