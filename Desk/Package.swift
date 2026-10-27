// swift-tools-version: 6.0
import PackageDescription

// Perfecto at a desk: a Mac app played from a game controller, on the same
// theory core and sound library as the phone (docs/desk.md).
let package = Package(
    name: "PerfectoDesk",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../Perfecto")],
    targets: [
        // The layouts, as pure functions of the controller's frames.
        .target(
            name: "DeskCore",
            dependencies: [.product(name: "MusicTheoryCore", package: "Perfecto")]
        ),
        // The app: the controllers, the audio, MIDI and the screens.
        .executableTarget(
            name: "PerfectoDesk",
            dependencies: [
                "DeskCore",
                .product(name: "MusicTheoryCore", package: "Perfecto"),
                .product(name: "PerfectoSound", package: "Perfecto"),
            ]
        ),
        .testTarget(
            name: "DeskCoreTests",
            dependencies: ["DeskCore", .product(name: "MusicTheoryCore", package: "Perfecto")]
        ),
    ]
)
