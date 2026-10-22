import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UserNotifications

enum SettingsTab: Hashable {
    case general, automation, power, history
}

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var tab: SettingsTab = .general
}

struct SettingsView: View {
    @State private var navigation = SettingsNavigation.shared

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("General", systemImage: "gearshape", value: .general) { GeneralSettings() }
            Tab("Automation", systemImage: "wand.and.stars", value: .automation) { AutomationSettings() }
            Tab("Power", systemImage: "battery.75percent", value: .power) { PowerSettings() }
            Tab("History", systemImage: "chart.bar.xaxis", value: .history) { HistoryView() }
        }
        .frame(width: 560, height: 600)
    }
}

private struct GeneralSettings: View {
    @AppStorage(PrefKey.leftClickToggles) private var leftClickToggles = true
    @AppStorage(PrefKey.allowDisplaySleep) private var allowDisplaySleep = false
    @AppStorage(PrefKey.defaultMinutes) private var defaultMinutes = 0
    @AppStorage(PrefKey.activateAtLaunch) private var activateAtLaunch = false
    @AppStorage(PrefKey.showCountdown) private var showCountdown = true
    @AppStorage(PrefKey.notifyOnEnd) private var notifyOnEnd = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Activate when Wakeful launches", isOn: $activateAtLaunch)
            }
            Section {
                Picker("Left click on the menu bar icon", selection: $leftClickToggles) {
                    Text("Toggles keep-awake").tag(true)
                    Text("Opens the menu").tag(false)
                }
                Picker("Default duration", selection: $defaultMinutes) {
                    Text("Indefinitely").tag(0)
                    ForEach([15, 30, 60, 120, 300, 480], id: \.self) { minutes in
                        Text(DurationText.minutes(minutes)).tag(minutes)
                    }
                }
                KeyboardShortcuts.Recorder("Toggle shortcut", name: .toggleKeepAwake)
            }
            Section {
                Toggle("Allow display to sleep (keep only the system awake)", isOn: $allowDisplaySleep)
                Toggle("Show countdown in the menu bar", isOn: $showCountdown)
                Toggle("Notify when a session ends", isOn: $notifyOnEnd)
                    .onChange(of: notifyOnEnd) { _, enabled in
                        if enabled {
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PowerSettings: View {
    @AppStorage(PrefKey.stopOnBattery) private var stopOnBattery = false
    @AppStorage(PrefKey.batteryThreshold) private var batteryThreshold = 15
    @AppStorage(PrefKey.keepAwakeLidClosed) private var keepAwakeLidClosed = false

    var body: some View {
        Form {
            Section("Battery") {
                Toggle("Stop when the Mac switches to battery", isOn: $stopOnBattery)
                Picker("Stop when battery drops to", selection: $batteryThreshold) {
                    Text("Never").tag(0)
                    ForEach([5, 10, 15, 20, 30, 50], id: \.self) { percent in
                        Text(Double(percent) / 100, format: .percent).tag(percent)
                    }
                }
                .disabled(stopOnBattery)
            }
            Section {
                Toggle("Keep awake with the lid closed", isOn: $keepAwakeLidClosed)
            } footer: {
                Text("macOS only allows this while the Mac is connected to power. On battery, closing the lid still puts it to sleep.")
            }
        }
        .formStyle(.grouped)
    }
}

enum DurationText {
    static func minutes(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    static func seconds(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(seconds)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
