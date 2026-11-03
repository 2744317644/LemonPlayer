// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonDownloads",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LemonDownloads", targets: ["LemonDownloads"])
    ],
    targets: [
        .target(name: "LemonDownloads")
    ]
)
