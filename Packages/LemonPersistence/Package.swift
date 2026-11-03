// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LemonPersistence",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LemonPersistence", targets: ["LemonPersistence"])
    ],
    dependencies: [
        .package(path: "../LemonSubtitle")
    ],
    targets: [
        .target(
            name: "LemonPersistence",
            dependencies: ["LemonSubtitle"],
            linkerSettings: [.linkedFramework("Security")]
        )
    ]
)
