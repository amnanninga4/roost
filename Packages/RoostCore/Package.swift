// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RoostCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RoostCore", targets: ["RoostCore"]),
    ],
    targets: [
        .target(name: "RoostCore"),
        .testTarget(name: "RoostCoreTests", dependencies: ["RoostCore"]),
    ]
)
