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
    ],
    targets: [
        .target(
            name: "SwiftUsdShell"
        ),
        .testTarget(
            name: "SwiftUsdShellTests",
            dependencies: ["SwiftUsdShell"]
        ),
    ]
)
