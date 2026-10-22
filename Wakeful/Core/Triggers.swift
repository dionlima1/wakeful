import Foundation

/// A condition that, while true, keeps the Mac awake automatically.
enum TriggerCondition: Codable, Hashable {
    case externalDisplay
    case powerAdapter
    case wifi(name: String)
    case appRunning(bundleID: String, name: String)
    case appFrontmost(bundleID: String, name: String)
    case videoCall
    /// `weekdays` uses `Calendar` numbering (1 = Sunday). Minutes are since midnight; an end before
    /// the start spans midnight.
    case schedule(weekdays: Set<Int>, startMinute: Int, endMinute: Int)

    var title: String {
        switch self {
        case .externalDisplay: String(localized: "An external display is connected")
        case .powerAdapter: String(localized: "The power adapter is connected")
        case .wifi(let name): String(localized: "Connected to Wi‑Fi “\(name)”")
        case .appRunning(_, let name): String(localized: "\(name) is open")
        case .appFrontmost(_, let name): String(localized: "\(name) is in front")
        case .videoCall: String(localized: "The camera or microphone is in use")
        case .schedule(let weekdays, let start, let end):
            String(localized: "\(Self.weekdayList(weekdays)), \(Self.time(start))–\(Self.time(end))")
        }
    }

    var symbol: String {
        switch self {
        case .externalDisplay: "display"
        case .powerAdapter: "powerplug"
        case .wifi: "wifi"
        case .appRunning: "app"
        case .appFrontmost: "macwindow"
        case .videoCall: "video"
        case .schedule: "calendar.badge.clock"
        }
    }

    func isSatisfied(now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch self {
        case .externalDisplay: Sensors.hasExternalDisplay()
        case .powerAdapter: Sensors.isOnPowerAdapter()
        case .wifi(let name): Sensors.currentWiFiName() == name
        case .appRunning(let bundleID, _): Sensors.isRunning(bundleID: bundleID)
        case .appFrontmost(let bundleID, _): Sensors.frontmostBundleID() == bundleID
        case .videoCall: Sensors.isCameraInUse() || Sensors.isMicrophoneInUse()
        case .schedule(let weekdays, let start, let end):
            Self.scheduleContains(now, weekdays: weekdays, start: start, end: end, calendar: calendar)
        }
    }

    static func scheduleContains(_ date: Date, weekdays: Set<Int>, start: Int, end: Int, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday else { return false }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start <= end {
            return weekdays.contains(weekday) && minute >= start && minute < end
        }
        // Overnight window: the part after midnight belongs to the previous day's schedule.
        let previous = weekday == 1 ? 7 : weekday - 1
        return (weekdays.contains(weekday) && minute >= start) || (weekdays.contains(previous) && minute < end)
    }

    static func time(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func weekdayList(_ weekdays: Set<Int>) -> String {
        if weekdays.count == 7 { return String(localized: "Every day") }
        if weekdays == [2, 3, 4, 5, 6] { return String(localized: "Weekdays") }
        if weekdays == [1, 7] { return String(localized: "Weekends") }
        let symbols = Calendar.current.shortWeekdaySymbols
        let firstWeekday = Calendar.current.firstWeekday
        return (0..<7)
            .map { (firstWeekday - 1 + $0) % 7 + 1 }
            .filter(weekdays.contains)
            .map { symbols[$0 - 1] }
            .formatted(.list(type: .and, width: .narrow))
    }
}

struct Trigger: Codable, Hashable, Identifiable {
    var id = UUID()
    var condition: TriggerCondition
    var isEnabled = true
}

@MainActor
@Observable
final class TriggerStore {
    static let shared = TriggerStore()
    private static let key = "triggers"

    var triggers: [Trigger] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Trigger].self, from: data) {
            triggers = decoded
        } else {
            triggers = []
        }
    }

    /// Titles of the enabled triggers whose condition currently holds.
    func activeReasons() -> [String] {
        triggers.filter { $0.isEnabled && $0.condition.isSatisfied() }.map(\.condition.title)
    }

    var needsLocation: Bool {
        triggers.contains { if case .wifi = $0.condition { true } else { false } }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(triggers) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
