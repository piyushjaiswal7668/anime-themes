import AppKit

@MainActor
enum WallpaperModule {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tiff"]
    private static let lastKey = "lastWallpaper"

    static func images(for v: Variant) -> [URL] {
        let dir = v.folder.appendingPathComponent("wallpapers")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    /// Sets a random wallpaper from the variant's folder on every screen.
    /// With no images yet, it uses a gradient made from the palette.
    /// Returns a short note for the status line.
    @discardableResult
    static func apply(_ v: Variant) throws -> String {
        var list = images(for: v)
        let last = UserDefaults.standard.string(forKey: lastKey)
        if list.count > 1 { list.removeAll { $0.path == last } }

        let url: URL
        let note: String
        if let pick = list.randomElement() {
            url = pick
            note = pick.lastPathComponent
        } else {
            url = try paletteWallpaper(v)
            note = "palette gradient (add images to the wallpapers folder)"
        }
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
        UserDefaults.standard.set(url.path, forKey: lastKey)
        return note
    }

    /// Draws a soft gradient in the variant's colors so a theme looks right before any downloads.
    static func paletteWallpaper(_ v: Variant) throws -> URL {
        let out = Paths.generated.appendingPathComponent("wallpapers/\(v.fileStem).png")
        if FileManager.default.fileExists(atPath: out.path) { return out }
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)

        let w = 3456, h = 2234
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw AppError("Could not create the wallpaper image.") }

        let c = v.spec.colors
        let size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let base = NSGradient(colors: [RGB.of(c.bg).nsColor, RGB.of(c.surface).nsColor])
        base?.draw(in: NSRect(origin: .zero, size: size), angle: -30)

        let accent = RGB.of(c.accent).nsColor
        let glow = NSGradient(colors: [accent.withAlphaComponent(0.42), accent.withAlphaComponent(0)])
        glow?.draw(in: NSRect(x: size.width * 0.45, y: -size.height * 0.55,
                              width: size.width * 0.95, height: size.width * 0.95),
                   relativeCenterPosition: .zero)

        let accent3 = RGB.of(c.accent3).nsColor
        let glow2 = NSGradient(colors: [accent3.withAlphaComponent(0.22), accent3.withAlphaComponent(0)])
        glow2?.draw(in: NSRect(x: -size.width * 0.25, y: size.height * 0.45,
                               width: size.width * 0.7, height: size.width * 0.7),
                    relativeCenterPosition: .zero)

        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw AppError("Could not save the wallpaper image.")
        }
        try data.write(to: out)
        return out
    }
}
