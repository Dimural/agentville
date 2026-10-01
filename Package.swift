// swift-tools-version:6.0
// Agentville: one SwiftPM package, no .xcodeproj (docs/decisions/0004-swiftpm-no-xcodeproj.md).
import PackageDescription

let package = Package(
    name: "Agentville",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "agentville-hook", targets: ["agentville-hook"]),
        .executable(name: "agentville-replay", targets: ["agentville-replay"]),
        .executable(name: "Agentville", targets: ["Agentville"]),
        .library(name: "AgentvilleCore", targets: ["AgentvilleCore"]),
    ],
    targets: [
        // Pure, testable logic. No AppKit. See docs/architecture/overview.md#module-boundaries.
        .target(name: "AgentvilleCore"),

        // The hook Claude Code runs. Must stay tiny and fast (docs/architecture/hook.md).
        .executableTarget(name: "agentville-hook", dependencies: ["AgentvilleCore"]),

        // Dev tool: sends scripted WireEvents to the app's socket.
        .executableTarget(name: "agentville-replay", dependencies: ["AgentvilleCore"]),

        // The menu bar app.
        .executableTarget(
            name: "Agentville",
            dependencies: ["AgentvilleCore"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SpriteKit")]
        ),

        .testTarget(
            name: "AgentvilleCoreTests",
            dependencies: ["AgentvilleCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "HookIntegrationTests",
            dependencies: ["AgentvilleCore"]
        ),
    ]
)
