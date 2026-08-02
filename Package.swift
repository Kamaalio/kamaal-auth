// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "KamaalAuth",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "KamaalAuthCore", targets: ["KamaalAuthCore"]),
        .library(name: "KamaalAuthClient", targets: ["KamaalAuthClient"]),
        .library(name: "KamaalAuthUI", targets: ["KamaalAuthUI"]),
        .library(name: "KamaalAuthTestSupport", targets: ["KamaalAuthTestSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Kamaalio/KamaalSwift", .upToNextMajor(from: "3.5.0")),
        .package(url: "https://github.com/apple/swift-http-types", .upToNextMajor(from: "1.6.0")),
        .package(url: "https://github.com/apple/swift-openapi-runtime", .upToNextMajor(from: "1.12.0")),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", .upToNextMajor(from: "1.19.3")),
    ],
    targets: [
        .target(
            name: "KamaalAuthCore",
            dependencies: [
                .product(name: "KamaalUtils", package: "KamaalSwift"),
                .product(name: "KamaalExtensions", package: "KamaalSwift"),
            ],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "KamaalAuthClient",
            dependencies: [
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "KamaalLogger", package: "KamaalSwift"),
                .product(name: "KamaalExtensions", package: "KamaalSwift"),
                "KamaalAuthCore",
            ],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "KamaalAuthUI",
            dependencies: [
                .product(name: "KamaalUI", package: "KamaalSwift"),
                .product(name: "KamaalUtils", package: "KamaalSwift"),
                .product(name: "KamaalLogger", package: "KamaalSwift"),
                .product(name: "KamaalExtensions", package: "KamaalSwift"),
                "KamaalAuthCore",
                "KamaalAuthClient",
            ],
            resources: [.process("Resources")],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "KamaalAuthTestSupport",
            dependencies: [
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                "KamaalAuthCore",
                "KamaalAuthClient",
            ],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "KamaalAuthCoreTests",
            dependencies: ["KamaalAuthCore", "KamaalAuthTestSupport"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "KamaalAuthClientTests",
            dependencies: [
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                "KamaalAuthClient",
                "KamaalAuthTestSupport",
            ],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "KamaalAuthUITests",
            dependencies: [
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                "KamaalAuthUI",
                "KamaalAuthTestSupport",
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: swiftSettings,
        ),
    ]
)
