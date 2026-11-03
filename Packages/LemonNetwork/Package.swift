// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonNetwork",
    products: [
        .library(name: "LemonNetwork", targets: ["LemonNetwork"])
    ],
    targets: [
        .target(name: "LemonNetwork")
    ]
)
