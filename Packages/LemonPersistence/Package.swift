// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonPersistence",
    products: [
        .library(name: "LemonPersistence", targets: ["LemonPersistence"])
    ],
    targets: [
        .target(name: "LemonPersistence")
    ]
)
