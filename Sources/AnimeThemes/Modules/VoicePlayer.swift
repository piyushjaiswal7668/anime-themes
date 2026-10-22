import AVFoundation

/// Plays voice clips from voice/<language>/<event>/ in the active variant.
/// Events: switch, random, build-pass, build-fail, login.
@MainActor
final class VoicePlayer {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "aiff", "aif", "caf"]

    private var player: AVAudioPlayer?
    private let speech = AVSpeechSynthesizer()

    /// The clip that would play, trying languages in order (so an empty Hindi folder falls back).
    static func clip(for event: String, in v: Variant, languages: [String]) -> URL? {
        for lang in languages {
            if let url = v.files(in: "voice/\(lang)/\(event)", extensions: audioExtensions).randomElement() {
                return url
            }
        }
        // Nothing for this moment: use any clip the character has, still in language order,
        // so a theme whose clips all landed in e.g. build-pass still talks on switch.
        let events = ["random", "switch", "build-pass", "login", "build-fail"]
        for lang in languages {
            let all = events.flatMap { v.files(in: "voice/\(lang)/\($0)", extensions: audioExtensions) }
            if let url = all.randomElement() { return url }
        }
        return nil
    }

    /// Plays a clip. If there is none and `speakFallback` is given, reads that text aloud instead.
    @discardableResult
    func play(event: String, variant v: Variant, settings s: Settings, speakFallback: String? = nil) -> Bool {
        guard s.voice else { return false }
        if let url = Self.clip(for: event, in: v, languages: s.languageOrder) {
            player?.stop()
            player = try? AVAudioPlayer(contentsOf: url)
            player?.volume = Float(s.volume)
            player?.play()
            return player != nil
        }
        if s.speakWhenNoClips, let text = speakFallback {
            speech.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: text)
            utterance.volume = Float(s.volume)
            speech.speak(utterance)
            return true
        }
        return false
    }

    /// Counts clips per language so the menu can show what's available.
    static func summary(for v: Variant) -> String {
        let events = ["switch", "random", "build-pass", "build-fail", "login"]
        let parts = ["ja", "en", "hi"].map { lang -> String in
            let n = events.reduce(0) { $0 + v.files(in: "voice/\(lang)/\($1)", extensions: audioExtensions).count }
            return "\(lang) \(n)"
        }
        return "Clips: " + parts.joined(separator: " · ")
    }
}
