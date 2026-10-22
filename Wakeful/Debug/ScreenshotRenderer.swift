#if DEBUG
import AppKit
import SwiftUI

/// Renders localized App Store screenshots (2880×1800) for every App Store Connect locale.
///
///     Wakeful.app/Contents/MacOS/Wakeful --render-screenshots [locale,locale,…]
///
/// The app is sandboxed, so images go to its temporary directory, whose path is printed at the end.
@MainActor
enum ScreenshotRenderer {
    /// App Store Connect locale → app localization used to render it.
    static let storeLocales: [(store: String, app: String)] = [
        ("en-US", "en"), ("en-GB", "en"), ("en-AU", "en"), ("en-CA", "en"),
        ("ar-SA", "ar"), ("ca", "ca"), ("cs", "cs"), ("da", "da"), ("de-DE", "de"), ("el", "el"),
        ("es-ES", "es"), ("es-MX", "es"), ("fi", "fi"), ("fr-FR", "fr"), ("fr-CA", "fr"), ("he", "he"),
        ("hi", "hi"), ("hr", "hr"), ("hu", "hu"), ("id", "id"), ("it", "it"), ("ja", "ja"), ("ko", "ko"),
        ("ms", "ms"), ("nl-NL", "nl"), ("no", "nb"), ("pl", "pl"), ("pt-BR", "pt-BR"), ("pt-PT", "pt-PT"),
        ("ro", "ro"), ("ru", "ru"), ("sk", "sk"), ("sv", "sv"), ("th", "th"), ("tr", "tr"), ("uk", "uk"),
        ("vi", "vi"), ("zh-Hans", "zh-Hans"), ("zh-Hant", "zh-Hant"),
    ]

    static func run(outputPath: String?) {
        let only = outputPath.map { Set($0.split(separator: ",").map(String.init)) }
        let root = FileManager.default.temporaryDirectory.appending(path: "screenshots", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)

        for (store, app) in storeLocales where only?.contains(store) ?? true {
            let folder = root.appending(path: store, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let locale = Locale(identifier: app)
            L.use(language: app)
            let rtl = Locale.Language(identifier: app).characterDirection == .rightToLeft
            let shots: [(String, AnyView)] = [
                ("01-menu", AnyView(MenuShot())),
                ("02-agents", AnyView(AgentsShot())),
                ("03-triggers", AnyView(TriggersShot())),
                ("04-widgets", AnyView(WidgetsShot())),
            ]
            for (name, view) in shots {
                let content = view
                    .frame(width: 1440, height: 900)
                    .environment(\.locale, locale)
                    .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let image = renderer.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(name).png"))
            }
        }
        print(root.path)
    }
}

// MARK: - Shared pieces

/// Looks strings up in a specific language's .lproj, independent of the system language.
@MainActor
private enum L {
    private static var bundle = Bundle.main

    static func use(language: String) {
        let path = Bundle.main.path(forResource: language, ofType: "lproj")
            ?? Bundle.main.path(forResource: language.split(separator: "-").first.map(String.init), ofType: "lproj")
        bundle = path.flatMap(Bundle.init(path:)) ?? .main
    }

    static func string(_ key: String, table: String? = nil, _ args: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: table)
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    static func text(_ key: String, table: String? = nil, _ args: CVarArg...) -> Text {
        let format = bundle.localizedString(forKey: key, value: key, table: table)
        return Text(verbatim: args.isEmpty ? format : String(format: format, arguments: args))
    }
}

private enum Palette {
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.26)
    static let menu = Color(white: 0.985)
    static let ink = Color(white: 0.12)
}

private struct Backdrop<Content: View>: View {
    let headline: String
    let subheadline: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.23, green: 0.21, blue: 0.63), Color(red: 0.13, green: 0.12, blue: 0.39), Color(red: 0.06, green: 0.05, blue: 0.18)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [Palette.accent.opacity(0.35), .clear], center: .bottom, startRadius: 0, endRadius: 700)
            VStack(spacing: 14) {
                L.text(headline, table: "Marketing")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                L.text(subheadline, table: "Marketing")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 90)
            .padding(.top, 64)
            content
        }
    }
}

private struct MenuBarStrip: View {
    var active = true
    var countdown: String? = "1:24:10"

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
            Text(verbatim: "Finder").fontWeight(.bold)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: active ? "cup.and.saucer.fill" : "cup.and.saucer")
                if let countdown { Text(verbatim: countdown).monospacedDigit() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text(Date(timeIntervalSince1970: 1_790_000_000), format: .dateTime.weekday(.abbreviated).hour().minute())
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(.black.opacity(0.35))
    }
}

