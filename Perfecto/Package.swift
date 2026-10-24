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
        // The audio kernel: portable C++ behind a C interface. Its tests are
        // built to stop on any allocation made while rendering.
        .target(
            name: "PerfectoKernel",
            path: "Sources/PerfectoKernel",
            cxxSettings: [.define("PERFECTO_TRAP_ALLOCATIONS")]
        ),
        .testTarget(
            name: "PerfectoKernelTests",
            dependencies: ["PerfectoKernel"],
            path: "Tests/PerfectoKernelTests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
