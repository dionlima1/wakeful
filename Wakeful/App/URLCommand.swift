import Foundation

/// `wakeful://` URL scheme, used by scripts, the terminal and launchers like Raycast or Alfred.
///
///     wakeful://start                 default duration
///     wakeful://start?minutes=45
///     wakeful://stop
///     wakeful://toggle
///     wakeful://watch?pid=1234        stay awake until that process exits
///     wakeful://settings?tab=automation
@MainActor
enum URLCommand {
    static var openSettings: ((SettingsTab) -> Void)?

    static func handle(_ url: URL) {
        guard url.scheme == "wakeful", let command = url.host() else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        let session = SessionController.shared
        switch command {
        case "start":
            if let minutes = value("minutes").flatMap(Int.init) { session.start(minutes: minutes) } else { session.startDefault() }
        case "stop":
            session.stop()
        case "toggle":
            session.toggle()
        case "watch":
            guard let pid = value("pid").flatMap(Int32.init), ProcessList.isAlive(pid) else { return }
            let name = value("name") ?? ProcessList.all().first { $0.pid == pid }?.name ?? "PID \(pid)"
            session.start(.process(pid: pid, name: name))
        case "settings":
            let tabs: [String: SettingsTab] = [
                "general": .general, "automation": .automation, "power": .power, "history": .history,
            ]
            openSettings?(value("tab").flatMap { tabs[$0] } ?? .general)
        default:
            break
        }
    }
}
