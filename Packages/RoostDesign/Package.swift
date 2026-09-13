// swift-tools-version: 6.0
import PackageDescription

/// iOS 26 / macOS 26 floor. The version strings are deliberate: `.iOS(.v26)` needs a
/// swift-tools-version of 6.2, and the repo standardises on tools 6.0, so the floor is
/// spelled as a version string, which has been valid since tools 5.0.
///
/// One consequence worth knowing before adding code: the macOS floor is 26, so anything
/// that references a macOS 26-only SwiftUI symbol links strongly and `swift test` cannot
/// load the bundle on an older Mac (an `#available` check does not help — with a 26
/// deployment target the symbol is not weak-imported). iOS 26-only API therefore lives
/// behind `#if os(iOS)` with a material fallback for the macOS build. See RoostGlass.swift.
let package = Package(
    name: "RoostDesign",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "RoostDesign", targets: ["RoostDesign"]),
    ],
    targets: [
        .target(
            name: "RoostDesign",
            resources: [.copy("Resources/Fonts")]
        ),
        .testTarget(
            name: "RoostDesignTests",
            dependencies: ["RoostDesign"]
        ),
    ]
)
