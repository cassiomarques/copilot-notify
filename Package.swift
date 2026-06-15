// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CopilotNotify",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CopilotNotifyLib",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CopilotNotify",
            dependencies: ["CopilotNotifyLib"],
            path: "Sources/CopilotNotifyApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CopilotNotifyTests",
            dependencies: ["CopilotNotifyLib"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
