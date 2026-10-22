import AppKit

/// The 🍥 menu bar item. The menu is rebuilt each time it opens, so it always shows current state.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var store: ThemeStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ThemeStore()
        self.store = store

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🍥"
        item.button?.toolTip = "Anime Themes"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item

        store.onChange = { [weak self] in self?.updateTitle() }
        updateTitle()
        store.start()
    }

    private func updateTitle() {
        statusItem?.button?.title = store?.current?.spec.emoji ?? "🍥"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let store else { return }
        for item in buildItems(store) { menu.addItem(item) }
    }

    // MARK: Menu

    private func buildItems(_ store: ThemeStore) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let s = store.settings
        let hasTheme = store.current != nil

        if let v = store.current {
            items.append(.info("\(v.anime.series ?? v.anime.name) · \(v.spec.group ?? v.anime.name) · \(v.spec.name)", bold: true))
        } else {
            items.append(.info("No theme selected", bold: true))
        }
        let statusText = store.busy ? "Working…" : store.status
        for line in statusText.split(separator: "\n").prefix(6) {
            let text = String(line)
            items.append(.info(text.count > 90 ? String(text.prefix(88)) + "…" : text))
        }
        items.append(.separator())

        // Series → groups → characters (a series with one group lists its characters directly).
        for series in MenuSeries.build(store.animes) {
            func entries(_ variants: [Variant]) -> [NSMenuItem] {
                variants.map { v in
                    ActionItem("\(v.spec.emoji)  \(v.spec.name)", checked: store.currentID == v.id, enabled: !store.busy) {
                        store.select(v)
                    }
                }
            }
            let inSeries = series.groups.contains { $0.variants.contains { $0.id == store.currentID } }
            let content: [NSMenuItem]
            if series.groups.count == 1 {
                content = entries(series.groups[0].variants)
            } else {
                content = series.groups.map { group in
                    let item = NSMenuItem.submenu(group.title, entries(group.variants))
                    item.state = group.variants.contains { $0.id == store.currentID } ? .on : .off
                    return item
                }
            }
            let item = NSMenuItem.submenu("\(series.emoji)  \(series.title)", content)
            item.state = inSeries ? .on : .off
            items.append(item)
        }
        items.append(.separator())

        items.append(ActionItem("Next wallpaper", key: "n", enabled: hasTheme) { store.nextWallpaper() })
        items.append(ActionItem("Pause live wallpaper", checked: s.livePaused) { store.settings.livePaused.toggle() })
        items.append(ActionItem("New line now", enabled: hasTheme) { store.randomMoment() })
        items.append(ActionItem("Re-apply theme", enabled: hasTheme && !store.busy) {
            if let v = store.current { store.select(v) }
        })

        // Theme rotation
        let seriesName = store.current?.seriesName ?? "current anime"
        var rotation: [NSMenuItem] = [
            ActionItem("Keep the same theme", checked: s.rotation == "off") { store.settings.rotation = "off" },
            ActionItem("Random from all anime", checked: s.rotation == "all") { store.settings.rotation = "all" },
            ActionItem("Random from \(seriesName) only", checked: s.rotation == "series", enabled: hasTheme) {
                store.settings.rotation = "series"
            },
            .separator(),
            .info("Change theme"),
        ]
        for (minutes, name) in [(0, "Each time you log in"), (60, "Every hour"), (180, "Every 3 hours"), (1440, "Every day")] {
            rotation.append(ActionItem("   \(name)", checked: s.rotateMinutes == minutes, enabled: s.rotation != "off") {
                store.settings.rotateMinutes = minutes
            })
        }
        rotation.append(.separator())
        rotation.append(ActionItem("Shuffle now", key: "r", enabled: !store.busy) { store.shuffle() })
        let rotationTitle: String
        switch s.rotation {
        case "all": rotationTitle = "Theme rotation: all anime"
        case "series": rotationTitle = "Theme rotation: \(seriesName)"
        default: rotationTitle = "Theme rotation: off"
        }
        items.append(.submenu(rotationTitle, rotation))
        items.append(.separator())

        // Voice
        var voice: [NSMenuItem] = [
            ActionItem("Voice on", checked: s.voice) { store.settings.voice.toggle() },
            .separator(),
            .info("Language"),
        ]
        for (code, name) in [("ja", "Japanese"), ("en", "English"), ("hi", "Hindi")] {
            voice.append(ActionItem("   \(name)", checked: s.voiceLanguage == code) { store.settings.voiceLanguage = code })
        }
        voice.append(.info("Volume"))
        for (value, name) in [(0.35, "Low"), (0.7, "Medium"), (1.0, "High")] {
            voice.append(ActionItem("   \(name)", checked: abs(s.volume - value) < 0.01) { store.settings.volume = value })
        }
        voice.append(.separator())
        voice.append(ActionItem("Read lines aloud when there are no clips", checked: s.speakWhenNoClips) {
            store.settings.speakWhenNoClips.toggle()
        })
        voice.append(ActionItem("Play a test clip", enabled: hasTheme) { store.testVoice() })
        if !store.voiceSummary.isEmpty { voice.append(.info(store.voiceSummary)) }
        items.append(.submenu("Voice", voice))

        // Desktop widgets
        var widgetItems: [NSMenuItem] = [
            ActionItem("Show widgets", checked: s.widget) { store.settings.widget.toggle() },
            ActionItem("Edit layout (drag widgets)", checked: store.editingWidgets, enabled: s.widget) {
                store.toggleEditingWidgets()
            },
            ActionItem("Reset positions", enabled: s.widget) { store.resetWidgetPositions() },
            .separator(),
        ]
        for (kind, title) in WidgetManager.kinds {
            widgetItems.append(ActionItem(title, checked: s.enabledWidgets.contains(kind), enabled: s.widget) {
                store.toggleWidget(kind)
            })
        }
        widgetItems.append(.separator())
        widgetItems.append(.info("New quote every"))
        for (minutes, name) in [(15, "15 minutes"), (30, "30 minutes"), (60, "1 hour"), (0, "Never")] {
            widgetItems.append(ActionItem("   \(name)", checked: s.randomMinutes == minutes) { store.settings.randomMinutes = minutes })
        }
        items.append(.submenu("Desktop widgets", widgetItems))

        // What a theme changes
        let sketchy = store.hasSketchyBar
        let parts: [NSMenuItem] = [
            ActionItem("Wallpaper", checked: s.wallpaper) { store.settings.wallpaper.toggle() },
            ActionItem("Live wallpaper", checked: s.liveWallpaper) { store.settings.liveWallpaper.toggle() },
            ActionItem("Accent color", checked: s.accent) { store.settings.accent.toggle() },
            ActionItem("Terminal colors", checked: s.terminal) { store.settings.terminal.toggle() },
            ActionItem("Prompt, aliases & greeting", checked: s.shell) { store.settings.shell.toggle() },
            ActionItem("VS Code theme & font", checked: s.vscode) { store.settings.vscode.toggle() },
            ActionItem("App icons", checked: s.icons) { store.settings.icons.toggle() },
            ActionItem(sketchy ? "Menu bar (SketchyBar)" : "Menu bar (SketchyBar not installed)",
                       checked: s.menuBar && sketchy, enabled: sketchy) { store.settings.menuBar.toggle() },
            .separator(),
            ActionItem("Restore original app icons") { store.restoreIcons() },
        ]
        items.append(.submenu("What a theme changes", parts))
        items.append(ActionItem("Open at login", checked: store.opensAtLogin) {
            store.setOpensAtLogin(!store.opensAtLogin)
        })
        items.append(.separator())

        items.append(ActionItem("Open theme packs folder") { NSWorkspace.shared.open(Paths.packs) })
        items.append(ActionItem("Reload theme packs") { store.reload() })
        items.append(ActionItem("Quit Anime Themes", key: "q") { NSApp.terminate(nil) })
        return items
    }
}

/// A menu item that runs a closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", checked: Bool = false, enabled: Bool = true,
         handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

extension NSMenuItem {
    /// A grey, non-clickable line of text.
    static func info(_ text: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if bold {
            item.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        }
        return item
    }

    static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        items.forEach { menu.addItem($0) }
        item.submenu = menu
        return item
    }
}
