import Foundation

extension Database {
    /// Errors that can occur during database operations.
    public enum Error: Swift.Error, LocalizedError, Sendable {
        /// The database pool is shutting down and cannot accept new operations.
        case poolShuttingDown

        /// Connection to the database timed out.
        case connectionTimeout(TimeInterval)

        /// Maximum number of connections in the pool has been reached.
        case poolExhausted(maxConnections: Int)

        /// The database is not configured.
        case notConfigured

        /// A migration with the same identifier has already been registered.
        case duplicateMigration(identifier: String)

        /// A migration failed to apply.
        case migrationFailed(identifier: String, underlyingError: Swift.Error)

        /// The database schema needs to be erased but eraseDatabaseOnSchemaChange is false.
        case schemaChangeDetected(message: String)

        /// Transaction operation failed.
        case transactionFailed(underlyingError: Swift.Error)

        /// Invalid configuration provided.
        case invalidConfiguration(message: String)

        /// Invalid notification channel specification.
        case invalidNotificationChannels(String)

        /// Notification feature is not supported on this connection type.
        case notificationNotSupported(String)

        /// Invalid notification payload.
        case invalidNotificationPayload(String)

        /// Failed to decode notification payload.
        case notificationDecodingFailed(type: String, payload: String, underlying: Swift.Error)

        /// Notification payload exceeds PostgreSQL size limit.
        case notificationPayloadTooLarge(size: Int, limit: Int, hint: String)

        /// Failed to cleanup notification resources (UNLISTEN).
        case notificationCleanupFailed(channel: String, underlying: Swift.Error)

        public var errorDescription: String? {
            switch self {
            case .poolShuttingDown:
                return "Database pool is shutting down and cannot accept new operations"

            case .connectionTimeout(let timeout):
                return "Database connection timed out after \(timeout) seconds"

            case .poolExhausted(let maxConnections):
                return "Database connection pool exhausted (max connections: \(maxConnections))"

            case .notConfigured:
                return "Database has not been configured. Please configure the database before use."

            case .duplicateMigration(let identifier):
                return "Migration with identifier '\(identifier)' has already been registered"

            case .migrationFailed(let identifier, let error):
                return "Migration '\(identifier)' failed: \(error.localizedDescription)"

            case .schemaChangeDetected(let message):
                return
                    "Database schema change detected: \(message). Set eraseDatabaseOnSchemaChange to true to automatically handle this."

            case .transactionFailed(let error):
                return "Transaction failed: \(error.localizedDescription)"

            case .invalidConfiguration(let message):
                return "Invalid database configuration: \(message)"

            case .invalidNotificationChannels(let message):
                return "Invalid notification channels: \(message)"

            case .notificationNotSupported(let message):
                return "Notifications not supported: \(message)"

            case .invalidNotificationPayload(let message):
                return "Invalid notification payload: \(message)"

            case .notificationDecodingFailed(let type, let payload, let error):
                return
                    "Failed to decode notification payload as \(type). Payload: '\(payload)'. Error: \(error.localizedDescription)"

            case .notificationPayloadTooLarge(let size, let limit, let hint):
                return
                    "Notification payload size (\(size) bytes) exceeds PostgreSQL limit (\(limit) bytes). \(hint)"

            case .notificationCleanupFailed(let channel, let error):
                return
                    "Failed to cleanup notification channel '\(channel)': \(error.localizedDescription)"
            }
        }
    }
}
