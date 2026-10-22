import Foundation

/// State the app publishes for its widget and Control Center control, through the shared App Group.
struct SharedState: Codable, Equatable {
    var isActive: Bool
    var until: Date?
    var status: String

    static let off = SharedState(isActive: false, until: nil, status: "")

    private static let key = "sharedState"

    private static var defaults: UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "WakefulAppGroup") as? String, !group.isEmpty
        else { return nil }
        return UserDefaults(suiteName: group)
    }

    static func load() -> SharedState {
        guard let data = defaults?.data(forKey: key),
              let state = try? JSONDecoder().decode(SharedState.self, from: data)
        else { return .off }
        if let until = state.until, until <= .now { return .off }
        return state
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults?.set(data, forKey: Self.key)
    }
}

enum WakefulURL {
    static let toggle = URL(string: "wakeful://toggle")!
    static let stop = URL(string: "wakeful://stop")!
    static let start = URL(string: "wakeful://start")!

    static func start(minutes: Int) -> URL {
        URL(string: "wakeful://start?minutes=\(minutes)")!
    }
}

enum WidgetKinds {
    static let status = "com.dionlima.wakeful.status"
    static let control = "com.dionlima.wakeful.control"
}
