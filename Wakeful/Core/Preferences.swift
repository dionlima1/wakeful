import Foundation
import KeyboardShortcuts

enum PrefKey {
    static let leftClickToggles = "leftClickToggles"
    static let allowDisplaySleep = "allowDisplaySleep"
    static let defaultMinutes = "defaultMinutes"
    static let activateAtLaunch = "activateAtLaunch"
    static let showCountdown = "showCountdown"
    static let notifyOnEnd = "notifyOnEnd"
    static let stopOnBattery = "stopOnBattery"
    static let batteryThreshold = "batteryThreshold"
    static let autoAgentMode = "autoAgentMode"
    static let agentNames = "agentNames"
    static let keepAwakeLidClosed = "keepAwakeLidClosed"
    static let historyEnabled = "historyEnabled"
}

enum Preferences {
    static let defaultAgentNames = "claude, codex, gemini, aider, cursor-agent, opencode, goose, amp, ollama"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.leftClickToggles: true,
            PrefKey.allowDisplaySleep: false,
            PrefKey.defaultMinutes: 0,
            PrefKey.activateAtLaunch: false,
            PrefKey.showCountdown: true,
            PrefKey.notifyOnEnd: true,
            PrefKey.stopOnBattery: false,
            PrefKey.batteryThreshold: 15,
            PrefKey.autoAgentMode: false,
            PrefKey.agentNames: defaultAgentNames,
            PrefKey.keepAwakeLidClosed: false,
            PrefKey.historyEnabled: true,
        ])
    }

    private static var defaults: UserDefaults { .standard }

    static var leftClickToggles: Bool { defaults.bool(forKey: PrefKey.leftClickToggles) }
    static var allowDisplaySleep: Bool {
        get { defaults.bool(forKey: PrefKey.allowDisplaySleep) }
        set { defaults.set(newValue, forKey: PrefKey.allowDisplaySleep) }
    }
    /// 0 means indefinitely.
    static var defaultMinutes: Int { defaults.integer(forKey: PrefKey.defaultMinutes) }
    static var activateAtLaunch: Bool { defaults.bool(forKey: PrefKey.activateAtLaunch) }
    static var showCountdown: Bool { defaults.bool(forKey: PrefKey.showCountdown) }
    static var notifyOnEnd: Bool { defaults.bool(forKey: PrefKey.notifyOnEnd) }
    static var stopOnBattery: Bool { defaults.bool(forKey: PrefKey.stopOnBattery) }
    /// 0 disables the low-battery cut-off.
    static var batteryThreshold: Int { defaults.integer(forKey: PrefKey.batteryThreshold) }
    static var autoAgentMode: Bool {
        get { defaults.bool(forKey: PrefKey.autoAgentMode) }
        set { defaults.set(newValue, forKey: PrefKey.autoAgentMode) }
    }
    static var keepAwakeLidClosed: Bool {
        get { defaults.bool(forKey: PrefKey.keepAwakeLidClosed) }
        set { defaults.set(newValue, forKey: PrefKey.keepAwakeLidClosed) }
    }
    static var historyEnabled: Bool { defaults.bool(forKey: PrefKey.historyEnabled) }
    static var agentNames: [String] {
        (defaults.string(forKey: PrefKey.agentNames) ?? defaultAgentNames)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

extension KeyboardShortcuts.Name {
    static let toggleKeepAwake = Self("toggleKeepAwake")
}
