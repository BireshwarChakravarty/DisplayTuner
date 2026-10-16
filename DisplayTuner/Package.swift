// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DisplayTuner",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        // Research database, colour maths and the recommendation engine.
        // Foundation only, so it is fully unit-tested.
        .target(
            name: "TunerCore",
            path: "Sources/TunerCore"
        ),
        // The app: display detection, applying settings, SwiftUI.
        .executableTarget(
            name: "DisplayTuner",
            dependencies: ["TunerCore"],
            path: "Sources/DisplayTuner",
            linkerSettings: [
                // IOAVService* (Apple Silicon DDC) lives in IOKit but is not in the public headers.
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ColorSync"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "TunerCoreTests",
            dependencies: ["TunerCore"],
            path: "Tests/TunerCoreTests"
        )
    ]
)
