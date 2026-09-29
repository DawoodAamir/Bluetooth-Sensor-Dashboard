// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SensorCore", platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "SensorCore", targets: ["SensorCore"])],
    targets: [
        .target(name: "SensorCore", path: "Sources/Core"),
        .testTarget(name: "SensorCoreTests", dependencies: ["SensorCore"], path: "Tests"),
    ])
