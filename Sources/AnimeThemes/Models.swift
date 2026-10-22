import Foundation

/// Colors for one variant. `ansi` holds 16 terminal colors: 0-7 normal, 8-15 bright.
struct Palette: Codable, Hashable, Sendable {
    var bg: String
    var surface: String
    var fg: String
    var muted: String
    var accent: String
    var accent2: String
    var accent3: String
    var ansi: [String]

    /// Always returns 16 colors, padding with sensible greys if a pack is short.
    var ansi16: [String] {
        let fallback = ["#1e1e1e", "#d65d5d", "#8cc265", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#d0d0d0",
                        "#5c6370", "#ff7070", "#a3d97c", "#ffd77a", "#78aaff", "#dd9cf0", "#7ad9e0", "#ffffff"]
        return (0..<16).map { $0 < ansi.count ? ansi[$0] : fallback[$0] }
    }
}

/// Contents of `variant.json`.
struct VariantSpec: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var character: String
    var emoji: String
    /// Submenu inside the series (e.g. "Konoha 11"). Defaults to the pack's name.
    var group: String?
    var order: Int?
    var promptUser: String
    var promptHost: String
    var macAccent: String
    /// Shape drawn on generated app icons: swirl, cloud, fan, checks, bolt, flame, bamboo, butterfly.
    var motif: String?
    var colors: Palette
}

/// Contents of `anime.json`.
struct AnimeSpec: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var emoji: String
    /// Menu heading this pack belongs under (e.g. Akatsuki sits under "Naruto"). Defaults to `name`.
    var series: String?
    /// Position of the series in the menu.
    var order: Int?
    /// Order of the groups inside this pack's menu.
    var groups: [String]?
}

struct Variant: Identifiable, Hashable, Sendable {
    let anime: AnimeSpec
    let spec: VariantSpec
    let folder: URL
    let animeFolder: URL

    var id: String { "\(anime.id)/\(spec.id)" }
    /// The menu heading this theme sits under (Akatsuki counts as Naruto).
    var seriesName: String { anime.series ?? anime.name }
    var fileStem: String { "\(anime.id)-\(spec.id)" }
    var profileName: String { "Anime · \(spec.name)" }

    /// Lines from lines.txt, one per row.
    var lines: [String] {
        let text = (try? String(contentsOf: folder.appendingPathComponent("lines.txt"), encoding: .utf8)) ?? ""
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Files in a subfolder of this variant with one of the given extensions.
    func files(in sub: String, extensions: Set<String>) -> [URL] {
        let dir = folder.appendingPathComponent(sub)
        let list = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return list.filter { extensions.contains($0.pathExtension.lowercased()) }
    }
}

/// User choices that aren't part of a theme pack.
struct Settings: Codable, Equatable {
    // What a theme switch changes
    var wallpaper = true
    var liveWallpaper = true
    var accent = true
    var terminal = true
    var shell = true
    var vscode = true
    var icons = true
    var menuBar = true
    // Extras
    var voice = true
    var voiceLanguage = "ja"          // ja, en or hi
    var volume: Double = 0.7
    var speakWhenNoClips = false
    var widget = true
    var widgetCorner = "bottomLeft"   // no longer used; widgets are dragged into place
    var enabledWidgets = ["clock", "stats", "dev", "nowplaying", "portrait", "quote"]
    var randomMinutes = 30            // 0 = off
    var livePaused = false
    // Theme rotation
    var rotation = "off"              // off, all (any anime), series (same anime as the current theme)
    var rotateMinutes = 0             // 0 = each time you log in; otherwise every N minutes

    init() {}

