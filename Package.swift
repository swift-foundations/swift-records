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
        // Environment-variable idiom (ServerFoundationEnvVars). Replaces coenttb/swift-environment-variables.
        .package(url: "https://github.com/swift-foundations/swift-server-foundation.git", branch: "main"),
        // Wire execution (PostgresNIO confined to Core/PostgresNIO/ + the config entry points).
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        // Clocks trait matches the transitive requirement (postgresql-standard →
        // swift-tests → swift-clocks enables it); declaring it here keeps the direct
        // edge trait-consistent so the trait-conditional `Clock Primitives` product
        // resolves.
        .package(url: "https://github.com/swift-foundations/swift-dependencies.git", branch: "main",
            traits: ["Clocks"]),
    ],
    targets: [
        .target(
            name: "Records",
            dependencies: [
                .product(name: "PostgreSQL Standard", package: "swift-postgresql-standard"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ServerFoundationEnvVars", package: "swift-server-foundation"),
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
