// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RoostDesign",
    platforms: [.iOS(.v18), .macOS(.v15)],
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
