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
        .library(name: "PerfectoTheory", targets: ["PerfectoTheory"]),
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
        // The theory core again in portable C++, for the desk on engines and
        // platforms Swift does not reach (docs/desk-engine-and-audio.md). Its
        // own tests are built by CMake (CMakeLists.txt); here it is checked
        // against the Swift core, through a C probe that only the tests use.
        .target(
            name: "PerfectoTheory",
            path: "Sources/PerfectoTheory",
            // Each step rounded as Swift rounds it, never two fused into
            // one, so the C++ and the Swift agree to the last bit and every
            // compiler builds the same numbers (its README).
            cxxSettings: [.unsafeFlags(["-ffp-contract=off"])]
        ),
        .target(
            name: "PerfectoTheoryProbe",
            dependencies: ["PerfectoTheory"],
            path: "Tests/PerfectoTheoryProbe"
        ),
        .testTarget(
            name: "PerfectoTheoryParityTests",
            dependencies: ["MusicTheoryCore", "PerfectoTheoryProbe"],
            path: "Tests/PerfectoTheoryParityTests"
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
    cxxLanguageStandard: .cxx20
)
