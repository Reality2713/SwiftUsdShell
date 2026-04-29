// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftUsdShell",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "SwiftUsdShell",
            targets: ["SwiftUsdShell"]
        ),
        .library(
            name: "SwiftUsdShellOpenUSD",
            targets: ["SwiftUsdShellOpenUSD"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Reality2713/SwiftUsd.git", exact: "6.1.0-preflight.3"),
    ],
    targets: [
        .target(
            name: "SwiftUsdShell"
        ),
        .target(
            name: "SwiftUsdShellOpenUSD",
            dependencies: [
                "SwiftUsdShell",
                .product(name: "OpenUSD", package: "SwiftUsd"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .testTarget(
            name: "SwiftUsdShellTests",
            dependencies: ["SwiftUsdShell"]
        ),
    ],
    cxxLanguageStandard: .gnucxx17
)
