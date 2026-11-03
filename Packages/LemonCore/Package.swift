// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonCore",
    products: [
        .library(name: "LemonCore", targets: ["LemonCore"])
    ],
    targets: [
        .target(name: "LemonCore"),
        .testTarget(name: "LemonCoreTests", dependencies: ["LemonCore"])
    ]
)
