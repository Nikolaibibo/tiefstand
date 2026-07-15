// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TiefstandCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TiefstandCore", targets: ["TiefstandCore"]),
        .executable(name: "Tiefstand", targets: ["Tiefstand"]),
    ],
    targets: [
        .target(name: "TiefstandCore"),
        .executableTarget(name: "Tiefstand", dependencies: ["TiefstandCore"]),
        .testTarget(name: "TiefstandCoreTests", dependencies: ["TiefstandCore"]),
    ]
)
