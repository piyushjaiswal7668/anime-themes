import Foundation

/// Sets the macOS accent color. macOS only offers its preset colors,
/// so each variant names the closest one in `macAccent`.
enum AccentModule {
    static let values: [String: Int] = [
        "graphite": -1, "red": 0, "orange": 1, "yellow": 2,
        "green": 3, "blue": 4, "purple": 5, "pink": 6
    ]

    static func apply(_ v: Variant) throws {
        guard let n = values[v.spec.macAccent.lowercased()] else {
            throw AppError("Unknown accent “\(v.spec.macAccent)”. Use one of: \(values.keys.sorted().joined(separator: ", ")).")
        }
        try Run.run("/usr/bin/defaults", ["write", "-g", "AppleAccentColor", "-int", String(n)])
        // Let the text highlight color follow the accent.
        _ = try? Run.run("/usr/bin/defaults", ["delete", "-g", "AppleHighlightColor"])

        let center = DistributedNotificationCenter.default()
        for name in ["AppleColorPreferencesChangedNotification", "AppleAquaColorVariantChanged"] {
            center.postNotificationName(.init(name), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }
}
