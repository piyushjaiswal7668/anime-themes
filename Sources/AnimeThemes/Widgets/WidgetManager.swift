import AppKit

/// Owns the desktop widgets: shows the enabled ones in the current theme, places them,
/// and ticks them every 2 seconds.
@MainActor
final class WidgetManager {
    static let kinds: [(id: String, title: String)] = [
        ("clock", "Clock & date"),
        ("stats", "System stats"),
        ("dev", "Dev / git"),
        ("nowplaying", "Now playing"),
        ("portrait", "Character portrait"),
        ("quote", "Quote card"),
    ]

    private let clock = ClockWidget()
    private let stats = StatsWidget()
    private let dev = DevWidget()
    private let nowPlaying = NowPlayingWidget()
    private let portrait = PortraitWidget()
    private let quote = QuoteCardWidget()
    private var all: [DesktopWidget] { [clock, stats, dev, nowPlaying, portrait, quote] }

    private var timer: Timer?
    private var count = 0
    private(set) var editing = false

    init() {
        for w in all {
            w.onLayoutChange = { [weak self] in self?.layout() }
        }
    }

    func show(_ v: Variant, enabled: Set<String>, line: String) {
        quote.line = line
        for w in all {
            if enabled.contains(w.kind) {
                w.variant = v
                w.render()
            } else {
                w.hide()
            }
        }
        layout()
        startTimer()
    }

    func hideAll() {
        all.forEach { $0.hide() }
        timer?.invalidate()
        timer = nil
    }

    func setLine(_ line: String) { quote.line = line }

    func setEditing(_ on: Bool) {
        editing = on
        all.forEach { $0.setEditing(on) }
    }

    func resetPositions() {
        all.forEach { $0.forgetPosition() }
        layout()
    }

    /// Widgets you dragged stay where you put them. All others stack in two columns that
    /// re-flow whenever one of them changes height, so they never overlap: clock, stats,
    /// dev and music down the right side; quote card and portrait up the left side.
    private func layout() {
        guard let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        var rightTop = area.maxY - 24
        var leftBottom = area.minY + 24
        for w in all where w.isVisible {
            if let saved = w.savedOrigin {
                if !w.placed {
                    w.window.setFrameOrigin(saved)
                    w.placed = true
                }
                continue
            }
            let size = w.window.frame.size
            let origin: NSPoint
            if w.column == .left {
                origin = NSPoint(x: area.minX + 24, y: leftBottom)
                leftBottom += size.height + 16
            } else {
                rightTop -= size.height
                origin = NSPoint(x: area.maxX - size.width - 24, y: rightTop)
                rightTop -= 16
            }
            w.window.setFrameOrigin(origin)
            w.placed = true
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.count += 1
                for w in self.all where w.isVisible { w.tick(self.count) }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
