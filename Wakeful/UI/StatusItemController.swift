import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let session = SessionController.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    var openSettings: ((SettingsTab) -> Void)?

    private static let presets = [15, 30, 60, 120, 300, 480]

    override init() {
        super.init()
        menu.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
        }
        session.onChange = { [weak self] in self?.refreshButton() }
        refreshButton()
    }

    // MARK: - Button

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let symbol = switch session.kind {
        case nil: "cup.and.saucer"
        case .automatic: "cup.and.heat.waves.fill"
        default: "cup.and.saucer.fill"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: session.statusDescription)
            ?? NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: session.statusDescription)
        image?.isTemplate = true
        button.image = image
        button.toolTip = session.statusDescription
        button.setAccessibilityValue(session.statusDescription)

        if Preferences.showCountdown, let remaining = session.remaining {
            button.title = " " + SessionController.format(remaining)
        } else {
            button.title = ""
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        let quickToggle = Preferences.leftClickToggles ? !isRightClick : isRightClick

        if quickToggle {
            session.toggle()
        } else {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: session.statusDescription, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if case .automatic(let reasons) = session.kind, reasons.count > 1 {
            for reason in reasons.dropFirst() {
                let item = NSMenuItem(title: "· " + reason, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        if session.isActive {
            menu.addItem(item(String(localized: "Turn Off"), #selector(turnOff)))
        } else {
            menu.addItem(item(String(localized: "Keep Awake Indefinitely"), #selector(turnOnIndefinitely)))
        }

        let durations = NSMenu()
        for minutes in Self.presets {
            durations.addItem(item(DurationText.minutes(minutes), #selector(startPreset(_:)), represented: minutes))
        }
        durations.addItem(.separator())
        durations.addItem(item(String(localized: "Custom…"), #selector(startCustom)))
        menu.addItem(submenu(String(localized: "Keep Awake For"), durations))

        menu.addItem(submenu(String(localized: "While AI Agent Runs"), agentsMenu()))
        menu.addItem(submenu(String(localized: "While App Is Open"), appsMenu()))

        menu.addItem(.separator())
        let displayItem = item(String(localized: "Allow Display to Sleep"), #selector(toggleDisplaySleep))
        displayItem.state = Preferences.allowDisplaySleep ? .on : .off
        menu.addItem(displayItem)

        let lidItem = item(String(localized: "Keep Awake with Lid Closed"), #selector(toggleLidClosed))
        lidItem.state = Preferences.keepAwakeLidClosed ? .on : .off
        menu.addItem(lidItem)

        let autoItem = item(String(localized: "Auto-Activate When AI Agents Run"), #selector(toggleAutoAgents))
        autoItem.state = Preferences.autoAgentMode ? .on : .off
        menu.addItem(autoItem)

        menu.addItem(item(String(localized: "Automatic Triggers…"), #selector(showAutomation)))

        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…"), #selector(showSettings), key: ","))
        menu.addItem(item(String(localized: "Quit Wakeful"), #selector(quit), key: "q"))
    }

    private func agentsMenu() -> NSMenu {
        let sub = NSMenu()
        let agents = ProcessList.agents(matching: Preferences.agentNames)
        if agents.isEmpty {
            let empty = NSMenuItem(title: String(localized: "No AI agents running"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        } else {
            for agent in agents {
                sub.addItem(item("\(agent.name) — PID \(agent.pid)", #selector(startProcess(_:)), represented: agent))
            }
        }
        sub.addItem(.separator())
        sub.addItem(item(String(localized: "Edit Agent List…"), #selector(showAutomation)))
        return sub
    }

    private func appsMenu() -> NSMenu {
        let sub = NSMenu()
        for app in ProcessList.regularApps() {
            guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { continue }
            let entry = item(name, #selector(startApp(_:)), represented: [bundleID, name])
            if let icon = app.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
            }
            sub.addItem(entry)
        }
        return sub
    }

    private func item(_ title: String, _ action: Selector, key: String = "", represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.representedObject = represented
        return item
    }

    private func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }

    // MARK: - Actions

    @objc private func turnOff() { session.stop() }
    @objc private func turnOnIndefinitely() { session.start(.indefinite) }

    @objc private func startPreset(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        session.start(minutes: minutes)
    }

    @objc private func startProcess(_ sender: NSMenuItem) {
        guard let process = sender.representedObject as? RunningProcess else { return }
        session.start(.process(pid: process.pid, name: process.name))
    }

    @objc private func startApp(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String], info.count == 2 else { return }
        session.start(.app(bundleID: info[0], name: info[1]))
    }

    @objc private func startCustom() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Keep awake for how long?")
        alert.informativeText = String(localized: "Enter a duration in minutes.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "90"
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Start"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn, let minutes = Int(field.stringValue), minutes > 0 else { return }
        session.start(minutes: minutes)
    }

    @objc private func toggleDisplaySleep() { Preferences.allowDisplaySleep.toggle() }

    @objc private func toggleLidClosed() { Preferences.keepAwakeLidClosed.toggle() }

    @objc private func toggleAutoAgents() {
        Preferences.autoAgentMode.toggle()
        session.checkAutomation()
    }

    @objc private func showAutomation() { openSettings?(.automation) }
    @objc private func showSettings() { openSettings?(.general) }
    @objc private func quit() { NSApp.terminate(nil) }
}
