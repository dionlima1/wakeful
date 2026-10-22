import AppKit
import UserNotifications
import WidgetKit

enum SessionKind: Equatable {
    case indefinite
    case timed(until: Date)
    /// Stays awake while a specific process (CLI tool, script, agent) is alive.
    case process(pid: pid_t, name: String)
    /// Stays awake while a specific app is running.
    case app(bundleID: String, name: String)
    /// Started by triggers or by AI agent detection; ends when none of the reasons hold anymore.
    case automatic(reasons: [String])

    var historyLabel: String {
        switch self {
        case .indefinite: String(localized: "Manual")
        case .timed: String(localized: "Timer")
        case .process(_, let name), .app(_, let name): name
        case .automatic(let reasons): reasons.first ?? String(localized: "Automatic")
        }
    }
}

enum EndReason {
    case user, timerFinished, processExited(String), appQuit(String), agentsFinished, automationEnded
    case onBattery, lowBattery(Int)

    var message: String? {
        switch self {
        case .user, .automationEnded: nil
        case .timerFinished: String(localized: "Timer finished. Your Mac can sleep again.")
        case .processExited(let name): String(localized: "\(name) finished. Your Mac can sleep again.")
        case .appQuit(let name): String(localized: "\(name) quit. Your Mac can sleep again.")
        case .agentsFinished: String(localized: "All AI agents finished. Your Mac can sleep again.")
        case .onBattery: String(localized: "Stopped because the Mac is running on battery.")
        case .lowBattery(let percent): String(localized: "Stopped because the battery is at \(percent)%.")
        }
    }
}

@MainActor
final class SessionController {
    static let shared = SessionController()

    private(set) var kind: SessionKind?
    var isActive: Bool { kind != nil }
    var isAutomatic: Bool { if case .automatic = kind { true } else { false } }
    var onChange: (() -> Void)?

    private let assertion = PowerAssertion()
    private var startedAt: Date?
    private var ticker: Timer?
    private var tickCount = 0
    /// Set when the user turns off an automatic session, so it doesn't restart until its reasons go away.
    private var automationSuppressed = false
    private var lastAgentReason: String?

    private init() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAssertion() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAutomation() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                self?.appTerminated(bundleID: bundleID)
                self?.checkAutomation()
            }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkAutomation() }
            }
        }
        startTicker()
    }

    // MARK: - Public API

    func start(_ newKind: SessionKind) {
        if case .timed(let until) = newKind, until <= .now { return }
        guard acquireAssertion() else { return }

        closeHistoryEntry()
        kind = newKind
        startedAt = .now
        if !newKind.isAutomaticKind { automationSuppressed = false }
        publish()
    }

    func start(minutes: Int) {
        start(minutes > 0 ? .timed(until: .now.addingTimeInterval(TimeInterval(minutes * 60))) : .indefinite)
    }

    func startDefault() { start(minutes: Preferences.defaultMinutes) }

    func stop(_ reason: EndReason = .user) {
        guard kind != nil else { return }
        if isAutomatic, case .user = reason { automationSuppressed = true }
        closeHistoryEntry()
        assertion.release()
        kind = nil
        startedAt = nil
        publish()
        if let message = reason.message, Preferences.notifyOnEnd { notify(message) }
    }

    func toggle() { isActive ? stop() : startDefault() }

    var remaining: TimeInterval? {
        guard case .timed(let until) = kind else { return nil }
        return max(0, until.timeIntervalSinceNow)
    }

    var statusDescription: String {
        switch kind {
        case nil: String(localized: "Off — your Mac sleeps normally")
        case .indefinite: String(localized: "Awake indefinitely")
        case .timed: String(localized: "Awake for \(Self.format(remaining ?? 0)) more")
        case .process(_, let name): String(localized: "Awake while \(name) runs")
        case .app(_, let name): String(localized: "Awake while \(name) is open")
        case .automatic(let reasons): String(localized: "Awake automatically: \(reasons.first ?? "")")
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Assertions

    private func acquireAssertion() -> Bool {
        assertion.acquire(
            preventDisplaySleep: !Preferences.allowDisplaySleep,
            preventLidSleep: Preferences.keepAwakeLidClosed,
            reason: "Wakeful keep-awake session"
        )
    }

    private func refreshAssertion() {
        guard isActive else { return }
        _ = acquireAssertion()
        onChange?()
    }

    // MARK: - Monitoring

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker?.tolerance = 0.2
    }

    private func tick() {
        tickCount += 1

        if case .timed(let until) = kind {
            if until <= .now { stop(.timerFinished) } else { onChange?() }
        }

        if tickCount % 2 == 0, case .process(let pid, let name) = kind, !ProcessList.isAlive(pid) {
            stop(.processExited(name))
        }

        if tickCount % 5 == 0 { checkAutomation() }
        if tickCount % 30 == 0 { checkBattery() }
    }

    func checkAutomation() {
        var reasons: [String] = []
        var agentReason: String?
        if Preferences.autoAgentMode {
            let agents = ProcessList.agents(matching: Preferences.agentNames)
            if !agents.isEmpty {
                let names = Set(agents.map(\.name)).sorted().formatted(.list(type: .and))
                agentReason = String(localized: "AI agent running (\(names))")
                reasons.append(agentReason!)
            }
        }
        reasons += TriggerStore.shared.activeReasons()

        if reasons.isEmpty {
            automationSuppressed = false
            if isAutomatic { stop(lastAgentReason != nil ? .agentsFinished : .automationEnded) }
            lastAgentReason = nil
            return
        }
        lastAgentReason = agentReason

        switch kind {
        case .automatic(let current) where current != reasons:
            kind = .automatic(reasons: reasons)
            publish()
        case nil where !automationSuppressed && batteryAllowsStart():
            start(.automatic(reasons: reasons))
        default:
            break // A manual session takes precedence over automation.
        }
    }

    private func checkBattery() {
        guard isActive else { return }
        let status = Battery.status()
        guard status.onBattery else { return }
        if Preferences.stopOnBattery {
            stop(.onBattery)
        } else if Preferences.batteryThreshold > 0, let percent = status.percent,
                  percent <= Preferences.batteryThreshold {
            stop(.lowBattery(percent))
        }
    }

    private func batteryAllowsStart() -> Bool {
        let status = Battery.status()
        guard status.onBattery else { return true }
        if Preferences.stopOnBattery { return false }
        if Preferences.batteryThreshold > 0, let percent = status.percent {
            return percent > Preferences.batteryThreshold
        }
        return true
    }

    private func appTerminated(bundleID: String?) {
        if case .app(let watched, let name) = kind, watched == bundleID { stop(.appQuit(name)) }
    }

    // MARK: - Side effects

    private func closeHistoryEntry() {
        guard let kind, let startedAt else { return }
        HistoryStore.shared.record(start: startedAt, end: .now, label: kind.historyLabel)
    }

    private var lastPublished: SharedState?

    /// Updates the menu bar and, when the state actually changed, the widget and Control Center control.
    private func publish() {
        onChange?()
        var until: Date?
        if case .timed(let date) = kind { until = date }
        let state = SharedState(isActive: isActive, until: until, status: statusDescription)
        guard state.isActive != lastPublished?.isActive || state.until != lastPublished?.until else { return }
        lastPublished = state
        state.save()
        WidgetCenter.shared.reloadAllTimelines()
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: WidgetKinds.control)
        }
    }

    private func notify(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Wakeful"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

private extension SessionKind {
    var isAutomaticKind: Bool { if case .automatic = self { true } else { false } }
}
