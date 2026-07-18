// swift-tools-version: 6.3.3

import PackageDescription

let package = Package(
    name: "swift-records",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "Records",
            targets: ["Records"]
        )
    ],
    dependencies: [
        // L2 — institute-native PostgreSQL-dialect DSL (re-exports L1 Structured
        // Queries Primitives). Replaces the pointfreeco swift-structured-queries-postgres fork.
        .package(url: "https://github.com/swift-standards/swift-postgresql-standard.git", branch: "main"),
        // L1 — identifier/string quoting helpers (FullTextSearch SQL emission).
        .package(url: "https://github.com/swift-primitives/swift-structured-queries-primitives.git", branch: "main"),
        // L1 — Tagged functor for type-safe SQL identifiers (ChannelName/FunctionName/
        // TriggerName). Replaces pointfreeco/swift-tagged.
        .package(url: "https://github.com/swift-primitives/swift-tagged-primitives.git", branch: "main"),
        // Environment-variable idiom (EnvVars + \.envVars). Formerly ServerFoundationEnvVars (ssf dissolved, W3).
        .package(url: "https://github.com/swift-foundations/swift-environment-dependencies.git", branch: "main"),
        // Wire execution (PostgresNIO confined to Core/PostgresNIO/ + the config entry points).
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/swift-foundations/swift-dependencies.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Records",
            dependencies: [
                .product(name: "PostgreSQL Standard", package: "swift-postgresql-standard"),
                .product(name: "PostgreSQL Standard Macros", package: "swift-postgresql-standard"),
                .product(name: "Structured Queries Primitives Support", package: "swift-structured-queries-primitives"),
                .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
                .product(name: "Tagged Primitives Standard Library Integration", package: "swift-tagged-primitives"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Environment Dependencies", package: "swift-environment-dependencies"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility")
]

for index in package.targets.indices {
    package.targets[index].swiftSettings = swiftSettings
}
