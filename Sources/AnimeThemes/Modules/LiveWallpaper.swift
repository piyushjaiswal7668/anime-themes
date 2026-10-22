import AppKit
import AVFoundation

/// Plays a looping, muted video behind the desktop icons on every screen.
@MainActor
final class LiveWallpaper {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    private var windows: [NSWindow] = []
    private var players: [AVQueuePlayer] = []
    private var loopers: [AVPlayerLooper] = []
    private(set) var currentURL: URL?
    private var paused = false

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.players.forEach { $0.pause() } }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeIfAllowed() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let url = self.currentURL else { return }
                self.play(url, paused: self.paused)
            }
        }
    }

    var isShowing: Bool { !windows.isEmpty }

    /// A random video from the variant's live folder, or nil if there are none.
    static func pick(for v: Variant) -> URL? {
        v.files(in: "live", extensions: videoExtensions).randomElement()
    }

    func play(_ url: URL, paused: Bool) {
        stop()
        currentURL = url
        self.paused = paused
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)

        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = level
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.setFrame(screen.frame, display: false)

            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))

            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(layer)
            window.contentView = view
            window.orderFront(nil)

            if !paused { player.play() }
            windows.append(window)
            players.append(player)
            loopers.append(looper)
        }
    }

    func setPaused(_ on: Bool) {
        paused = on
        if on { players.forEach { $0.pause() } } else { players.forEach { $0.play() } }
    }

    private func resumeIfAllowed() {
        if !paused { players.forEach { $0.play() } }
    }

    func stop() {
        players.forEach { $0.pause() }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        players.removeAll()
        loopers.removeAll()
        currentURL = nil
    }
}
