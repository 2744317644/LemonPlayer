// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonNetwork",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LemonNetwork", targets: ["LemonNetwork"])
    ],
    dependencies: [
        .package(path: "../LemonCore")
    ],
    targets: [
        .target(name: "LemonNetwork", dependencies: ["LemonCore"]),
        .testTarget(name: "LemonNetworkTests", dependencies: ["LemonNetwork"])
    ]
)
