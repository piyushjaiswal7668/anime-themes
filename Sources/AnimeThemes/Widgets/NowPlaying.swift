import AppKit
import ApplicationServices
import IOKit.pwr_mgt

// MARK: Track

/// Where a seek or other command for the current track should go.
enum PlayerTarget: Equatable {
    case app(String)                                              // "Spotify" or "Music"
    case tab(app: String, safari: Bool, windowID: String, tab: Int)
}

struct NowPlayingTrack {
    var source: String          // "YouTube Music · Chrome", "Spotify", …
    var title: String
    var artist: String
    var playing: Bool?          // nil when it can't be told
    var artworkURL: String?     // https URL, or "music-app" for Apple Music's embedded art
    var position: Double?       // seconds
    var duration: Double?       // seconds
    var target: PlayerTarget?

    /// Same song and same look; position changes don't count.
    func sameDisplay(as o: NowPlayingTrack?) -> Bool {
        guard let o else { return false }
        return source == o.source && title == o.title && artist == o.artist && playing == o.playing
            && artworkURL == o.artworkURL && (duration == nil) == (o.duration == nil)
    }
}

// MARK: Widget

/// Cover art, song, a draggable time bar and ⏮ ⏯ ⏭ for browser music tabs,
/// Spotify and Apple Music.
final class NowPlayingWidget: DesktopWidget {
    private var track: NowPlayingTrack?
    /// After you press play/pause, your choice wins for a few seconds while the browser catches up.
    private var chosenState: (playing: Bool, until: Date)?
    private var positionAt: (value: Double, time: Date)?
    private weak var slider: NSSlider?
    private weak var elapsedLabel: NSTextField?
    private weak var remainingLabel: NSTextField?
    private weak var artView: NSView?
    private var progressTimer: Timer?

    init() { super.init(kind: "nowplaying", column: .right) }

    override var width: CGFloat { 330 }
    override var acceptsClicks: Bool { true }

