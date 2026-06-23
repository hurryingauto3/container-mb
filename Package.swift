// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ContainerMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ContainerCore", targets: ["ContainerCore"]),
        .executable(name: "ContainerMenuBar", targets: ["ContainerMenuBar"]),
        .executable(name: "ContainerCoreSmokeTests", targets: ["ContainerCoreSmokeTests"]),
    ],
    targets: [
        .target(name: "ContainerCore"),
        .executableTarget(
            name: "ContainerMenuBar",
            dependencies: ["ContainerCore"]
        ),
        .executableTarget(
            name: "ContainerCoreSmokeTests",
            dependencies: ["ContainerCore"]
        ),
    ]
)
