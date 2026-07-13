import Foundation
import Logging
import NIOCore
import NIOPosix
import PostgresNIO
import Records

/// Global EventLoopGroup for all test clients
/// Following PostgresNIO's pattern: one shared EventLoopGroup, shutdown in teardown
private let testEventLoopGroup = MultiThreadedEventLoopGroup.singleton

/// Shared PostgresClient for ALL test suites
/// This prevents "too many connections" by using a single connection pool
private actor SharedTestClient {
    private var client: PostgresClient?
    private var runTask: Task<Void, Never>?

    func getOrCreateClient(configuration: PostgresClient.Configuration) async -> PostgresClient {
        if let existing = client {
            return existing
        }

        // Create shared client with connection pooling
        let newClient = PostgresClient(
            configuration: configuration,
            eventLoopGroup: testEventLoopGroup,
            backgroundLogger: Logger(label: "test-db")
        )
        self.client = newClient

        // Start client.run() once for the shared client
        let task = Task {
            await newClient.run()
        }
        self.runTask = task

        // Register shutdown handler on first client creation
        if !shutdownHandlerRegistered {
            shutdownHandlerRegistered = true
            atexit {
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    await sharedTestClient.shutdown()
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + .seconds(5))
            }
        }

        // Give client time to initialize
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        return newClient
    }

    func shutdown() async {
        // Cancel run task
        runTask?.cancel()

        // Wait for cancellation
        if let task = runTask {
            await task.value
        }

        // Shutdown EventLoopGroup
        try? await testEventLoopGroup.shutdownGracefully()

        client = nil
        runTask = nil
    }
}

private let sharedTestClient = SharedTestClient()

/// Register shutdown handler on first use
private nonisolated(unsafe) var shutdownHandlerRegistered = false

/// Test database connection using shared PostgresClient
///
/// All test suites share a SINGLE PostgresClient with connection pooling.
/// This prevents "too many connections" errors while maintaining schema isolation
/// per test suite via PostgreSQL schemas.
final class TestConnection: Database.Writer, @unchecked Sendable {
    private let client: PostgresClient
    // `Database.Connection`'s wrapping init is package-scoped inside Records (wire
    // types deliberately confined), so this nested-package support delegates the
    // connection wrapping to the public `Database.ClientRunner` Writer. The shared
    // client's `run()` is owned by SharedTestClient; the runner must not start its own.
    private let runner: Database.ClientRunner

    /// Exposes the underlying PostgresClient for notification support
    package var postgresClient: PostgresClient {
        client
    }

    init(configuration: PostgresClient.Configuration) async {
        // Get or create the shared PostgresClient
        let client = await sharedTestClient.getOrCreateClient(configuration: configuration)
        self.client = client
        self.runner = await Database.ClientRunner(client: client, startRunTask: false)
    }

    func read<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await runner.read(block)
    }

    func write<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await runner.write(block)
    }

    func close() async throws {
        // Shutdown handled by global manager
    }
}
