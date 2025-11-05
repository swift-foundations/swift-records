import Dependencies
import Foundation

// MARK: - Database.DependencyKey

extension Database {
    /// A dependency that provides the default database connection.
    ///
    /// Use this dependency to access the database in your application:
    ///
    /// ```swift
    /// @Dependency(\.defaultDatabase) var database
    ///
    /// func fetchUsers() async throws -> [User] {
    ///     try await database.read { db in
    ///         try User.fetchAll(db)
    ///     }
    /// }
    /// ```
    public struct DependencyKey: Dependencies.DependencyKey {
        public static let liveValue: any Writer = Unconfigured()
        public static let testValue: any Writer = Unconfigured()
    }
}

// MARK: - DependencyValues Extension

extension DependencyValues {
    /// The default database connection.
    ///
    /// Configure this dependency at app startup:
    ///
    /// ```swift
    /// try await withDependencies {
    ///     $0.defaultDatabase = try await Database.Queue()
    /// } operation: {
    ///     // Your app code
    /// }
    /// ```
    public var defaultDatabase: any Database.Writer {
        get { self[Database.DependencyKey.self] }
        set { self[Database.DependencyKey.self] = newValue }
    }
}

// MARK: - Database.Unconfigured

extension Database {
    /// A placeholder database that reports an error when used.
    fileprivate struct Unconfigured: Writer {
        func read<T: Sendable>(
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T {
            fatalError(
                """
                The defaultDatabase dependency has not been configured.

                Configure it at app startup:

                try await prepareDependencies {
                    $0.defaultDatabase = try await Database.Queue()
                }

                Or in tests:

                try await withDependencies {
                    $0.defaultDatabase = try await Database.Queue()
                } operation: {
                    // Test code
                }
                """
            )
        }

        func write<T: Sendable>(
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T {
            try await read(block)
        }

        func close() async throws {
            fatalError()
        }
    }
}
