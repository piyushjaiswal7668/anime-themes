import Foundation
import CryptoKit

/// Builds one local VS Code extension holding a color theme for every variant,
/// then switches theme, font and sticker by editing settings.json. VS Code applies
/// settings changes live, so open windows recolor right away.
enum VSCodeModule {
    static let extensionID = "local.anime-themes"

    static func themeLabel(_ v: Variant) -> String { "Anime · \(v.spec.name)" }

    static func apply(_ v: Variant, all: [Variant]) throws -> String {
        let profiles = Profile.all()
        var notes: [String] = []
        let note = try ensureExtension(all, profiles: profiles)
        if !note.isEmpty { notes.append(note) }

        var pairs: [(String, String)] = [
            ("workbench.colorTheme", json(themeLabel(v))),
            ("editor.fontFamily", json(FontNames.codeFamilyCSS)),
            ("terminal.integrated.fontFamily", json(FontNames.codeFamilyCSS)),
            ("editor.fontLigatures", "true"),
        ]
        // Sticker and wallpaper, drawn by the "background" extension (shalldie.background),
        // which works with any color theme. A variant without them clears the images.
        pairs.append(("background.editor", try stickerSettings(v)))
        pairs.append(("background.fullscreen", try wallpaperSettings(v)))

        // Every VS Code profile keeps its own settings, so write them all.
        for profile in profiles {
            try setSettings(pairs, at: profile.settings)
        }

        if stickerPath(v) != nil || wallpaperPath(v) != nil {
            let missing = profiles.filter { !$0.hasExtension("shalldie.background") }
            if !missing.isEmpty {
                if let code = codeCLI() {
                    for p in missing { _ = try? Run.run(code, ["--install-extension", "shalldie.background"] + p.cliArgs) }
                    notes.append("installed the “background” extension; restart VS Code")
                } else {
                    notes.append("install the “background” extension (shalldie) to see stickers")
                }
            }
        }
        if profiles.count > 1 { notes.append("applied to \(profiles.count) VS Code profiles") }
        return notes.joined(separator: "; ")
    }

    /// The default VS Code profile plus any named ones (each has its own settings and extensions).
    struct Profile {
        let name: String?          // nil = default profile
        let folder: URL

        var settings: URL { folder.appendingPathComponent("settings.json") }
        var cliArgs: [String] { name.map { ["--profile", $0] } ?? [] }
        var key: String { name.map { "profile-" + $0.unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined() } ?? "default" }

        func hasExtension(_ id: String) -> Bool {
            if name == nil {
                let dir = Paths.home.appendingPathComponent(".vscode/extensions")
                let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                return names.contains { $0.lowercased().hasPrefix(id.lowercased() + "-") }
            }
            let list = (try? String(contentsOf: folder.appendingPathComponent("extensions.json"), encoding: .utf8)) ?? ""
            return list.lowercased().contains("\"" + id.lowercased() + "\"")
        }

        static func all() -> [Profile] {
            let user = Paths.vscodeSettings.deletingLastPathComponent()
            var list = [Profile(name: nil, folder: user)]
            let storage = user.appendingPathComponent("globalStorage/storage.json")
            if let data = try? Data(contentsOf: storage),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let profiles = obj["userDataProfiles"] as? [[String: Any]] {
                for p in profiles {
                    guard let location = p["location"] as? String else { continue }
                    let folder = location.hasPrefix("/") ? URL(fileURLWithPath: location)
                                                        : user.appendingPathComponent("profiles/\(location)")
                    list.append(Profile(name: p["name"] as? String, folder: folder))
                }
            }
            return list
        }
    }

