// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacListStandalone",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MacListCore", targets: ["MacListCore"]),
        .executable(name: "maclist", targets: ["maclist"])
    ],
    targets: [
        .target(name: "MacListCore"),
        .executableTarget(name: "maclist", dependencies: ["MacListCore"]),
        .testTarget(name: "MacListCoreTests", dependencies: ["MacListCore"])
    ]
)
