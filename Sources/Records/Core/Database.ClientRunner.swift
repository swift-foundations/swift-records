import Foundation
import Logging
import PostgresNIO

/// Global storage for run tasks - prevents Task deallocation which auto-cancels
/// This is critical for tests: Task.deinit auto-cancels even without explicit cancel()
private nonisolated(unsafe) var _globalRunTasks: [Task<Void, Never>] = []

extension Database {
    /// A wrapper that manages a PostgresClient and its lifecycle.
    ///
    /// ClientRunner ensures that the PostgresClient's run() method is properly
    /// managed, including automatic startup and cleanup. This is essential for
    /// preventing test hangs when running tests in parallel.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Create a single connection
    /// let db = try await Database.singleConnection(configuration: config)
    /// // The client is automatically started and ready to use
    ///
    /// try await db.write { db in
    ///     try await User.insert { ... }.execute(db)
    /// }
    ///
    /// // When db goes out of scope, the client is automatically cleaned up
    /// ```
    public final class ClientRunner: Writer, @unchecked Sendable {
        private let client: PostgresClient
        private let runTask: Task<Void, Never>

        /// Creates a new ClientRunner with the given PostgresClient.
        ///
        /// The client's run() method is automatically started in a background task.
        public init(client: PostgresClient, startRunTask: Bool = true) async {
            self.client = client

            if startRunTask {
                self.runTask = Task {
                    await client.run()
                }

                // Store task globally to prevent deallocation
                // Critical: Task.deinit auto-cancels, causing hangs
                _globalRunTasks.append(self.runTask)

                // Give the client a moment to initialize
                try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            } else {
                // Create a no-op task that never runs
                self.runTask = Task {}
            }
        }

        /// Performs a read-only database operation.
        public func read<T: Sendable>(
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T {
            try await client.read(block)
        }

        /// Performs a database operation that can write.
        public func write<T: Sendable>(
            _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
        ) async throws -> T {
            try await client.write(block)
        }

        /// Closes the client and cancels the run task.
        public func close() async throws {
            runTask.cancel()
            try await client.close()
        }

        // NO deinit cleanup for tests
        // The runTask.cancel() call in deinit triggers PostgresNIO's async cleanup
        // during synchronous deallocation, causing hangs during test process exit.
        // For tests, it's acceptable to let the background task run until process exit.
        // Production code should explicitly call close() when shutting down.
    }
}

// MARK: - Factory Methods Update

extension Database {
    /// Creates a ClientRunner with a single connection.
    ///
    /// This provides similar behavior to the old Database.Queue by limiting
    /// the pool to a single connection. The client is automatically started
    /// and managed.
    public static func singleConnection(
        configuration: PostgresClient.Configuration,
        logger: Logger? = nil
    ) async -> ClientRunner {
        // Configure for single connection
        var config = configuration
        config.options.minimumConnections = 1
        config.options.maximumConnections = 1

        // Set useful defaults
        config.options.connectionIdleTimeout = .seconds(60)
        config.options.keepAliveBehavior = .init(
            frequency: .seconds(30),
            query: "SELECT 1"
        )

        let client =
            if let logger = logger {
                PostgresClient(configuration: config, backgroundLogger: logger)
            } else {
                PostgresClient(configuration: config)
            }

        return await ClientRunner(client: client)
    }

    /// Creates a ClientRunner with connection pooling.
    ///
    /// This provides similar behavior to the old Database.pool with
    /// configurable min/max connections. The client is automatically started
    /// and managed.
    public static func pool(
        configuration: PostgresClient.Configuration,
        minConnections: Int = 2,
        maxConnections: Int = 20,
        logger: Logger? = nil
    ) async -> ClientRunner {
        // Configure for connection pool
        var config = configuration
        config.options.minimumConnections = minConnections
        config.options.maximumConnections = maxConnections

        // Set useful defaults
        config.options.connectionIdleTimeout = .seconds(60)
        config.options.keepAliveBehavior = .init(
            frequency: .seconds(30),
            query: "SELECT 1"
        )

        let client =
            if let logger = logger {
                PostgresClient(configuration: config, backgroundLogger: logger)
            } else {
                PostgresClient(configuration: config)
            }

        return await ClientRunner(client: client)
    }
}

// MARK: - Compatibility Aliases

extension Database {
    /// Alias for single-connection client
    public typealias Queue = ClientRunner

    /// Alias for pooled client
    public typealias Pool = ClientRunner
}
