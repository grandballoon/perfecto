// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Perfecto",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    // What another app is built from: the phone's app compiles these same
    // files itself, and the desk (`Desk/`) takes them as libraries.
    products: [
        .library(name: "MusicTheoryCore", targets: ["MusicTheoryCore"]),
        .library(name: "PerfectoSound", targets: ["PerfectoSound"]),
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
        // The audio kernel: portable C++ behind a C interface. Its tests are
        // built to stop on any allocation made while rendering, as is any
        // debug build of an app made from it.
        .target(
            name: "PerfectoKernel",
            path: "Sources/PerfectoKernel",
            cxxSettings: [.define("PERFECTO_TRAP_ALLOCATIONS", .when(configuration: .debug))]
        ),
        .testTarget(
            name: "PerfectoKernelTests",
            dependencies: ["PerfectoKernel"],
            path: "Tests/PerfectoKernelTests"
        ),
        // The kernel as an Audio Unit's renderer. Objective-C++, so nothing
        // on the render thread passes through Swift.
        .target(
            name: "PerfectoKernelHost",
            dependencies: ["PerfectoKernel"],
            path: "Sources/PerfectoKernelHost"
        ),
        // The sound library: the presets, the patches they are made of, and
        // the kernel as an Audio Unit that plays them.
        .target(
            name: "PerfectoSound",
            dependencies: ["PerfectoKernel", "PerfectoKernelHost"],
            path: "Sources/PerfectoSound"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
