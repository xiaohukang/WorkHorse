// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WorkHorse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WorkHorse", targets: ["WorkHorse"])
    ],
    targets: [
        .executableTarget(
            name: "WorkHorse",
            path: "Sources/WorkHorse"
        )
    ],
    swiftLanguageVersions: [.v5]
)
