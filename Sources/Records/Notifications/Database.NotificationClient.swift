import Foundation
import Logging
import PostgresNIO

extension Database {
    /// Dedicated PostgresClient for LISTEN/NOTIFY connections (optional optimization).
    ///
    /// **You typically don't need this client** - the notification API automatically
    /// uses your existing database connection pool. This dedicated client is an
    /// **optional optimization** for production systems with many concurrent listeners.
    ///
    /// ## When to Use
    ///
    /// Use the dedicated notification client when:
    /// - You have 10+ concurrent LISTEN connections
    /// - LISTEN connections are long-lived (minutes to hours)
    /// - You notice query performance degradation due to pool exhaustion
    ///
    /// For most applications (including all tests), the default behavior is sufficient.
    ///
    /// ## Configuration
    ///
    /// This client is specifically configured for long-lived notification subscriptions:
    ///
    /// - Long connection idle timeout (1 hour vs 60s default)
    /// - Keep-alive pings to maintain connection health
    /// - Bounded concurrency to prevent resource exhaustion
    /// - Separate from query connections to avoid interference
    ///
    /// ## Architecture Decision
    ///
    /// LISTEN connections have fundamentally different lifecycle characteristics than
    /// query connections:
    ///
    /// **Query Connections** (fast lease/release):
    /// ```
    /// Acquire → Execute Query (milliseconds) → Release
    /// ```
    ///
    /// **LISTEN Connections** (long-lived subscriptions):
    /// ```
    /// Acquire → LISTEN → Wait for notifications (seconds/minutes/hours) → UNLISTEN → Release
    /// ```
    ///
    /// Mixing these in the same pool causes:
    /// - LISTEN connections block query connections from being used
    /// - Query connection timeouts interrupt long-running listeners
    /// - Pool exhaustion when many listeners are active
    ///
    /// ## Configuration
    ///
    /// The notification client is configured with:
    /// - **Minimum Connections**: 2 (pre-warmed for common case)
    /// - **Maximum Connections**: 50 (allows many concurrent listeners)
    /// - **Idle Timeout**: 1 hour (long-lived subscriptions)
    /// - **Keep-Alive**: 5 minutes (detect dead connections)
    ///
    /// These can be overridden via environment variables:
    /// - `NOTIFICATION_MIN_CONNECTIONS`
    /// - `NOTIFICATION_MAX_CONNECTIONS`
    /// - `NOTIFICATION_IDLE_TIMEOUT_SECONDS`
    /// - `NOTIFICATION_KEEP_ALIVE_SECONDS`
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Notification client is automatically used by notifications API
    /// let stream = try await db.notifications(on: channel, expecting: MyType.self)
    ///
    /// // Monitor pool health
    /// let client = Database.notificationClient
    /// logger.info("Active listeners", metadata: [
    ///     "connections": "\(client.eventLoopGroup.description)"
    /// ])
    /// ```
    public final class NotificationClient: Sendable {
        /// Shared instance of the notification client
        ///
        /// This is lazily initialized on first use and configured from environment
        /// variables or sensible defaults.
        public static let shared: NotificationClient = {
            do {
                return try NotificationClient(
                    configuration: .notificationDefaults()
                )
            } catch {
                fatalError("Failed to initialize notification client: \(error)")
            }
        }()

        /// The underlying PostgresClient configured for notifications
        private let client: PostgresClient

        /// Logger for notification pool operations
        private let logger = Logger(label: "database.notifications.pool")

        /// Initialize a notification client with custom configuration
        ///
        /// - Parameter configuration: PostgresClient configuration optimized for notifications
        public init(configuration: PostgresClient.Configuration) throws {
            self.client = PostgresClient(
                configuration: configuration,
                backgroundLogger: Logger(label: "database.notifications.postgres")
            )
        }

        /// Run the notification client
        ///
        /// This must be called in a background task to start the client:
        ///
        /// ```swift
        /// Task {
        ///     await Database.NotificationClient.shared.run()
        /// }
        /// ```
        public func run() async {
            await client.run()
        }

        /// Execute a block with a connection from the notification pool
        ///
        /// - Parameter block: The block to execute with the connection
        /// - Returns: The result of the block
        /// - Throws: Connection errors or block errors
        func withConnection<T: Sendable>(
            _ block: @Sendable (PostgresConnection) async throws -> T
        ) async throws -> T {
            try await client.withConnection(block)
        }
    }
}

// MARK: - Configuration Extensions

extension PostgresClient.Configuration {
    /// Default configuration for notification clients
    ///
    /// Optimized for long-lived LISTEN connections with:
    /// - Extended idle timeout (1 hour)
    /// - Keep-alive pings (5 minutes)
    /// - Reasonable connection limits
    public static func notificationDefaults() throws -> PostgresClient.Configuration {
        var config = try PostgresClient.Configuration.fromEnvironment()

        // Notification-specific options
        config.options.minimumConnections =
            Int(
                ProcessInfo.processInfo.environment["NOTIFICATION_MIN_CONNECTIONS"] ?? "2"
            ) ?? 2

        config.options.maximumConnections =
            Int(
                ProcessInfo.processInfo.environment["NOTIFICATION_MAX_CONNECTIONS"] ?? "50"
            ) ?? 50

        // Long idle timeout for long-lived subscriptions (1 hour default)
        let idleTimeoutSeconds =
            Int(
                ProcessInfo.processInfo.environment["NOTIFICATION_IDLE_TIMEOUT_SECONDS"] ?? "3600"
            ) ?? 3600
        config.options.connectionIdleTimeout = .seconds(Int64(idleTimeoutSeconds))

        // Keep-alive to detect dead connections (5 minutes default)
        let keepAliveSeconds =
            Int(
                ProcessInfo.processInfo.environment["NOTIFICATION_KEEP_ALIVE_SECONDS"] ?? "300"
            ) ?? 300
        config.options.keepAliveBehavior = .init(
            frequency: .seconds(Int64(keepAliveSeconds))
        )

        return config
    }
}
