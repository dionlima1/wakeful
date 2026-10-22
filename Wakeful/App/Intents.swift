import AppIntents

struct StartKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Prevents your Mac from sleeping, optionally for a number of minutes.")

    @Parameter(title: "Minutes", description: "Leave empty to keep awake indefinitely.")
    var minutes: Int?

    @MainActor
    func perform() async throws -> some IntentResult {
        SessionController.shared.start(minutes: minutes ?? 0)
        return .result()
    }
}

struct StopKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Let Mac Sleep"

    @MainActor
    func perform() async throws -> some IntentResult {
        SessionController.shared.stop()
        return .result()
    }
}

struct ToggleKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Keep Awake"

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        SessionController.shared.toggle()
        return .result(value: SessionController.shared.isActive)
    }
}

struct IsKeepAwakeActiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Is Mac Kept Awake?"

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: SessionController.shared.isActive)
    }
}

struct WakefulShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartKeepAwakeIntent(),
            phrases: ["Keep my Mac awake with \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Keep Awake",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: StopKeepAwakeIntent(),
            phrases: ["Stop \(.applicationName)", "Let my Mac sleep with \(.applicationName)"],
            shortTitle: "Let Mac Sleep",
            systemImageName: "cup.and.saucer"
        )
    }
}
