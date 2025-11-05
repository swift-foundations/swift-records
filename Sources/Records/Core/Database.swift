import Foundation

/// The main namespace for database-related types and functionality.
///
/// `Database` serves as a namespace for all database-related types in the Records library.
/// It provides types for connection management, configuration, and database operations.
///
/// ## Topics
///
/// ### Connection Types
/// - ``Queue``: Serial database access with a single connection
/// - ``Pool``: Concurrent database access with connection pooling
///
/// ### Protocols
/// - ``Reader``: Read-only database access
/// - ``Writer``: Read-write database access
///
/// ### Configuration
/// - ``Configuration``: Database connection configuration
/// - ``Error``: Database-specific errors
///
/// ## Setup
///
/// Configure the database dependency at your app's entry point:
///
/// ```swift
/// import Dependencies
/// import Records
///
/// @main
/// struct MyApp {
///     static func main() async throws {
///         // Configure database at startup
///         let database = try await Database.Pool(
///                 configuration: .fromEnvironment(),
///                 minConnections: 5,
///                 maxConnections: 20
///             )
///         try await prepareDependencies {
///             $0.defaultDatabase = database
///         }
///
///         // Run your app
///     }
/// }
/// ```
///
/// ## Usage
///
/// Once configured, access the database via dependency injection:
///
/// ```swift
/// import Dependencies
/// import Records
///
/// struct UserService {
///     @Dependency(\.defaultDatabase) var db
///
///     func fetchUsers() async throws -> [User] {
///         try await db.read { db in
///             try await User.fetchAll(db)
///         }
///     }
///
///     func createUser(name: String, email: String) async throws {
///         try await db.write { db in
///             try await User.insert {
///                 ($0.name, $0.email, $0.createdAt)
///             } values: {
///                 (name, email, Date())
///             }.execute(db)
///         }
///     }
/// }
/// ```
///
/// ## Choosing Between Queue and Pool
///
/// ### Use Queue when:
/// - Developing or testing locally
/// - Building simple applications with low concurrency
/// - Working with SQLite or embedded databases
/// - You want predictable, serial execution
///
/// ### Use Pool when:
/// - Building production applications
/// - Handling multiple concurrent requests
/// - Need to scale read operations
/// - Working with remote database servers
///
/// ```swift
/// // Development/Testing
/// let db = try await Database.Queue(
///     configuration: .fromEnvironment()
/// )
/// prepareDependencies {
///     $0.defaultDatabase = db
/// }
///
/// // Production
/// let db = try await Database.Pool(
///     configuration: .fromEnvironment(),
///     minConnections: 5,
///     maxConnections: 20
/// )
/// prepareDependencies {
///     $0.defaultDatabase = db
/// }
/// ```
///
/// ## Error Handling
///
/// Database operations can throw various errors that should be handled appropriately:
///
/// ```swift
/// do {
///     try await db.write { db in
///         try await User.insert { ... }.execute(db)
///     }
/// } catch Database.Error.poolExhausted(let max) {
///     // Handle connection pool exhaustion
///     logger.error("Connection pool exhausted (max: \(max))")
///     throw ServiceUnavailable()
/// } catch Database.Error.connectionTimeout(let timeout) {
///     // Handle connection timeout
///     logger.error("Database connection timed out after \(timeout)s")
///     throw ServiceUnavailable()
/// } catch {
///     // Handle other database errors
///     logger.error("Database error: \(error)")
///     throw error
/// }
/// ```
///
/// ### Transaction Error Handling
///
/// ```swift
/// do {
///     try await db.withTransaction(isolation: .serializable) { db in
///         // Critical operations
///     }
/// } catch Database.Error.transactionFailed(let underlying) {
///     // Handle transaction failure
///     if isSerializationError(underlying) {
///         // Retry the transaction
///         return try await retryTransaction()
///     }
///     throw underlying
/// }
/// ```
public enum Database {
    // Namespace holder - never instantiated
}
