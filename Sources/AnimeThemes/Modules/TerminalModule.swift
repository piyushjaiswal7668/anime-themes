import AppKit

/// Themes the built-in Terminal app with one profile per variant ("Anime · Zenitsu").
@MainActor
enum TerminalModule {
    static let bundleID = "com.apple.Terminal"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func apply(_ v: Variant) async throws {
        let profile = profileDict(for: v)

        guard isRunning else {
            // Terminal is closed: write the profile straight into its settings.
            writePrefs(profile, name: v.profileName)
            return
        }

        if try !profileExists(v.profileName) {
            // Terminal is open: importing a .terminal file adds the profile. Terminal names the
            // profile after the file, so the file is named exactly like the profile. Importing
            // also opens a window; it is closed again right after, so this happens once per variant
            // and leaves nothing behind.
            let windowsBefore = Set(try windowIDs())
            let file = Paths.generated.appendingPathComponent("terminal/\(v.profileName).terminal")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
            try data.write(to: file)
            try Run.run("/usr/bin/open", ["-g", "-a", "Terminal", file.path])
            var found = false
            for _ in 0..<20 {
                try await Task.sleep(nanoseconds: 300_000_000)
                if try profileExists(v.profileName) { found = true; break }
            }
            try await Task.sleep(nanoseconds: 400_000_000)
            for id in try windowIDs() where !windowsBefore.contains(id) {
                _ = try? AppleScript.run("tell application \"Terminal\" to close (every window whose id is \(id))")
            }
            if !found {
                throw AppError("Terminal didn't add the “\(v.profileName)” profile. Quit Terminal and pick the theme again; it will be added without opening Terminal.")
            }
        }

        let name = v.profileName.replacingOccurrences(of: "\"", with: "\\\"")
        try AppleScript.run("""
        tell application "Terminal"
            set s to settings set "\(name)"
            set default settings to s
            set startup settings to s
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set current settings of t to s
                    end try
                end repeat
            end repeat
        end tell
        """)
    }

    /// IDs of Terminal's open windows.
    static func windowIDs() throws -> [Int] {
        let list = try AppleScript.run("tell application \"Terminal\" to get id of every window")
        guard list.numberOfItems > 0 else { return [] }
        return (1...list.numberOfItems).compactMap { list.atIndex($0).map { Int($0.int32Value) } }
    }

    static func profileExists(_ name: String) throws -> Bool {
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        let result = try AppleScript.run("tell application \"Terminal\" to return (exists settings set \"\(escaped)\")")
        return result.booleanValue
    }

    static func profileDict(for v: Variant) -> [String: Any] {
        let c = v.spec.colors
        func color(_ hex: String, alpha: CGFloat = 1) -> Data {
            let ns = RGB.of(hex).nsColor.withAlphaComponent(alpha)
            return (try? NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: false)) ?? Data()
        }
        var d: [String: Any] = [
            "name": v.profileName,
            "type": "Window Settings",
            "ProfileCurrentVersion": 2.07,
            "BackgroundColor": color(c.bg, alpha: 0.97),
            "BackgroundBlur": 0.4,
            "TextColor": color(c.fg),
            "TextBoldColor": color(c.fg),
            "CursorColor": color(c.accent),
            "CursorType": 1,
            "SelectionColor": color(c.accent, alpha: 0.35),
            "UseBrightBold": true,
            "columnCount": 110,
            "rowCount": 32,
        ]
        let names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
        let ansi = c.ansi16
        for (i, n) in names.enumerated() {
            d["ANSI\(n)Color"] = color(ansi[i])
            d["ANSIBright\(n)Color"] = color(ansi[i + 8])
        }
        if let font = Fonts.codeFont(size: 14),
           let data = try? NSKeyedArchiver.archivedData(withRootObject: font, requiringSecureCoding: false) {
            d["Font"] = data
        }
        return d
    }

    private static func writePrefs(_ profile: [String: Any], name: String) {
        let app = bundleID as CFString
        var all = (CFPreferencesCopyAppValue("Window Settings" as CFString, app) as? [String: Any]) ?? [:]
        all[name] = profile
        CFPreferencesSetAppValue("Window Settings" as CFString, all as CFDictionary, app)
        CFPreferencesSetAppValue("Default Window Settings" as CFString, name as CFString, app)
        CFPreferencesSetAppValue("Startup Window Settings" as CFString, name as CFString, app)
        CFPreferencesAppSynchronize(app)
    }
}
