// swift-tools-version: 6.3.3

import PackageDescription

let package = Package(
    name: "testing",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: ".."),
        .package(path: "../../swift-tests"),
        .package(path: "../../swift-dependencies", traits: ["Clocks"]),
        .package(path: "../../swift-server-foundation"),
        .package(path: "../../../swift-standards/swift-postgresql-standard"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    targets: [
        .target(
            name: "Records Test Support",
            dependencies: [
                .product(name: "Records", package: "swift-records"),
                .product(name: "PostgreSQL Standard", package: "swift-postgresql-standard"),
                .product(name: "PostgreSQL Standard Test Support", package: "swift-postgresql-standard"),
                .product(name: "Tests Inline Snapshot", package: "swift-tests"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Dependencies Test Support", package: "swift-dependencies"),
                .product(name: "ServerFoundationEnvVars", package: "swift-server-foundation"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ],
            path: "Records Test Support"
        ),
        .testTarget(
            name: "Records Tests",
            dependencies: [
                "Records Test Support",
                .product(name: "Records", package: "swift-records"),
                .product(name: "PostgreSQL Standard", package: "swift-postgresql-standard"),
                .product(name: "Tests Inline Snapshot", package: "swift-tests"),
                .product(name: "Tests Apple Testing Bridge", package: "swift-tests"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Dependencies Test Support", package: "swift-dependencies"),
                .product(name: "ServerFoundationEnvVars", package: "swift-server-foundation"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ],
            path: "Records Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

// Matches the PARENT's language posture (MemberImportVisibility only): the test
// support conforms to Records' Reader/Writer protocols, and enabling
// NonisolatedNonsendingByDefault here while the parent compiles without it makes
// every async witness non-matching (`@concurrent` vs `nonisolated(nonsending)`).
for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .enableUpcomingFeature("MemberImportVisibility")
    ]

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem
}
