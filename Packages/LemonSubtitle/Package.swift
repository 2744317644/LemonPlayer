// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonSubtitle",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LemonSubtitle", targets: ["LemonSubtitle"])
    ],
    targets: [
        .target(name: "LemonSubtitle"),
        .testTarget(name: "LemonSubtitleTests", dependencies: ["LemonSubtitle"])
    ]
)