    override func makeContent(_ v: Variant) -> NSView? {
        let k = Card.colors(v.spec.colors)
        var views: [NSView] = [Card.heading("Now playing", color: k.accent)]

        guard let t = track else {
            views.append(Card.label("Nothing playing", size: 12, color: k.muted))
            views.append(centered(controls(k.accent, playing: nil)))
            return Card.vstack(views, spacing: 8)
        }

        // Cover art + song
        let art = NSView()
        art.wantsLayer = true
        art.layer?.cornerRadius = 8
        art.layer?.masksToBounds = true
        art.layer?.backgroundColor = k.muted.withAlphaComponent(0.25).cgColor
        art.layer?.contentsGravity = .resizeAspectFill
        art.widthAnchor.constraint(equalToConstant: 64).isActive = true
        art.heightAnchor.constraint(equalToConstant: 64).isActive = true
        artView = art
        loadArtwork(t)

        let title = Card.label(t.title, size: 15, weight: .semibold, color: k.fg)
        let detail = Card.label(t.artist.isEmpty ? t.source : "\(t.artist) · \(t.source)", size: 12, color: k.muted)
        let text = Card.vstack([title, detail], spacing: 3)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = Card.hstack([art, text], spacing: 12)
        views.append(header)

        // Time bar
        if let duration = t.duration, duration > 0 {
            let s = FirstClickSlider(value: t.position ?? 0, minValue: 0, maxValue: duration,
                                     target: ActionTarget.shared, action: #selector(ActionTarget.fireSlider(_:)))
            s.isContinuous = false              // seek when you let go
            s.controlSize = .small
            s.trackFillColor = k.accent
            s.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
            ActionTarget.shared.sliderHandlers[ObjectIdentifier(s)] = { [weak self] value in self?.seek(to: value) }
            slider = s

            let elapsed = Card.label(Self.clock(t.position ?? 0), size: 11, color: k.muted, mono: true)
            let remaining = Card.label("-" + Self.clock(duration - (t.position ?? 0)), size: 11, color: k.muted, mono: true)
            remaining.alignment = .right
            elapsedLabel = elapsed
            remainingLabel = remaining
            // Pinned to the left and right edges (not stack spacers, which Auto Layout can
            // resolve differently on each redraw).
            let times = NSView()
            for l in [elapsed, remaining] {
                l.translatesAutoresizingMaskIntoConstraints = false
                times.addSubview(l)
            }
            NSLayoutConstraint.activate([
                times.widthAnchor.constraint(equalToConstant: width - 32),
                elapsed.leadingAnchor.constraint(equalTo: times.leadingAnchor),
                remaining.trailingAnchor.constraint(equalTo: times.trailingAnchor),
                elapsed.topAnchor.constraint(equalTo: times.topAnchor),
                remaining.topAnchor.constraint(equalTo: times.topAnchor),
                elapsed.bottomAnchor.constraint(equalTo: times.bottomAnchor),
                remaining.bottomAnchor.constraint(equalTo: times.bottomAnchor),
            ])
            views.append(Card.vstack([s, times], spacing: 2))
        } else if case .tab(let app, _, _, _)? = t.target {
            views.append(Card.label("Time bar: allow JavaScript from Apple Events in \(app)", size: 10, color: k.muted))
        } else if t.target == nil, t.source.contains("·") {
            views.append(Card.label("Time bar: allow JavaScript from Apple Events in your browser", size: 10, color: k.muted))
        }

        views.append(centered(controls(k.accent, playing: t.playing)))
        startProgressTimer()
        return Card.vstack(views, spacing: 8)
    }

    /// A full-width row with the view fixed in its exact middle, so the buttons never move
    /// when the play icon changes or the card redraws.
    private func centered(_ view: NSView) -> NSView {
        let row = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(view)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: width - 32),
            view.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            view.topAnchor.constraint(equalTo: row.topAnchor),
            view.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    private func controls(_ color: NSColor, playing: Bool?) -> NSView {
        // Pause icon while playing, play icon while paused; the combined icon only if unknown.
        let symbol = playing == true ? "pause.fill" : (playing == false ? "play.fill" : "playpause.fill")
        let previous = button("backward.fill", color: color, size: 15) { [weak self] in self?.control(.previous) }
        let play = button(symbol, color: color, size: 22) { [weak self] in self?.control(.playPause) }
        let next = button("forward.fill", color: color, size: 15) { [weak self] in self?.control(.next) }
        return Card.hstack([previous, play, next], spacing: 22)
    }

    // MARK: Updating

    override func tick(_ count: Int) {
        if count % 2 == 0 { refresh() }   // every 4 seconds
    }

    func refresh() {
        var fresh = Self.current()
        if let chosen = chosenState {
            if Date() < chosen.until, fresh != nil, fresh?.playing != nil {
                fresh?.playing = chosen.playing
            } else if Date() >= chosen.until {
                chosenState = nil
            }
        }
        if let p = fresh?.position { positionAt = (p, Date()) } else { positionAt = nil }
        let changed = !(fresh?.sameDisplay(as: track) ?? (track == nil))
        track = fresh
        if changed { render() } else { updateProgress() }
    }

    /// Moves the time bar between checks, so it runs smoothly while playing.
    private func startProgressTimer() {
        guard progressTimer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateProgress() }
        }
        RunLoop.main.add(t, forMode: .common)
        progressTimer = t
    }

    private func updateProgress() {
        guard let t = track, let duration = t.duration, duration > 0, let base = positionAt else { return }
        guard NSEvent.pressedMouseButtons == 0 else { return }       // don't fight a drag
        var now = base.value
        if t.playing == true { now += Date().timeIntervalSince(base.time) }
        now = min(max(now, 0), duration)
        slider?.doubleValue = now
        elapsedLabel?.stringValue = Self.clock(now)
        remainingLabel?.stringValue = "-" + Self.clock(duration - now)
    }

    private func loadArtwork(_ t: NowPlayingTrack) {
        guard let source = t.artworkURL else { return }
        Artwork.image(for: source) { [weak self] image in
            guard let self, let image, self.track?.artworkURL == source else { return }
            self.artView?.layer?.contents = image
        }
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds.rounded()))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Actions

    private func control(_ key: MediaKeys.Key) {
        if case .app(let app)? = track?.target {
            let cmd = key == .next ? "next track" : (key == .previous ? "previous track" : "playpause")
            _ = try? AppleScript.run("tell application \"\(app)\" to \(cmd)")
        } else {
            MediaKeys.press(key)
        }
        if key == .playPause, let playing = track?.playing {
            track?.playing = !playing
            chosenState = (!playing, Date().addingTimeInterval(5))
            if let p = positionAt { positionAt = (p.value + (playing ? Date().timeIntervalSince(p.time) : 0), Date()) }
            render()
        } else if key != .playPause {
            chosenState = nil
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            self?.refresh()
        }
    }

    private func seek(to seconds: Double) {
        guard let target = track?.target else { return }
        Players.seek(target, to: seconds)
        positionAt = (seconds, Date())
        updateProgress()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self?.refresh()
        }
    }

    private func button(_ symbol: String, color: NSColor, size: CGFloat, action: @escaping () -> Void) -> NSButton {
        let b = FirstClickButton()
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold))
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.contentTintColor = color
        // Fixed size: the play and pause icons have different widths, which would nudge
        // the neighbouring buttons each time the state flips.
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: size + 14).isActive = true
        b.heightAnchor.constraint(equalToConstant: size + 10).isActive = true
        b.target = ActionTarget.shared
        b.action = #selector(ActionTarget.fire(_:))
        ActionTarget.shared.handlers[ObjectIdentifier(b)] = action
        return b
    }

    /// Picks the best candidate: playing beats unknown beats paused.
    static func current() -> NowPlayingTrack? {
        let all = Players.nativeTracks() + Players.browserTracks()
        func rank(_ t: NowPlayingTrack) -> Int { t.playing == true ? 3 : (t.playing == nil ? 2 : 1) }
        return all.max { rank($0) < rank($1) }
    }
}

