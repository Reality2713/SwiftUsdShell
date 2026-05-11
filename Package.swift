// swift-tools-version: 6.2

import PackageDescription
import Foundation

struct AppleTextureConverterToolchain {
    let includePath: String
    let libraryPath: String
}

func discoverAppleTextureConverterToolchain() -> AppleTextureConverterToolchain? {
    let fileManager = FileManager.default
    var developerRoots: [String] = []

    if let envDeveloperDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !envDeveloperDir.isEmpty {
        developerRoots.append(envDeveloperDir)
    }
    developerRoots.append("/Applications/Xcode.app/Contents/Developer")

    if let apps = try? fileManager.contentsOfDirectory(atPath: "/Applications") {
        for app in apps where app.hasPrefix("Xcode") && app.hasSuffix(".app") {
            developerRoots.append("/Applications/\(app)/Contents/Developer")
        }
    }

    var seen = Set<String>()
    for root in developerRoots {
        let normalized = NSString(string: root).standardizingPath
        if !seen.insert(normalized).inserted { continue }
        let includePath = "\(normalized)/usr/include"
        let libraryPath = "\(normalized)/usr/lib"
        let headerPath = "\(includePath)/AppleTextureConverter.h"
        let archivePath = "\(libraryPath)/libAppleTextureConverter.a"
        if fileManager.fileExists(atPath: headerPath), fileManager.fileExists(atPath: archivePath) {
            return AppleTextureConverterToolchain(includePath: includePath, libraryPath: libraryPath)
        }
    }
    return nil
}

let atcToolchain = discoverAppleTextureConverterToolchain()
let atcCSettings: [CSetting] = {
    guard let atcToolchain else { return [] }
    return [
        .define("ATC_BRIDGE_ENABLED", .when(platforms: [.macOS])),
        .unsafeFlags(["-I\(atcToolchain.includePath)"], .when(platforms: [.macOS]))
    ]
}()

let atcLinkerSettings: [LinkerSetting] = {
    guard let atcToolchain else { return [] }
    return [
        .unsafeFlags(
            [
                "-L\(atcToolchain.libraryPath)",
                "-lAppleTextureConverter",
                "-framework", "CoreFoundation",
                "-framework", "Foundation",
                "-framework", "AppKit",
                "-framework", "Metal",
                "-framework", "ImageIO",
                "-framework", "Accelerate"
            ],
            .when(platforms: [.macOS])
        )
    ]
}()

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
        .library(
            name: "SwiftUsdShellAppleTools",
            targets: ["SwiftUsdShellAppleTools"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Reality2713/SwiftUsd.git", exact: "6.1.0-preflight.6"),
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
        .target(
            name: "CAppleTextureConverterBridgeShell",
            dependencies: [],
            path: "Sources/CAppleTextureConverterBridgeShell",
            publicHeadersPath: "include",
            cSettings: atcCSettings,
            linkerSettings: atcLinkerSettings
        ),
        .target(
            name: "SwiftUsdShellAppleTools",
            dependencies: [
                "SwiftUsdShell",
                .target(name: "CAppleTextureConverterBridgeShell", condition: .when(platforms: [.macOS])),
            ],
            path: "Sources/SwiftUsdShellAppleTools"
        ),
        .testTarget(
            name: "SwiftUsdShellTests",
            dependencies: ["SwiftUsdShell"]
        ),
    ],
    cxxLanguageStandard: .gnucxx17
)
