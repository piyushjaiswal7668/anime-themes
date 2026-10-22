import AppKit

// MARK: Clock & date

final class ClockWidget: DesktopWidget {
    private var timeLabel: NSTextField?
    private var dateLabel: NSTextField?
    private let timeFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    private let dateFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"; return f }()

    init() { super.init(kind: "clock", column: .right) }

    override func makeContent(_ v: Variant) -> NSView? {
        let k = Card.colors(v.spec.colors)
        let now = Date()
        let time = Card.label(timeFormat.string(from: now), size: 52, weight: .bold, color: k.fg, mono: true)
        let date = Card.label(dateFormat.string(from: now), size: 14, weight: .medium, color: k.muted)
        let tag = Card.heading("\(v.spec.emoji)  \(v.spec.name)", color: k.accent)
        timeLabel = time
        dateLabel = date
        return Card.vstack([time, date, tag], spacing: 4)
    }

    override func tick(_ count: Int) {
        let now = Date()
        timeLabel?.stringValue = timeFormat.string(from: now)
        dateLabel?.stringValue = dateFormat.string(from: now)
    }
}

// MARK: System stats

final class StatsWidget: DesktopWidget {
    private struct Row { let bar: BarView; let value: NSTextField }
    private var rows: [String: Row] = [:]

    init() { super.init(kind: "stats", column: .right) }

    override func makeContent(_ v: Variant) -> NSView? {
        let k = Card.colors(v.spec.colors)
        var views: [NSView] = [Card.heading("System", color: k.accent)]
        rows = [:]
        for (key, title) in [("cpu", "CPU"), ("mem", "Memory"), ("bat", "Battery"), ("disk", "Disk")] {
            let name = Card.label(title, size: 12, weight: .medium, color: k.muted)
            name.widthAnchor.constraint(equalToConstant: 58).isActive = true
            let bar = BarView()
            bar.trackColor = k.muted.withAlphaComponent(0.25)
            bar.fillColor = key == "cpu" ? k.accent : (key == "mem" ? k.accent2 : k.accent)
            bar.widthAnchor.constraint(equalToConstant: 120).isActive = true
            bar.heightAnchor.constraint(equalToConstant: 8).isActive = true
            let value = Card.label("…", size: 12, color: k.fg, mono: true)
            value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: 72).isActive = true
            rows[key] = Row(bar: bar, value: value)
            views.append(Card.hstack([name, bar, value], spacing: 8))
        }
        update()
        return Card.vstack(views, spacing: 9)
    }

    override func tick(_ count: Int) { update() }

    private func update() {
        if let c = SystemStats.cpu() { set("cpu", c, String(format: "%.0f%%", c * 100)) }
        if let m = SystemStats.memory() { set("mem", m.used / m.total, SystemStats.gigabytes(m.used)) }
        if let b = SystemStats.battery() { set("bat", Double(b.percent) / 100, "\(b.percent)%" + (b.charging ? " ⚡" : "")) }
        else { rows["bat"]?.value.stringValue = "AC" }
        if let d = SystemStats.disk() { set("disk", d.used / d.total, SystemStats.gigabytes(d.total - d.used) + " free") }
    }

    private func set(_ key: String, _ fraction: Double, _ text: String) {
        rows[key]?.bar.fraction = CGFloat(fraction)
        rows[key]?.value.stringValue = text
    }

    override var width: CGFloat { 300 }
}

// MARK: Dev / git

/// Shows the git project you were last in (the shell hook records it), that project's own
/// last build result, and a button to open it in VS Code.
final class DevWidget: DesktopWidget {
    struct Build: Equatable { var ok: Bool; var command: String; var date: Date }
    struct Info: Equatable {
        var path: String?
        var repo: String?
        var branch = ""
        var changes = 0
        var ahead = 0
        var behind = 0
        var build: Build?
    }

    private var info = Info()
    private var loading = false

    init() { super.init(kind: "dev", column: .right) }

    override var width: CGFloat { 320 }
    override var acceptsClicks: Bool { true }   // for the Open in VS Code button

    override func makeContent(_ v: Variant) -> NSView? {
        let k = Card.colors(v.spec.colors)
        var views: [NSView] = [Card.heading("Dev", color: k.accent)]
        if let repo = info.repo {
            views.append(Card.label(repo, size: 16, weight: .semibold, color: k.fg))
            views.append(Card.label("⎇ \(info.branch)", size: 13, color: k.accent2, mono: true))
            var status = info.changes == 0 ? "Clean" : "\(info.changes) changed file\(info.changes == 1 ? "" : "s")"
            if info.ahead > 0 { status += " · ↑\(info.ahead)" }
            if info.behind > 0 { status += " · ↓\(info.behind)" }
            views.append(Card.label(status, size: 12, color: info.changes == 0 ? k.green : k.fg))
            if let b = info.build {
                let ago = RelativeDateTimeFormatter().localizedString(for: b.date, relativeTo: Date())
                views.append(Card.label("\(b.ok ? "✓" : "✗") \(b.command) · \(ago)", size: 12,
                                        color: b.ok ? k.green : k.red, mono: true))
            } else {
                views.append(Card.label("No build run here yet", size: 12, color: k.muted))
            }
            if let path = info.path, let button = openButton(path: path, color: k.accent) {
                views.append(button)
            }
        } else {
            views.append(Card.label("cd into a git project in Terminal", size: 12, color: k.muted))
            load()
        }
        return Card.vstack(views, spacing: 5)
    }

