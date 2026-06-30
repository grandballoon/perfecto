// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Perfecto",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    targets: [
        .target(
            name: "MusicTheoryCore",
            path: "Sources/MusicTheoryCore"
        ),
        .testTarget(
            name: "MusicTheoryCoreTests",
            dependencies: ["MusicTheoryCore"],
            path: "Tests/MusicTheoryCoreTests"
        ),
    ]
)
