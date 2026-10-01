// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mochi",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MochiCore", targets: ["MochiCore"]),
        .executable(name: "MochiApp", targets: ["MochiApp"]),
        .executable(name: "mochi", targets: ["mochi"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "MochiCore",
            dependencies: []
        ),
        .executableTarget(
            name: "MochiApp",
            dependencies: ["MochiCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "mochi",
            dependencies: [
                "MochiCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "MochiCoreTests",
            dependencies: ["MochiCore"]
        )
    ]
)
