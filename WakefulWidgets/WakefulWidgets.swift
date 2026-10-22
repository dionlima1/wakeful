import AppIntents
import SwiftUI
import WidgetKit

@main
struct WakefulWidgets: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        if #available(macOS 26.0, *) {
            KeepAwakeControl()
        }
    }
}

// MARK: - Desktop / Notification Center widget

struct StatusEntry: TimelineEntry {
    let date: Date
    let state: SharedState
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, state: SharedState(isActive: true, until: nil, status: ""))
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, state: context.isPreview ? placeholder(in: context).state : SharedState.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let state = SharedState.load()
        var entries = [StatusEntry(date: .now, state: state)]
        // Flip to "off" when a timed session runs out; the app reloads us on every other change.
        if let until = state.until { entries.append(StatusEntry(date: until, state: .off)) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.status, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Wakeful")
        .description("See whether your Mac is kept awake and switch it with one click.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private var isActive: Bool { entry.state.isActive }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isActive ? AnyShapeStyle(.orange.gradient) : AnyShapeStyle(.secondary))
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(isActive ? "Awake" : "Sleeps normally")
                    .font(.headline)
                    .lineLimit(2)
                Group {
                    if let until = entry.state.until {
                        Text(until, style: .timer)
                    } else if isActive {
                        Text("Until you turn it off")
                    } else {
                        Text("Click to keep awake")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if family == .systemMedium {
                VStack(spacing: 6) {
                    quickButton(minutes: 30)
                    quickButton(minutes: 60)
                    quickButton(minutes: 120)
                    Link(destination: isActive ? WakefulURL.stop : WakefulURL.start) {
                        Text(isActive ? "Turn Off" : "Indefinitely")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(isActive ? AnyShapeStyle(.red.opacity(0.25)) : AnyShapeStyle(.orange.opacity(0.3)), in: Capsule())
                    }
                }
                .font(.caption.weight(.medium))
                .frame(width: 110)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WakefulURL.toggle)
    }

    private func quickButton(minutes: Int) -> some View {
        Link(destination: WakefulURL.start(minutes: minutes)) {
            Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        }
    }
}

// MARK: - Control Center / menu bar control (macOS 26)

@available(macOS 26.0, *)
struct KeepAwakeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.control, provider: Provider()) { isOn in
            ControlWidgetToggle("Keep Awake", isOn: isOn, action: SetKeepAwakeIntent()) { on in
                Label(on ? "Awake" : "Off", systemImage: on ? "cup.and.saucer.fill" : "cup.and.saucer")
            }
            .tint(.orange)
        }
        .displayName("Keep Mac Awake")
        .description("Prevents your Mac from sleeping.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            SharedState.load().isActive
        }
    }
}

/// Runs in the widget extension, so it hands the change to the app through its URL scheme.
@available(macOS 26.0, *)
struct SetKeepAwakeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"

    @Parameter(title: "Awake")
    var value: Bool

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(value ? WakefulURL.start : WakefulURL.stop))
    }
}
