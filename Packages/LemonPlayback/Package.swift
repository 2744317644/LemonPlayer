// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonPlayback",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LemonPlayback", targets: ["LemonPlayback"])
    ],
    targets: [
        .target(name: "LemonPlayback")
    ]
)
