// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonGuangya",
    products: [
        .library(name: "LemonGuangya", targets: ["LemonGuangya"])
    ],
    dependencies: [
        .package(path: "../LemonCore"),
        .package(path: "../LemonNetwork")
    ],
    targets: [
        .target(name: "LemonGuangya", dependencies: ["LemonCore", "LemonNetwork"]),
        .testTarget(name: "LemonGuangyaTests", dependencies: ["LemonGuangya"])
    ]
)
