// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ArxivDiscoveryApp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArxivDiscoveryCore", targets: ["ArxivDiscoveryCore"]),
        .executable(name: "ArxivDiscoveryApp", targets: ["ArxivDiscoveryApp"]),
        .executable(name: "ArxivDiscoveryCoreCheck", targets: ["ArxivDiscoveryCoreCheck"]),
    ],
    targets: [
        .target(name: "ArxivDiscoveryCore"),
        .executableTarget(name: "ArxivDiscoveryApp", dependencies: ["ArxivDiscoveryCore"]),
        .executableTarget(name: "ArxivDiscoveryCoreCheck", dependencies: ["ArxivDiscoveryCore"]),
    ]
)