    /// Reads saved settings, keeping defaults for anything missing (so new options don't reset old ones).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        wallpaper = try c.decodeIfPresent(Bool.self, forKey: .wallpaper) ?? d.wallpaper
        liveWallpaper = try c.decodeIfPresent(Bool.self, forKey: .liveWallpaper) ?? d.liveWallpaper
        accent = try c.decodeIfPresent(Bool.self, forKey: .accent) ?? d.accent
        terminal = try c.decodeIfPresent(Bool.self, forKey: .terminal) ?? d.terminal
        shell = try c.decodeIfPresent(Bool.self, forKey: .shell) ?? d.shell
        vscode = try c.decodeIfPresent(Bool.self, forKey: .vscode) ?? d.vscode
        icons = try c.decodeIfPresent(Bool.self, forKey: .icons) ?? d.icons
        menuBar = try c.decodeIfPresent(Bool.self, forKey: .menuBar) ?? d.menuBar
        voice = try c.decodeIfPresent(Bool.self, forKey: .voice) ?? d.voice
        voiceLanguage = try c.decodeIfPresent(String.self, forKey: .voiceLanguage) ?? d.voiceLanguage
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? d.volume
        speakWhenNoClips = try c.decodeIfPresent(Bool.self, forKey: .speakWhenNoClips) ?? d.speakWhenNoClips
        widget = try c.decodeIfPresent(Bool.self, forKey: .widget) ?? d.widget
        widgetCorner = try c.decodeIfPresent(String.self, forKey: .widgetCorner) ?? d.widgetCorner
        enabledWidgets = try c.decodeIfPresent([String].self, forKey: .enabledWidgets) ?? d.enabledWidgets
        randomMinutes = try c.decodeIfPresent(Int.self, forKey: .randomMinutes) ?? d.randomMinutes
        livePaused = try c.decodeIfPresent(Bool.self, forKey: .livePaused) ?? d.livePaused
        rotation = try c.decodeIfPresent(String.self, forKey: .rotation) ?? d.rotation
        rotateMinutes = try c.decodeIfPresent(Int.self, forKey: .rotateMinutes) ?? d.rotateMinutes
    }

    /// Languages to try in order: the chosen one first, then the others.
    var languageOrder: [String] {
        [voiceLanguage] + ["ja", "en", "hi"].filter { $0 != voiceLanguage }
    }
}

struct Anime: Identifiable, Hashable, Sendable {
    let spec: AnimeSpec
    let folder: URL
    var variants: [Variant]
    var id: String { spec.id }
}

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let packs = home.appendingPathComponent("AnimeThemes")
    static let generated = packs.appendingPathComponent(".generated")
    static let shellActive = home.appendingPathComponent(".config/anime-themes/active")
    static let vscodeSettings = home.appendingPathComponent("Library/Application Support/Code/User/settings.json")
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum PackLoader {
    /// Reads ~/AnimeThemes/<anime>/anime.json and ~/AnimeThemes/<anime>/<variant>/variant.json.
    static func load() -> [Anime] {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        guard let animeDirs = try? fm.contentsOfDirectory(at: Paths.packs, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var result: [Anime] = []
        for dir in animeDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("anime.json")),
                  let anime = try? decoder.decode(AnimeSpec.self, from: data) else { continue }
            let subdirs = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles])) ?? []
            var variants: [Variant] = []
            for sub in subdirs {
                let file = sub.appendingPathComponent("variant.json")
                guard let vdata = try? Data(contentsOf: file) else { continue }
                do {
                    let spec = try decoder.decode(VariantSpec.self, from: vdata)
                    variants.append(Variant(anime: anime, spec: spec, folder: sub, animeFolder: dir))
                } catch {
                    NSLog("AnimeThemes: could not read \(file.path): \(error)")
                }
            }
            variants.sort { ($0.spec.order ?? 99, $0.spec.name) < ($1.spec.order ?? 99, $1.spec.name) }
            if !variants.isEmpty { result.append(Anime(spec: anime, folder: dir, variants: variants)) }
        }
        return result.sorted { ($0.spec.order ?? 99, $0.spec.name) < ($1.spec.order ?? 99, $1.spec.name) }
    }
}

/// How the menu shows the packs: series → groups → characters.
struct MenuSeries {
    let title: String
    let emoji: String
    let groups: [(title: String, variants: [Variant])]

    static func build(_ animes: [Anime]) -> [MenuSeries] {
        var order: [String] = []
        var members: [String: [Anime]] = [:]
        for a in animes {
            let key = a.spec.series ?? a.spec.name
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(a)
        }
        return order.map { key in
            let packs = members[key] ?? []
            var groupOrder: [String] = []
            var byGroup: [String: [Variant]] = [:]
            for a in packs {
                for g in a.spec.groups ?? [] where !groupOrder.contains(g) { groupOrder.append(g) }
                for v in a.variants {
                    let g = v.spec.group ?? a.spec.name
                    if !groupOrder.contains(g) { groupOrder.append(g) }
                    byGroup[g, default: []].append(v)
                }
            }
            let groups = groupOrder.compactMap { g -> (title: String, variants: [Variant])? in
                guard let vs = byGroup[g], !vs.isEmpty else { return nil }
                return (g, vs.sorted { ($0.spec.order ?? 99, $0.spec.name) < ($1.spec.order ?? 99, $1.spec.name) })
            }
            return MenuSeries(title: key, emoji: packs.first?.spec.emoji ?? "", groups: groups)
        }
    }
}
