// swift-tools-version: 6.3.3

import PackageDescription

let package = Package(
    name: "swift-records",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "Records",
            targets: ["Records"]
        ),
        .library(
            name: "Records SQL Integration",
            targets: ["Records SQL Integration"]
        ),
    ],
    dependencies: [
        // L2 — institute-native PostgreSQL-dialect DSL (re-exports L1 Structured
        // Queries Primitives). Replaces the pointfreeco swift-structured-queries-postgres fork.
        .package(
            url: "https://github.com/swift-standards/swift-postgresql-standard.git",
            revision: "b9d6f35a35089e397a7cfc025e75ca3de7ffc2d1"
        ),
        // L1 — identifier/string quoting helpers (FullTextSearch SQL emission).
        .package(
            url: "https://github.com/swift-primitives/swift-structured-queries-primitives.git",
            revision: "6bb7361a5d0edb60d49863ba2c4d49e1394edc7c"
        ),
        // L1 — `Byte`, the element type of `QueryBinding`'s blob/jsonb payloads and
        // of the `QueryDecoder` blob requirement since the L1 Foundation drain.
        .package(
            url: "https://github.com/swift-primitives/swift-byte-primitives.git",
            branch: "main"
        ),
        // L1 — `Instant`, the payload of `QueryBinding.date`/`.dateArray` and of the
        // `QueryDecoder` timestamp requirement since the same drain.
        .package(
            url: "https://github.com/swift-primitives/swift-time-primitives.git",
            branch: "main"
        ),
        // L1 — Tagged functor for type-safe SQL identifiers (ChannelName/FunctionName/
        // TriggerName). Replaces pointfreeco/swift-tagged.
        .package(
            url: "https://github.com/swift-primitives/swift-tagged-primitives.git",
            branch: "main"
        ),
        // Environment-variable idiom (EnvVars + \.envVars). Formerly ServerFoundationEnvVars (ssf dissolved, W3).
        .package(
            url: "https://github.com/swift-foundations/swift-environment-dependencies.git",
            branch: "main"
        ),
        // Provider-neutral SQL execution and its PostgreSQL Structured Queries bridge.
        .package(
            url: "https://github.com/swift-foundations/swift-sql.git",
            branch: "main",
            traits: ["PostgreSQLStandardIntegration"]
        ),
        // Wire execution (PostgresNIO confined to Core/PostgresNIO/ + the config entry points).
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(
            url: "https://github.com/swift-foundations/swift-dependencies.git",
            branch: "main"
        ),
    ],
    targets: [
        .target(
            name: "Records",
            dependencies: [
                .product(name: "PostgreSQL Standard", package: "swift-postgresql-standard"),
                .product(name: "PostgreSQL Standard Macros", package: "swift-postgresql-standard"),
                .product(
                    name: "Structured Queries Primitives Support",
                    package: "swift-structured-queries-primitives"
                ),
                // Wire execution is PostgresNIO's, whose column codecs are Foundation
                // types (`Date`, `UUID`, `Data`). The L1 core no longer speaks them,
                // so this opt-in integration supplies the bridges the PostgresNIO
                // boundary needs (`Date.instant`, `Date.init(_ instant:)`,
                // `QueryBinding.UUID.init(_ uuid:)`, `UUID.init?(_ identifier:)`).
                .product(
                    name: "Structured Queries Primitives Foundation Integration",
                    package: "swift-structured-queries-primitives"
                ),
                .product(name: "Byte Primitives", package: "swift-byte-primitives"),
                .product(name: "Time Primitives", package: "swift-time-primitives"),
                .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
                .product(
                    name: "Tagged Primitives Standard Library Integration",
                    package: "swift-tagged-primitives"
                ),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(
                    name: "Environment Dependencies",
                    package: "swift-environment-dependencies"
                ),
            ]
        ),
        // An additive membrane from Records' established public protocols to the engine-free SQL
        // execution surface. This target must remain provider-free: a provider conforms to SQL in
        // its own leaf, then an application elects to compose that provider with this adapter.
        .target(
            name: "Records SQL Integration",
            dependencies: [
                "Records",
                .product(name: "SQL", package: "swift-sql"),
                .product(name: "SQL PostgreSQL Standard Integration", package: "swift-sql"),
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
