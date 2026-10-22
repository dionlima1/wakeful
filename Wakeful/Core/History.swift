import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    var label: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Local-only log of keep-awake sessions. Nothing leaves the Mac.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()
    private static let maxEntries = 1000

    private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL = {
        let folder = URL.applicationSupportDirectory.appending(path: "Wakeful", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "history.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    func record(start: Date, end: Date, label: String) {
        guard Preferences.historyEnabled, end.timeIntervalSince(start) >= 5 else { return }
        entries.insert(HistoryEntry(start: start, end: end, label: label), at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    /// Awake time per calendar day for the last `days` days, oldest first. Sessions crossing
    /// midnight are split between the days they cover.
    func dailyTotals(days: Int, calendar: Calendar = .current) -> [(day: Date, seconds: TimeInterval)] {
        let today = calendar.startOfDay(for: .now)
        return (0..<days).reversed().compactMap { offset in
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let seconds = entries.reduce(0.0) { total, entry in
                let overlap = min(entry.end, dayEnd).timeIntervalSince(max(entry.start, dayStart))
                return total + max(0, overlap)
            }
            return (dayStart, seconds)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
