import AppKit

/// Gives your apps icons in the variant's colors. Apps are listed in ~/AnimeThemes/icons.json.
/// Your own image wins: put `<bundle id>.png` or `<App Name>.png` in the variant's icons/ folder.
/// Built-in Apple apps (Terminal, Safari, Finder…) are protected by macOS and can't be changed.
@MainActor
enum IconsModule {
    struct Target: Codable {
        var bundleID: String
        var symbol: String
    }

    static var targetsFile: URL { Paths.packs.appendingPathComponent("icons.json") }

    static func targets() -> [Target] {
        guard let data = try? Data(contentsOf: targetsFile),
              let list = try? JSONDecoder().decode([Target].self, from: data) else { return [] }
        return list
    }

    /// Returns a status note like "7 app icons".
    static func apply(_ v: Variant) -> String {
        var changed = 0, skipped: [String] = []
        for t in targets() {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: t.bundleID) else { continue }
            let name = app.deletingPathExtension().lastPathComponent
            let image = customIcon(v, bundleID: t.bundleID, appName: name) ?? makeIcon(v, symbol: t.symbol)
            if NSWorkspace.shared.setIcon(image, forFile: app.path, options: []) {
                changed += 1
            } else {
                skipped.append(name)
            }
        }
        if changed > 0 { refreshDock() }
        var note = "\(changed) app icons"
        if !skipped.isEmpty { note += " (couldn't change \(skipped.joined(separator: ", ")))" }
        return note
    }

    static func restore() -> Int {
        var n = 0
        for t in targets() {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: t.bundleID) else { continue }
            if NSWorkspace.shared.setIcon(nil, forFile: app.path, options: []) { n += 1 }
        }
        if n > 0 { refreshDock() }
        return n
    }

    private static func refreshDock() {
        _ = try? Run.run("/usr/bin/killall", ["Dock"])
    }

    private static func customIcon(_ v: Variant, bundleID: String, appName: String) -> NSImage? {
        let dir = v.folder.appendingPathComponent("icons")
        for base in [bundleID, appName] {
            for ext in ["png", "icns"] {
                let url = dir.appendingPathComponent("\(base).\(ext)")
                if let img = NSImage(contentsOf: url) { return img }
            }
        }
        return nil
    }

    // MARK: Drawing

    /// A 1024px macOS-style icon: palette gradient, the variant's motif, and the app's symbol.
    static func makeIcon(_ v: Variant, symbol: String) -> NSImage {
        let c = v.spec.colors
        let size: CGFloat = 1024
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
            let shape = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

            // Shadow under the plate, like system icons.
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 28
            shadow.shadowOffset = NSSize(width: 0, height: -12)
            shadow.set()
            RGB.of(c.bg).nsColor.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSGradient(colors: [RGB.of(c.surface).nsColor, RGB.of(c.bg).nsColor])?.draw(in: plate, angle: -90)
            drawMotif(v.spec.motif ?? "swirl", in: plate, color: RGB.of(c.accent).nsColor.withAlphaComponent(0.85),
                      second: RGB.of(c.accent2).nsColor.withAlphaComponent(0.6))
            NSGraphicsContext.restoreGraphicsState()

            // App symbol in a small badge so apps stay recognizable.
            let badge = NSRect(x: 560, y: 160, width: 300, height: 300)
            RGB.of(c.bg).nsColor.withAlphaComponent(0.92).setFill()
            NSBezierPath(ovalIn: badge).fill()
            RGB.of(c.accent).nsColor.setStroke()
            let ring = NSBezierPath(ovalIn: badge.insetBy(dx: 6, dy: 6))
            ring.lineWidth = 12
            ring.stroke()
            let config = NSImage.SymbolConfiguration(pointSize: 150, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [RGB.of(c.fg).nsColor]))
            if let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let s = sym.size
                let scale = min(170 / max(s.width, 1), 170 / max(s.height, 1))
                let w = s.width * scale, h = s.height * scale
                sym.draw(in: NSRect(x: badge.midX - w / 2, y: badge.midY - h / 2, width: w, height: h))
            }
            return true
        }
    }

    nonisolated private static func drawMotif(_ motif: String, in r: NSRect, color: NSColor, second: NSColor) {
        let cx = r.midX - 60, cy = r.midY + 60
        color.setFill()
        color.setStroke()
        switch motif {
        case "swirl":
            let p = NSBezierPath()
            var first = true
            for i in 0...420 {
                let t = Double(i) / 30
                let rad = 18 * t
                let pt = NSPoint(x: cx + CGFloat(cos(t) * rad), y: cy + CGFloat(sin(t) * rad))
                if first { p.move(to: pt); first = false } else { p.line(to: pt) }
            }
            p.lineWidth = 44
            p.lineCapStyle = .round
            p.stroke()
        case "cloud":
            let blobs: [(CGFloat, CGFloat, CGFloat)] = [(-150, -20, 230), (-30, 40, 290), (110, -20, 230), (-60, -80, 260)]
            for (dx, dy, d) in blobs {
                NSBezierPath(ovalIn: NSRect(x: cx + dx - d / 2, y: cy + dy - d / 2, width: d, height: d)).fill()
            }
            NSColor.white.withAlphaComponent(0.85).setStroke()
            let edge = NSBezierPath(ovalIn: NSRect(x: cx - 170, y: cy - 150, width: 360, height: 280))
            edge.lineWidth = 16
            edge.stroke()
        case "fan":
            NSBezierPath(ovalIn: NSRect(x: cx - 210, y: cy - 120, width: 420, height: 420)).fill()
            second.setFill()
            NSBezierPath(roundedRect: NSRect(x: cx - 30, y: cy - 400, width: 60, height: 300), xRadius: 30, yRadius: 30).fill()
            NSColor.white.withAlphaComponent(0.8).setFill()
            NSBezierPath(rect: NSRect(x: cx - 210, y: cy + 80, width: 420, height: 18)).fill()
        case "checks":
            let s: CGFloat = 103
            for row in 0..<8 { for col in 0..<8 where (row + col) % 2 == 0 {
                NSBezierPath(rect: NSRect(x: r.minX + CGFloat(col) * s, y: r.minY + CGFloat(row) * s, width: s, height: s)).fill()
            } }
        case "bolt":
            let p = NSBezierPath()
            p.move(to: NSPoint(x: cx + 60, y: cy + 330))
            p.line(to: NSPoint(x: cx - 170, y: cy - 20))
            p.line(to: NSPoint(x: cx - 10, y: cy - 20))
            p.line(to: NSPoint(x: cx - 90, y: cy - 330))
            p.line(to: NSPoint(x: cx + 170, y: cy + 60))
            p.line(to: NSPoint(x: cx + 10, y: cy + 60))
            p.close()
            p.fill()
        case "flame":
            let layers: [(CGFloat, NSColor)] = [(1.0, color), (0.6, second)]
            for (scale, col) in layers {
                col.setFill()
                let w = 360 * scale, h = 560 * scale, base = cy - 260
                let p = NSBezierPath()
                p.move(to: NSPoint(x: cx, y: base))
                p.curve(to: NSPoint(x: cx, y: base + h),
                        controlPoint1: NSPoint(x: cx - w, y: base),
                        controlPoint2: NSPoint(x: cx - w * 0.1, y: base + h * 0.6))
                p.curve(to: NSPoint(x: cx, y: base),
                        controlPoint1: NSPoint(x: cx + w * 0.6, y: base + h * 0.55),
                        controlPoint2: NSPoint(x: cx + w, y: base))
                p.fill()
            }
        case "bamboo":
            let stalks: [CGFloat] = [cx - 180, cx - 20, cx + 140]
            for (i, x) in stalks.enumerated() {
                (i == 1 ? second : color).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: r.minY - 20, width: 90, height: r.height + 40), xRadius: 30, yRadius: 30).fill()
                NSColor.black.withAlphaComponent(0.35).setFill()
                for j in 0..<4 {
                    NSBezierPath(rect: NSRect(x: x, y: r.minY + 140 + CGFloat(j) * 190 + CGFloat(i) * 40, width: 90, height: 14)).fill()
                }
            }
        case "butterfly":
            let wings: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(-230, 0, 230, 280), (0, 0, 230, 280), (-190, -220, 190, 200), (0, -220, 190, 200)]
            for (dx, dy, w, h) in wings {
                NSBezierPath(ovalIn: NSRect(x: cx + dx, y: cy + dy - 40, width: w, height: h)).fill()
            }
            second.setFill()
            NSBezierPath(roundedRect: NSRect(x: cx - 14, y: cy - 260, width: 28, height: 520), xRadius: 14, yRadius: 14).fill()
        case "ripples":
            // Concentric rings around a small dot.
            for (i, radius) in ([CGFloat(380), 290, 200, 110] as [CGFloat]).enumerated() {
                let ring = NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
                ring.lineWidth = 26
                (i % 2 == 0 ? color : second).setStroke()
                ring.stroke()
            }
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - 40, y: cy - 40, width: 80, height: 80)).fill()
        case "scroll":
            // An open scroll: paper with rolled ends and lines of writing.
            let paper = NSRect(x: cx - 300, y: cy - 200, width: 600, height: 400)
            second.setFill()
            NSBezierPath(rect: paper).fill()
            color.setFill()
            for x in [paper.minX - 40, paper.maxX - 40] {
                NSBezierPath(roundedRect: NSRect(x: x, y: paper.minY - 40, width: 80, height: paper.height + 80),
                             xRadius: 40, yRadius: 40).fill()
            }
            NSColor.black.withAlphaComponent(0.45).setFill()
            for (j, w) in ([CGFloat(420), 340, 400, 260] as [CGFloat]).enumerated() {
                NSBezierPath(roundedRect: NSRect(x: paper.minX + 70, y: paper.maxY - 90 - CGFloat(j) * 80, width: w, height: 22),
                             xRadius: 11, yRadius: 11).fill()
            }
        case "diamond":
            // A diamond with a smaller one inside.
            for (size, col) in [(CGFloat(330), color), (CGFloat(170), second)] {
                col.setFill()
                let p = NSBezierPath()
                p.move(to: NSPoint(x: cx, y: cy + size))
                p.line(to: NSPoint(x: cx + size * 0.7, y: cy))
                p.line(to: NSPoint(x: cx, y: cy - size))
                p.line(to: NSPoint(x: cx - size * 0.7, y: cy))
                p.close()
                p.fill()
            }
        case "blossom":
            // Five petals around a center.
            for k in 0..<5 {
                let petal = NSBezierPath(ovalIn: NSRect(x: -80, y: 40, width: 160, height: 290))
                var t = AffineTransform(translationByX: cx, byY: cy)
                t.rotate(byDegrees: CGFloat(k) * 72)
                petal.transform(using: t)
                petal.fill()
            }
            second.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - 60, y: cy - 60, width: 120, height: 120)).fill()
        case "crescent":
            // A big circle with an offset circle cut out of it.
            NSGraphicsContext.saveGraphicsState()
            let cut = NSBezierPath(rect: r.insetBy(dx: -200, dy: -200))
            cut.appendOval(in: NSRect(x: cx - 200, y: cy - 280, width: 520, height: 520))
            cut.windingRule = .evenOdd
            cut.addClip()
            NSBezierPath(ovalIn: NSRect(x: cx - 340, y: cy - 340, width: 680, height: 680)).fill()
            NSGraphicsContext.restoreGraphicsState()
            second.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx + 230, y: cy + 190, width: 60, height: 60)).fill()
        case "wave":
            // Three rolling waves.
            for (i, dy) in ([CGFloat(140), 0, -140] as [CGFloat]).enumerated() {
                let p = NSBezierPath()
                for step in 0...80 {
                    let x = r.minX - 40 + CGFloat(step) * (r.width + 80) / 80
                    let y = cy + dy + CGFloat(60 * sin(Double(step) / 80 * .pi * 4 + Double(i)))
                    if step == 0 { p.move(to: NSPoint(x: x, y: y)) } else { p.line(to: NSPoint(x: x, y: y)) }
                }
                p.lineWidth = 34
                p.lineCapStyle = .round
                (i == 1 ? second : color).setStroke()
                p.stroke()
            }
        case "burst":
            // A twelve-point explosion with a bright core.
            let p = NSBezierPath()
            for k in 0..<24 {
                let angle = Double(k) * .pi / 12
                let radius: CGFloat = k % 2 == 0 ? 360 : 150
                let pt = NSPoint(x: cx + radius * CGFloat(cos(angle)), y: cy + radius * CGFloat(sin(angle)))
                if k == 0 { p.move(to: pt) } else { p.line(to: pt) }
            }
            p.close()
            p.fill()
            second.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - 110, y: cy - 110, width: 220, height: 220)).fill()
        case "strings":
            // Puppet strings hanging from the top, each ending in a bead.
            let ends: [CGFloat] = [0.55, 0.35, 0.65, 0.42, 0.58]
            for (k, end) in ends.enumerated() {
                let x = r.minX + 150 + CGFloat(k) * 130
                let y = r.minY + r.height * end
                let line = NSBezierPath()
                line.move(to: NSPoint(x: x, y: r.maxY + 10))
                line.line(to: NSPoint(x: x, y: y))
                line.lineWidth = 12
                line.stroke()
                second.setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 34, y: y - 34, width: 68, height: 68)).fill()
            }
        case "triangle":
            // A circle with an upside-down triangle inside.
            let ring = NSBezierPath(ovalIn: NSRect(x: cx - 320, y: cy - 320, width: 640, height: 640))
            ring.lineWidth = 30
            ring.stroke()
            let t = NSBezierPath()
            t.move(to: NSPoint(x: cx - 250, y: cy + 160))
            t.line(to: NSPoint(x: cx + 250, y: cy + 160))
            t.line(to: NSPoint(x: cx, y: cy - 300))
            t.close()
            t.lineWidth = 30
            t.lineJoinStyle = .round
            second.setStroke()
            t.stroke()
        case "stitch":
            // Rows of stitches.
            for row in 0..<3 {
                let y = cy + 200 - CGFloat(row) * 200
                let seam = NSBezierPath()
                seam.move(to: NSPoint(x: r.minX + 60, y: y))
                seam.line(to: NSPoint(x: r.maxX - 60, y: y))
                seam.lineWidth = 22
                color.setStroke()
                seam.stroke()
                second.setStroke()
                for k in 0..<7 {
                    let x = r.minX + 120 + CGFloat(k) * 100
                    let tick = NSBezierPath()
                    tick.move(to: NSPoint(x: x - 30, y: y - 45))
                    tick.line(to: NSPoint(x: x + 30, y: y + 45))
                    tick.lineWidth = 16
                    tick.lineCapStyle = .round
                    tick.stroke()
                }
            }
        case "leaf":
            // A pointed leaf with a center vein.
            let leaf = NSBezierPath()
            leaf.move(to: NSPoint(x: cx - 250, y: cy - 300))
            leaf.curve(to: NSPoint(x: cx + 260, y: cy + 330),
                       controlPoint1: NSPoint(x: cx - 380, y: cy + 150),
                       controlPoint2: NSPoint(x: cx - 60, y: cy + 400))
            leaf.curve(to: NSPoint(x: cx - 250, y: cy - 300),
                       controlPoint1: NSPoint(x: cx + 330, y: cy + 60),
                       controlPoint2: NSPoint(x: cx + 80, y: cy - 280))
            leaf.fill()
            let vein = NSBezierPath()
            vein.move(to: NSPoint(x: cx - 250, y: cy - 300))
            vein.curve(to: NSPoint(x: cx + 260, y: cy + 330),
                       controlPoint1: NSPoint(x: cx - 80, y: cy - 60),
                       controlPoint2: NSPoint(x: cx + 80, y: cy + 160))
            vein.lineWidth = 18
            second.setStroke()
            vein.stroke()
        case "snake":
            // An S-shaped snake with a head.
            let body = NSBezierPath()
            body.move(to: NSPoint(x: cx - 300, y: cy - 330))
            body.curve(to: NSPoint(x: cx, y: cy),
                       controlPoint1: NSPoint(x: cx + 250, y: cy - 380),
                       controlPoint2: NSPoint(x: cx + 250, y: cy - 60))
            body.curve(to: NSPoint(x: cx + 120, y: cy + 300),
                       controlPoint1: NSPoint(x: cx - 250, y: cy + 60),
                       controlPoint2: NSPoint(x: cx - 220, y: cy + 330))
            body.lineWidth = 80
            body.lineCapStyle = .round
            body.stroke()
            NSBezierPath(ovalIn: NSRect(x: cx + 60, y: cy + 250, width: 170, height: 120)).fill()
            second.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx + 160, y: cy + 305, width: 26, height: 26)).fill()
        case "kunai":
            // A three-pronged kunai: center blade, two side prongs, wrapped handle and ring.
            let blade = NSBezierPath()
            blade.move(to: NSPoint(x: cx, y: cy + 360))
            blade.line(to: NSPoint(x: cx + 70, y: cy + 60))
            blade.line(to: NSPoint(x: cx - 70, y: cy + 60))
            blade.close()
            blade.fill()
            for side: CGFloat in [-1, 1] {
                let prong = NSBezierPath()
                prong.move(to: NSPoint(x: cx + side * 230, y: cy + 230))
                prong.line(to: NSPoint(x: cx + side * 40, y: cy + 40))
                prong.line(to: NSPoint(x: cx + side * 90, y: cy + 10))
                prong.close()
                prong.fill()
            }
            second.setFill()
            NSBezierPath(roundedRect: NSRect(x: cx - 30, y: cy - 260, width: 60, height: 300), xRadius: 14, yRadius: 14).fill()
            let ring = NSBezierPath(ovalIn: NSRect(x: cx - 60, y: cy - 380, width: 120, height: 120))
            ring.lineWidth = 22
            second.setStroke()
            ring.stroke()
        case "paw":
            // A paw print: one big pad and four toes.
            NSBezierPath(ovalIn: NSRect(x: cx - 190, y: cy - 280, width: 380, height: 320)).fill()
            let toes: [(CGFloat, CGFloat)] = [(-260, 60), (-110, 200), (60, 200), (210, 60)]
            for (dx, dy) in toes {
                NSBezierPath(ovalIn: NSRect(x: cx + dx, y: cy + dy, width: 150, height: 190)).fill()
            }
        case "eye":
            // An almond-shaped eye with an iris and pupil.
            let eye = NSBezierPath()
            eye.move(to: NSPoint(x: cx - 380, y: cy))
            eye.curve(to: NSPoint(x: cx + 380, y: cy),
                      controlPoint1: NSPoint(x: cx - 160, y: cy + 300), controlPoint2: NSPoint(x: cx + 160, y: cy + 300))
            eye.curve(to: NSPoint(x: cx - 380, y: cy),
                      controlPoint1: NSPoint(x: cx + 160, y: cy - 300), controlPoint2: NSPoint(x: cx - 160, y: cy - 300))
            eye.fill()
            second.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - 150, y: cy - 150, width: 300, height: 300)).fill()
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - 60, y: cy - 60, width: 120, height: 120)).fill()
        default:
            NSBezierPath(ovalIn: NSRect(x: cx - 200, y: cy - 200, width: 400, height: 400)).fill()
        }
    }
}
