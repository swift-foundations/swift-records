import Foundation
import Logging
import NIOSSL
import PostgresNIO

extension Database {
    /// PostgresClient adapter that conforms to Database.Writer protocol.
    ///
    /// This provides a bridge between PostgresNIO's PostgresClient and the
    /// Records library's Database.Writer protocol, allowing us to use
    /// PostgresClient's battle-tested connection pooling.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let config = PostgresClient.Configuration(
    ///     host: "localhost",
    ///     port: 5432,
    ///     username: "user",
    ///     password: "pass",
    ///     database: "mydb",
    ///     tls: .disable
    /// )
    ///
    /// let client = PostgresClient(configuration: config)
    ///
    /// // Run the client in a background task
    /// Task {
    ///     await client.run()
    /// }
    ///
    /// // Use as Database.Writer
    /// let users = try await client.read { db in
    ///     try await User.fetchAll(db)
    /// }
    /// ```
}

// MARK: - PostgresClient conformance to Database.Writer

extension PostgresClient: Database.Writer {
    /// Performs a read-only database operation.
    ///
    /// Although PostgresClient doesn't distinguish between reads and writes,
    /// we maintain the API for consistency and potential future optimizations.
    public func read<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await withConnection { postgresConnection in
            let connection = Database.Connection(postgresConnection)
            return try await block(connection)
        }
    }

    /// Performs a database operation that can write.
    ///
    /// Uses PostgresClient's connection pooling to get a connection
    /// for the duration of the block.
    public func write<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await withConnection { postgresConnection in
            let connection = Database.Connection(postgresConnection)
            return try await block(connection)
        }
    }

    /// Closes the client.
    ///
    /// Note: PostgresClient manages its lifecycle through the run() method.
    /// This method is provided for protocol conformance but typically
    /// you should cancel the task running run() instead.
    public func close() async throws {
        // PostgresClient doesn't have a direct close method
        // It's managed by cancelling the task running run()
        // This is here for protocol conformance
    }
}
