import AppKit
import KeyboardShortcuts
import SwiftUI
import UserNotifications

@main
@MainActor
enum Main {
    static func main() {
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-screenshots") {
            let output = CommandLine.arguments.dropFirst(index + 1).first
            ScreenshotRenderer.run(outputPath: output)
            return
        }
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        UNUserNotificationCenter.current().delegate = self
        if Preferences.notifyOnEnd {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        ProStore.shared.onProRequired = { [weak self] in self?.showSettings(tab: .pro) }
        ProStore.shared.start()

        let controller = StatusItemController()
        controller.openSettings = { [weak self] tab in self?.showSettings(tab: tab) }
        URLCommand.openSettings = { [weak self] tab in self?.showSettings(tab: tab) }
        statusItem = controller

        KeyboardShortcuts.onKeyUp(for: .toggleKeepAwake) {
            SessionController.shared.toggle()
        }

        if TriggerStore.shared.needsLocation { LocationPermission.shared.request() }
        if Preferences.activateAtLaunch { SessionController.shared.startDefault() }
        SessionController.shared.checkAutomation()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(URLCommand.handle)
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionController.shared.stop()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private func showSettings(tab: SettingsTab) {
        SettingsNavigation.shared.tab = tab
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = String(localized: "Wakeful Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
