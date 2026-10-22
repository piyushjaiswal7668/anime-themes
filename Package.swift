// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AnimeThemes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AnimeThemes", path: "Sources/AnimeThemes")
    ]
)
