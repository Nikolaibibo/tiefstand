// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TiefstandCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TiefstandCore", targets: ["TiefstandCore"]),
    ],
    targets: [
        .target(name: "TiefstandCore"),
        .testTarget(name: "TiefstandCoreTests", dependencies: ["TiefstandCore"]),
    ]
)