    override func tick(_ count: Int) {
        if count % 5 == 0 { load() }   // every 10 seconds
    }

    private func load() {
        guard !loading else { return }
        loading = true
        Task {
            let fresh = await Task.detached { DevWidget.read() }.value
            loading = false
            if fresh != info {
                info = fresh
                render()
            }
        }
    }

    // MARK: Open in VS Code

    private func openButton(path: String, color: NSColor) -> NSButton? {
        guard let vscode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else { return nil }
        let b = FirstClickButton()
        b.title = "Open in VS Code"
        b.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        b.imagePosition = .imageLeading
        b.isBordered = false
        b.contentTintColor = color
        b.attributedTitle = NSAttributedString(string: " Open in VS Code", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: color,
        ])
        b.target = ActionTarget.shared
        b.action = #selector(ActionTarget.fire(_:))
        ActionTarget.shared.handlers[ObjectIdentifier(b)] = {
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: vscode,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
        return b
    }

    // MARK: Reading state

    nonisolated static func read() -> Info {
        var info = Info()
        let state = Paths.home.appendingPathComponent(".config/anime-themes/state")
        guard let dir = (try? String(contentsOf: state.appendingPathComponent("repo"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !dir.isEmpty,
            FileManager.default.fileExists(atPath: dir) else { return info }

        func git(_ args: [String]) -> String? {
            (try? Run.run("/usr/bin/git", ["-C", dir] + args))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        info.path = dir
        info.repo = URL(fileURLWithPath: dir).lastPathComponent
        info.branch = git(["rev-parse", "--abbrev-ref", "HEAD"]) ?? "?"
        info.changes = (git(["status", "--porcelain"]) ?? "").split(separator: "\n").count
        if let counts = git(["rev-list", "--left-right", "--count", "@{upstream}...HEAD"]) {
            let parts = counts.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Int($0) }
            if parts.count == 2 { info.behind = parts[0]; info.ahead = parts[1] }
        }

        // builds.tsv: one line per project — path, pass|fail, unix time, command (tab-separated)
        if let text = try? String(contentsOf: state.appendingPathComponent("builds.tsv"), encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let f = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                guard f.count == 4, f[0] == dir, let t = Double(f[2]) else { continue }
                let cmd = f[3].count > 28 ? String(f[3].prefix(27)) + "…" : f[3]
                info.build = Build(ok: f[1] == "pass", command: cmd, date: Date(timeIntervalSince1970: t))
            }
        }
        return info
    }
}

// MARK: Character portrait

final class PortraitWidget: DesktopWidget {
    private var imageWidth: CGFloat = 220

    init() { super.init(kind: "portrait", column: .left) }

    override var width: CGFloat { imageWidth + 32 }

    override func makeContent(_ v: Variant) -> NSView? {
        guard let path = VSCodeModule.stickerPath(v), let image = NSImage(contentsOfFile: path),
              image.size.height > 0 else { return nil }
        let height: CGFloat = 260
        imageWidth = min(300, image.size.width * height / image.size.height)
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.widthAnchor.constraint(equalToConstant: imageWidth).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        let k = Card.colors(v.spec.colors)
        return Card.vstack([view, Card.heading("\(v.spec.emoji)  \(v.spec.character)", color: k.accent)], spacing: 8)
    }
}

/// Routes button clicks to closures.
@MainActor
final class ActionTarget: NSObject {
    static let shared = ActionTarget()
    var handlers: [ObjectIdentifier: () -> Void] = [:]
    var sliderHandlers: [ObjectIdentifier: (Double) -> Void] = [:]
    @objc func fire(_ sender: NSButton) { handlers[ObjectIdentifier(sender)]?() }
}

// MARK: Quote card

final class QuoteCardWidget: DesktopWidget {
    var line = "" { didSet { if line != oldValue, isVisible { render() } } }

    init() { super.init(kind: "quote", column: .left) }

    override var width: CGFloat { 380 }

    override func makeContent(_ v: Variant) -> NSView? {
        guard !line.isEmpty else { return nil }
        let k = Card.colors(v.spec.colors)
        let emoji = Card.label(v.spec.emoji, size: 26, color: k.fg)
        emoji.setContentHuggingPriority(.required, for: .horizontal)
        let text = Card.label(line, size: 15, color: k.fg, mono: true, wraps: true)
        text.preferredMaxLayoutWidth = width - 32 - 40 - 12
        let column = Card.vstack([text, Card.heading(v.spec.name, color: k.accent)], spacing: 8)
        let row = Card.hstack([emoji, column], spacing: 12)
        row.alignment = .top
        return row
    }
}
