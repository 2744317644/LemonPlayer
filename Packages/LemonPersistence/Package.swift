// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonPersistence",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LemonPersistence", targets: ["LemonPersistence"])
    ],
    targets: [
        .target(
            name: "LemonPersistence",
            linkerSettings: [.linkedFramework("Security")]
        )
    ]
)
