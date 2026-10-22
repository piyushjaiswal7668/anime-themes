import AppKit

/// One desktop widget: a themed card in its own borderless window, above the desktop icons
/// and below your app windows. Subclasses build the card's inside and update it on `tick`.
@MainActor
class DesktopWidget: NSObject {
    enum Column { case right, left }

    let kind: String
    let column: Column
    let window: NSWindow
    var variant: Variant?
    /// Set once the window has a position on screen.
    var placed = false
    private(set) var isVisible = false
    private var editing = false
    /// Called when the widget's height changes or it was dragged, so the others can make room.
    var onLayoutChange: (() -> Void)?

    /// Card width. Subclasses can override.
    var width: CGFloat { 300 }
    /// Widgets with buttons take clicks even outside edit mode.
    var acceptsClicks: Bool { false }

    init(kind: String, column: Column) {
        self.kind = kind
        self.column = column
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                          styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        updateMouseHandling()
    }

    /// The inside of the card for this variant, or nil to hide the widget.
    func makeContent(_ v: Variant) -> NSView? { nil }

    /// Called every 2 seconds while visible. `count` increases by one each time.
    func tick(_ count: Int) {}

    // MARK: Showing

    func render() {
        guard let v = variant, let content = makeContent(v) else { hide(); return }
        let card = Card.make(content, colors: v.spec.colors, width: width, editing: editing)
        card.layoutSubtreeIfNeeded()
        let size = NSSize(width: width, height: max(40, card.fittingSize.height))
        let top = window.frame.maxY
        let heightChanged = isVisible && abs(window.frame.height - size.height) > 0.5

        window.setContentSize(size)
        card.frame = NSRect(origin: .zero, size: size)
        if editing {
            let overlay = DragOverlay(frame: card.bounds)
            overlay.autoresizingMask = [.width, .height]
            overlay.onDragEnd = { [weak self] in
                self?.savePosition()
                self?.onLayoutChange?()
            }
            card.addSubview(overlay)
        }
        window.contentView = card
        if placed { window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - size.height)) }
        window.orderFront(nil)
        isVisible = true
        if heightChanged { onLayoutChange?() }
    }

    func hide() {
        window.orderOut(nil)
        isVisible = false
    }

    func setEditing(_ on: Bool) {
        editing = on
        updateMouseHandling()
        if isVisible { render() }
    }

    private func updateMouseHandling() {
        window.ignoresMouseEvents = !(editing || acceptsClicks)
    }

    // MARK: Position

    private var positionKey: String { "widget.\(kind).origin" }

    var savedOrigin: NSPoint? {
        guard let a = UserDefaults.standard.array(forKey: positionKey) as? [Double], a.count == 2 else { return nil }
        let p = NSPoint(x: a[0], y: a[1])
        return NSScreen.screens.contains { $0.frame.insetBy(dx: -20, dy: -20).contains(p) } ? p : nil
    }

    func savePosition() {
        let o = window.frame.origin
        UserDefaults.standard.set([Double(o.x), Double(o.y)], forKey: positionKey)
    }

    func forgetPosition() {
        UserDefaults.standard.removeObject(forKey: positionKey)
        placed = false
    }
}

/// Covers a widget in edit mode so it can be dragged anywhere.
final class DragOverlay: NSView {
    var onDragEnd: (() -> Void)?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + p.x - startMouse.x, y: startOrigin.y + p.y - startMouse.y))
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.openHand.set()
        onDragEnd?()
    }
}

/// A button that works on the first click, even though the app is in the background.
final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A thin rounded progress bar.
final class BarView: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var trackColor = NSColor.darkGray
    var fillColor = NSColor.orange

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 8) }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        trackColor.setFill()
        NSBezierPath(roundedRect: b, xRadius: b.height / 2, yRadius: b.height / 2).fill()
        var f = b
        f.size.width = max(b.height, b.width * min(max(fraction, 0), 1))
        fillColor.setFill()
        NSBezierPath(roundedRect: f, xRadius: b.height / 2, yRadius: b.height / 2).fill()
    }
}

/// Shared styling for widget cards.
@MainActor
enum Card {
    static func make(_ content: NSView, colors c: Palette, width: CGFloat, editing: Bool) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = RGB.of(c.surface).nsColor.withAlphaComponent(0.9).cgColor
        card.layer?.cornerRadius = 14
        card.layer?.borderWidth = editing ? 2 : 1
        card.layer?.borderColor = RGB.of(c.accent).nsColor.withAlphaComponent(editing ? 1 : 0.5).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: width),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        return card
    }

    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor, mono: Bool = false, wraps: Bool = false) -> NSTextField {
        let l = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        if mono, let f = Fonts.codeFont(size: size) {
            l.font = weight == .bold || weight == .semibold
                ? NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) : f
        } else {
            l.font = .systemFont(ofSize: size, weight: weight)
        }
        l.textColor = color
        l.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    /// Small spaced-out capitals, used as each widget's title.
    static func heading(_ text: String, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: color,
            .kern: 1.6,
        ])
        return l
    }

    static func vstack(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = spacing
        return s
    }

    static func hstack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.alignment = .centerY
        s.spacing = spacing
        return s
    }

    static func colors(_ c: Palette) -> (fg: NSColor, muted: NSColor, accent: NSColor, accent2: NSColor, green: NSColor, red: NSColor) {
        let a = c.ansi16
        return (RGB.of(c.fg).nsColor, RGB.of(c.muted).nsColor, RGB.of(c.accent).nsColor,
                RGB.of(c.accent2).nsColor, RGB.of(a[10]).nsColor, RGB.of(a[9]).nsColor)
    }
}
