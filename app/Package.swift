// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacList",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MacListCore", targets: ["MacListCore"]),
        .executable(name: "MacList", targets: ["MacList"]),
        .executable(name: "DialogHarness", targets: ["DialogHarness"])
    ],
    targets: [
        .target(name: "MacListCore"),
        .executableTarget(
            name: "MacList",
            dependencies: ["MacListCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "DialogHarness",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "MacListCoreTests",
            dependencies: ["MacListCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
