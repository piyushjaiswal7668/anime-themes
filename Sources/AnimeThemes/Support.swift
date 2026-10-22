import AppKit

/// An sRGB color parsed from "#rrggbb".
struct RGB {
    var r: Double, g: Double, b: Double   // 0...1

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    static func of(_ hex: String) -> RGB { RGB(hex: hex) ?? RGB(r: 0.5, g: 0.5, b: 0.5) }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    /// Relative brightness, good enough to choose black or white text on top.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// Nearest color in the xterm 256-color table. The built-in Terminal on macOS 15 is
    /// reliable with 256 colors, so the shell prompt uses these indexes.
    var xterm256: Int {
        let levels: [Double] = [0, 95, 135, 175, 215, 255]
        let R = r * 255, G = g * 255, B = b * 255
        func nearest(_ x: Double) -> Int {
            var best = 0
            for i in 1..<levels.count where abs(levels[i] - x) < abs(levels[best] - x) { best = i }
            return best
        }
        let ri = nearest(R), gi = nearest(G), bi = nearest(B)
        let cubeDist = pow(levels[ri] - R, 2) + pow(levels[gi] - G, 2) + pow(levels[bi] - B, 2)
        let avg = (R + G + B) / 3
        let grayIndex = max(0, min(23, Int(((avg - 8) / 10).rounded())))
        let gv = 8 + 10 * Double(grayIndex)
        let grayDist = pow(gv - R, 2) + pow(gv - G, 2) + pow(gv - B, 2)
        return grayDist < cubeDist ? 232 + grayIndex : 16 + 36 * ri + 6 * gi + bi
    }
}

enum Run {
    /// Runs a command and returns its combined output. Throws if it exits with an error.
    @discardableResult
    static func run(_ path: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        if p.terminationStatus != 0 {
            let name = URL(fileURLWithPath: path).lastPathComponent
            throw AppError("\(name) failed: \(out.prefix(300))")
        }
        return out
    }
}

enum FontNames {
    /// Font list VS Code asks for.
    static let codeFamilyCSS = "'Maple Mono', 'Maple Mono NF', Menlo, monospace"
}

@MainActor
enum Fonts {
    /// Maple Mono if it is installed, otherwise Menlo.
    static func codeFont(size: CGFloat) -> NSFont? {
        let names = NSFontManager.shared.availableFonts
        let pick = names.first { $0 == "MapleMono-Regular" }
            ?? names.first { $0.hasPrefix("MapleMono") && $0.hasSuffix("-Regular") }
            ?? names.first { $0.hasPrefix("MapleMono") }
        if let pick, let font = NSFont(name: pick, size: size) { return font }
        return NSFont(name: "Menlo-Regular", size: size)
    }

    static var mapleInstalled: Bool {
        NSFontManager.shared.availableFonts.contains { $0.hasPrefix("MapleMono") }
    }
}

@MainActor
enum AppleScript {
    @discardableResult
    static func run(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw AppError("Could not build the AppleScript.") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let msg = (error[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -1743 {
                throw AppError("macOS blocked control of Terminal. Allow it in System Settings → Privacy & Security → Automation → Anime Themes.")
            }
            throw AppError(msg)
        }
        return result
    }
}
