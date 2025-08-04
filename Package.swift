// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TranscriptionIndicator",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "TranscriptionIndicator", targets: ["TranscriptionIndicator"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "TranscriptionIndicator",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Collections", package: "swift-collections")
            ],
            path: "Sources",
            sources: [
                "TranscriptionIndicator/main.swift",
                "TranscriptionIndicator/App.swift",
                "Communication/SimpleCommandProcessor.swift",
                "Communication/SimpleStdinHandler.swift",
                "Core/Errors.swift",
                "Core/Models.swift",
                "Core/Protocols.swift",
                "Core/SingleInstanceManager.swift"
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ForwardTrailingClosures"),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TranscriptionIndicatorTests",
            dependencies: ["TranscriptionIndicator"],
            path: "Tests"
        )
    ]
)