private enum MenuRow {
    case header(Text)
    case item(Text, checked: Bool = false, submenu: Bool = false, highlighted: Bool = false)
    case separator
}

private struct MockMenu: View {
    let rows: [MenuRow]
    var width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .header(let text):
                    text.foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 5)
                case .separator:
                    Divider().padding(.vertical, 5).padding(.horizontal, 10)
                case .item(let text, let checked, let submenu, let highlighted):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").opacity(checked ? 1 : 0).font(.system(size: 11, weight: .bold))
                        text
                        Spacer(minLength: 12)
                        if submenu { Image(systemName: "chevron.forward").font(.system(size: 11, weight: .semibold)) }
                    }
                    .foregroundStyle(highlighted ? .white : Palette.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(highlighted ? Palette.accent : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .padding(.horizontal, 5)
                }
            }
        }
        .font(.system(size: 14))
        .lineLimit(1)
        .padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Palette.menu)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.black.opacity(0.12)))
        .environment(\.colorScheme, .light)
    }
}

private struct Window<Content: View>: View {
    var title: String?
    var width: CGFloat
    var dark = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
                    Spacer()
                }
                if let title {
                    L.text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(dark ? .white.opacity(0.7) : .secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            content
        }
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(dark ? Color(white: 0.11) : Color(white: 0.96))
                .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(dark ? 0.12 : 0.0)))
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Screens

private struct MenuShot: View {
    @Environment(\.locale) private var locale

    var body: some View {
        Backdrop(headline: "Keep your Mac awake. One click.", subheadline: "Timers, a global shortcut and a live countdown, right in the menu bar.") {
            VStack(spacing: 0) {
                Spacer().frame(height: 236)
                MenuBarStrip()
                HStack(alignment: .top, spacing: 0) {
                    Spacer()
                    MockMenu(rows: [
                        .header(L.text("Awake for %@ more", "1:24:10")),
                        .separator,
                        .item(L.text("Turn Off")),
                        .item(L.text("Keep Awake For"), submenu: true, highlighted: true),
                        .item(L.text("While AI Agent Runs"), submenu: true),
                        .item(L.text("While App Is Open"), submenu: true),
                        .separator,
                        .item(L.text("Allow Display to Sleep")),
                        .item(L.text("Keep Awake with Lid Closed"), checked: true),
                        .item(L.text("Auto-Activate When AI Agents Run"), checked: true),
                        .item(L.text("Automatic Triggers…")),
                        .separator,
                        .item(L.text("Settings…")),
                        .item(L.text("Quit Wakeful")),
                    ])
                    MockMenu(rows: [15, 30, 60, 120, 300, 480].map { minutes in
                        .item(Text(verbatim: duration(minutes)), highlighted: minutes == 120)
                    } + [.separator, .item(L.text("Custom…"))], width: 200)
                    .padding(.top, 70)
                    .padding(.trailing, 150)
                }
                .scaleEffect(1.25, anchor: .topTrailing)
                .padding(.top, 6)
                Spacer()
            }
        }
    }

    private func duration(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide).locale(locale))
    }
}

private struct AgentsShot: View {
    var body: some View {
        Backdrop(headline: "Your AI agents keep working.", subheadline: "Stays awake while Claude Code, Codex or Gemini run, then lets your Mac sleep.") {
            HStack(alignment: .top, spacing: 36) {
                Window(width: 600, dark: true) {
                    VStack(alignment: .leading, spacing: 11) {
                        Text(verbatim: "~/shop $ claude \"migrate checkout to API v2\"").foregroundStyle(.white)
                        Text(verbatim: "⏺ Reading 148 files…").foregroundStyle(.white.opacity(0.7))
                        Text(verbatim: "⏺ Updating PaymentService.swift").foregroundStyle(.white.opacity(0.7))
                        Text(verbatim: "⏺ Running 412 tests…").foregroundStyle(Palette.accent)
                        Text(verbatim: " ").font(.system(size: 6))
                        Text(verbatim: "~/api $ codex exec \"fix the flaky tests\"").foregroundStyle(.white)
                        Text(verbatim: "⏺ Working… 37 min").foregroundStyle(.white.opacity(0.7))
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 17, design: .monospaced))
                    .lineLimit(1)
                    .padding(24)
                    .frame(width: 600, height: 340, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 40) {
                    MockMenu(rows: [
                        .header(L.text("Awake automatically: %@", L.string("AI agent running (%@)", "claude, codex"))),
                        .separator,
                        .item(L.text("Turn Off")),
                        .item(L.text("While AI Agent Runs"), submenu: true, highlighted: true),
                        .separator,
                        .item(L.text("Auto-Activate When AI Agents Run"), checked: true),
                    ], width: 500)

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 40, height: 40)
                            .background(Color(red: 0.16, green: 0.15, blue: 0.42), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: "Wakeful").font(.system(size: 15, weight: .semibold))
                            L.text("All AI agents finished. Your Mac can sleep again.").font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(16)
                    .frame(width: 500, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(white: 0.97))
                            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    )
                }
            }
            .padding(.top, 270)
        }
    }
}

