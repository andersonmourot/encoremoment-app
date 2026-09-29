// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EncoreMomentCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "EncoreMomentCore",
            targets: ["EncoreMomentCore"]
        )
    ],
    targets: [
        .target(
            name: "EncoreMomentCore"
        ),
        .testTarget(
            name: "EncoreMomentCoreTests",
            dependencies: ["EncoreMomentCore"]
        )
    ]
)
