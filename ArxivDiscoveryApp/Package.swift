// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ArxivDiscovery",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArxivDiscoveryCore", targets: ["ArxivDiscoveryCore"]),
        .executable(name: "ArxivDiscoveryApp", targets: ["ArxivDiscoveryApp"]),
        .executable(name: "ArxivDiscoveryIntegration", targets: ["ArxivDiscoveryIntegration"]),
        .executable(name: "ArxivDiscoveryCoreChecks", targets: ["ArxivDiscoveryCoreChecks"])
    ],
    targets: [
        .target(
            name: "ArxivDiscoveryCore",
            path: "Sources/ArxivDiscoveryCore"
        ),
        .executableTarget(
            name: "ArxivDiscoveryApp",
            dependencies: ["ArxivDiscoveryCore"],
            path: "Sources/ArxivDiscoveryApp"
        ),
        .executableTarget(
            name: "ArxivDiscoveryIntegration",
            dependencies: ["ArxivDiscoveryCore"],
            path: "Sources/ArxivDiscoveryIntegration"
        ),
        .executableTarget(
            name: "ArxivDiscoveryCoreChecks",
            dependencies: ["ArxivDiscoveryCore"],
            path: "Sources/ArxivDiscoveryCoreChecks"
        )
    ]
)