    /// A random sticker from the variant folder: sticker.png, sticker-2.png, sticker-3.png, …
    static func stickerPath(_ v: Variant) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: v.folder.path)) ?? []
        let stickers = names.filter {
            $0.range(of: #"^sticker(-\d+)?\.(png|gif|webp)$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return stickers.randomElement().map { v.folder.appendingPathComponent($0).path }
    }

    /// A random still from the variant's wallpapers folder, used faintly behind the whole VS Code window.
    static func wallpaperPath(_ v: Variant) -> String? {
        v.files(in: "wallpapers", extensions: ["jpg", "jpeg", "png", "webp"]).randomElement()?.path
    }

    /// The `background.fullscreen` object: the theme's wallpaper, faint, behind everything.
    private static func wallpaperSettings(_ v: Variant) throws -> String {
        let images: [String] = wallpaperPath(v).map { [$0] } ?? []
        let object: [String: Any] = [
            "images": images,
            "opacity": 0.12,
            "size": "cover",
            "position": "center",
            "interval": 0,
            "random": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// The `background.editor` object: one image pinned to the bottom-right of each editor.
    private static func stickerSettings(_ v: Variant) throws -> String {
        let images: [String] = stickerPath(v).map { [$0] } ?? []
        let object: [String: Any] = [
            "useFront": true,
            "style": [
                "background-position": "100% 100%",
                "background-size": "auto 38%",
                "background-repeat": "no-repeat",
                "opacity": 0.75,
            ],
            "styles": [],
            "images": images,
            "interval": 0,
            "random": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Extension

    private static func ensureExtension(_ all: [Variant], profiles: [Profile]) throws -> String {
        let fm = FileManager.default
        let root = Paths.generated.appendingPathComponent("vscode")
        let stage = root.appendingPathComponent("vsix")
        let ext = stage.appendingPathComponent("extension")

        var themes: [[String: Any]] = []
        var files: [(String, Data)] = []
        for v in all {
            let path = "themes/\(v.fileStem).json"
            let data = try JSONSerialization.data(withJSONObject: themeJSON(v), options: [.prettyPrinted, .sortedKeys])
            files.append((path, data))
            themes.append(["label": themeLabel(v), "uiTheme": "vs-dark", "path": "./\(path)"])
        }
        let manifest: [String: Any] = [
            "name": "anime-themes", "displayName": "Anime Themes (local)", "publisher": "local",
            "version": "1.0.0", "description": "Generated by the Anime Themes menu bar app.",
            "engines": ["vscode": "^1.70.0"], "categories": ["Themes"],
            "contributes": ["themes": themes],
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])

        // Skip the reinstall when nothing changed.
        var digestInput = manifestData
        for (_, d) in files { digestInput.append(d) }
        let hash = SHA256.hash(data: digestInput).map { String(format: "%02x", $0) }.joined()
        let vsix = root.appendingPathComponent("anime-themes.vsix")
        let builtFile = root.appendingPathComponent("built.hash")
        if (try? String(contentsOf: builtFile, encoding: .utf8)) != hash || !fm.fileExists(atPath: vsix.path) {
            try? fm.removeItem(at: stage)
            try fm.createDirectory(at: ext.appendingPathComponent("themes"), withIntermediateDirectories: true)
            try manifestData.write(to: ext.appendingPathComponent("package.json"))
            for (path, data) in files { try data.write(to: ext.appendingPathComponent(path)) }
            try vsixMetadata.write(to: stage.appendingPathComponent("extension.vsixmanifest"), atomically: true, encoding: .utf8)
            try contentTypes.write(to: stage.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
            try? fm.removeItem(at: vsix)
            try Run.run("/usr/bin/zip", ["-r", "-X", "-q", vsix.path, "."], cwd: stage)
            try hash.write(to: builtFile, atomically: true, encoding: .utf8)
        }

        guard let code = codeCLI() else {
            // No `code` command: copy the extension folder in directly (default profile only).
            let dest = Paths.home.appendingPathComponent(".vscode/extensions/\(extensionID)-1.0.0")
            try? fm.removeItem(at: dest)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: ext, to: dest)
            return "restart VS Code once to load the themes"
        }

        // Install into each profile whose copy is missing or out of date.
        var failed: [String] = []
        for p in profiles {
            let marker = root.appendingPathComponent("installed-\(p.key).hash")
            let current = (try? String(contentsOf: marker, encoding: .utf8)) == hash
            if current && p.hasExtension(extensionID) { continue }
            if (try? Run.run(code, ["--install-extension", vsix.path, "--force"] + p.cliArgs)) != nil {
                try? hash.write(to: marker, atomically: true, encoding: .utf8)
            } else {
                failed.append(p.name ?? "Default")
            }
        }
        return failed.isEmpty ? "" : "couldn't add the themes to profile \(failed.joined(separator: ", "))"
    }

    static func codeCLI() -> String? {
        let candidates = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            Paths.home.appendingPathComponent("Applications/Visual Studio Code.app/Contents/Resources/app/bin/code").path,
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static let vsixMetadata = """
    <?xml version="1.0" encoding="utf-8"?>
    <PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
      <Metadata>
        <Identity Language="en-US" Id="anime-themes" Version="1.0.0" Publisher="local" />
        <DisplayName>Anime Themes (local)</DisplayName>
        <Description xml:space="preserve">Generated by the Anime Themes menu bar app.</Description>
        <Categories>Themes</Categories>
        <Properties>
          <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.70.0" />
        </Properties>
      </Metadata>
      <Installation>
        <InstallationTarget Id="Microsoft.VisualStudio.Code" />
      </Installation>
      <Dependencies />
      <Assets>
        <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
      </Assets>
    </PackageManifest>
    """

    private static let contentTypes = """
    <?xml version="1.0" encoding="utf-8"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension=".json" ContentType="application/json" /><Default Extension=".vsixmanifest" ContentType="text/xml" /></Types>
    """

    // MARK: Theme

    static func themeJSON(_ v: Variant) -> [String: Any] {
        let c = v.spec.colors
        let a = c.ansi16
        let onAccent = RGB.of(c.accent).luminance > 0.45 ? c.bg : "#ffffff"
        var colors: [String: String] = [
            "editor.background": c.bg, "editor.foreground": c.fg,
            "editorLineNumber.foreground": c.muted + "99", "editorLineNumber.activeForeground": c.accent,
            "editorCursor.foreground": c.accent,
            "editor.selectionBackground": c.accent + "40", "editor.lineHighlightBackground": c.surface + "99",
            "editor.findMatchHighlightBackground": c.accent2 + "40",
            "editorBracketMatch.border": c.accent, "editorIndentGuide.background1": c.surface,
            "editorWidget.background": c.surface, "editorSuggestWidget.background": c.surface,
            "editorSuggestWidget.selectedBackground": c.accent + "33",
            "activityBar.background": c.surface, "activityBar.foreground": c.accent,
            "activityBar.inactiveForeground": c.muted, "activityBarBadge.background": c.accent,
            "activityBarBadge.foreground": onAccent,
            "sideBar.background": c.surface, "sideBar.foreground": c.fg, "sideBarTitle.foreground": c.accent,
            "sideBarSectionHeader.background": c.bg,
            "titleBar.activeBackground": c.bg, "titleBar.activeForeground": c.fg, "titleBar.inactiveBackground": c.bg,
            "statusBar.background": c.accent, "statusBar.foreground": onAccent,
            "statusBar.noFolderBackground": c.surface, "statusBar.debuggingBackground": c.accent3,
            "tab.activeBackground": c.bg, "tab.activeForeground": c.fg, "tab.activeBorderTop": c.accent,
            "tab.inactiveBackground": c.surface, "tab.inactiveForeground": c.muted,
            "editorGroupHeader.tabsBackground": c.surface,
            "panel.background": c.bg, "panel.border": c.surface, "panelTitle.activeBorder": c.accent,
            "terminal.background": c.bg, "terminal.foreground": c.fg, "terminalCursor.foreground": c.accent,
            "focusBorder": c.accent + "99", "progressBar.background": c.accent, "textLink.foreground": c.accent,
            "button.background": c.accent, "button.foreground": onAccent,
            "badge.background": c.accent, "badge.foreground": onAccent,
            "list.activeSelectionBackground": c.accent + "33", "list.inactiveSelectionBackground": c.accent + "22",
            "list.hoverBackground": c.bg, "list.highlightForeground": c.accent,
            "input.background": c.bg, "dropdown.background": c.surface,
            "scrollbarSlider.background": c.muted + "33", "scrollbarSlider.hoverBackground": c.muted + "55",
        ]
        let ansiNames = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
        for (i, n) in ansiNames.enumerated() {
            colors["terminal.ansi\(n)"] = a[i]
            colors["terminal.ansiBright\(n)"] = a[i + 8]
        }
        func rule(_ scopes: [String], _ fg: String, _ style: String? = nil) -> [String: Any] {
            var s: [String: Any] = ["foreground": fg]
            if let style { s["fontStyle"] = style }
            return ["scope": scopes, "settings": s]
        }
        let tokens: [[String: Any]] = [
            rule(["comment", "punctuation.definition.comment"], c.muted, "italic"),
            rule(["keyword", "storage", "storage.type", "storage.modifier", "keyword.control"], c.accent),
            rule(["keyword.operator", "punctuation.separator", "punctuation.accessor"], a[14]),
            rule(["string", "string.quoted", "string.template"], a[10]),
            rule(["constant.numeric", "constant.language", "constant.character", "constant.other"], a[11]),
            rule(["entity.name.function", "support.function", "meta.function-call.generic"], a[12]),
            rule(["entity.name.type", "entity.name.class", "support.class", "support.type", "entity.other.inherited-class"], c.accent3),
            rule(["variable", "variable.other", "meta.definition.variable"], c.fg),
            rule(["variable.parameter"], c.accent2, "italic"),
            rule(["entity.name.tag"], c.accent),
            rule(["entity.other.attribute-name"], c.accent2),
            rule(["markup.heading"], c.accent, "bold"),
            rule(["invalid"], a[9]),
        ]
        return ["name": themeLabel(v), "type": "dark", "semanticHighlighting": true,
                "colors": colors, "tokenColors": tokens]
    }

    // MARK: settings.json

    /// Sets keys in settings.json without disturbing comments or anything else in the file.
    /// Values are JSON literals (a quoted string, true/false or a number).
    static func setSettings(_ pairs: [(String, String)], at url: URL = Paths.vscodeSettings) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = "{\n}\n" }

        let backup = url.deletingLastPathComponent().appendingPathComponent("settings.before-anime-themes.json")
        if !fm.fileExists(atPath: backup.path), fm.fileExists(atPath: url.path) {
            try? fm.copyItem(at: url, to: backup)
        }

        for (key, value) in pairs {
            if let r = valueRange(of: key, in: text) {
                text.replaceSubrange(r, with: value)
            } else if let brace = text.firstIndex(of: "{") {
                let rest = text[text.index(after: brace)...].drop { $0.isWhitespace || $0.isNewline }
                let comma = rest.first == "}" ? "" : ","
                text.insert(contentsOf: "\n    \"\(key)\": \(value)\(comma)", at: text.index(after: brace))
            } else {
                throw AppError("VS Code settings.json doesn't look like JSON; left it unchanged.")
            }
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Where the value for `key` sits in settings.json: a string, number, true/false/null,
    /// or a whole { } object / [ ] array (brackets inside strings are ignored).
    static func valueRange(of key: String, in text: String) -> Range<String.Index>? {
        let k = NSRegularExpression.escapedPattern(for: key)
        guard let keyRE = try? NSRegularExpression(pattern: "\"\(k)\"\\s*:\\s*"),
              let m = keyRE.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let head = Range(m.range, in: text) else { return nil }
        let start = head.upperBound
        guard start < text.endIndex else { return nil }

        let first = text[start]
        if first == "{" || first == "[" {
            var depth = 0
            var inString = false
            var escaped = false
            var i = start
            while i < text.endIndex {
                let ch = text[i]
                if inString {
                    if escaped { escaped = false }
                    else if ch == "\\" { escaped = true }
                    else if ch == "\"" { inString = false }
                } else if ch == "\"" {
                    inString = true
                } else if ch == "{" || ch == "[" {
                    depth += 1
                } else if ch == "}" || ch == "]" {
                    depth -= 1
                    if depth == 0 { return start..<text.index(after: i) }
                }
                i = text.index(after: i)
            }
            return nil
        }

        let scalar = "\"(?:[^\"\\\\]|\\\\.)*\"|true|false|null|-?\\d+(?:\\.\\d+)?"
        guard let re = try? NSRegularExpression(pattern: scalar),
              let sm = re.firstMatch(in: text, options: .anchored, range: NSRange(start..., in: text)) else { return nil }
        return Range(sm.range, in: text)
    }

    private static func json(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
