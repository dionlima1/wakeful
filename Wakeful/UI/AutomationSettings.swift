import AppKit
import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct AutomationSettings: View {
    @AppStorage(PrefKey.autoAgentMode) private var autoAgentMode = false
    @AppStorage(PrefKey.agentNames) private var agentNames = Preferences.defaultAgentNames
    @State private var triggers = TriggerStore.shared
    @State private var editor: TriggerEditor?
    @State private var pickingApp: AppTriggerKind?

    enum TriggerEditor: Identifiable {
        case wifi, schedule
        var id: Self { self }
    }

    enum AppTriggerKind: Identifiable {
        case running, frontmost
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Keep the Mac awake automatically while an AI agent runs", isOn: $autoAgentMode)
                TextField("Agent process names", text: $agentNames, prompt: Text(verbatim: Preferences.defaultAgentNames))
                HStack {
                    Spacer()
                    Button("Restore Defaults") { agentNames = Preferences.defaultAgentNames }
                }
            } header: {
                Text("AI Agents")
            } footer: {
                Text("Comma-separated process names. Wakeful checks every few seconds and lets the Mac sleep again once they all finish.")
            }

            Section {
                if triggers.triggers.isEmpty {
                    Text("No triggers yet. Add one to keep the Mac awake automatically in certain situations.")
                        .foregroundStyle(.secondary)
                }
                ForEach($triggers.triggers) { $trigger in
                    HStack {
                        Image(systemName: trigger.condition.symbol)
                            .frame(width: 20)
                            .foregroundStyle(.tint)
                        Toggle(trigger.condition.title, isOn: $trigger.isEnabled)
                        Button(role: .destructive) {
                            triggers.triggers.removeAll { $0.id == trigger.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove trigger")
                    }
                }
                addMenu
            } header: {
                Text("Triggers")
            } footer: {
                Text("While any enabled trigger is active, your Mac stays awake. A session you start by hand always takes precedence.")
            }

            Section("Terminal") {
                Text("Keep awake until a command finishes:")
                Text(verbatim: "open -g \"wakeful://watch?pid=$$\" && your-command")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Text("Or control Wakeful from scripts, Raycast or Alfred:")
                Text(verbatim: "wakeful://start?minutes=45 · wakeful://stop · wakeful://toggle")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editor) { editor in
            switch editor {
            case .wifi: WiFiTriggerSheet { add(.wifi(name: $0)) }
            case .schedule: ScheduleTriggerSheet { add($0) }
            }
        }
        .fileImporter(
            isPresented: Binding(get: { pickingApp != nil }, set: { if !$0 { pickingApp = nil } }),
            allowedContentTypes: [.application]
        ) { result in
            guard let url = try? result.get(), let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier
            else { return }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            add(pickingApp == .frontmost ? .appFrontmost(bundleID: bundleID, name: name) : .appRunning(bundleID: bundleID, name: name))
        }
    }

    private var addMenu: some View {
        Menu {
            Button("External display connected") { add(.externalDisplay) }
            Button("Power adapter connected") { add(.powerAdapter) }
            Button("Camera or microphone in use (video calls)") { add(.videoCall) }
            Button("Connected to a Wi‑Fi network…") { editor = .wifi }
            Button("On a schedule…") { editor = .schedule }
            Divider()
            Menu("App is open") { appItems(frontmost: false) }
            Menu("App is in front") { appItems(frontmost: true) }
        } label: {
            Label("Add Trigger", systemImage: "plus")
        }
        .fixedSize()
    }

    @ViewBuilder
    private func appItems(frontmost: Bool) -> some View {
        ForEach(ProcessList.regularApps(), id: \.processIdentifier) { app in
            if let bundleID = app.bundleIdentifier, let name = app.localizedName {
                Button(name) {
                    add(frontmost ? .appFrontmost(bundleID: bundleID, name: name) : .appRunning(bundleID: bundleID, name: name))
                }
            }
        }
        Divider()
        Button("Choose App…") { pickingApp = frontmost ? .frontmost : .running }
    }

    private func add(_ condition: TriggerCondition) {
        guard !triggers.triggers.contains(where: { $0.condition == condition }) else { return }
        triggers.triggers.append(Trigger(condition: condition))
        SessionController.shared.checkAutomation()
    }
}

private struct WiFiTriggerSheet: View {
    var onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var location = LocationPermission.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep awake on a Wi‑Fi network").font(.headline)
            TextField("Network name", text: $name)
            HStack {
                Button("Use Current Network") {
                    if let current = Sensors.currentWiFiName() { name = current } else { location.request() }
                }
                if !location.isAuthorized {
                    Text("macOS requires Location access to read the Wi‑Fi name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    onAdd(name.trimmingCharacters(in: .whitespaces))
                    location.request()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

private struct ScheduleTriggerSheet: View {
    var onAdd: (TriggerCondition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var end = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep awake on a schedule").font(.headline)
            HStack(spacing: 6) {
                ForEach(orderedWeekdays, id: \.self) { day in
                    let selected = weekdays.contains(day)
                    Button(Calendar.current.veryShortWeekdaySymbols[day - 1]) {
                        if selected { weekdays.remove(day) } else { weekdays.insert(day) }
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? .accentColor : .secondary)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                }
            }
            DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
            DatePicker("To", selection: $end, displayedComponents: .hourAndMinute)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    onAdd(.schedule(weekdays: weekdays, startMinute: minutes(start), endMinute: minutes(end)))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(weekdays.isEmpty || minutes(start) == minutes(end))
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

@MainActor
@Observable
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermission()
    private let manager = CLLocationManager()
    private(set) var isAuthorized = false

    override private init() {
        super.init()
        manager.delegate = self
        isAuthorized = manager.authorizationStatus == .authorizedAlways
    }

    func request() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { isAuthorized = status == .authorizedAlways }
    }
}