/// A slider that responds on the first click even though the app is in the background.
final class FirstClickSlider: NSSlider {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension ActionTarget {
    @objc func fireSlider(_ sender: NSSlider) { sliderHandlers[ObjectIdentifier(sender)]?(sender.doubleValue) }
}

// MARK: Players

@MainActor
enum Players {
    // Spotify & Music apps

    private static let nativeApps: [(app: String, bundleID: String)] = [
        ("Spotify", "com.spotify.client"),
        ("Music", "com.apple.Music"),
    ]

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Asks a player only if it is already running, so nothing gets launched.
    static func nativeTracks() -> [NowPlayingTrack] {
        var result: [NowPlayingTrack] = []
        for p in nativeApps where isRunning(p.bundleID) {
            // Spotify reports duration in milliseconds and has an artwork URL; Music uses seconds.
            let duration = p.app == "Spotify" ? "((duration of current track) / 1000)" : "(duration of current track)"
            let art = p.app == "Spotify" ? "(artwork url of current track)" : "\"music-app\""
            let script = """
            tell application "\(p.app)"
                try
                    if player state is stopped then return ""
                    set sep to "|~|"
                    return (name of current track) & sep & (artist of current track) & sep & (player state as string) & sep & (player position as string) & sep & (\(duration) as string) & sep & \(art)
                on error
                    return ""
                end try
            end tell
            """
            guard let text = try? AppleScript.run(script).stringValue, !text.isEmpty else { continue }
            let f = text.components(separatedBy: "|~|")
            guard f.count >= 6 else { continue }
            result.append(NowPlayingTrack(source: p.app, title: f[0], artist: f[1], playing: f[2] == "playing",
                                          artworkURL: f[5].isEmpty ? nil : f[5],
                                          position: number(f[3]), duration: number(f[4]),
                                          target: .app(p.app)))
        }
        return result
    }

    // Browsers

    private struct Browser { let app: String; let bundleID: String; let safari: Bool; let pathMarker: String }
    private static let browsers: [Browser] = [
        .init(app: "Google Chrome", bundleID: "com.google.Chrome", safari: false, pathMarker: "/Google Chrome.app/"),
        .init(app: "Arc", bundleID: "company.thebrowser.Browser", safari: false, pathMarker: "/Arc.app/"),
        .init(app: "Brave Browser", bundleID: "com.brave.Browser", safari: false, pathMarker: "/Brave Browser.app/"),
        .init(app: "Microsoft Edge", bundleID: "com.microsoft.edgemac", safari: false, pathMarker: "/Microsoft Edge.app/"),
        .init(app: "Safari", bundleID: "com.apple.Safari", safari: true, pathMarker: "com.apple.WebKit"),
    ]

