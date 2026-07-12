import Foundation
import PostgresNIO

/// A protocol for database types that can provide PostgreSQL LISTEN/NOTIFY functionality.
///
/// This protocol allows test databases and wrappers to expose their underlying PostgresClient
/// for notification support without creating circular dependencies between modules.
///
/// ## Implementation
///
/// Types that wrap a PostgresClient should implement this protocol to enable notification support:
///
/// ```swift
/// final class TestDatabase: Database.Writer, NotificationCapable {
///     private let client: PostgresClient
///
///     var postgresClient: PostgresClient? {
///         client
///     }
/// }
/// ```
///
/// The notification system will automatically detect and use this capability.
public protocol NotificationCapable {
    /// The underlying PostgresClient, if available.
    ///
    /// Return `nil` if this database type doesn't support PostgreSQL notifications.
    /// This is an async property to support lazy initialization of test databases.
    var postgresClient: PostgresClient? { get async throws }
}
