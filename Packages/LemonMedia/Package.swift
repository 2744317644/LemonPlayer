// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonMedia",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LemonMedia", targets: ["LemonMedia"])
    ],
    targets: [
        .target(name: "LemonMedia"),
        .testTarget(name: "LemonMediaTests", dependencies: ["LemonMedia"])
    ]
)
