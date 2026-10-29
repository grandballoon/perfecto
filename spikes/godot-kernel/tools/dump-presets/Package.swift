// swift-tools-version: 6.0
import PackageDescription

// Writes every preset, as the kernel takes it, to JSON for the Godot spike:
// the sounds stay defined once, in `PerfectoSound`.
let package = Package(
    name: "DumpPresets",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../../../Perfecto")],
    targets: [
        .executableTarget(
            name: "dump-presets",
            dependencies: [.product(name: "PerfectoSound", package: "Perfecto")],
            path: "Sources"
        ),
    ]
)
