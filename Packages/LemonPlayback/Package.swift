// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonPlayback",
    products: [
        .library(name: "LemonPlayback", targets: ["LemonPlayback"])
    ],
    targets: [
        .target(name: "LemonPlayback")
    ]
)
