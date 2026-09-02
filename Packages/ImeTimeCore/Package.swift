// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImeTimeCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ImeTimeCore", targets: ["ImeTimeCore"]),
    ],
    targets: [
        .target(name: "ImeTimeCore"),
        .testTarget(name: "ImeTimeCoreTests", dependencies: ["ImeTimeCore"]),
    ]
)
