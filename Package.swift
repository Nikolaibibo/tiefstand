// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TiefstandCore",
    // Desktop-placed widgets require macOS 14 (Sonoma); the whole package tracks
    // that so the app and widget share one deployment floor.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TiefstandCore", targets: ["TiefstandCore"]),
        .library(name: "TiefstandUI", targets: ["TiefstandUI"]),
        .executable(name: "Tiefstand", targets: ["Tiefstand"]),
        .executable(name: "TiefstandWidget", targets: ["TiefstandWidget"]),
    ],
    targets: [
        .target(name: "TiefstandCore"),
        .target(name: "TiefstandUI", dependencies: ["TiefstandCore"]),
        .executableTarget(name: "Tiefstand", dependencies: ["TiefstandCore", "TiefstandUI"]),
        .executableTarget(name: "TiefstandWidget", dependencies: ["TiefstandCore", "TiefstandUI"]),
        .testTarget(name: "TiefstandCoreTests", dependencies: ["TiefstandCore"]),
    ]
)