private struct TriggersShot: View {
    @Environment(\.locale) private var locale

    var body: some View {
        Backdrop(headline: "Automatic, when it matters.", subheadline: "External display, power, Wi‑Fi, apps, video calls and schedules.") {
            Window(title: "Automation", width: 820) {
                VStack(alignment: .leading, spacing: 0) {
                    L.text("Triggers").font(.system(size: 15, weight: .semibold)).padding(.bottom, 10)
                    VStack(spacing: 0) {
                        row("display", L.text("An external display is connected"), on: true)
                        row("powerplug", L.text("The power adapter is connected"), on: true)
                        row("wifi", L.text("Connected to Wi‑Fi “%@”", "Office"), on: true)
                        row("app", L.text("%@ is open", "Zoom"), on: true)
                        row("video", L.text("The camera or microphone is in use"), on: true)
                        row("calendar.badge.clock", L.text("%@, %@–%@", L.string("Weekdays"), time(9 * 60), time(18 * 60)), on: false, last: true)
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.08)))
                    HStack {
                        Label { L.text("Add Trigger") } icon: { Image(systemName: "plus") }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.white, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.1)))
                        Spacer()
                    }
                    .padding(.top, 14)
                }
                .font(.system(size: 15))
                .foregroundStyle(Palette.ink)
                .padding(24)
                .frame(width: 820, alignment: .leading)
            }
            .scaleEffect(1.1)
            .padding(.top, 280)
        }
    }

    private func time(_ minutes: Int) -> String {
        let date = Calendar(identifier: .gregorian).date(bySettingHour: minutes / 60, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    private func row(_ symbol: String, _ text: Text, on: Bool, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(Palette.accent)
                text.lineLimit(1)
                Spacer()
                Capsule().fill(on ? Palette.accent : Color(white: 0.85)).frame(width: 38, height: 22)
                    .overlay(Circle().fill(.white).padding(2).offset(x: on ? 8 : -8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            if !last { Divider().padding(.leading, 50) }
        }
    }
}

private struct WidgetsShot: View {
    @Environment(\.locale) private var locale

    var body: some View {
        Backdrop(headline: "Widgets, Control Center and history.", subheadline: "Private by design: everything stays on your Mac.") {
            HStack(alignment: .top, spacing: 40) {
                VStack(spacing: 30) {
                    // Small widget.
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.orange.gradient)
                        Spacer()
                        L.text("Awake").font(.system(size: 20, weight: .semibold))
                        Text(verbatim: "1:24:10").font(.system(size: 15)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(width: 210, height: 210, alignment: .leading)
                    .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 26))

                    // Control Center toggle.
                    HStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Palette.accent, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            L.text("Keep Awake").font(.system(size: 15, weight: .semibold))
                            L.text("Awake").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(width: 210)
                    .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 22))
                }
                .foregroundStyle(Palette.ink)
                .environment(\.colorScheme, .light)

                Window(title: "History", width: 600) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 40) {
                            stat("Today", duration(hours: 6, minutes: 40))
                            stat("Last 7 days", duration(hours: 31, minutes: 15))
                            stat("Sessions", 42.formatted(.number.locale(locale)))
                        }
                        HStack(alignment: .bottom, spacing: 22) {
                            ForEach(Array([3.5, 5.2, 4.1, 7.8, 6.0, 1.2, 6.7].enumerated()), id: \.offset) { _, hours in
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Palette.accent.gradient)
                                    .frame(width: 46, height: hours * 26)
                            }
                        }
                        .frame(height: 220, alignment: .bottom)
                        L.text("History is stored only on this Mac and is never sent anywhere.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(26)
                    .frame(width: 600, alignment: .leading)
                }
            }
            .padding(.top, 280)
        }
    }

    private func duration(hours: Int, minutes: Int) -> String {
        Duration.seconds(hours * 3600 + minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            L.text(title).font(.system(size: 13)).foregroundStyle(.secondary)
            Text(verbatim: value).font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.ink)
        }
    }
}
#endif