    private static let sites: [(match: String, name: String)] = [
        ("music.youtube.com", "YouTube Music"),
        ("youtube.com/watch", "YouTube"),
        ("jiosaavn.com", "JioSaavn"),
        ("gaana.com", "Gaana"),
        ("wynk.in", "Wynk"),
        ("open.spotify.com", "Spotify Web"),
        ("music.amazon", "Amazon Music"),
        ("soundcloud.com", "SoundCloud"),
        ("music.apple.com", "Apple Music"),
    ]

    private static let titleEndings = [
        " - YouTube Music", " - YouTube", " | JioSaavn", " - JioSaavn", " | Gaana.com", " - Gaana",
        " | Gaana", " | Wynk Music", " - Wynk Music", " | Spotify", " - Spotify", " | Amazon Music",
        " | SoundCloud", " - SoundCloud", " - Apple Music", " on Apple Music",
    ]

    /// Song, artist, play state, artwork and position from the page's media session and player element.
    private static let js = "(function(){var m=navigator.mediaSession;var d=m&&m.metadata;var e=document.querySelector('video,audio');var s=(m&&m.playbackState&&m.playbackState!='none')?m.playbackState:(e?(e.paused?'paused':'playing'):'');var a=(d&&d.artwork&&d.artwork.length)?d.artwork[d.artwork.length-1].src:'';var p=(e&&isFinite(e.duration)&&e.duration>0)?(e.currentTime+'|~|'+e.duration):'|~|';return (d?d.title:'')+'|~|'+(d?d.artist:'')+'|~|'+s+'|~|'+a+'|~|'+p;})()"

    static func browserTracks() -> [NowPlayingTrack] {
        var result: [NowPlayingTrack] = []
        let audioPaths = AudioActivity.processPathsPlayingMedia()   // nil if macOS won't say
        for b in browsers where isRunning(b.bundleID) {
            guard let text = try? AppleScript.run(listScript(for: b)).stringValue, !text.isEmpty else { continue }
            let browserIsPlaying: Bool? = audioPaths.map { paths in paths.contains { $0.contains(b.pathMarker) } }
            let shortName = b.app.replacingOccurrences(of: " Browser", with: "")
            for row in text.components(separatedBy: "\n") where !row.isEmpty {
                // windowID, tabIndex, url, title, [jsTitle, jsArtist, jsState, jsArt, jsPos, jsDur]
                let f = row.components(separatedBy: "|~|")
                guard f.count >= 4, let site = sites.first(where: { f[2].contains($0.match) }) else { continue }
                let target = PlayerTarget.tab(app: b.app, safari: b.safari, windowID: f[0], tab: Int(f[1]) ?? 1)
                let source = "\(site.name) · \(shortName)"
                let thumb = youTubeThumbnail(f[2])
                if f.count >= 10, !f[4].isEmpty {
                    result.append(NowPlayingTrack(
                        source: source, title: f[4], artist: f[5],
                        playing: f[6].isEmpty ? browserIsPlaying : f[6] == "playing",
                        artworkURL: f[7].hasPrefix("http") ? f[7] : thumb,
                        position: number(f[8]), duration: number(f[9]), target: target))
                } else if let parsed = parse(title: f[3]) {
                    result.append(NowPlayingTrack(
                        source: source, title: parsed.title, artist: parsed.artist, playing: browserIsPlaying,
                        artworkURL: thumb, position: nil, duration: nil, target: target))
                }
            }
        }
        return result
    }

    /// "Song • Artist - YouTube Music" → ("Song", "Artist"). Returns nil for home/search pages.
    static func parse(title raw: String) -> (title: String, artist: String)? {
        var t = raw.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) { t.removeSubrange(r) }
        for ending in titleEndings where t.hasSuffix(ending) { t = String(t.dropLast(ending.count)); break }
        t = t.trimmingCharacters(in: .whitespaces)
        let generic = ["YouTube Music", "YouTube", "JioSaavn", "Gaana", "Wynk Music", "SoundCloud", "Amazon Music", "Apple Music"]
        if t.isEmpty || generic.contains(t) || t.lowercased().hasPrefix("spotify") { return nil }
        for sep in [" • ", " · "] where t.contains(sep) {
            let parts = t.components(separatedBy: sep)
            return (parts[0], parts.dropFirst().joined(separator: sep))
        }
        return (t, "")
    }

