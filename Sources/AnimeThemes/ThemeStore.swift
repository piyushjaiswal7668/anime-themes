import AppKit
import ServiceManagement

/// App state and actions. Plain AppKit (no SwiftUI), so the menu can't hit SwiftUI view-graph crashes.
@MainActor
final class ThemeStore {
    /// Called when something the menu bar title shows has changed.
    var onChange: (() -> Void)?

    private(set) var animes: [Anime] = []
    private(set) var currentID: String? { didSet { onChange?() } }
    private(set) var status = "Pick a theme"
    private(set) var busy = false
    private(set) var currentLine = ""
    var settings: Settings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "settings") }
            if settings != oldValue { settingsChanged(from: oldValue) }
        }
    }

    private let live = LiveWallpaper()
    private let voice = VoicePlayer()
    private let widgets = WidgetManager()
    private var timer: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let saved = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = saved
        } else {
            settings = Settings()
        }
        currentID = UserDefaults.standard.string(forKey: "current")
        reload()
    }

    /// Runs once the menu bar item exists: brings back the live wallpaper, card and timer, then says hello.
    func start() {
        scheduleRotation()
        // Rotation on: start with a fresh theme (it greets you with its own switch clip).
        if settings.rotation != "off", rotationDue(atLogin: true), let next = randomTheme() {
            select(next)
            return
        }
        guard let v = current else { return }
        refreshRuntime(v, newLine: true)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            self.voice.play(event: "login", variant: v, settings: self.settings)
        }
    }

    var allVariants: [Variant] { animes.flatMap(\.variants) }
    var current: Variant? { allVariants.first { $0.id == currentID } }
    var hasSketchyBar: Bool { SketchyBarModule.isInstalled }
    var voiceSummary: String { current.map { VoicePlayer.summary(for: $0) } ?? "" }

    func reload() {
        animes = PackLoader.load()
        if animes.isEmpty {
            status = "No theme packs found in ~/AnimeThemes. Run install.sh again."
        }
    }

    func select(_ v: Variant) {
        guard !busy else { return }
        Task { await apply(v) }
    }

    // MARK: Switching theme

    func apply(_ v: Variant) async {
        busy = true
        defer { busy = false }
        currentID = v.id
        UserDefaults.standard.set(v.id, forKey: "current")
        UserDefaults.standard.set(Date(), forKey: "lastThemeChange")
        status = "Applying \(v.spec.name)…"

        let s = settings
        var problems: [String] = []
        var notes: [String] = []

        // Fast, visible changes first.
        if s.wallpaper {
            do { _ = try WallpaperModule.apply(v) } catch { problems.append("Wallpaper: \(error.localizedDescription)") }
        }
        refreshRuntime(v, newLine: true)
        voice.play(event: "switch", variant: v, settings: s, speakFallback: currentLine)

        if s.accent {
            do { try AccentModule.apply(v) } catch { problems.append("Accent: \(error.localizedDescription)") }
        }
        if s.shell {
            do { try ShellModule.apply(v, settings: s) } catch { problems.append("Shell: \(error.localizedDescription)") }
        }
        if s.terminal {
            do { try await TerminalModule.apply(v) } catch { problems.append("Terminal: \(error.localizedDescription)") }
        }
        if s.vscode {
            let all = allVariants
            do {
                let note = try await Task.detached { try VSCodeModule.apply(v, all: all) }.value
                if !note.isEmpty { notes.append("VS Code: \(note)") }
            } catch {
                problems.append("VS Code: \(error.localizedDescription)")
            }
        }
        if s.menuBar, SketchyBarModule.isInstalled {
            do { try await Task.detached { try SketchyBarModule.apply(v) }.value }
            catch { problems.append("Menu bar: \(error.localizedDescription)") }
        }
        if s.icons {
            notes.append(IconsModule.apply(v))
        }
        if !Fonts.mapleInstalled { notes.append("Maple Mono isn't installed yet") }

        if problems.isEmpty {
            status = (["\(v.spec.emoji) \(v.spec.name) is on"] + notes).joined(separator: " · ")
        } else {
            status = problems.joined(separator: "\n")
            NSLog("AnimeThemes: %@", status)
        }
    }

    /// Live wallpaper, desktop card and the random-line timer. Cheap, so it runs on every change.
    private func refreshRuntime(_ v: Variant, newLine: Bool) {
        let s = settings
        if s.liveWallpaper, let url = LiveWallpaper.pick(for: v) {
            if live.currentURL?.deletingLastPathComponent() != url.deletingLastPathComponent() || !live.isShowing {
                live.play(url, paused: s.livePaused)
            } else {
                live.setPaused(s.livePaused)
            }
        } else {
            live.stop()
        }

        if newLine || currentLine.isEmpty { currentLine = v.lines.randomElement() ?? "" }
        if s.widget {
            widgets.show(v, enabled: Set(s.enabledWidgets), line: currentLine)
        } else {
            widgets.hideAll()
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard settings.randomMinutes > 0 else { return }
        let t = Timer(timeInterval: TimeInterval(settings.randomMinutes * 60), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.randomMoment() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// New line on the card, plus a random voice clip.
    func randomMoment() {
        guard let v = current else { return }
        currentLine = v.lines.randomElement() ?? currentLine
        widgets.setLine(currentLine)
        voice.play(event: "random", variant: v, settings: settings, speakFallback: currentLine)
    }

    // MARK: Theme rotation

    private var rotationTimer: Timer?

    /// The themes rotation can pick from right now.
    var rotationPool: [Variant] {
        switch settings.rotation {
        case "series":
            guard let series = current?.seriesName else { return allVariants }
            return allVariants.filter { $0.seriesName == series }
        default:
            return allVariants
        }
    }

    /// A random theme from the pool, never the one you're on (unless it's the only one).
    func randomTheme() -> Variant? {
        let pool = rotationPool
        return pool.filter { $0.id != currentID }.randomElement() ?? pool.first
    }

    /// Switches now to a random theme from the pool ("all" when rotation is off).
    func shuffle() {
        let pool = settings.rotation == "off" ? allVariants : rotationPool
        guard let next = pool.filter({ $0.id != currentID }).randomElement() ?? pool.first else { return }
        select(next)
    }

    /// Whether it's time for a new theme: at login in "each login" mode, or once the
    /// interval has passed since the last change (also counted across restarts and sleep).
    private func rotationDue(atLogin: Bool) -> Bool {
        if settings.rotateMinutes == 0 { return atLogin }
        let last = UserDefaults.standard.object(forKey: "lastThemeChange") as? Date ?? .distantPast
        return Date().timeIntervalSince(last) >= TimeInterval(settings.rotateMinutes * 60)
    }

    /// Checks once a minute, so a long interval still fires on time after the Mac wakes.
    private func scheduleRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard settings.rotation != "off", settings.rotateMinutes > 0 else { return }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.busy, self.rotationDue(atLogin: false),
                      let next = self.randomTheme() else { return }
                self.select(next)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        rotationTimer = t
    }

    private func settingsChanged(from old: Settings) {
        if old.rotation != settings.rotation || old.rotateMinutes != settings.rotateMinutes {
            // Count the new interval from now rather than switching the moment you pick it.
            UserDefaults.standard.set(Date(), forKey: "lastThemeChange")
            scheduleRotation()
            onChange?()
            return
        }
        guard let v = current else { return }
        refreshRuntime(v, newLine: false)
        // The shell reads voice settings from its env file.
        let voiceChanged = old.voice != settings.voice || old.voiceLanguage != settings.voiceLanguage || old.volume != settings.volume
        if settings.shell, voiceChanged { try? ShellModule.apply(v, settings: settings) }
    }

    // MARK: Menu actions

    func nextWallpaper() {
        guard let v = current else { return }
        do {
            let name = try WallpaperModule.apply(v)
            if settings.liveWallpaper, let url = LiveWallpaper.pick(for: v) {
                live.play(url, paused: settings.livePaused)
                status = "Live wallpaper: \(url.lastPathComponent)"
            } else {
                status = "Wallpaper: \(name)"
            }
        } catch {
            status = "Wallpaper: \(error.localizedDescription)"
        }
    }

    func testVoice() {
        guard let v = current else { return }
        if !voice.play(event: "random", variant: v, settings: settings, speakFallback: currentLine) {
            status = settings.voice ? "No voice clips yet for \(v.spec.name)" : "Voice is off"
        }
    }

    func restoreIcons() {
        let n = IconsModule.restore()
        settings.icons = false
        status = "Restored \(n) original app icons"
    }

    // MARK: Widgets

    var editingWidgets: Bool { widgets.editing }

    func toggleEditingWidgets() {
        widgets.setEditing(!widgets.editing)
    }

    func resetWidgetPositions() {
        widgets.resetPositions()
    }

    func toggleWidget(_ kind: String) {
        if let i = settings.enabledWidgets.firstIndex(of: kind) {
            settings.enabledWidgets.remove(at: i)
        } else {
            settings.enabledWidgets.append(kind)
        }
    }

    // MARK: Login item

    var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = "Couldn't change “Open at login”: \(error.localizedDescription)"
        }
        onChange?()
    }
}
