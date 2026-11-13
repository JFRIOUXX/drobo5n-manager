// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DroboMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Épinglé sur la série 0.11.x : la 0.12+ exige macOS 14, or la cible ici est macOS 13+.
        .package(url: "https://github.com/orlandos-nl/Citadel.git", "0.11.0" ..< "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "DroboMenuBar",
            dependencies: [
                .product(name: "Citadel", package: "Citadel")
            ]
        )
    ]
)