    /// YouTube thumbnails can be built from the video ID, no page access needed.
    static func youTubeThumbnail(_ url: String) -> String? {
        guard url.contains("youtube.com"), let comps = URLComponents(string: url),
              let id = comps.queryItems?.first(where: { $0.name == "v" })?.value, !id.isEmpty else { return nil }
        return "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"
    }

    private static func listScript(for b: Browser) -> String {
        let titleKey = b.safari ? "name of t" : "title of t"
        let runJS = b.safari ? "do JavaScript \"\(js)\" in t" : "execute t javascript \"\(js)\""
        let matches = sites.map { "u contains \"\($0.match)\"" }.joined(separator: " or ")
        return """
        set out to ""
        set sep to "|~|"
        tell application "\(b.app)"
            repeat with w in windows
                set wid to ""
                try
                    set wid to (id of w) as string
                end try
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    try
                        set u to URL of t
                        if \(matches) then
                            set extra to ""
                            try
                                set extra to sep & (\(runJS))
                            end try
                            set out to out & wid & sep & (i as string) & sep & u & sep & (\(titleKey)) & extra & linefeed
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return out
        """
    }

    // Seeking

    static func seek(_ target: PlayerTarget, to seconds: Double) {
        let pos = String(format: "%.2f", seconds)
        switch target {
        case .app(let app):
            _ = try? AppleScript.run("tell application \"\(app)\" to set player position to \(pos)")
        case .tab(let app, let safari, let windowID, let tab):
            let js = "(function(){var e=document.querySelector('video,audio');if(e){e.currentTime=\(pos);return 'ok'}return ''})()"
            let tabRef = "tab \(tab) of (first window whose id is \(windowID))"
            let run = safari ? "do JavaScript \"\(js)\" in \(tabRef)" : "execute \(tabRef) javascript \"\(js)\""
            _ = try? AppleScript.run("tell application \"\(app)\" to \(run)")
        }
    }

    private static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: Artwork

/// Loads and caches cover art: web images, or Apple Music's embedded artwork.
@MainActor
enum Artwork {
    private static var cache: [String: NSImage] = [:]

    static func image(for source: String, done: @escaping (NSImage?) -> Void) {
        if let hit = cache[source] { done(hit); return }
        if source == "music-app" {
            // Not cached: it changes with every song.
            let desc = try? AppleScript.run("tell application \"Music\" to get data of artwork 1 of current track")
            done(desc.flatMap { NSImage(data: $0.data) })
            return
        }
        guard let url = URL(string: source), url.scheme == "https" else { done(nil); return }
        Task {
            let data = try? await URLSession.shared.data(from: url).0
            let image = data.flatMap { NSImage(data: $0) }
            if let image { cache[source] = image }
            done(image)
        }
    }
}

// MARK: Media keys

/// Presses the Mac's play/pause, next and previous keys, which control whatever is playing,
/// including browser tabs. macOS asks once for Accessibility permission.
enum MediaKeys {
    enum Key: Int { case playPause = 16, next = 17, previous = 18 }

    static func press(_ key: Key) {
        guard trusted(prompt: true) else { return }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (key.rawValue << 16) | ((down ? 0xa : 0xb) << 8)
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static func trusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: Audio activity

/// Which processes are playing media right now, from macOS power assertions. Browsers hold one
/// (e.g. "Playing audio", "Video Wake Lock", "WebKit Media Playback") while a tab plays sound.
enum AudioActivity {
    static func processPathsPlayingMedia() -> [String]? {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byPID = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return nil }
        var paths: [String] = []
        for (pid, assertions) in byPID {
            let names = assertions.compactMap { $0["AssertName"] as? String }.map { $0.lowercased() }
            guard names.contains(where: { $0.contains("audio") || $0.contains("media") || $0.contains("playback") || $0.contains("video wake lock") }) else { continue }
            if let path = executablePath(pid.int32Value) { paths.append(path) }
        }
        return paths
    }

    private static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
